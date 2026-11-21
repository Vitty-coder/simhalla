# Simhalla

Sandbox universal de combates ATB (Godot 4.7.2). Especificación maestra: [`PROJECT.md`](PROJECT.md).

**Estado:** fases 1 (núcleo ATB headless), 2 (paquetes de contenido), 3 (habilidades y eventos), 4 (IA: estrategias, memoria, predicción, reacciones) 5 (scripts aislados SimScript) 6 (equilibrio y valoración de PC) 7 (simulaciones: individual y por lotes) 8 (informes y estadística) y 9 (UI y biblioteca) completadas — ver [`docs/ROADMAP.md`](docs/ROADMAP.md).

```bash
tools/run_tests.sh                      # 279 pruebas headless
godot --headless --path . --script res://tools/run_duel.gd -- attacker_a.json attacker_b.json 42 --log
```

| Documento | Contenido |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Módulos, flujo, puntos de extensión |
| [`docs/COMBAT_RULES.md`](docs/COMBAT_RULES.md) | Reglamento implementado (marcado lo provisional) |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Registro de decisiones técnicas |
| [`docs/EVENTS.md`](docs/EVENTS.md) | Catálogo de eventos y condiciones |
| [`docs/PACKAGES.md`](docs/PACKAGES.md) · [`schemas/`](schemas) | Paquetes importables, esquemas públicos, versiones y seguridad |
| [`docs/DATA_SCHEMAS.md`](docs/DATA_SCHEMAS.md) · [`CHARACTER_CREATION`](docs/CHARACTER_CREATION.md) · [`ABILITY_REFERENCE`](docs/ABILITY_REFERENCE.md) · [`AI_REFERENCE`](docs/AI_REFERENCE.md) | Crear contenido válido |
| [`docs/TESTING.md`](docs/TESTING.md) | Pruebas, golden, Android |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Fases y limitaciones conocidas |

Primera ejecución tras clonar: `godot --headless --path . --import` (o simplemente `tools/run_tests.sh`).

## Plataformas
Exportación Linux/Android, conformidad multiplataforma (`--selftest`, pantalla Plataforma) y límites: `docs/PLATFORMS.md`. Licencias: `docs/LICENSES.md`. Guía de uso: `docs/USER_GUIDE.md`.

## Ejecutable de Windows
`dist/simhalla-windows-x64.zip` contiene `simhalla.exe` (Windows x86_64, un solo archivo con los datos embebidos; no necesita instalar nada).
1. Descomprímelo y ejecuta `simhalla.exe`. Windows SmartScreen avisará de «editor desconocido» porque **no está firmado**: «Más información → Ejecutar de todos modos».
2. En **Biblioteca** pulsa «Instalar ejemplos incluidos» y prueba un **Duelo**; guía en `docs/USER_GUIDE.md`.
3. Integridad: compara `dist/simhalla-windows-x64.zip.sha256` con `certutil -hashfile simhalla-windows-x64.zip SHA256`.

**Aviso honesto:** este `.exe` se compiló desde Linux con las plantillas oficiales de Godot 4.7.2 y se comprobó su formato (PE x86_64, datos embebidos), pero **no se ha podido ejecutar en Windows** (ni se ha visto la interfaz en pantalla). Si falla algo, abre un *issue* con el mensaje o con el informe de **Plataforma → Ejecutar**. Para regenerarlo: `tools/build_windows.sh` (necesita las plantillas de exportación de Godot 4.7.2).
