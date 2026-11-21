#!/usr/bin/env bash
# Verifica un exportado:
#   tools/verify_export.sh linux    ejecuta build/linux/simhalla.x86_64 en una carpeta VACIA con `-- --selftest` (diagnostico de plataforma:
#                                   si el filtro de exportacion omitiera archivos necesarios, fallaria) y exige codigo 0
#   tools/verify_export.sh android  comprueba el APK (firma, SDK, arquitecturas, ausencia de INTERNET, contenido imprescindible)
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
linux)
  BIN="$PWD/build/linux/simhalla.x86_64"
  [ -x "$BIN" ] || { echo "falta $BIN (ejecute tools/build_linux.sh)"; exit 2; }
  TMP="$(mktemp -d)"
  ( cd "$TMP" && XDG_DATA_HOME="$TMP/data" "$BIN" --headless -- --selftest ) | tee "$TMP/out.txt" | tail -40
  grep -q "COMPATIBLE con la referencia" "$TMP/out.txt" && echo "EXPORT LINUX OK" || { echo "EXPORT LINUX FALLO"; exit 1; }
  rm -rf "$TMP"
  ;;
android)
  APK="${2:-build/simhalla-debug.apk}"
  BT="$HOME/tools/android/build-tools/37.0.0"
  export JAVA_HOME="${JAVA_HOME:-$HOME/tools/jdk17}"; export PATH="$JAVA_HOME/bin:$PATH"
  [ -f "$APK" ] || { echo "falta $APK (ejecute tools/build_android.sh)"; exit 2; }
  echo "== firma =="; "$BT/apksigner" verify --verbose "$APK" | head -6
  echo "== badging =="; "$BT/aapt2" dump badging "$APK" | grep -E "^package|sdkVersion|targetSdk|native-code|launchable|application-label:" 
  echo "== permisos =="; PERMS="$("$BT/aapt2" dump permissions "$APK" | grep -c "uses-permission" || true)"; "$BT/aapt2" dump permissions "$APK" | head -10
  if "$BT/aapt2" dump permissions "$APK" | grep -qi "android.permission.INTERNET"; then echo "AVISO: el APK declara INTERNET (exportacion de depuracion)"; fi
  echo "== contenido =="; python3 - "$APK" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = z.namelist()
want = ["assets/", "lib/arm64-v8a/libgodot_android.so", "AndroidManifest.xml", "classes.dex"]
for w in want:
    hits = [n for n in names if n.startswith(w) or n == w]
    print(("OK    " if hits else "FALTA ") + w, "(%d)" % len(hits))
print("tamano total (descomprimido): %.1f MB; arquitecturas: %s" % (sum(i.file_size for i in z.infolist()) / 1e6, sorted({n.split('/')[1] for n in names if n.startswith('lib/')})))
PY
  ;;
*) echo "uso: tools/verify_export.sh linux|android [apk]"; exit 2;;
esac
