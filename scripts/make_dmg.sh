#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
APP_NAME="MenuMeter"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
INSTALLED_APP="$HOME/Applications/${APP_NAME}.app"

./scripts/build_app.sh

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

cp -R "$INSTALLED_APP" "$STAGING/${APP_NAME}.app"
ln -s /Applications "$STAGING/Applications"
chmod 755 "$STAGING"
chmod -R a+rX "$STAGING/${APP_NAME}.app"

mkdir -p dist
rm -f "dist/${DMG_NAME}"

diskutil image create from \
    --format UDZO \
    --volumeName "$APP_NAME" \
    "$STAGING" \
    "dist/${DMG_NAME}"

echo "Oluşturuldu: dist/${DMG_NAME}"
