# COMBAT_RULES — Reglamento de combate implementado (fases 1–3)

Todo lo marcado **[prov.]** es una decisión inicial **provisional** de la fase 1
para un punto que PROJECT.md §21 dejaba abierto. Está externalizado en el
reglamento (`content/rulesets/default_ruleset.json`) cuando procede y
registrado en `docs/DECISIONS.md`. **No son reglas de equilibrio definitivas.**

## 1. Unidades y representación

| Magnitud | Representación interna | Nota |
|---|---|---|
| Tiempo virtual | entero en microunidades (`Ruleset.TIME_SCALE = 1 000 000`) | en informes/UI se muestra en unidades |
| Iniciativa | entero en microunidades | umbral por defecto 1000 u. |
| Estadísticas, HP, daño | `float` (doble precisión) | redondeo configurable en puntos definidos |
| Probabilidades y multiplicadores | normalizados: ACC 1.0 = 100 %, EVA 0.10 = 10 %, CRIT_DMG 1.5 = ×1,5 | la UI los mostrará como %. |

Catálogo de estadísticas base (valores gratuitos del `BalanceProfile`, ilustrativos):
`HP` (máx.) 1000, `ATK` 100, `MAG` 100, `DEF` 100, `RES` 100, `SPD` 100, `ACC` 1.0,
`EVA` 0.10, `CRIT` 0.10, `CRIT_DMG` 1.5, `HEAL_REC` 1.0; `ELEM_AFF.<elem>` y
`ELEM_RES.<elem>` valen 0 si no se declaran. Cualquier otro identificador es una
estadística personalizada válida. La vida actual (`hp`) no es una estadística.

## 2. ATB

- `delta_initiative = SPD_efectiva * delta_tiempo`. SPD ≤ 0 no gana iniciativa **[prov.]** (política `clamp_zero`; no resta).
- Al alcanzar el umbral (`atb.initiative_threshold`, 1000) la entidad está *lista*. Al empezar su turno se descuenta el umbral y **se conserva el excedente**.
- El motor salta al siguiente instante relevante (turno o evento temporizado); no simula fotogramas vacíos. `time_until_ready = ceil(restante / SPD)` en microunidades.
- La iniciativa acumulada está al día antes de cualquier cambio de SPD porque el reloj siempre se adelanta al instante del evento **antes** de procesarlo (hay prueba).
- **Empates** (varias entidades listas): criterios en orden, configurables (`atb.tie_break`): `initiative_excess_desc` (más excedente primero), `spd_desc`, `slot_asc` (orden de alta), `random` (flujo `tiebreak`, reproducible). Siempre hay un orden total final por `slot`. Por defecto: excedente → SPD → slot **[prov.]**.
- Varias entidades listas en el mismo instante actúan una tras otra sin avanzar el reloj. Una entidad con iniciativa ≥ 2×umbral actúa varias veces seguidas.
- Evento temporizado y turno en el mismo instante: el evento primero (`atb.timed_events_first`, true) **[prov.]**.
- Iniciativa suspendida (`initiative_suspended`) = no gana.

## 3. Turno

- Presupuesto por turno: 1 acción **principal** (`turn.main_actions_per_turn`) y acciones **gratuitas** sin cuota universal (los límites los fijará cada habilidad; fase 3). Las **reacciones** no se eligen durante el turno propio (fase 3).
- Máx. de acciones por turno 20 (límite técnico, techo duro 100).
- **Espera/pasar** (`AIDecision.wait`) es siempre válida y **termina el turno**.
- El turno termina automáticamente cuando no quedan acciones legales **[prov.]** (motivo `no_more_actions`).
- Decisión inválida de la IA (habilidad inexistente, objetivo inválido, sin hueco, coste impagable…): eventos `action_rejected` + `ai_fallback` y se aplica la política `wait` **[prov.]**. La IA nunca ejecuta una capacidad que el PJ no tiene.
- `turn_started` es interceptable: cancelarlo omite el turno (`turn_skipped`); el turno consume la iniciativa igualmente.

## 4. Acciones: orden de resolución **[prov.]**

1. La IA propone (vista limitada de solo lectura).
2. El motor valida (siempre).
3. `action_started` (PRE). Si un interceptor lo cancela → `action_interrupted`: **el hueco de acción se consume pero no se pagan costes**.
4. Se pagan los costes (política *pagar al comprometer*; evento `resource_changed`).
5. Cada efecto en orden, mediante su operación registrada.
6. `action_resolved`.
7. Se evalúa la victoria (**punto seguro**: ya resueltas muertes y reacciones).

Cooldowns, usos, cargas, estados requeridos y procs llegan con la fase 3.

## 5. Daño

Tres tipos: `physical` (mitiga DEF), `magical` (mitiga RES), `true` (ignora DEF y RES; sigue sujeto a resistencia elemental). Tipo y elemento son independientes. Una acción puede tener varios componentes.

### 5.1 Tiradas

- `P(impacto) = clamp(ACC_atacante − EVA_objetivo, hit.min_chance, hit.max_chance)` (por defecto [0, 1]) **[prov.]**. `always_hit` salta la comprobación.
- Crítico solo tras impacto y si el efecto lo permite (`can_crit`, por defecto true en daño y false en curación): `P = clamp(CRIT + crit_bonus, 0, 1)`; multiplica por `CRIT_DMG`.
- Se consume siempre una tirada de impacto (salvo `always_hit`) y, con impacto y `can_crit`, una de crítico: las secuencias son estables.
- Alcance de las tiradas (`damage.roll_scope`): `per_action` (por defecto): una tirada de impacto/crítico por (acción, objetivo), compartida por todos los componentes y efectos de daño de la acción; `per_component`: una por componente **[prov.]**.
- Flujos RNG independientes: `hit`, `crit`, `tiebreak`. Sin variación aleatoria de daño.

### 5.2 Cálculo (`DamageCalculator.compute`)

```
1  base           = fórmula del componente (negativa → 0)
2  si crítico:      × CRIT_DMG
3  si hay elemento: × max(1 + ELEM_AFF.<elem> del atacante, 0)
4  mitigación (no para "true"):
       def_ef = max( DEF·(1 − pen_pct) − pen_flat , damage.min_effective_defense )
       valor  = valor × 100 / (100 + def_ef)            # 200 vs DEF 100 → 100
5  si hay elemento: res = clamp(ELEM_RES.<elem> − elem_pen, min, max)  # [-1, 1] por defecto
       valor  = valor × (1 − res)       # res ≥ 1: inmunidad; res < 0: vulnerabilidad
6  redondeo (damage.rounding) y mínimo 0
```
- Penetración: porcentual primero, plana después **[prov.]**; se declara por componente (`pen_pct` 0..1, `pen_flat`, `elem_pen`), no es estadística base.
- Defensa efectiva negativa: se acota a `min_effective_defense` (0) **[prov.]**; el reglamento rechaza valores ≤ −100 (evita división por cero).
- Absorción elemental (conversión a curación), escudos, bloqueo, parada, reducción plana/porcentual, redirección, conversión: fase 3, como interceptores de `damage_pre`.
- Redondeo por defecto: `round` (mitad lejos de cero), 0 decimales; modos `none|round|floor|ceil|trunc`, 0–9 decimales **[prov.]**.

### 5.3 Eventos y trazabilidad de un golpe

`hit|miss` (con `chance` y `roll`) → `crit` → `damage_pre` (**PRE**: interceptores pueden modificar `amount` o cancelar) → `damage_dealt` (`intended`, `premitigation`, `mitigated`, `amount`, `applied`, `overkill`, `hp_before`, `hp_after`) → `hp_changed` → `death_pre`/`death`.
Se separan **daño intentado** (`intended`), **premitigación**, **efectivo** (`amount`), **aplicado** (limitado a la vida restante) y **sobreexceso** (`overkill`).

## 6. Curación

`curación_efectiva = redondeo(raw × HEAL_REC_receptor)`; `aplicada = min(efectiva, vida faltante)`; `overheal` = resto. `HEAL_REC = 0` bloquea la curación. Crítico solo si `can_crit`. Eventos `heal_pre` (PRE) y `heal_done`.

## 7. Muerte y victoria

- Una entidad con HP 0 se evalúa **inmediatamente** tras aplicar el daño **[prov.]**: `death_pre` (PRE) → si un interceptor cancela (prevención), sobrevive con `damage.survive_hp` (1) → si no, `death`.
- Objetivos ya muertos se **revalidan**: los componentes siguientes de una acción multigolpe no se aplican (`target_skipped`/omisión).
- **Victoria estándar:** queda un único equipo con entidades vivas que cuentan para la victoria (`counts_for_victory`; las invocaciones auxiliares pueden no contar). Se evalúa **tras** resolver la acción completa.
- **Muerte simultánea** (nadie queda): empate `simultaneous_death`.
- **Sin actor posible** (todas con SPD ≤ 0, sin eventos pendientes): empate `no_actor_can_act` (`kind: stalemate`).

## 8. Límites del combate (finales reglamentarios, no errores)

| Límite (`victory.limits`) | Defecto | Cuándo se evalúa |
|---|---|---|
| `max_virtual_time` | 10 000 u. | al planificar el siguiente instante |
| `max_turns` | 1000 | al empezar a buscar turno (se juegan exactamente N turnos) |
| `max_actions` | 5000 | antes de cada decisión |
| `stagnation_turns` | 50 | turnos seguidos sin ningún cambio de HP |

Al alcanzarse: `victory.limit_resolution` = `draw` (por defecto) o `highest_hp_ratio` (gana el equipo con mayor fracción de vida; empate exacto = empate). Resultado `kind: limit`, evento `limit_reached`.

## 9. Fin técnico (≠ derrota ni empate)

`outcome = aborted` con `error {code, message}` y `kind` `technical|cancelled`: exceso de eventos (`max_events`), profundidad (`max_event_depth`), fórmula con error en tiempo de ejecución (`formula_error`), operación desconocida, cancelación del usuario.

## 10. Reproducibilidad

Mismo motor + mismo reglamento + mismos datos + misma semilla ⇒ misma secuencia de eventos y misma huella (`CombatResult.log_hash`, SHA-256 sobre JSON canónico de todos los eventos). La huella no depende del nivel de traza (`full`/`reduced`). El resultado incluye semilla, versión del motor y `ruleset {id, version, hash}`. Cambiar reglas o contenido **cambia** la huella (la semilla igual no garantiza el mismo combate si cambian las reglas). Verificado entre procesos distintos (`tests/golden`).
Determinismo multiplataforma (PC/Android): **objetivo no verificado todavía** (ver ROADMAP).

## 11. Fase 3 — estados, restricciones, reacciones, canalización, invocaciones, formas, temporalidad

Todo **[prov.]** salvo indicación; decisiones D-039…D-050 en `DECISIONS.md`.

### 11.1 Duraciones (estados, cooldowns, vida de invocaciones, recargas)
Unidades: `target_turns`, `caster_turns`, `global_actions`, `time`, `events` (con filtro), `permanent`. Convención: **los estados decrementan al final del turno** de la entidad correspondiente y el turno en que se aplicaron no cuenta (un estado de 2 turnos afecta a los 2 turnos completos siguientes); un turno omitido (aturdimiento) también cuenta. **Los cooldowns decrementan al inicio del turno del dueño** (cooldown 3 = reutilizable 3 turnos después). `global_actions`: tras cada acción resuelta (la que lo aplicó no cuenta). `time`: caducan exactamente en `t + amount` (evento temporizado). Efectos periódicos: `turn_start`/`turn_end` del afectado; en `turn_end` el efecto ocurre **antes** de decrementar la duración.

### 11.2 Aplicación de estados y políticas
Orden: lanzador/afectado vivos → inmunidad (`immune_status_tags`) → política de reaplicación → `status_applied` (pre, cancelable) → instancia + modificadores + escudo/forma/suspensión → `on_apply` → `status_gained`. Políticas: ver `ABILITY_REFERENCE` §3. Los modificadores escalan con las pilas. Al morir una entidad se retiran todos sus estados (sin `on_expire`); `on_expire` solo en caducidad.

### 11.3 Restricciones de uso
Se comprueban al elegir (legalidad) y se **gastan al comprometer** la acción (tras `action_started`): coste, cooldown, uso por combate/turno, carga. Una acción interrumpida antes de comprometerse no gasta nada; **una canalización interrumpida no devuelve** el coste. Bloqueos de estados (`block_tags`, `block_action_types`) y provocación (`taunt`) afectan a la legalidad. La provocación restringe objetivos `enemy` salvo `ignore_taunt`.

### 11.4 Defensas nativas
Solo las concede un estado. Orden por estado (en orden de aplicación): inmunidad → absorción elemental (el daño se convierte en curación) → parada → bloqueo → reducción (% y luego plana) → escudo de absorción (se retira al agotarse). `reflect` devuelve daño verdadero (nunca se refleja el reflejo). `prevent_death` cancela `death_pre`, fija `survive_hp` y se consume. El daño intentado, premitigado, mitigado y efectivo permanecen separados en `damage_dealt`.

### 11.5 Reacciones, automáticas y golpe letal
Una habilidad con `trigger` se suscribe al evento; se evalúan `when`, restricciones, coste, `limit_per_turn` y `chance`; si procede se emite `reaction_triggered` y se resuelve como acción (paga costes, interrumpible, respeta cooldown). **Fuera del turno propio** no consumen hueco. **Golpe letal (D-043):** `damage_dealt` se notifica con la vida ya aplicada pero la entidad sigue "viva" hasta resolverse la muerte: puede reaccionar (incluso curarse y evitar morir) salvo que la reacción exija `self.hp > 0`. Las reacciones de un muerto solo ocurren con `while_dead` (p. ej. última palabra sobre `death`). Cadena máxima de reacciones: `safety.max_reaction_chain` (4).

### 11.6 Canalización
`cast_time` > 0: se paga y compromete al empezar; la iniciativa queda suspendida; el turno termina; a `t + cast_time` se resuelven los efectos (`channel_completed`). Se interrumpe por muerte, estados con `interrupt_channel` (aturdimiento) u otra interrupción si `interruptible` (muerte siempre). Los objetivos muertos al completarse se omiten.

### 11.7 Invocaciones
Entidades completas con barra ATB propia (empiezan en 0), mismo equipo, `owner_id`, no cuentan para la victoria salvo plantilla. Vida limitada opcional. Al morir/desaparecer el dueño desaparecen (`summons.on_owner_death`). Límites por invocador/global/profundidad → `limit_reached`, sin abortar.

### 11.8 Formas
Estado con bloque `form` (+ `group` para exclusividad): cambia estadísticas/afinidades vía modificadores, añade/quita habilidades y sustituye la IA; al terminar por cualquier motivo se restaura todo (`reverted`).

### 11.9 Temporalidad
`record_state`/`restore_state` cambian el estado con operaciones registradas (HP/recursos), son consumibles (no duplicables), no reviven y **no tocan el RNG**; el rebobinado del visor (fase 9) es otra cosa. `delayed_effect` programa efectos a `t + delay` sobre los mismos objetivos (muertos omitidos); la victoria se evalúa tras liberarse. `repeat_action`/`copy_action` ejecutan gratis (sin hueco, costes ni cooldown); profundidad máxima 3.

### 11.10 Iniciativa y recursos
`modify_initiative` (add/set/steal/extra_turn; nunca < 0), suspensión por estado/canalización (sin ganar ni actuar), regeneración de recursos al inicio del turno del dueño, `resource_limit` al tocar mínimo/máximo.

### 11.11 Cierre de la fase 3
- **Inversión (D-052):** invierte modificadores (flat/pct_add → signo contrario; mult → inverso) y periódicos (daño → curación por la suma de sus componentes; curación → daño verdadero); no toca defensas ni banderas; repetir deshace; el filtro `beneficial` cuenta al revés.
- **Propagación (D-053):** copia estados (pilas, magnitud, duración restante, origen) a receptores elegidos por relación, orden de `slot` y, si es aleatorio, flujo `select`; `on_expire`/`on_death` extienden un estado al expirar/morir el portador.
- **Suspensión (D-054):** un estado con `suspend_statuses` deja a los estados coincidentes sin efecto ni cuenta atrás mientras exista; las duraciones por tiempo se pausan y se rearman; `suspend_cooldowns` detiene los cooldowns/recargas por turnos y acciones (los de tiempo no).
- **Restaurar estados (D-055):** reemplaza el conjunto actual por el grabado (incluye estados no disipables), con duración restante e inversión.
- **Selectores `on` (D-056):** `all_enemies`, `all_allies`, `random_enemy`, `random_ally`, `lowest_hp_enemy`; triggers: `random_enemy`.
- **Catálogo elemental (D-057):** `elements` del reglamento; validado al montar el combate e importar.
- **Artefacto (D-058):** recursos, estados, invocaciones y reglas de IA propios además de modificadores y habilidades.
