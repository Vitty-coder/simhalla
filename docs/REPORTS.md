# REPORTS — Informes, estadística y depuración (fase 8)

Un **modelo único y versionado** (`simhalla.report/1`, `schemas/report.schema.json`) alimenta los **tres formatos confirmados: JSON, Markdown y HTML** (no se exige CSV ni PDF). Código en `src/analytics/` (`Stats`) y `src/reports/`.

## 1. Informe individual (`IndividualReport`)
`IndividualReport.build(engine, options)` → `{ok, errors, report}`. Exige **traza completa**; se calcula **escaneando el registro de eventos** (no depende de contadores aparte) y se cruza con `CombatStats` en las pruebas. options: `config` (config de `DuelRunner`, permite reproducirlo), `balance` (`BalanceReport.to_dict()`), `history` (`none|summary|full`), `history_limit`.
| Sección | Contenido |
|---|---|
| `meta` | versión del motor, reglamento (id/versión/hash), semilla (**texto**), `log_hash`, entidades con su contenido versionado/huellas (y huellas de scripts), `initial_overrides` |
| `result` | ganador/empate, causa, tipo, error técnico y estado final |
| `duration` | tiempo virtual, turnos globales y propios/omitidos, acciones, eventos y eventos por tipo |
| `damage` | por entidad: causado (efectivo), recibido, **intentado, premitigación, mitigado, absorbido, sobreexceso, reflejado** (separados: sin doble conteo); por tipo, por elemento, por fuente→habilidad, matriz fuente→objetivo, mitigación por fuente (`event_modified` sobre `damage_pre`) |
| `healing` | generada, efectiva, recibida y desperdiciada (overheal) |
| `attacks` | impactos, fallos, críticos, esquivas y tasas |
| `abilities` | usos, interrupciones, daño/curación efectivos atribuidos y recursos gastados por habilidad. Atribución por **cadena causal** (evento `action_started` ancestro); sin acción → `(otros)` |
| `resources` | inicial/final, generado, consumido (por motivo), veces en máximo/mínimo (el desperdicio exacto no se registra) |
| `statuses` | aplicaciones, rechazos, pilas máx., retiradas, expiraciones, disipaciones y duración media |
| `defenses` | mitigación por fuente, paradas/bloqueos, eventos cancelados y por quién |
| `ai` | decisiones, esperas, motivos, habilidades elegidas, fallbacks, rechazadas, reacciones declinadas, candidatos medios |
| `randomness` | tiradas de impacto (probabilidad media vs observada), críticos, procs (esperados vs observados) |
| `balance` | (opcional) perfil usado (etiqueta PRUEBA si es ilustrativo), coste, bruto/créditos, restante, componentes principales, **discrepancias** (presupuesto, no evaluables) |
| `metrics` | métricas de contenido: nombre, tipo `sum`, unidad (**aún no declarable**: vacía), origen, total, veces, media, por entidad, regla de agregación |
| `history` | cronología con `cause` (relaciones causales); `summary` = hitos (tope), `full` = todos |
| `reproduce` | semilla, versión, `log_hash` y la **configuración** completa |
`IndividualReport.verify_invariants` comprueba que daño causado = recibido = Σ por tipo = Σ por fuente/habilidad, curación efectiva = recibida, impactos+fallos = ataques.

## 2. Informe masivo (`BatchReport`)
`BatchReport.build(BatchResult)` a partir **solo de los registros** (orden de trabajo): mismo lote ⇒ mismo informe, con 1 o N workers. Muestra **n, denominadores y configuración** siempre.
- `meta`/`sample`: plan, semilla maestra (texto), modo de semillas, huella del plan y del lote, versiones/huellas de contenido por escenario; trabajos planificados/ejecutados/pendientes/resueltos y **errores y cancelados aparte**.
- Por escenario: resultados (victorias por contendiente y empates con **Wilson 95 %**; sin resueltos ⇒ sin tasa), distribuciones de turnos/tiempo/eventos (media con IC t, desviación, mediana, cuartiles, mín/máx, **histograma**), daño y curación medios por combate, **eficacia de habilidades** (uso, usos medios, daño medio, victoria si se usa / si no: **asociación, no causalidad**), métricas de contenido (resumen entre combates), errores agrupados, y **semillas/hashes para reproducir** (primeros trabajos y abortados).
- Global: `ranking` por contendiente, `matrix` de enfrentamientos favorables/desfavorables (ambos lados, todos los escenarios) y `comparisons` entre variantes del mismo grupo: **emparejada** (misma semilla) o **independiente (Newcombe)**.
- `methods`: la metodología escrita. `measurement`: rendimiento medido (**fuera de la huella** y omitido de MD/HTML por defecto).

## 3. Metodología estadística (`Stats`)
Tasas: **Wilson** 95 % (z = 1,959964). Diferencia de tasas independientes: **Newcombe** (híbrido de puntuación; validado con el ejemplo publicado 56/70 vs 48/80 ⇒ 0,2 [0,052; 0,334]). Emparejados: diferencias por pareja con **IC t** al 95 % + parejas discordantes. Medias: **IC t** (valores críticos tabulados; normal para df > 120). Cuantiles de tipo 7. Los intervalos son **aproximados** y anchos con muestras pequeñas; igualdad de resultados no implica igualdad de poder.

## 4. Formatos y exportadores (`ReportExporter`)
- **JSON** = el modelo (claves ordenadas, precisión completa, **sin marcas de tiempo**). Las semillas de 64 bits van como **texto** (un número JSON perdería precisión).
- **Markdown**: tablas y barras de texto; todo texto del modelo **escapado** (`|`, saltos, `<`, `>`, `&`, corchetes, acentos graves).
- **HTML**: autónomo, **sin CDN, sin red y sin JavaScript**; estilos y gráficas **SVG** (barras con intervalos, histogramas) en línea; claro/oscuro; tablas con scroll horizontal; cabecera **CSP** `default-src 'none'`; todo texto/dato **escapado** (`& < > " '`, controles). Los nombres/etiquetas importados hostiles no inyectan HTML ni Markdown (verificado).
- `content_hash(modelo)` = SHA-256 del modelo canónico (sin `measurement`; enteros normalizados y decimales a 9 cifras como texto, pues el analizador JSON de Godot no es exacto en el último bit): una ida y vuelta por JSON no cambia la huella. Va en el pie de MD/HTML. `write_all(modelo, dir, base)` escribe los tres archivos.
- CLI: `godot --headless --path . --script res://tools/report_tool.gd -- duel a.json b.json <semilla> [--history none|summary|full] [--balance perfil.json] [--out dir]` y `… -- batch plan.json [--workers N] [--out dir]`.

## 5. Verificación (`ReportVerifier`)
`check_individual` / `check_batch` (coherencia interna: sumas, denominadores, tasas = k/n, Wilson recalculado, matriz simétrica, histogramas), `verify_batch(modelo, lote)` (recalcula desde los registros y exige el mismo contenido; detecta cifras alteradas) y `reproduce_individual(modelo)` (re-ejecuta `reproduce.config`: mismo `log_hash` y mismo informe).

## 6. Depuración avanzada (`DebugInspector`)
Canal **separado** de la vista limitada de la IA (que no puede referenciarlo: lo verifica una prueba sobre `src/ai` y `src/scripting`, y la vista no filtra memoria/variables de otras entidades). Solo lectura (copias): estado interno de una entidad (estadísticas con desglose y **modificadores con origen**, recursos, estados, cooldowns/usos, canalización, **variables de scripts**, **memoria de IA**), `rng_states()`, `scheduler_state()`, `filter_events({entity,type,ability,chain_of,descendants_of,from,to,limit})`, `rolls()`, `explain_event(id)` (cadena causal y modificaciones), `validation_causes(data, perfil, reglamento)` (errores técnicos + valoración de PC) y `abort_diagnostic()` (error + últimos eventos).

## 7. Límites conocidos
Unidad y tipo de las métricas de contenido no son declarables aún (`unit` vacío, `type: sum`); el desperdicio exacto de recursos y la contribución por habilidad en reacciones concurrentes son aproximados; sin informes comparativos de **versiones de reglamento** más allá de `compare_rulesets`; sin gráficas en MD (solo texto); no hay biblioteca de informes (persistencia/consulta: fase 9); el HTML no se ha probado visualmente en navegador real en este entorno (sí estructura y escape); intervalos aproximados (ver §3).
