#!/bin/bash
# Builds "Mac Volume Mixer.app" from the Swift package.
#
#   scripts/build-app.sh                  # release build, ad-hoc signed
#   CODESIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#   CONFIGURATION=debug scripts/build-app.sh
#   UNIVERSAL=1 scripts/build-app.sh      # Apple Silicon + Intel binary
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="$ROOT/build/Mac Volume Mixer.app"

ARCH_ARGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
fi

cd "$ROOT"
swift build -c "$CONFIGURATION" --product MacVolumeMixer "${ARCH_ARGS[@]}"
BIN_DIR="$(swift build -c "$CONFIGURATION" "${ARCH_ARGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacVolumeMixer" "$APP/Contents/MacOS/MacVolumeMixer"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

SIGN_ARGS=(--force --sign "$IDENTITY" --entitlements "$ROOT/Resources/MacVolumeMixer.entitlements")
if [[ "$IDENTITY" != "-" ]]; then
    # Hardened runtime + secure timestamp are required for notarization.
    SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
if [[ "$IDENTITY" == "-" ]]; then
    echo "Note: ad-hoc signed. macOS may ask for System Audio Recording permission again after each rebuild."
fi
