#!/bin/bash
# Builds ClaudeUsageBar.app into ~/Applications and launches it (macOS 13+).
set -euo pipefail

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Install the Xcode Command Line Tools:  xcode-select --install"
  exit 1
fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/ClaudeUsageBar.app"
BIN="$APP/Contents/MacOS/ClaudeUsageBar"

mkdir -p "$APP/Contents/MacOS"
swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  "$SRC_DIR/ClaudeUsageBar.swift" -o "$BIN"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.migatronix.claudeusagebar</string>
  <key>CFBundleName</key><string>ClaudeUsageBar</string>
  <key>CFBundleExecutable</key><string>ClaudeUsageBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
pkill -x ClaudeUsageBar 2>/dev/null || true
open "$APP"
echo "Built and launched: $APP"
echo "To start at login: System Settings → General → Login Items → + → ClaudeUsageBar"
