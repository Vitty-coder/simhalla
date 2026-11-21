# AI_REFERENCE — IA de comportamiento implementada (fases 1 y 4)

Contrato: `AIController.decide(view: Dictionary) -> AIDecision`. La IA **solo propone**; el motor revalida y resuelve. Sin azar estratégico: desempates deterministas. Scripts de IA: ver `SCRIPTING_API.md`.

Una IA se declara en `"ai": {...}` (personaje, invocación, forma) o como estrategia nombrada en un paquete `ai` (`ai.json` → `strategies`, referenciable con `ai_ref`). Tipos: `passive`, `priority_list`, `scored`, `state_machine`, `behavior_tree`, `script`. Todos admiten `"reactions"`. Se pueden intercambiar sin tocar el personaje; cambiar de IA no cuesta PC.

## Tipos declarativos
- `{"type": "passive"}`: siempre espera.
- `priority_list`: la primera regla aplicable gana; si ninguna, espera.
  `{"ability","target","when","remember"}`
  - `target`: `self`, `first_enemy`, `lowest_hp_enemy`, `highest_hp_enemy`, `lowest_hp_ally`, `first_ally`, `last_attacker` (último rival que me dañó, memoria). Por defecto `first_enemy`.
  - `when`: ver *Condiciones*. `remember`: `{"set": {var: valor}, "incr": {var: n}}`, se aplica si la regla se ejecuta.
  - La habilidad debe existir y ser legal ahora; si no, se descarta (`details.discarded`).
- `scored`: puntúa **todas** las parejas (habilidad legal, objetivo) y elige la mayor. Empate: la primera en el orden de la vista.
  `{"weights":{…}, "bias":{ability:n}, "tag_bias":{tag:n}, "modifiers":[{"when","weights","bias"}], "exclude":[ids], "wait_below": n}`
  Características (0..1, calculadas con el predictor; solo información visible):
  `damage` (daño esperado ponderado por impacto/crítico ÷ vida visible), `lethal`, `lethal_potential`, `heal` (curación efectiva ÷ vida máx.), `need` (1 − vida relativa del objetivo, si cura), `low_target` (1 − vida relativa del rival, si daña), `status` (aplica un estado que el objetivo no tiene), `hit` (probabilidad estimada), `cost` (coste relativo a los recursos; peso negativo = conservar), `tempo` (1 − fracción del intervalo de turno que le falta al rival: alto = actúa pronto; 0 sin observación), `reaction_risk` (1 si dañas a un rival del que ya se han visto reacciones; peso negativo para evitarlo).
  Dañar a aliados/uno mismo invierte el signo de `damage`/`lethal`; curar a rivales invierte `heal`. `modifiers` suma pesos/bias cuando su `when` (ámbito estado) se cumple. `wait_below`: si la mejor puntuación es menor, **espera** (reservar acción/recursos).
- `state_machine`: `{"initial","states":{nombre:{"strategy":{passive|priority_list|scored},"transitions":[{"to","when","remember"}]}}}`. El estado actual vive en la memoria. Cada decisión evalúa las transiciones del estado actual en orden (como mucho **una** por decisión) y decide con la estrategia del estado resultante. Sin anidar máquinas. Máx. 16 estados.

- `behavior_tree`: `{"root": nodo}`. En cada decisión se recorre el árbol (un *tick*, sin estado entre ticks; el estado persistente vive en la memoria con `remember`) hasta que una hoja produce una decisión. Nodos: `selector` (primer hijo con éxito), `sequence` (guardas + acción: falla en el primer fallo; el hijo que decide termina el tick), `condition {when}` (ámbito estado), `action {ability,target,when,remember}` (como una regla de `priority_list`), `strategy {strategy: passive|priority_list|scored}`, `wait {reason}`, `not {child}`, `succeed {child}`. Sin decisión al final: espera (`bt_no_decision`). Límites: 64 nodos, profundidad 8; `strategy` no admite otro árbol ni máquinas. Puede usarse como estrategia de un estado de `state_machine`. La traza del recorrido va en `details.tree`.

- `script`: `{"script": "<id>"}` — IA programada en SimScript (`fn decide(view)`), con la misma vista limitada, solo consultas (`predict`, `observed_ratio`) y funciones puras. Un error o resultado inválido ⇒ `ai_fallback` + espera (no aborta). Ver `SCRIPTING_API.md`. Puede ser estrategia de un estado, de un nodo `strategy` o envolverse con `ai_rules` del artefacto.

## Reglas de IA del artefacto
`artifact.ai_rules` se antepone a `priority_list` (fusionadas) y envuelve a `scored`, `state_machine` y `behavior_tree` (`OverlayAI`: si una regla del artefacto aplica gana, razón `artifact_rule_N`; si no, decide la IA base y se anota `artifact_rules_discarded`). Con `passive` sigue siendo error.

## Condiciones (`when`)
`{"<ruta>": {"<op>": valor}}`, todas deben cumplirse; `op`: `lt le gt ge eq ne`; booleanos = 1/0; ruta sin dato visible ⇒ condición falsa (nunca se infiere lo oculto).

| Ruta | Significado |
|---|---|
| `self.hp`, `self.hp_ratio`, `self.res.<id>`, `self.stat.<STAT>`, `self.status.<id>` | estado propio completo (`status` = pilas) |
| `mem.<var>` | variable de memoria (0 si no existe) |
| `enemy.alive_count`, `enemy.lowest_hp_ratio`, `ally.alive_count`, `ally.lowest_hp_ratio` | grupos (según campos visibles) |
| `turn`, `time`, `state_turns` | turno global, tiempo virtual, turnos propios en el estado actual (máquinas) |
| `target.hp`, `target.hp_ratio`, `target.res.<id>`, `target.status.<id>` | objetivo elegido (reglas y reacciones; solo campos visibles) |
| `predict.damage`, `predict.damage_max`, `predict.hit_chance`, `predict.lethal`, `predict.lethal_potential`, `predict.heal`, `predict.time_to_turn`, `predict.reactions_seen` | predicción para (habilidad, objetivo); `time_to_turn` (tiempo virtual hasta el próximo turno del objetivo) es desconocido —condición falsa— hasta observar sus turnos; `reactions_seen` = reacciones distintas observadas |
| `event.amount` | cantidad del evento disparador (solo reacciones) |

## Predicción (`AIPredictor`, funciones puras sobre la vista)
Nunca modifica el estado, no consume RNG ni conoce estadísticas ocultas. Devuelve **estimaciones con rango** o `null`/`known=false`:
- Daño propio: fórmulas evaluadas solo con las estadísticas del lanzador (formulas con `target.*` ⇒ desconocido). Afinidad elemental y crítico propios.
- Mitigación del rival: solo la **observada** en el daño causado (razón importe/premitigación por tipo y elemento; memoria `obs.<id>.mit`). Sin observaciones: se supone sin mitigación (`max`), `min=0`, `known=false`, y `lethal` es falso (solo `lethal_potential`). Daño verdadero: conocido.
- Impacto: tasa observada (≥ 2 tiradas) o `ACC` propia (EVA rival desconocida). `time_to_turn`: intervalo observado × fracción de umbral restante (iniciativa visible). `seen_reactions`: reacciones observadas del rival.

## Memoria (`AIMemory`)
`entity.ai_memory`, reiniciada en cada combate/invocación (no se comparte entre batallas ni entidades). Solo recoge lo **observable** por esa entidad: su daño causado/recibido y tiradas de impacto, acciones públicas ajenas (habilidad usada, reacciones, inicio de turno), y su historial de decisiones (máx. 16). Variables de usuario (`vars`, máx. 32) y estado de la máquina: la IA **propone** `memory_ops` (`set`, `incr`, `state`) en su decisión y el motor las aplica. Los observadores solo se registran si alguna IA los necesita.

## Reacciones
`"reactions": {"default": "allow|decline", "rules": [{"ability": id|"*", "decision": "allow|decline", "when": {…}}]}`. Solo sobre habilidades `action_type: reaction` con `trigger` que el motor ya considera elegibles (coste, restricciones, objetivo). Primera regla que coincide decide; si ninguna, `default` (allow). Declinar ocurre **antes** de la tirada de probabilidad y del coste, y emite `reaction_declined` con el motivo. Sin política, las reacciones se ejecutan siempre (fase 3). Las automáticas y pasivas no pasan por la IA.

## Vista de solo lectura (`ViewBuilder`)
```
{ "atb_threshold", "time", "turn",
  "self":   {id, team, hp, hp_max, hp_ratio, initiative, resources{}, stats{efectivas},
             abilities[{id, action_type, cost, targeting, tags, profile}], tags[], statuses[], cooldowns[], memory{}},
  "others": [{id, team, alive, relation, + campos visibles de ai.visible_fields}],
  "legal_actions": [{ability_id, action_type, targets[]}],
  "turn_state": {main_remaining, actions_taken} }
```
`profile` (solo si la IA usa predicción/memoria) resume los efectos propios (daño/curación/estados) evaluados con las estadísticas del lanzador. Del resto de entidades **no** se exponen estadísticas, habilidades, cooldowns, memoria ni variables internas (hay pruebas de no filtración, incluidas las nuevas funciones). La vista es una copia.

## Decisión y trazabilidad
`AIDecision{kind: ability|wait, ability_id, target_ids, reason, details, memory_ops}` se registra en `action_selected`: regla usada y descartes (`priority_list`), mejores candidatos con puntuación y características (`scored`: `top`, `best_features`, `modifiers`, `excluded`), estado y transición (`state_machine`: `state`, `transition`). Decisión inválida ⇒ `action_rejected` + `ai_fallback` + espera (política `wait`). La IA nunca ejecuta una capacidad de la que el PJ carezca; las referencias a habilidades inexistentes se rechazan al construir.

## Perfiles genéricos (`content/packages/ai_profiles`)
`aggressive`, `defensive`, `balanced`, `conservative` (reserva con `wait_below`), `opportunistic` y la máquina `adaptive` (`attack`⇄`recover`). Solo usan pesos, sin ids de habilidades: sirven a cualquier PJ. El perfil aleatorio opcional (§10.1) **no** se implementa (sin azar estratégico).

## Límites conocidos
Pesos/umbrales de los perfiles son ilustrativos y no están equilibrados (D-062). Predicción hipotética «de segundo orden» (simular turnos futuros) no implementada. Scripts de IA: ver `SCRIPTING_API.md` (fase 5).
