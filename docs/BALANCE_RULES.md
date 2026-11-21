# BALANCE_RULES — Equilibrio y puntos de creación (PC) implementados (fase 6)

Los PC **solo regulan la construcción** del PJ; son independientes de los costes de uso en combate (recursos, cooldowns). El cálculo es **automático**, sale **solo** de las reglas de un perfil externo y versionado (`content/balance/*.json`) y es **trazable**. El creador no puede aportar costes ni créditos: cualquier campo no definido (`creation_cost`, `pc`, `credits`, `disadvantages`…) se rechaza al construir la entidad.

> **Todo perfil incluido es ILUSTRATIVO** (`illustrative: true`): `reference_costs` existe para probar el valorador. Sus cifras no son un equilibrio definitivo ni salen de simulaciones; los informes que lo usan se etiquetan **PRUEBA**. Las ecuaciones reales se ajustarán empíricamente en perfiles futuros sin tocar el motor.

## 1. Contrato
```
creation_cost = Σ items contados  = stat_adjustments + componentes_comprados + otros_costes − créditos_aplicados
remaining     = budget − creation_cost
```
- **Estadísticas base: gratis** (las del perfil). Se cobra la diferencia; por debajo de la base es **crédito** (× `credit_factor`).
- **Ataque básico universal e IA: gratuitos** (el perfil no puede cambiarlo: `costs.free.ai/basic_attack` deben ser `true`). Potenciar el ataque (p. ej. ATK) sí se valora. Una IA programada no puede dar capacidades mecánicas (no puede mutar el combate; ver `SCRIPTING_API.md`).
- **Sin recargo por sinergias:** el coste es la suma de las partes.
- **Referencias no duplicadas:** la definición de un estado se cobra **una vez** por entidad aunque la referencien varias habilidades (cada aplicación paga lo suyo); las instancias concedidas por otra capacidad (invocaciones) se valoran con el alcance de esa capacidad (la plantilla se valora como un PJ y cada operación paga por instancia).
- **Desventajas = créditos automáticos**, nunca declarados: estadísticas bajo la base, modificadores pasivos negativos, vulnerabilidades elementales (`ELEM_RES` negativa) y daño autoinfligido (`weaknesses.self_damage`). Las **restricciones** (cooldown, coste, usos, requisitos, canalización, probabilidad/límite de disparo) abaratan la habilidad vía la fórmula `ability`. Los créditos totales se limitan con `credit_cap.fraction_of_gross` (ajuste visible como item `credit_cap`).
- Informe: cada item lleva `id`, `kind`, `origin` (`character`, `artifact:<id>`, `native`…), `rule`, `facts`, `formula`, importe y `parent`. Las operaciones de una habilidad son **informativas** (no se cuentan dos veces); el importe cuenta en la habilidad. El desglose suma exactamente `creation_cost`.
- **Igualdad de PC no implica igualdad de poder.** La evaluación empírica (resultados de combate) es una fase aparte (fase 7+).

## 2. Modos
| Modo | Comportamiento |
|---|---|
| `free` | Exige validez técnica (se construye y se ensaya en un motor real). Exceder el presupuesto, componentes no evaluables o un perfil sin costes **solo avisan**. |
| `regulated` | Además exige: **dentro del presupuesto** (`[presupuesto]`, requiere presupuesto: `budget` o `default_budget`), **todo evaluable** (`[no_evaluable]`) y perfil con costes. Los incumplimientos son errores (`valid() == false`). |
Validez **técnica** (`technical_errors`: esquema, tipos, referencias, fórmulas, scripts seguros, perfil inválido) bloquea en ambos modos y no produce valoración.

## 3. Componentes no evaluables (sin precio inventado)
Se listan en `unevaluable` con motivo y no suman: operaciones sin regla en el perfil, estadísticas sin regla, modificadores `min`/`max`, fórmulas no resolubles, plantillas de invocación con componentes no evaluables, **scripts** con poder mecánico sin contrato verificable. Scripts:
- Sin llamadas con poder (`deal_damage`, `heal`, `apply_status`, `remove_status`, `modify_resource`): coste 0 (`script.sin_poder_mecanico`).
- Con **`contract`** en el efecto (`{"max_damage": N, "max_heal": M}`): el **motor hace cumplir** los topes por ejecución (superarlos = `script_error`) y se valoran como el daño/curación declarativos equivalentes de **peor caso** (siempre impacta, crítico, penetración total, 1 objetivo). El contrato debe cubrir lo que el script usa (`deal_damage`↔`max_damage`, `heal`↔`max_heal`); `apply_status`/`remove_status`/`modify_resource` no se pueden cubrir (el script es no evaluable sin contrato; con contrato es error de construcción).
- Si no hay contrato y hay poder mecánico: no evaluable. En modo reglamentado queda fuera; en libre se ejecuta si es técnicamente válido.

## 4. Formato del perfil (`schemas/balance.schema.json`, `simhalla.balance/1`)
Claves: `id`, `version`, `illustrative`, `description`, `base_stats`, `budgets` (`{id: {points, label}}`; 500/1000/2000/5000 son **ejemplos**), `default_budget`, `rounding` (`{mode: none|round|floor|ceil|trunc, decimals 0..6}`, se aplica a cada item), `credit_cap`, `costs`.

`costs` = reglas con `{"formula": "…"}` en la **gramática segura** (`+ - * / % ^`, `min max clamp abs floor ceil round sqrt`; sin `eval`) sobre **hechos nombrados** (un hecho no disponible para esa regla es error al cargar):
| Regla | Hechos |
|---|---|
| `stats.default / rules.<STAT> / patterns."ELEM_RES.*" / custom` | `delta, base, value` (+ `credit_factor` 0..1) |
| `operations.<tipo>` | comunes: `chance, targets, on_caster`; `damage`: `power, components, pen_pct, pen_flat, elem_pen, always_hit, can_crit, crit_bonus, true_share`; `heal`: `power, can_crit`; `apply_status`: `stacks, duration, magnitude`; `remove_status`: `count, force, by_tags`; `extend_status`: `amount`; `transfer_status`: `count, steal, give`; `invert_status`/`propagate_status`: `count`; `modify_resource`: `amount, is_max, is_set`; `modify_initiative`: `amount, extra_turn, steal`; `modify_cooldown`: `amount, reset, all`; `summon`: `count, lifespan, template_cost, inherit_pct`; `record_state`: `what_count`; `restore_state`: `what_count, consume`; `delayed_effect`: `delay, inner`; `repeat_action`: `times`; `copy_action`: — |
| `ability` (+`min`) | `effects, has_effects, cooldown, resource_cost, resource_cost_ratio, limited, uses_per_combat, uses_per_turn, charges, cast_time, requires, is_free, is_reaction, is_triggered, trigger_chance, trigger_limit, target_count` |
| `resource` | `initial, max, min, regen` |
| `status_def` | `inner, modifiers, flags, defense, periodic, has_form, max_stacks, beneficial` |
| `weaknesses.self_damage` | `power` |
| `free` | `basic_attack: true`, `ai: true`, `operations: [emit_event, metric, …]` (gratuitas) |
`power` de daño/curación = fórmulas del propio contenido evaluadas con las estadísticas del PJ (con afinidad elemental propia) y un **objetivo de referencia con las estadísticas base del perfil**. `targets`: `target_count` de la habilidad; `all_*` = equipo de referencia de 3 (supuesto documentado, `BalanceEvaluator.REFERENCE_TEAM_SIZE`); `caster`/`random_*` = 1. `duration` permanente = 999. Modificadores de estados aplicados a otros se valoran por valor absoluto (poder ofensivo, no desventaja).

## 5. Uso
- **API:** `BalanceEvaluator.evaluate(data, perfil, reglamento, registro, {mode, budget})` → `BalanceReport` (`to_dict()`, `to_markdown()`, `valid()`, `within_budget()`, `evaluable()`).
- **CLI:** `godot --headless --path . --script res://tools/balance_tool.gd -- <entidad.json | carpeta/zip | pkg:id[@ver]> [--profile p] [--mode free|regulated] [--budget id] [--json|--md]` (salida 2 si no es válido según el modo).
- **Importador:** `PackageImporter.balance = {"profile": BalanceProfile, "mode", "budget"}` → `ImportReport.balance`; en reglamentado se rechaza con `[equilibrio]`.
- **Combate:** `DuelRunner` acepta `"balance": {"profile": ruta, "mode", "budget"}`; en reglamentado un PJ inválido impide el combate; devuelve `balance` (informes).

## 6. Límites conocidos
Cifras del perfil sin ajustar empíricamente (D-076); la valoración es estructural (sin simular); sin migración de perfiles entre versiones ni comparación automática de perfiles; `targets` y objetivo de referencia son supuestos; los estados con fórmulas que dependan de contexto dinámico se valoran con pilas 1 y magnitud 1; los scripts con contrato se valoran en peor caso (puede encarecer scripts muy conservadores); sin presupuesto por categorías (solo global, como pide la spec).

## 6. Calibración empírica de costes (D-118) y valores por defecto (D-119)
`BalanceCalibrator` **no inventa cifras**: parte de un perfil con costes, valora a cada contendiente, los enfrenta en un torneo todos-contra-todos (ambos lados, semillas derivadas, determinista) y estima cuánto **poder** (log-odds suavizado de la puntuación) da cada punto de coste en cada categoría (`stats`, `abilities`, `statuses`, `resources`; `other` no se escala). Mediante regresión ridge (contracción hacia la pendiente global del coste total) obtiene un **multiplicador por categoría**, acotado a [0,5; 2] y renormalizado para conservar el coste medio ponderado (los presupuestos siguen significando lo mismo). La **propuesta** es el perfil con cada fórmula de la categoría envuelta en `(fórmula) * m`, versión parche siguiente, id `<perfil>_cal`, **siempre `illustrative: true`**, con la procedencia (contendientes, repeticiones, semilla, perfil base) en su descripción, y se re-valora para informar la mejora de la correlación de Spearman coste–poder.
- **Uso:** `godot --headless --path . --script res://tools/calibrate_tool.gd -- <entidad.json|pkg:id>… (≥ 4) [--profile p] [--reps 10] [--seed 1] [--workers 0] [--out propuesta.json] [--json]`, o `RulesModel.calibrate(paquetes, opts)` y `save_calibrated(resultado)` (guarda como perfil versionado y lo anota en el historial). **Nunca se activa sola**: una persona revisa y elige el perfil activo.
- **Fiabilidad:** avisa con < 6 contendientes o < 10 repeticiones; no propone nada si el coste total no predice el poder, si todos cuestan lo mismo o si no hay categorías con varianza. Mide correlación **en ese conjunto**, no equilibrio universal; con pocos personajes la propuesta es solo orientativa. Rendimiento: ≈ 25 duelos/s (300 duelos ≈ 12 s en el equipo de pruebas).
- **Valores por defecto actuales** (ajustes iniciales, cambiables): perfil `builtin/reference_costs` (**ILUSTRATIVO**, etiquetado PRUEBA en los informes), presupuesto `standard` (1000 puntos, «ejemplo no definitivo»), modo **libre**. Siguen siendo provisionales hasta que se calibren con un conjunto real de contenido y se decida un perfil definitivo (§21).
- **Interfaz:** sección «Calibración empírica de costes» de la pantalla **Reglas y equilibrio**: se eligen ≥ 4 personajes de la biblioteca y las repeticiones; el torneo se ejecuta **por tramos** (la interfaz no se congela) con progreso y **cancelación**; se muestran avisos, tabla coste/puntuación/poder/veredicto, multiplicadores por categoría y la mejora de Spearman; «Guardar propuesta como perfil» la almacena versionada e ilustrativa. Los duelos usan la biblioteca, el reglamento y el perfil de la aplicación.
