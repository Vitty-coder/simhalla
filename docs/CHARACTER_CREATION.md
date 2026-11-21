# CHARACTER_CREATION — Crear un PJ válido (fase 1)

> Hay dos vías: (A) **paquete** importable (carpeta/ZIP con `manifest.json`, versiones y
> dependencias) — la vía normal, ver [`PACKAGES.md`](PACKAGES.md); (B) un único JSON de
> entidad para pruebas rápidas. Costes de creación (PC): **fase 6** — hasta entonces un PJ
> no tiene presupuesto y el validador avisa de ello.

## Vía A — paquete de personaje (recomendada)
Estructura mínima: `manifest.json` + `character.json`. Ejemplos completos y validados en
`content/packages/arcane_duelist` (con artefacto, recursos, habilidades e IA importadas) y
`content/packages/iron_vanguard` (sin dependencias). Pasos:
```bash
godot --headless --path . --script res://tools/package_tool.gd -- validate ruta/mi_paquete   # errores por archivo y ruta
godot --headless --path . --script res://tools/package_tool.gd -- import ruta/mi_paquete
godot --headless --path . --script res://tools/run_duel.gd -- pkg:mi_ns/mi_heroe pkg:examples/iron_vanguard 42 --log
```

## Vía B — JSON de entidad (pruebas rápidas)

## Pasos
1. Cree `mi_personaje.json` (formato en `DATA_SCHEMAS.md` §3). Solo `id` y `team` son imprescindibles.
2. Indique solo lo que difiera de la base gratuita (`stats`), añada `resources`, `abilities` e `ai`.
3. Valide y lance un duelo:

```bash
godot --headless --path . --script res://tools/run_duel.gd -- res://ruta/mi_personaje.json attacker_b.json 42 --log
```
Los errores se muestran con el campo afectado (p. ej. `habilidad 'x': effects[0]: damage.components[0].formula: división…`). El comando devuelve código 2 si el contenido es inválido.

## Ejemplo completo y validado (`content/fixtures/entities/glass_cannon.json`)
```json
{
  "id": "glass_cannon", "name": "Canon de cristal", "team": "A",
  "tags": ["fixture", "magic"],
  "stats": {"HP": 600, "MAG": 220, "DEF": 40, "RES": 40, "SPD": 140, "CRIT": 0.25, "ELEM_AFF.fire": 0.2},
  "resources": {"mana": {"initial": 60, "max": 60}},
  "basic_attack": true,
  "abilities": [
    {"id": "fireball", "name": "Bola de fuego", "action_type": "main", "targeting": "enemy",
     "cost": {"mana": 20},
     "effects": [{"type": "damage", "components": [
       {"damage_type": "magical", "element": "fire", "formula": "caster.MAG * 1.5"}]}]}
  ],
  "ai": {"type": "priority_list", "rules": [
    {"ability": "fireball", "target": "lowest_hp_enemy"},
    {"ability": "basic_attack", "target": "lowest_hp_enemy"}
  ]}
}
```
Este fichero se valida y se ejecuta en la suite de pruebas (`test_fixture_files_all_valid`).

## Reglas para quien genere contenido (humano o IA)
- **No invente** operaciones, campos ni variables que no figuren en `ABILITY_REFERENCE.md`, `AI_REFERENCE.md` y `DATA_SCHEMAS.md`. Lo desconocido se rechaza con error.
- Probabilidades/multiplicadores en forma normalizada (0.25 = 25 %, `CRIT_DMG` 1.5 = ×1,5).
- Código solo en SimScript (`scripts/*.sim`, ver `SCRIPTING_API.md`): nada de GDScript ni de código del anfitrión. Lo declarativo y las fórmulas son preferibles; los scripts quedan marcados como no evaluables hasta la fase 6.
- Un PJ sin `basic_attack` ni habilidades solo puede esperar (es válido).

## Antes de entregar un paquete (lista de comprobación)
1. `validate` sin errores; los avisos (dependencia sin usar, costes no evaluados) revisados.
2. Un duelo de prueba con `--log` muestra que las habilidades e IA se comportan como esperaba.
3. Versión semver coherente: cambios de contenido ⇒ versión nueva (nunca reimportar la misma versión con cambios).
