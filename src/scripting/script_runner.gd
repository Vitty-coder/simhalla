class_name ScriptRunner
extends RefCounted
## Ejecuta scripts de efecto dentro del motor. Un error del script (limite, tipo, API) aborta el
## combate con diagnostico (`script_error`): nunca se cuenta como derrota o empate.

## Compila `source` con los limites del reglamento. {"program","errors"}.
static func compile(source: String, script_name: String, rules: Ruleset) -> Dictionary:
	return ScriptCompiler.compile(source, script_name, ScriptLimits.from_ruleset(rules))


static func run_effect(ctx: ActionContext, script_id: String, args: Variant, contract: Variant = null) -> void:
	var eng := ctx.engine
	var prog: ScriptProgram = ctx.actor.scripts.get(script_id, null)
	if prog == null:
		eng.abort("script_error", "%s: el script '%s' no esta disponible en la entidad" % [ctx.actor.id, script_id])
		return
	var limits := ScriptLimits.from_ruleset(eng.rules)
	var host := EffectHost.new(ctx, limits)
	host.contract = contract if contract is Dictionary else null
	var interp := ScriptInterpreter.new(prog, limits, host, ScriptApi.EFFECT)
	var targets: Array = ctx.targets.map(func(t): return t.id)
	var arg_value: Variant = ScriptValue.to_script(args if args != null else {})["value"]
	var sctx := {
		"caster": ctx.actor.id, "targets": targets, "ability": ctx.ability.id if ctx.ability != null else "",
		"args": arg_value, "turn": float(eng.turn_count),
	}
	var res := interp.call_entry(ScriptProgram.ENTRY["effect"], [sctx])
	eng.emit(EventTypes.SCRIPT_RUN, ctx.actor.id, "", {
		"script": script_id, "hash": prog.source_hash.substr(0, 16), "ok": bool(res["ok"]),
		"instructions": int(res["instructions"]), "api_calls": interp.api_calls, "mutations": host.mutations,
	}, ctx.cause_id)
	if not bool(res["ok"]):
		eng.abort("script_error", "%s: %s" % [ctx.actor.id, str(res["error"])])
