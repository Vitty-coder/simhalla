class_name AIController
extends RefCounted
## Contrato de IA de comportamiento (intercambiable por personaje).
##
## `decide` recibe SOLO una vista de lectura (Dictionary desacoplado del estado
## real, ver ViewBuilder) y devuelve una AIDecision. Debe ser determinista: sin
## azar estrategico ni acceso al RNG real ni al reloj de pared. La memoria de
## combate vive en `entity.ai_memory` (la escribe el motor a partir de
## `AIDecision.memory_ops` y de acontecimientos observables, ver AIMemory).
##
## Reacciones: `decide_reaction` solo puede aceptar o declinar una reaccion que el
## motor ya considera elegible; nunca proponer otra distinta.

## Politica opcional de reacciones (clave "reactions" de la configuracion).
var reaction_policy: AIReactionPolicy = null


func ai_id() -> String:
	return "abstract"


func decide(_view: Dictionary) -> AIDecision:
	return AIDecision.wait("ia_abstracta")


## ¿Necesita memoria de observaciones? (evita coste en IAs sin estado).
func wants_memory() -> bool:
	return reaction_policy != null # las condiciones de reaccion pueden usar mem.*/predict.*


## Habilidades del propio personaje que la IA referencia (se validan al construir).
func referenced_abilities() -> Array:
	var out: Array = []
	if reaction_policy != null:
		out.append_array(reaction_policy.referenced_abilities())
	return out


## Enlaza los scripts compilados de la entidad (por id) con las IAs que los usan. Devuelve errores.
func bind_scripts(_scripts: Dictionary, _limits: ScriptLimits) -> Array:
	return []


## req: {ability_id, target_id, event}. Devuelve {allow: bool, reason: String, rule: int}.
func decide_reaction(view: Dictionary, req: Dictionary) -> Dictionary:
	if reaction_policy == null:
		return {"allow": true, "reason": "no_policy", "rule": -1}
	return reaction_policy.decide(view, req)


## ¿Tiene politica propia de reacciones? (el motor solo consulta si la hay)
func has_reaction_policy() -> bool:
	return reaction_policy != null
