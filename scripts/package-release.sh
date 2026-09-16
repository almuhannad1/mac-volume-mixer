#!/bin/bash
# Builds a universal "Mac Volume Mixer.app" and packages it for distribution:
#
#   dist/MacVolumeMixer-<version>.dmg   drag-to-Applications disk image
#   dist/MacVolumeMixer-<version>.zip   plain archive of the app
#
#   scripts/package-release.sh
#   CODESIGN_IDENTITY="Developer ID Application: …" scripts/package-release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
APP="$ROOT/build/Mac Volume Mixer.app"
DIST="$ROOT/dist"
NAME="MacVolumeMixer-$VERSION"

UNIVERSAL=1 "$ROOT/scripts/build-app.sh"

rm -rf "$DIST"
mkdir -p "$DIST"

# ditto keeps the bundle's symlinks, permissions and signature intact (plain zip can break them).
ditto -c -k --keepParent "$APP" "$DIST/$NAME.zip"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Mac Volume Mixer.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "Mac Volume Mixer $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DIST/$NAME.dmg"

echo
echo "Packages for version $VERSION:"
(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip")
