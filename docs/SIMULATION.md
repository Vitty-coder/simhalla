# SIMULATION — Simulación individual y por lotes (fase 7)

Todo usa **el mismo motor** que el combate normal (`DuelRunner` → `CombatEngine`): sin escenas ni nodos por duelo, sin UI. Código en `src/simulation/` (+ `tools/batch_tool.gd`).

## 1. Simulación individual controlable (`SimulationSession`)
`SimulationSession.open(config)` (config de `DuelRunner`; la traza es siempre completa) → `{ok, errors, session}`.
| Control | Qué hace |
|---|---|
| `step_action()` | un **paso** del motor (comenzar un turno, o resolver una decisión/acción) |
| `step_turn()` | hasta completar el turno en curso (o el siguiente entero si no hay) |
| `advance(n)` | hasta `n` pasos (velocidad = `n` por fotograma; en pausa no avanza) |
| `pause()` / `resume()` | pausar y reanudar |
| `run_to_end()` | resolver al instante hasta el final |
| `cancel()` | aborta como `cancelled` (nunca derrota ni empate) |
Inspección (solo lectura): `snapshot()` (tiempo, turno, entidades con vida/iniciativa/recursos/estados), `forecast(n)` (próximos turnos; **orientativo**, cambia si cambian las condiciones), `events_since_last()` (lectura incremental del registro), `causal_chain(event_id)` (hasta la raíz). **Hacia atrás:** `reconstruct_at(paso)` rejuega determinista (misma configuración y semilla) en una sesión **nueva**: el estado exacto de ese instante sin tocar la partida real; `repeat_same_seed()`. La configuración inicial alternativa (`initial_overrides`: vida, iniciativa, recursos) queda registrada en `combat_started`. La sesión no ejecuta reglas propias.

## 2. Plan de lote (`BatchPlan`, `simhalla.batch/1`, `schemas/batch.schema.json`)
```
{"schema":"simhalla.batch/1","name","master_seed","repetitions","seed_mode":"per_scenario|paired",
 "base":{ruleset, profile, library, ruleset_overrides, initial_overrides, balance},
 "scenarios":[{"key","label","group","entities":[spec,…],"sides":{"A":etiqueta,"B":…},"params":{},
               "ruleset_overrides":{},"initial_overrides":{},"repetitions":n}]}
```
`spec` = especificación de `DuelRunner`: `{"path"|"package","version","overrides","patch"}`; `overrides` sustituye claves enteras, **`patch` fusiona en profundidad** (variar un stat suelto); el reglamento admite `ruleset_overrides`.
- **Semillas:** `seed = f(maestra, clave de escenario, repetición)` (modo `per_scenario`) o `f(maestra, grupo, repetición)` (modo `paired`: **mismos azares** en todas las variantes del grupo, comparación emparejada). **Nunca** depende del orden de ejecución, de los workers ni de la posición en el plan.
- Límites: ≤ 10 000 escenarios, ≤ 1 000 000 trabajos. `fingerprint()` = huella canónica del plan (a prueba de ida y vuelta por JSON).

## 3. Modalidades (`BatchModes`; cada una devuelve un plan)
`duel` (A vs B × N) · `tournament` (todos contra todos en duelos 1v1, ambos lados opcional) · `gauntlet` (PJ de prueba contra biblioteca de adversarios) · `compare_variants` (versiones de PJ/componentes: `{"package","version"}`) · `compare_ai` (perfiles de IA del mismo PJ) · `compare_rulesets` (reglamentos globales) · `sweep` (variación controlada: producto cartesiano de ejes `stats.X` sobre una entidad, tope configurable; los ids con punto como `ELEM_AFF.fire` se toman enteros). Las comparaciones usan por defecto semillas **emparejadas**.

## 4. Ejecución (`BatchRunner`)
- `workers = 0`: cooperativo — `run_slice(max_jobs, max_ms)` ejecuta una porción y devuelve el control (UI/Android por fotograma).
- `workers = 1..8`: hilos de fondo — `start()`, `poll()` (hilo principal: agrega incrementalmente, llama `on_progress`), `wait()`. Cada trabajo construye su propio reglamento/perfil/registro/motor (nada mutable compartido); un combate descartable de un turno precarga clases antes de lanzar hilos.
- `cancel()`: detiene lo no empezado y pide abortar los combates en curso (`status: cancelled`, **no** derrota/empate/error técnico). Lo terminado sigue siendo válido y reproducible; el resultado es parcial (`status: cancelled`, `pending()`).
- **Reproducción:** cada registro lleva índice, semilla y `log_hash`; `BatchRunner.replay(plan, i)` rejuega el duelo con traza completa y `verify(plan, rec)` comprueba el hash. Un trabajo del lote == el mismo duelo individual. `keep_traces` guarda el registro de eventos de todos los trabajos (mucha memoria; por defecto no).
- Registro del lote: `engine_version`, huella del plan, huellas de contenido (`contents`: id/versión/hash de cada entidad por escenario), `fingerprint` global.

## 5. Agregación incremental (`BatchAccumulator`; la estadística inferencial es de la fase 8)
Por escenario y por etiqueta de contendiente: victorias, derrotas, empates, **abortos técnicos y errores de preparación aparte** (nunca cuentan como derrota/empate), cancelados, pendientes. Denominadores explícitos: `n_finished = victorias + empates`, `n_errors`, `denominator`. Tasas = victorias/`n_finished`. Medias y varianza (Welford) de turnos, tiempo virtual y eventos; daño/curación medios por etiqueta. El resumen final se **recalcula en orden de trabajo** (`rebuild`), así que no depende del orden de llegada.

## 6. Coherencia garantizada (verificada)
Mismo lote ⇒ **misma `fingerprint`** con 0, 1 o 3 workers, con traza reducida o completa, y el resultado de cada escenario no depende del orden del plan. Funciona igual con contenido con scripts e IA programada en hilos. `perf` (jobs/s, eventos/s, ms) es metadato de medición y **no** entra en la huella.

## 7. Rendimiento medido (2 vCPU, GDScript, escenario simple de 2 atacantes, ≈ 300 eventos/duelo; sin objetivo fijado)
| workers | duelos/s | eventos/s |
|---|---|---|
| 0 (cooperativo) | 23 | 6 800 |
| 1 | 25 | 7 300 |
| 2 | 36 | 10 600 |
| 4 | 35 | 10 100 |
≈ 12 % del tiempo por duelo es construir el motor; el resto es el bucle de eventos. Escalado ≈ 1,45× con 2 workers (2 vCPU físicas). **Sin medir en Android** ni con escenarios complejos/invocaciones (pendiente: fase 10).

## 8. CLI
`godot --headless --path . --script res://tools/batch_tool.gd -- plan.json [--workers N] [--out resultado.json] [--keep-traces] [--quiet]` (ejemplo: `content/batches/demo_duel.json`). Salida 0 completo, 3 cancelado/parcial, 2 plan inválido.

## 9. Límites conocidos
Sin persistencia ni historial de lotes (fase 9); sin intervalos de confianza, medianas ni informes (fase 8); sin pausa/reanudación de lotes a mitad de camino tras cerrar el proceso (se reproduce por plan+semilla); `compare_*` y `sweep` comparan solo duelos 1v1 en los constructores (el plan admite más entidades por escenario); rendimiento en Android sin verificar; hilos probados en PC (Linux).
