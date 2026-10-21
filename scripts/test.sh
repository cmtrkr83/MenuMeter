#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_PATH="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"

cd "$ROOT"
exec swift test --enable-swift-testing \
    -Xswiftc -plugin-path \
    -Xswiftc "$PLUGIN_PATH" \
    "$@"
