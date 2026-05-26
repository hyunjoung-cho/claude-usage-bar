#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_SRC="$ROOT/launchd/com.goldplat.claude-usage-bar.plist"
PLIST_DEST_DIR="$HOME/Library/LaunchAgents"
PLIST_DEST="$PLIST_DEST_DIR/com.goldplat.claude-usage-bar.plist"
APP="$HOME/Applications/ClaudeUsageBar.app"
APP_BIN="$APP/Contents/MacOS/ClaudeUsageBar"
LOG_DIR="$HOME/Library/Logs"
LABEL="com.goldplat.claude-usage-bar"

if [[ ! -d "$APP" ]]; then
    echo "❌ $APP 가 없습니다. 먼저 'make install' 실행하세요." >&2
    exit 1
fi

if [[ ! -f "$PLIST_SRC" ]]; then
    echo "❌ $PLIST_SRC 가 없습니다. 'launchd/com.goldplat.claude-usage-bar.plist' 파일을 만들어주세요." >&2
    exit 1
fi

mkdir -p "$PLIST_DEST_DIR" "$LOG_DIR"

# 기존 등록 해제 (있다면)
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

# plist 복사
cp "$PLIST_SRC" "$PLIST_DEST"

# 새로 등록 + 즉시 시작
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "✅ LaunchAgent 등록 완료 : $PLIST_DEST"
echo "👉 로그아웃 후 다시 로그인하면 자동 실행됩니다."
echo "👉 로그 : tail -f $LOG_DIR/ClaudeUsageBar.log"
