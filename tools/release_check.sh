#!/usr/bin/env bash
# Comprobacion de version: pruebas, exportados y verificacion. Uso: tools/release_check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(tools/run_tests.sh 2>&1 || true)
grep -q "TODAS LAS PRUEBAS OK" <<<"$out" || { echo "FALLO: pruebas"; exit 1; }
tools/build_linux.sh release >/dev/null 2>&1 && tools/verify_export.sh linux >/dev/null 2>&1 || { echo "FALLO: Linux"; exit 1; }
if [ -f "$HOME/tools/android/build.env" ]; then
  tools/build_android.sh debug >/dev/null 2>&1 && tools/verify_export.sh android >/dev/null 2>&1 || { echo "FALLO: Android"; exit 1; }
else
  echo "AVISO: sin entorno Android; APK no comprobado"
fi
echo "RELEASE CHECK OK (Android sin ejecutar en dispositivo)"
