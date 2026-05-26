#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/ClaudeUsageBar.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/ClaudeUsageBar.app"

if [[ ! -d "$SRC" ]]; then
    echo "❌ $SRC 가 없습니다. 먼저 'make bundle' 실행하세요." >&2
    exit 1
fi

mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "✅ 설치 완료 : $DEST"
echo "👉 Finder에서 ~/Applications 폴더를 열어 ClaudeUsageBar.app을 더블클릭하면 메뉴바에 등장합니다."
