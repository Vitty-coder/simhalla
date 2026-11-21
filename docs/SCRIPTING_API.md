# SCRIPTING_API — SimScript v1 (API v1)

Lenguaje propio, mínimo y **aislado** para mecánicas extraordinarias (efectos de habilidades/estados) e IA programada. Implementado en `src/scripting` (compilador → AST, intérprete con presupuesto, API de lista permitida). No se ejecuta GDScript ni código del anfitrión: SimScript no tiene `eval`, importación, reflexión, E/S, red, reloj, funciones como valores ni acceso a objetos de Godot. Compatible PC/Android (GDScript puro, sin plugins).

## 1. Dónde viven y cómo se usan
- **Paquetes de personaje:** `scripts/<id>.sim` (UTF-8 sin BOM, `id` en minúsculas/dígitos/`_`, ≤ 32 por entidad). En bibliotecas (`abilities`/`ai`) los scripts se rechazan. Entidades JSON sueltas: clave `"scripts": {"<id>": "<código>"}`.
- **Efecto:** `{"type": "script", "script": "<id>", "args": {…datos…}, "contract": {…}}` (`contract` opcional, ver §6) en cualquier lista de efectos (habilidades, estados, pasivas/reacciones…). Se ejecuta `fn run(ctx)` **una vez por acción**.
- **IA:** `{"type": "script", "script": "<id>"}` (sola, como estado de `state_machine`, como `strategy` de un árbol, o bajo `artifact.ai_rules` vía `OverlayAI`). Se ejecuta `fn decide(view)`.
- **Importar nunca ejecuta:** solo se compila (sintaxis, lista permitida, referencias, contexto) y se hace el ensayo de construcción habitual. Un script con bucle infinito se importa sin problema; falla (controladamente) al ejecutarse.
- La huella SHA-256 de cada script va en `combat_started` (`entities[].scripts`) y en la huella del paquete.

## 2. Lenguaje
```
// comentario
const BASE = 40;                         // solo literales
fn helper(a, b) { return a * b + BASE; } // funciones propias (recursión acotada)
fn run(ctx) {
  let total = 0;                         // `let` declara; `=` asigna (variables, l[i], m.k, m["k"])
  for t in ctx.targets { total = total + hp(t); }      // sobre una lista
  for i in range(3) { }  for i in range(2, 5) { }      // range solo en `for`
  while total > 100 { total = total - 50; }            // acotado por el presupuesto
  if total > 10 and not alive(ctx.caster) { return null; } else if false { } else { }
  deal_damage(ctx.targets[0], total, {"damage_type": "magical", "element": "fire"});
}
```
- **Tipos:** número (float), texto, booleano, `null`, lista, mapa (claves texto; `{a: 1, "b c": 2}`). Operadores `+ - * / % == != < <= > >=`, `and`/`&&`, `or`/`||`, `not`/`!`, `[i]`, `.clave`. `+` suma números, une textos y concatena listas.
- **Estricto:** las condiciones y `and/or/not` exigen booleanos; `<` compara números o textos; división/módulo por cero, índice fuera de rango, `sqrt` negativo y resultados no finitos o > 1e15 son errores controlados. Una clave ausente de un mapa vale `null`.
- **Copia al guardar:** guardar una colección dentro de otra (literal, `push`, asignación a índice/miembro) la copia en profundidad ⇒ no existen ciclos. `let a = b` comparte referencia.
- **Validación estática al compilar:** variables no declaradas, funciones desconocidas o no permitidas, aridad, asignación a constantes, `break` fuera de bucle, nombres reservados o de la API, llamadas a métodos (`x.f()`) y sentencias de expresión que no sean llamadas.

## 3. Funciones
**Puras (ambos contextos):** `abs min max floor ceil round sqrt clamp len str num push pop keys has sort sum type concat`.

**Efectos** (`fn run(ctx)`; `ctx = {caster, targets, ability, args, turn}`, entidades = id de texto):
| Función | Tipo | Notas |
|---|---|---|
| `stat(id, nombre)` `hp(id)` `hp_max(id)` `hp_ratio(id)` `res(id, recurso)` `res_max(id, recurso)` `alive(id)` `team(id)` `is_enemy(a, b)` `enemies(id)` `allies(id)` `status_stacks(id, estado)` `has_tag(id, etiqueta)` `turn()` `time()` | consulta | Estado autorizado (mismo alcance que las fórmulas). `res` = `null` si no existe el recurso |
| `deal_damage(id, base, {damage_type, element, pen_pct, pen_flat, elem_pen, crit})` | combate | Usa `DamageCalculator` (defensa, afinidad, resistencia, redondeo) y `deliver_damage` ⇒ `damage_pre` interceptable + eventos. Siempre impacta (use `attack_roll`) |
| `heal(id, cantidad)` | combate | `direct_heal` (HEAL_REC, `heal_pre`/`heal_done`) |
| `modify_resource(id, recurso, delta)` | combate | `change_resource`; límites con `resource_limit` |
| `apply_status(id, estado, {stacks, duration, magnitude})` / `remove_status(id, estado)` | combate | Solo estados del catálogo; sin forzar |
| `attack_roll(id)` | combate | Tirada de impacto del motor (`hit`/`miss`) ⇒ booleano |
| `emit(nombre, {datos})` / `metric(nombre, cantidad)` | combate | `user.<nombre>` (≤ 16 claves escalares) / métrica de usuario |
| `rand()` `rand_int(n)` `chance(p)` | RNG | Flujo `"script"` del RNG del motor: determinista y separado de los de combate |
| `get_var(clave)` / `set_var(clave, valor)` | estado | Variables del script por entidad (≤ 64; valores ≤ 64 elementos); se reinician en cada combate |

Los objetivos muertos se omiten con `target_skipped`; las cantidades negativas, ids inexistentes, opciones desconocidas, elementos fuera del catálogo, etc. son **error de script**.

**IA** (`fn decide(view)`): solo las puras más `predict(vista, habilidad, objetivo)` (= `AIPredictor.evaluate`) y `observed_ratio(vista, objetivo, tipo, elemento)`. **Sin** operaciones de combate, RNG ni variables: la IA propone y el motor revalida. Resultado: `{ability, target | targets, reason?, remember?: {set, incr}}` o `{wait: true, reason?}`; claves desconocidas o formas inválidas ⇒ fallback.

La lista completa y su versión viven en `ScriptApi.CATALOG` (`ScriptApi.VERSION` = 1). Cada función declara los contextos permitidos; se comprueba al enlazar (solo lo **alcanzable** desde `run`/`decide`).

## 4. Límites (reglamento `scripting.*`, con techo duro)
| Clave | Defecto | Techo | Efecto |
|---|---|---|---|
| `max_instructions` | 20 000 | 1 000 000 | nodos evaluados por ejecución (bucles incluidos) |
| `max_call_depth` | 16 | 64 | profundidad de llamadas |
| `max_collection` | 256 | 4 096 | elementos por lista/mapa; también literales |
| `max_string` | 256 | 4 096 | caracteres por texto |
| `max_mutations` | 32 | 1 024 | operaciones de combate (y `set_var`) por ejecución |
| `max_source_bytes` | 16 384 | 262 144 | tamaño del script |
| `max_ast_nodes` | 3 000 | 50 000 | complejidad (también limita anidamiento: 32 niveles) |
El contenido no puede cambiarlos. Las colecciones/copias y las llamadas a la API cobran instrucciones adicionales.

## 5. Errores y reproducibilidad
- **Efecto:** cualquier error ⇒ el combate se **aborta** con `script_error` y diagnóstico (`script.sim:línea: motivo`); nunca cuenta como derrota ni empate. Cada ejecución emite `script_run` (`script`, `hash`, `ok`, `instructions`, `api_calls`, `mutations`).
- **IA:** error o resultado inválido ⇒ `ai_fallback` (`reason`, `policy: wait`) y espera; el combate sigue. La propuesta válida la revalida el motor como cualquier otra.
- Determinista: sin reloj ni azar propio; mismas semilla y código ⇒ mismas instrucciones y mismo `log_hash`.

## 6. Contrato mecánico y valoración (fase 6)
Un efecto `script` puede declarar `"contract": {"max_damage": N, "max_heal": M}` (topes **por ejecución**, ≤ 10 000 000). El motor los **hace cumplir** (`deal_damage`/`heal` por encima del tope acumulado ⇒ `script_error` `[contrato]`, sin aplicar el exceso) y, al construir, comprueba que el contrato cubre lo que el script usa (`deal_damage`↔`max_damage`, `heal`↔`max_heal`; `apply_status`/`remove_status`/`modify_resource` no son cubribles). Con contrato, el script se valora como daño/curación declarativos de peor caso; sin contrato y con poder mecánico es **no evaluable**. Ver `BALANCE_RULES.md`.

`ScriptProgram.analysis` = `{api_version, calls, functions, mutates, uses_rng, has_loops, uses_state, nodes, source_hash}`; `reachable_calls(contexto)`; `check_contract(contrato)`. Es información verificable; **no** asigna coste por sí misma.
`ScriptProgram.analysis` = `{api_version, calls, functions, mutates, uses_rng, has_loops, uses_state, nodes, source_hash}`; `reachable_calls(contexto)`. Es información verificable para contratos mecánicos; **no** asigna coste. Al construir la entidad cada script usado emite una advertencia «no evaluable automáticamente»; el valorador (fase 6) lo trata según su contrato.

## 7. Ejemplo
`content/packages/rune_caster`: rayo en cadena, sobrecarga e IA en SimScript (`scripts/chain.sim`, `overload.sim`, `rune_ai.sim`), sin cambios en el motor (`test_scripting.gd`).

## 8. Qué NO hay (todavía)
Scripts en paquetes de biblioteca (`abilities`/`ai`) ni compartidos entre paquetes; scripts de condición/fórmula (las fórmulas siguen siendo la gramática segura); depurador paso a paso; migraciones de versiones de la API (solo v1); valoración automática de scripts (fase 6). Aislamiento verificado con pruebas, pero **no auditado externamente**.
