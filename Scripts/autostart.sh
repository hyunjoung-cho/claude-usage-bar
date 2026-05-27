#!/usr/bin/env bash
set -euo pipefail

LABEL="com.goldplat.claude-usage-bar"
APP="$HOME/Applications/ClaudeUsageBar.app"
APP_BIN="$APP/Contents/MacOS/ClaudeUsageBar"
PLIST_DEST_DIR="$HOME/Library/LaunchAgents"
PLIST_DEST="$PLIST_DEST_DIR/$LABEL.plist"
LOG="$HOME/Library/Logs/ClaudeUsageBar.log"

if [[ ! -x "$APP_BIN" ]]; then
    echo "❌ $APP_BIN 가 없습니다. 먼저 'make install' 실행하세요." >&2
    exit 1
fi

mkdir -p "$PLIST_DEST_DIR" "$(dirname "$LOG")"

# 현재 사용자 홈 경로로 plist 동적 생성 (username 하드코딩 X)
cat > "$PLIST_DEST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLIST

# 기존 등록 해제 후 재등록
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "✅ LaunchAgent 등록 완료 : $PLIST_DEST"
echo "👉 로그 : tail -f $LOG"
