#!/bin/bash
# SessionStart hook for the usage-meter-mac plugin — MIGATRONIX
# Runs every time Claude Code starts. Keeps the status line and the menu-bar app
# installed and up to date with the plugin version, then makes sure the app is running.
# Prints nothing: SessionStart stdout is added to Claude's context, so all output goes to a log.

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
DEST="$HOME/.claude/usage-meter"
SETTINGS="$HOME/.claude/settings.json"
APP="$HOME/Applications/ClaudeUsageBar.app"
LOG="$DEST/hook.log"

mkdir -p "$DEST" || exit 0
[ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 200000 ] && : > "$LOG"
exec >>"$LOG" 2>&1
echo "== $(date '+%F %T') session-start ($ROOT)"

# 1. Status-line script at a stable path (the plugin root changes with every update).
cp -f "$ROOT/statusline-usage.sh" "$DEST/statusline-usage.sh" && chmod +x "$DEST/statusline-usage.sh"

# 2. Point settings.json at it — only when statusLine is unset or already one of ours.
if command -v jq >/dev/null 2>&1; then
  WANT="$DEST/statusline-usage.sh"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  CUR=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)
  if [ $? -eq 0 ] && [ "$CUR" != "$WANT" ] && { [ -z "$CUR" ] || [[ "$CUR" == *statusline-usage* ]]; }; then
    cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
    TMP=$(mktemp)
    if jq --arg cmd "$WANT" '.statusLine = {type: "command", command: $cmd, refreshInterval: 30}' "$SETTINGS" > "$TMP"; then
      mv "$TMP" "$SETTINGS"
      echo "statusLine set to $WANT"
    else
      rm -f "$TMP"
    fi
  fi
else
  echo "jq not found: statusLine not configured (brew install jq)"
fi

# 3. Menu-bar app: rebuild when the plugin ships new source, otherwise just make sure it runs.
SRC="$ROOT/ClaudeUsageBar.swift"
NEW_HASH=$(shasum -a 256 "$SRC" 2>/dev/null | cut -d' ' -f1)
OLD_HASH=$(cat "$DEST/app.sha256" 2>/dev/null)

if [ ! -x "$APP/Contents/MacOS/ClaudeUsageBar" ] || [ "$NEW_HASH" != "$OLD_HASH" ]; then
  if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc not found: menu-bar app not built (xcode-select --install)"
  elif mkdir "$DEST/build.lock" 2>/dev/null; then
    # Build in the background so Claude Code does not wait for the compiler.
    nohup bash -c '
      if bash "$1/build-menubar.sh"; then echo "$2" > "$3/app.sha256"; fi
      rmdir "$3/build.lock"
    ' _ "$ROOT" "$NEW_HASH" "$DEST" </dev/null >>"$LOG" 2>&1 &
    disown
    echo "building menu-bar app in background"
  else
    # Another session is building; clear a lock left behind by a crash (older than 10 minutes).
    if [ -n "$(find "$DEST/build.lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
      rmdir "$DEST/build.lock"
    fi
  fi
elif ! pgrep -x ClaudeUsageBar >/dev/null 2>&1; then
  open -g "$APP" && echo "menu-bar app started"
fi

exit 0
