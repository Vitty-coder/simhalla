#!/usr/bin/env bash
# Ejecuta la suite de pruebas headless. Uso: tools/run_tests.sh [filtro]
# GODOT puede apuntar al binario (por defecto: godot en PATH o ~/tools/godot/godot).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo "$HOME/tools/godot/godot")}"
# Primera vez (o tras anadir clases): reconstruye la cache de clases globales.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --path . --script res://tests/run_tests.gd -- "$@"
