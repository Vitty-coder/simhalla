#!/usr/bin/env bash
# Exporta Simhalla para Android (APK arm64-v8a firmado) en build/. Para distribucion LOCAL: firma con la clave de depuracion de
# ~/tools/android/build.env (fuera del repo, no versionar). Sin permiso INTERNET (la aplicacion es offline).
#   tools/build_android.sh [debug|release]    (por defecto debug)
# Requiere JDK 17, el SDK de Android (build-tools + platform-tools) y las plantillas android_*.apk de Godot 4.7.2.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo "$HOME/tools/godot/godot")}"
ENVF="${ANDROID_ENV:-$HOME/tools/android/build.env}"
[ -f "$ENVF" ] && source "$ENVF"
export JAVA_HOME="${JAVA_HOME:-$HOME/tools/jdk17}"
SDK="${ANDROID_SDK:-$HOME/tools/android}"
MODE="${1:-debug}"
# Ajustes del editor en un directorio temporal (no toca los del usuario)
CFG="$(mktemp -d)"
mkdir -p "$CFG/godot"
cat > "$CFG/godot/editor_settings-4.7.tres" <<TRES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "$JAVA_HOME"
export/android/android_sdk_path = "$SDK"
export/android/debug_keystore = "${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-}"
export/android/debug_keystore_user = "${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-}"
export/android/debug_keystore_pass = "${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-}"
TRES
export XDG_CONFIG_HOME="$CFG"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-}"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-}"
mkdir -p build
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-$MODE "Android" "build/simhalla-$MODE.apk"
rm -rf "$CFG"
ls -la build
