#!/bin/bash
# Installs the usage status line into ~/.claude (backs up settings.json first).
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Install it with:  brew install jq"
  exit 1
fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/statusline-usage.sh"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$HOME/.claude"
cp "$SRC_DIR/statusline-usage.sh" "$DEST"
chmod +x "$DEST"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
BACKUP="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUP"

if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
  echo "Note: an existing statusLine was replaced (old copy in $BACKUP)."
fi

TMP=$(mktemp)
jq --arg cmd "$DEST" \
  '.statusLine = {type: "command", command: $cmd, refreshInterval: 30}' \
  "$SETTINGS" > "$TMP"
mv "$TMP" "$SETTINGS"

echo "Installed: $DEST"
echo "Settings updated: $SETTINGS  (backup: $BACKUP)"
echo "Start a new Claude Code session and send one message to see usage."
