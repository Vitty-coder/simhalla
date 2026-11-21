# ROADMAP — Estado de fases y limitaciones conocidas

Orden aceptado en PROJECT.md §18. Estado a **2026-11-20** (fases 1 a 9 completadas el mismo día).

| Fase | Estado | Notas |
|---|---|---|
| 1. Núcleo | **Completada y verificada** (125 casos OK) | Ver abajo qué se verificó y qué no |
| 2. Contenido (paquetes, esquemas, dependencias, validación) | **Completada y verificada** (165 casos OK) | Ver `PACKAGES.md`; limitaciones abajo |
| 3. Habilidades y eventos (estados, reacciones, recursos avanzados, artefacto, invocaciones, formas, temporalidad) | **Completada y cerrada** (279 casos OK) | Ver `ABILITY_REFERENCE.md`; incrementos de cierre hechos |
| 4. IA (estrategias, memoria, predicción, reacciones) | **Completada y verificada** (310 casos OK) | Ver `AI_REFERENCE.md`; limitaciones abajo |
| 5. Scripts aislados | **Completada y verificada** (339 casos OK) | SimScript v1; ver `SCRIPTING_API.md` y limitaciones abajo |
| 6. Equilibrio (PC, perfiles, modos libre/reglamentado) | **Completada y verificada** (367 casos OK) | Valorador automático y trazable con perfil de PRUEBA; ver `BALANCE_RULES.md` y limitaciones abajo |
| 7. Simulaciones (lotes, torneos, variaciones) | **Completada y verificada** (385 casos OK) | Ver `SIMULATION.md` y limitaciones abajo |
| 8. Informes (MD/JSON/HTML) | **Completada y verificada** (408 casos OK) | Ver `REPORTS.md` y limitaciones abajo |
| 9. UI y biblioteca | **Completada y verificada en headless** (434 casos OK) | Ver `UI.md`; **sin prueba visual ni en dispositivo** (limitaciones abajo) |
| 10. Plataformas | **Completada salvo verificación en dispositivo** (445 casos OK) | Ver `PLATFORMS.md` |

## Fase 10 — qué se verificó y limitaciones
- Verificado: exportado Linux x86_64 ejecutado en directorio vacío con `--selftest` (14 comprobaciones de conformidad OK); APK arm64 firmado (v2/v3), sin permisos, solo `arm64-v8a`, con contenido necesario y sin archivos de desarrollo; auditoría offline y de activos de terceros; selector de archivos con bandeja de entrada; ejemplos instalables.
- Limitaciones: **APK no ejecutado en dispositivo/emulador; determinismo PC↔Android sin verificar** (la batería existe para ejecutarla allí); rendimiento solo medido en Linux (≈ 10–36 duelos/s); optimización del registro de eventos pendiente (afectaría al hash canónico).

## Fase 9 — qué se verificó y limitaciones
- **Criterio de avance (flujo completo importación → duelo/lote → informe usable):** automatizado de extremo a extremo tanto en los modelos de aplicación como en la **escena principal Godot** (importar con vista previa → biblioteca → duelo con coste/versión/modo → visor con retroceso → guardar → informe verificado → reproducir el combate guardado; lote → informe).
- Almacenamiento con índice local, versiones inmutables, colisiones explícitas, combates reproducibles con contenido fijado, borrado protegido, informes verificables y **bundles portables** seguros; localización es/en completa; retratos con sustituto; diseño adaptable verificado a nivel lógico; el modo libre/reglamentado y el perfil ilustrativo siempre visibles.
- Limitaciones: **no se ha visto la interfaz renderizada** (sin pantalla en este entorno) ni probado en Android/táctil real; el selector nativo de archivos no está integrado (se pide una ruta); gráficos `_draw` básicos; retroceso O(pasos); depurador como JSON de solo lectura; el arranque en árbol real se comprobó en headless 30 fotogramas sin errores de script.

## Fase 8 — qué se verificó y limitaciones
- **Criterio de avance (datos consistentes y reproducibles desde los informes):** el informe individual coincide con las estadísticas del motor y con sus invariantes; el mismo combate da el mismo informe byte a byte y se reproduce desde su propia configuración; el informe masivo es idéntico con 0 o 3 workers, se recalcula desde los registros y cualquier cifra alterada se detecta (coherencia interna y verificación); JSON/MD/HTML salen del mismo modelo.
- Estadística validada contra valores publicados (Wilson, Newcombe); errores y cancelados siempre aparte; muestra y configuración siempre visibles; HTML autónomo y texto hostil escapado; depurador separado de la IA.
- Limitaciones: unidad/tipo de las métricas de contenido no declarables aún; desperdicio exacto de recursos no registrado; **sin biblioteca/persistencia de informes (fase 9)**; HTML sin prueba visual en navegador real en este entorno; intervalos aproximados; sin comparación automática entre informes de lotes distintos.

## Fase 7 — qué se verificó y limitaciones
- **Criterio de avance (coherencia entre modos, cancelación, rendimiento medido):** misma huella de lote con 0/1/3 workers, traza reducida/completa y orden de plan distinto; un trabajo del lote == el duelo individual y se reproduce; cancelación con resultados parciales válidos que no cuentan como derrota/empate/error; rendimiento medido (≈ 23 → 36 duelos/s con 2 workers en 2 vCPU).
- Sesión individual con control por acción/turno, pausa, instantánea, previsión y **reconstrucción determinista hacia atrás**; siete modalidades de lote; agregación incremental con denominadores y errores aparte; CLI `batch_tool`.
- Limitaciones: **sin estadística inferencial ni informes** (fase 8); sin persistencia/historial (fase 9); rendimiento **sin medir en Android** ni con escenarios complejos; hilos solo probados en Linux; sin objetivo de throughput fijado (§15); la reconstrucción hacia atrás rejuega desde cero (coste O(pasos)).

## Fase 6 — qué se verificó y limitaciones
- **Contrato de coste** (`creation_cost = stats + componentes − créditos`, `remaining`), desglose que suma exactamente el total, con regla/hechos/fórmula/origen por componente; informes **etiquetados PRUEBA** con perfil ilustrativo.
- **Reglas confirmadas:** estadísticas base gratis, desventajas automáticas con tope, restricciones que abaratan, **sin recargo por sinergias**, IA y ataque básico gratuitos (no negociable por perfil), referencias no duplicadas (estados una vez, invocaciones por instancia), costes arbitrarios del autor rechazados.
- **No evaluables sin precio inventado** y **scripts con contrato** (topes que el motor hace cumplir en ejecución; valoración de peor caso); modos **libre/reglamentado**; integración con importador, `DuelRunner` y CLI `balance_tool`.
- Perfiles validados al cargar (fórmulas de la gramática segura, hechos por regla, esquema público `balance.schema.json`).
- Limitaciones: **las cifras no son un equilibrio** (perfil ilustrativo sin ajuste empírico; la evaluación por simulación pertenece a la fase 7+); valoración estructural (supuestos: equipo de referencia 3, objetivo de referencia con stats base, pilas/magnitud 1 en estados); los contratos solo cubren daño y curación; sin migración ni comparación de perfiles; sin presupuesto por categorías.

## Fase 5 — qué se verificó y limitaciones
- **Lenguaje:** aritmética/texto/listas/mapas, control de flujo, funciones y recursión, ámbito, copia al guardar; ~20 errores de ejecución y ~20 de compilación con mensaje `script:línea`.
- **Aislamiento:** ninguna función del anfitrión (`OS`, `load`, `FileAccess`, `eval`, `call`, `get_node`, `Engine`…) es alcanzable —error al compilar, jamás se ejecuta—; sin métodos ni reflexión; solo datos cruzan la frontera (objetos, callables y claves no textuales se rechazan); la IA no puede mutar ni consumir RNG.
- **Límites:** instrucciones (bucles infinitos), profundidad (recursión), textos/listas/mapas, tamaño de fuente, nodos y anidamiento del compilador, operaciones por ejecución, variables; límites del reglamento aplicados y validados (con techos).
- **Motor:** daño/curación/recursos/estados/eventos/métricas vía pipeline (interceptables y trazables), RNG propio sin alterar los flujos de combate, errores ⇒ `script_error` abortado con diagnóstico (nunca empate), fallback de IA, revalidación de propuestas, determinismo y huellas en la traza.
- **Paquetes:** importar no ejecuta; rechazos por sintaxis, funciones prohibidas, entrada ausente, nombres/extensiones, BOM, no-UTF-8, tamaño, bibliotecas; la huella del paquete cambia con el script; ejemplo `rune_caster`.
- Limitaciones: aislamiento verificado por pruebas, **sin auditoría externa**; sin scripts en bibliotecas ni compartidos entre paquetes; sin scripts de condición/fórmula ni depurador; solo API v1 (sin migraciones); rendimiento del intérprete sin medir en lotes grandes; valoración automática en la fase 6.

## Fase 4 — qué se verificó y limitaciones
- **Estrategias intercambiables** (`passive`, `priority_list`, `scored`, `state_machine`) validadas por esquema público y al construir; 6 perfiles genéricos comparables entre sí con la misma semilla (comportamientos distintos, reproducibles).
- **Memoria** observable, acotada y reiniciada por combate; **predicción** como estimación con rango, sin tocar estado ni RNG (mismo `log_hash` con y sin consultas); **privacidad** de la vista (sin filtraciones, incluida la memoria); **reacciones** aceptadas/declinadas con trazabilidad.
- Incluye árboles de comportamiento declarativos, reglas de artefacto sobre cualquier IA declarativa y predictor accesible desde condiciones/puntuaciones. Limitaciones: pesos de perfiles sin equilibrar; sin predicción de segundo orden (simular turnos futuros); sin detección de combos como concepto propio (solo historial); `time_to_turn` requiere haber observado al rival; `lethal` solo con mitigación conocida; el perfil aleatorio opcional no se implementa; la lista exacta de campos visibles sigue siendo configurable y provisional (D-020).

## Fase 3 — qué se verificó
- **Estados:** todas las unidades de duración y las 7 políticas de reaplicación; modificadores con pilas; banderas (aturdir, silencio, provocación, inmunidad por etiqueta, suspender iniciativa, interrumpir canalización); disipar, extender/acortar, robar/copiar/dar; periódicos, `on_apply`/`on_expire`; estados nativos como datos.
- **Restricciones:** cooldown, usos por combate/turno, cargas con recarga, `requires` sobre uno mismo/objetivo/estados, bloqueos; costes al comprometer.
- **Defensas** nativas (escudos, reducción, inmunidad, absorción elemental, parada, bloqueo, reflejo, prevención de muerte) con trazabilidad de mitigación.
- **Reacciones y automáticas** con condiciones sobre el evento, probabilidad, costes, cooldown, golpe letal, última palabra y cadena acotada; eventos y métricas de usuario.
- **Canalización/carga**, **invocaciones** (entidades completas, límites, vida, dueño), **formas**, **temporalidad** (guardar/restaurar, efectos retrasados, repetir/copiar).
- **Combinaciones y límites:** escenario combinado determinista y causalmente consistente; paridad de trazas; 15 semillas sin abortos; contenido hostil frenado por límites técnicos sin abortar.
- Importación de paquetes con estados propios, invocaciones y disparadores; ensayo en motor real para validar referencias.
- Se corrigió una **fuga de memoria heredada de la fase 1** (ciclos motor↔servicios): `dispose()`.

## Fase 3 — incrementos de cierre (completados)
Invertir y propagar estados, suspender efectos y cooldowns, restaurar estados, artefacto con recursos/estados/invocaciones/reglas de IA, selectores de objetivo deterministas, catálogo elemental validado y patrón de "reservar" (preparar y liberar). Verificados con `test_phase3_closure.gd` (22 casos). Decisiones D-051…D-058 (provisionales).

### Qué sigue pendiente (no de la fase 3)
- **Reservar con decisión de IA** y selección estratégica: fase 4. **Scripts** para lógica personalizada: fase 5. **Costes de creación**: fase 6.
- Los cooldowns por **tiempo** no se pausan con `suspend_cooldowns`; la inversión no afecta a defensas/banderas (limitaciones documentadas).
- Las convenciones D-040…D-058 son provisionales y deben revisarse con el responsable del diseño.
- Rendimiento ≈ 28 duelos/s en traza reducida (D-028); sin objetivo fijado.

## Fase 2 — qué se verificó
- Importar **dos PJ externos** (`arcane_duelist`, `iron_vanguard`) con dependencias (`core_spells`, `basic_ai`), artefacto, recursos e IA importada, y combatir con ellos; mismo paquete + semilla = mismo combate.
- Rechazo claro (archivo, código y ruta) de: esquema/propiedades desconocidas, referencias rotas, dependencias ausentes/mal tipadas/duplicadas/autodependencia, versión incompatible, motor incompatible, fórmulas y costes inválidos, archivos desconocidos o no soportados (scripts/efectos/invocaciones), JSON/BOM/UTF-8, rutas peligrosas, colisiones, enlaces, límites, bombas ZIP, ZIP corrupto, assets falsos.
- Biblioteca: versiones inmutables, idempotencia, resolución semver, importación atómica, detección de alteración, trazabilidad de versión/huella en cada combate.

## Fase 2 — limitaciones conocidas
1. Biblioteca simple basada en directorios (sin índice persistente, historial ni exportación portable: fase 9). Estado de `user://` en Android no probado.
2. Dependencias solo hacia bibliotecas `abilities`/`ai` y sin dependencias entre bibliotecas; no existen aún paquetes de efectos/estados/artefactos reutilizables (fase 3).
3. (Histórico de la fase 2; ya resuelto en las fases 3 y 5 para personajes) `effects.json`, `summons.json` y `scripts/` se rechazaban hasta que existieran sus fases; no hay migraciones de esquema (solo la versión `/1`).
4. Sin firma ni verificación de autoría; el hash garantiza integridad, no procedencia.
5. Catálogo elemental aún abierto (cualquier identificador válido) y sin evaluación de costes (fase 6; cada importación avisa).
6. `SchemaValidator` implementa un subconjunto de JSON Schema (documentado); herramientas externas pueden validar con los mismos archivos, pero la validación semántica adicional solo la hace el motor.

## Fase 1 — qué se verificó
- Reloj ATB en tiempo virtual entero, excedente conservado, empates configurables, SPD ≤ 0, suspensión, eventos temporizados, previsión.
- Fórmulas de daño/curación/impacto/crítico, elementos, penetración, redondeo; criterio de aceptación 19.1 (200 vs DEF 100 = 100).
- Pipeline por eventos (interceptores trazables), RNG propio reproducible, huella de registro, paridad de trazas, reproducción entre procesos distintos.
- Victoria, empates, límites, abortos técnicos separados de resultados de combate.
- Seguridad: gramática de fórmulas sin `eval`, límites duros no superables por contenido, vista de IA sin filtraciones.
- Equipos/multi-entidad (3 FFA, 2v2), invocaciones que no cuentan para la victoria.

## Fase 1 — limitaciones conocidas y pendientes (honestas)
(Las de la fase 1 siguen vigentes salvo la del punto 5 parcialmente resuelta por D-036/D-037.)
1. **Determinismo PC ↔ Android no verificado** (solo Linux x86-64). Riesgo: aritmética en `float`; mitigado por tiempo/iniciativa enteros. Siguiente paso: ejecutar el golden en dispositivo.
2. **Android**: el APK exporta y firma, pero no se ha ejecutado en dispositivo/emulador.
3. **Rendimiento** (D-028): ≈ 33 duelos/s en traza reducida, ≈ 100 µs/evento (2 vCPU, GDScript); el hash JSON+SHA-256 es ≈ 27 % del coste y `Ruleset.get_path_value` otro tanto. Candidatos de optimización antes de la fase 7: cachear valores del reglamento en campos tipados, hash incremental más barato, evitar `effective_map()` por decisión. No hay objetivo fijado (PROJECT.md §15).
4. Sin cooldowns, usos, cargas, estados, duraciones, reacciones y acciones gratuitas reales, artefacto, transformaciones, invocación dinámica, restauración temporal, escudos/bloqueo/absorción: **fase 3** (hay puntos de extensión y tipos reservados en `EventTypes`).
5. Catálogo elemental abierto (cualquier cadena); sin validación contra un catálogo configurable todavía.
6. Reglas provisionales de D-008…D-018 sujetas a revisión del responsable del diseño.
7. `ai.failure_policy` y `victory.simultaneous_death` solo admiten un valor (`wait`, `draw`).
8. Vista de IA: `statuses` siempre vacío hasta la fase 3.
9. `CombatEngine` no se puede reiniciar: cada combate usa una instancia nueva (diseño intencionado).
