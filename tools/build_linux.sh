#!/usr/bin/env bash
# Exporta Simhalla para Linux x86_64 (binario con el .pck embebido) en build/linux/. Requiere las plantillas de exportacion de Godot 4.7.2
# (linux_release.x86_64 / linux_debug.x86_64 en ~/.local/share/godot/export_templates/4.7.2.stable/).
#   tools/build_linux.sh [debug|release]      (por defecto release)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo "$HOME/tools/godot/godot")}"
MODE="${1:-release}"
mkdir -p build/linux
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-$MODE "Linux" build/linux/simhalla.x86_64
ls -la build/linux
