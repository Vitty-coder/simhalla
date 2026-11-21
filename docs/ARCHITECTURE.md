# ARCHITECTURE — Simhalla

Estado: **fases 1 (núcleo ATB), 2 (contenido) y 3 (habilidades y eventos) completadas**; la fase 3 se amplía con incrementos futuros solo para lo listado en `ROADMAP.md`. Este documento describe lo
**realmente implementado**; las capas futuras están marcadas como tales.

## 1. Principios

1. **Núcleo sin UI.** Todo el motor son clases `RefCounted` (sin `Node`, sin
   `SceneTree`, sin `_process`). No depende de framerate, reloj de pared ni red.
2. **Datos, no clases por personaje.** El comportamiento sale de estadísticas,
   habilidades declarativas, recursos, etiquetas e IA descritas en JSON.
3. **Todo cambio pasa por el motor.** Las operaciones, la IA y (en el futuro) los
   scripts nunca mutan HP/recursos directamente: llaman a `CombatEngine`, que
   valida, emite eventos interceptables y registra.
4. **Determinismo.** Tiempo e iniciativa enteros, RNG propio con flujos con nombre,
   orden total estable de eventos, huella SHA-256 del registro.
5. **Reglamento ≠ equilibrio.** El reglamento (`Ruleset`) define qué ocurre en
   combate; el perfil (`BalanceProfile`) define estadísticas base/costes. Ambos
   son datos versionables fuera del motor.

## 2. Capas y módulos

| Capa (PROJECT.md §2) | Directorio | Estado |
|---|---|---|
| Motor universal | `src/combat`, `src/events`, `src/effects`, `src/domain` | **Fase 1** |
| Reglamento global | `src/domain/ruleset.gd` + `content/rulesets/` | **Fase 1** |
| Perfil de equilibrio | `src/balance`, `content/balance/` | Mínimo (stats base); PC en fase 6 |
| Contenido importable | `src/content`, `schemas/`, `content/packages/` | **Fase 2** (paquetes, esquemas, dependencias, biblioteca) |
| IA de comportamiento | `src/ai` | Prioridades, puntuaciones, máquina de estados, memoria, predicción, política de reacciones (fase 4); scripts: fase 5 |
| Almacenamiento | `src/storage` (`AppStorage`, `VersionedStore`, `RecordStore`, `BundleIO`) | **Fase 9** (ver `UI.md`) |
| Aplicación (casos de uso) | `src/application` (`AppController`, `LibraryModel`, `ImportModel`, `DuelSetupModel`, `ViewerModel`, `BatchModel`, `ReportsModel`, `RulesModel`, `EventText`, `PortraitProvider`) | **Fase 9** |
| Interfaz | `src/ui` (`MainUI`, pantallas, widgets, `LocaleService`) | **Fase 9** (solo presenta; no ejecuta reglas) |
| Informes y estadística | `src/analytics` (`Stats`), `src/reports` (`IndividualReport`, `BatchReport`, `ReportDocument`, renderizadores, `ReportExporter`, `ReportVerifier`, `DebugInspector`) | **Fase 8** (ver `REPORTS.md`) |
| Simulación y lotes | `src/simulation` (`SimulationSession`, `BatchPlan`, `BatchModes`, `BatchRunner`, `BatchAccumulator`, `BatchResult`) | **Fase 7** (ver `SIMULATION.md`) |
| Equilibrio / PC | `src/balance` (`BalanceProfile`, `CostRules`, `BalanceEvaluator`, `BalanceReport`) | **Fase 6** (valoración automática, modos libre/reglamentado) |
| Scripts aislados | `src/scripting` (`ScriptCompiler`, `ScriptInterpreter`, `ScriptApi`, `EffectHost`, `AiHost`, `ScriptRunner`, `ScriptLimits`) + `ScriptOperation`, `ScriptAI` | **Fase 5** (SimScript v1) |
| Aplicación | `src/application` | `DuelRunner`; resto fases 7–9 |
| Simulación/lotes, analítica, informes, almacenamiento, UI | `src/simulation`, `analytics`, `reports`, `storage`, `ui` | Fases 7–9 |

Dependencias permitidas (flecha = “puede usar”):

```
application ─► combat ─► effects ─► domain
     │            │         ▲
     │            ├──────► events
     │            └──────► ai ──► (vista de solo lectura, sin referencias al motor)
     └─► content ─► domain, ai, balance
```
`domain` no depende de nadie salvo de sí mismo (excepciones menores:
`CombatEntity` referencia `AIController`/`AbilityDef`). La UI futura solo
consumirá `application` y resultados.

## 3. Mapa de clases (fase 1)

**domain/** — `Rng` (SplitMix64), `RngService` (flujos con nombre), `Rounding`,
`Formula` (expresiones seguras), `StatSet`/`StatModifier`, `ResourceState`,
`AbilityDef`, `CombatEntity`, `Ruleset`.

**events/** — `EventTypes` (catálogo), `CombatEvent` (+fase INFO/PRE/POST),
`EventDispatcher` (interceptores/observadores con prioridad), `EventLog`
(registro append-only + hash).

**combat/** — `CombatEngine` (bucle y API), `AtbScheduler` (reloj, desempates,
eventos temporizados, previsión), `TurnState`, `ActionValidator`,
`ActionResolver`, `VictoryCondition` → `LastTeamStanding`, `LimitCondition`,
`CombatResult`, `CombatStats`.

**effects/** — `EffectOperation` (contrato), `OperationRegistry` (punto de
extensión), `DamageCalculator` (cálculo puro), `FormulaContext`, `ActionContext` y
las 20 operaciones: `damage`, `heal`, `apply/remove/extend/transfer_status`,
`modify_resource/initiative/cooldown`, `summon`, `record/restore_state`,
`delayed_effect`, `repeat/copy_action`, `emit_event`, `metric`.

**Fase 3 (en `combat/` y `domain/`):** `Duration`, `StatusDef`, `StatusInstance`,
`StatusCatalog` (dominio); `StatusService` (estados, duraciones, periódicos, formas),
`DefenseService` (escudos/inmunidad/reflejo/prevención), `TriggerService` (reacciones,
automáticas), `AbilityRuntime` (cooldown/usos/cargas/bloqueos), `ConditionEvaluator`.
El motor ofrece los puntos únicos `deliver_damage`, `direct_heal`, `change_resource`,
`change_initiative`, `add_entity`/`despawn`, `add_ability`/`remove_ability`,
`begin_channel`/`interrupt_channel`.

**ai/** — `AIController` (contrato), `AIDecision` (+ `memory_ops`), `PassiveAI`, `PriorityListAI`,
`ScoredAI`, `StateMachineAI`, `BehaviorTreeAI`, `OverlayAI`, `AIFactory`, `ViewBuilder` (vista limitada), `AIConditions`
(condiciones declarativas), `AIPredictor` (estimaciones sobre la vista), `AIMemory`
(observaciones y operaciones validadas), `AIReactionPolicy` (aceptar/declinar reacciones).

**content/** — `PackageSource` (lectura segura carpeta/ZIP), `SchemaValidator`,
`SemVer`, `PackageImporter` (validación en capas) → `ImportReport`,
`ContentLibrary` (versiones inmutables + huella + integridad), `EntityComposer`
(fusiona personaje + dependencias), `EntityFactory` (validación técnica y
construcción; incluye artefacto). **balance/** — `BalanceProfile`.
**application/** — `DuelRunner` (acepta ficheros o paquetes de la biblioteca).

### Flujo de importación (fase 2)
```
PackageImporter.import_package(ruta)
  PackageSource.read        rutas/tamaños/enlaces/bombas ZIP  ─► ficheros en memoria (sin ejecutar nada)
  JSON + SchemaValidator    schemas/*.schema.json (propiedades desconocidas = error)
  coherencia                manifiesto, dependencias (existen, tipo, versión), imports, archivos permitidos
  EntityComposer + EntityFactory   misma validación técnica que en combate
  ContentLibrary.store      atómico, id@version inmutable, huella SHA-256
DuelRunner ─► ContentLibrary.build_entity ─► recalcula huella ─► CombatEntity (content_ref en combat_started)
```

## 4. Flujo de ejecución de un combate

```
DuelRunner.run(config)
  └─ carga Ruleset, BalanceProfile, entidades (EntityFactory) ─► CombatEngine.setup(...)
CombatEngine.run()  ==  while step(): pass
  step():
    ¿sin turno activo?  ─► _begin_next_turn():
         evaluar límites (turn_boundary)
         plan = scheduler.plan()  ─ siguiente instante relevante (turno | evento temporizado)
         avanzar reloj (TIME_ADVANCED), disparar eventos temporizados / elegir entidad lista
         _begin_turn(): TURN_STARTED (PRE; cancelar = turno omitido)
    ¿turno activo?      ─► _process_decision():
         ViewBuilder.build ─► AIController.decide ─► ACTION_SELECTED
         WAIT ─► fin de turno           │  ActionValidator.validate (siempre revalida)
         ActionResolver.resolve:
            ACTION_STARTED (PRE) ─► pagar costes ─► operaciones (damage/heal…) ─► ACTION_RESOLVED
              cada daño: HIT/MISS/CRIT ─► DAMAGE_PRE (PRE) ─► DAMAGE_DEALT ─► HP_CHANGED ─► muerte (DEATH_PRE/DEATH)
         evaluar victoria (after_action)  ─► fin de turno si no quedan acciones legales
  al terminar: COMBAT_ENDED + CombatResult (con huella, semilla, versión del motor y hash del reglamento)
```
`step()` avanza **una unidad de progreso** (buscar turno *o* resolver una
decisión), pensado para que el visor de la fase 9 avance acción a acción.

## 5. Puntos de extensión (cómo se añadirán las fases siguientes)

| Necesidad futura | Dónde se engancha | Sin tocar |
|---|---|---|
| Nuevas operaciones (p. ej. invertir/propagar estados) | `OperationRegistry.register(EffectOperation)` + `allowed_keys()`/`validate()` + ampliar `schemas/common.schema.json` | `CombatEngine` |
| Nuevos archivos de paquete (`effects.json`, `summons.json`, `scripts/`) | `PackageImporter.UNSUPPORTED/ALLOWED_BY_TYPE` + esquema nuevo | biblioteca |
| Escudos, bloqueo, absorción, reflejo | interceptores de `DAMAGE_PRE`/`HEAL_PRE` y nuevas fases en `DamageCalculator` | operaciones existentes |
| Estados con duración | observadores de `TURN_STARTED/ENDED`, `TIME_ADVANCED` + `scheduler.schedule()` | scheduler |
| Reacciones y acciones gratuitas | suscriptores de eventos POST que proponen acciones; `AbilityDef.ActionType` ya distingue main/free/reaction | validador |
| Cooldowns/usos/cargas | `ActionValidator` (restricciones) + estado en `CombatEntity` | resolver |
| Transformaciones | operaciones que sustituyen `StatSet`/habilidades/IA con eventos | motor |
| Invocaciones | `CombatEngine` ya admite N entidades, equipos, `owner_id`, `counts_for_victory` | victoria |
| Condiciones de victoria alternativas | nuevas `VictoryCondition` en `engine.end_conditions` | bucle |
| Nuevas funciones de la API de scripts | `ScriptApi.CATALOG` (+ versión) + implementación en `EffectHost`/`AiHost` | intérprete, motor |
| Árboles de comportamiento / IA por scripts | nuevas subclases de `AIController` registradas en `AIFactory`; `ViewBuilder` entrega vista copiada | motor |
| Lotes y reproducción | `simulation` reutiliza `CombatEngine`; `snapshot()` y `EventLog` ya existen | núcleo |

## 6. Seguridad y límites (ya activos)

- Importación: ver `PACKAGES.md` §4 (rutas, ZIP, tamaños, enlaces, assets; scripts solo compilados).
- Scripts (SimScript): lenguaje propio sin acceso al anfitrión; solo datos cruzan la frontera; API de lista permitida y versionada; presupuesto de instrucciones/profundidad/memoria/operaciones (`scripting.*`, techos duros); errores de efecto abortan con diagnóstico, errores de IA caen a espera. Ver `SCRIPTING_API.md`.
- Formulas: gramática propia, sin `eval`; longitud ≤ 512, ≤ 256 nodos, profundidad ≤ 32; variables solo `caster.*`/`target.*` autorizadas.
- Motor: máximo de eventos (200 000 por defecto, techo duro 5 000 000), profundidad de eventos (32; techo 64), acciones por turno (20; techo 100). El contenido/reglamento **no puede superar los techos duros** (`Ruleset.HARD_*`).
- Errores técnicos ⇒ `outcome = aborted` con `error {code,message}`; nunca derrota/empate silencioso.
- La IA recibe copias (`ViewBuilder`) y solo propone; el motor revalida.

## 7. Memoria y ciclo de vida
`CombatEngine` y sus servicios se referencian mutuamente (y mediante closures). Al terminar un combate el motor llama a `dispose()` (vacía suscripciones y temporizadores) para que la memoria se libere; el registro, las entidades y el resultado siguen disponibles. Cada combate usa una instancia nueva.
