#!/usr/bin/env bash
# Compila SoundFast SIN firmar y lo empaqueta como build/SoundFast.ipa.
# La firma la pone Sideloadly / AltStore al instalar con tu Apple ID.
# Uso (solo en macOS): bash scripts/build-ipa.sh [numero_de_build]
set -euo pipefail

BUILD_NUMBER="${1:-1}"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%MZ)"

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Instalando XcodeGen"
  brew install xcodegen
fi

xcodebuild -version

echo "==> Generando SoundFast.xcodeproj"
xcodegen generate

echo "==> Compilando (build $BUILD_NUMBER, $BUILD_DATE)"
rm -rf build && mkdir -p build
LOG=build/xcodebuild.log
if ! xcodebuild \
  -project SoundFast.xcodeproj \
  -scheme SoundFast \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  SF_BUILD_DATE="$BUILD_DATE" \
  build >"$LOG" 2>&1; then
  echo "==> FALLÓ la compilación. Errores:" >&2
  grep -E "error:" "$LOG" | sort -u >&2 || true
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    # Anotaciones visibles en la página del run (y por la API sin iniciar sesión).
    ROOT="$(pwd)/"
    grep -E "^/.*:[0-9]+:[0-9]+: error: " "$LOG" | sort -u | head -n 50 | while IFS= read -r line; do
      file="${line%%:*}"; rest="${line#*:}"
      ln="${rest%%:*}"; rest="${rest#*:}"
      col="${rest%%:*}"; msg="${rest#*: error: }"
      echo "::error file=${file#$ROOT},line=$ln,col=$col::$msg"
    done
  fi
  echo "==> Últimas líneas del log:" >&2
  tail -n 40 "$LOG" >&2
  exit 1
fi
grep -E "warning:" "$LOG" | sort -u || true

APP="build/DerivedData/Build/Products/Release-iphoneos/SoundFast.app"
if [ ! -d "$APP" ]; then
  echo "No se generó $APP" >&2
  exit 1
fi

echo "==> Empaquetando IPA"
mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && zip -qry ../SoundFast.ipa Payload)
ls -lh build/SoundFast.ipa
