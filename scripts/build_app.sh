#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP="$HOME/Applications/MenuMeter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/MenuMeter "$APP/Contents/MacOS/MenuMeter"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP"

echo "Kuruldu: $APP"
