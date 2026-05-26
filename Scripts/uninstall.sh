#!/usr/bin/env bash
set -euo pipefail

LABEL="com.goldplat.claude-usage-bar"
APP="$HOME/Applications/ClaudeUsageBar.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_SUPPORT="$HOME/Library/Application Support/ClaudeUsageBar"
LOG="$HOME/Library/Logs/ClaudeUsageBar.log"

echo "⚠️  Claude Usage Bar 제거 시작…"

# LaunchAgent 해제
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"

# .app 삭제
rm -rf "$APP"

# Application Support 데이터 삭제 (config + 캐릭터셋)
rm -rf "$APP_SUPPORT"

# 로그 삭제
rm -f "$LOG"

# Keychain 항목 삭제
security delete-generic-password -s "$LABEL" -a "claude-ai-session-key" 2>/dev/null || true

echo "✅ 제거 완료 — 단, Keychain 비밀번호가 묻힌 경우 시스템 keychain.app에서 'com.goldplat.claude-usage-bar' 검색해 수동 삭제 권장."
