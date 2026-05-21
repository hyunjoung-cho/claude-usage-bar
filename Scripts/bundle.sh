#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/ClaudeUsageBar.app"
BIN="$ROOT/.build/release/ClaudeUsageBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp "$ROOT/Info.plist" "$APP/Contents/"
cp -R "$ROOT/Sources/ClaudeUsageBar/Resources/default-sets" "$APP/Contents/Resources/"
echo "✅ Built $APP"
