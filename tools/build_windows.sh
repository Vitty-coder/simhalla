#!/usr/bin/env bash
# Exporta Simhalla para Windows x86_64 (simhalla.exe con el .pck embebido) en build/windows/. Requiere las plantillas de exportacion de Godot
# 4.7.2 (windows_release_x86_64.exe en ~/.local/share/godot/export_templates/4.7.2.stable/). Se puede compilar desde Linux; NO se puede
# ejecutar aqui. El .exe no esta firmado (Windows SmartScreen avisara) y no lleva icono propio (no hay rcedit).
#   tools/build_windows.sh [debug|release]      (por defecto release)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo "$HOME/tools/godot/godot")}"
MODE="${1:-release}"
mkdir -p build/windows
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-$MODE "Windows" build/windows/simhalla.exe
ls -la build/windows
