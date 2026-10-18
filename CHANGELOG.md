# Changelog

All MIGATRONIX Claude Code tools in the `migatronix` marketplace.

## 2026-10-18

- **Windows tray app rewritten as a native program** (`ClaudeUsageTray.exe`, built on the PC from `ClaudeUsageTray.cs` by the plugin hook). The PowerShell version ran inside a console window and could be closed together with a terminal, so the icon disappeared. The new program has no console, logs to `tray.log`, catches errors instead of exiting, and checks every 2 seconds whether Claude is open. The hook removes the old PowerShell tray.
- **Windows tray app**: the icon is shown only while Claude is open (desktop app — chat or Code — or Claude Code in a terminal) and hides when Claude closes. An `always-show` file in `~/.claude/usage-meter/` keeps it visible at all times.
- **Windows plugin**: the tray icon now keeps running after Claude Code closes (it is launched through Explorer instead of as a child of Claude Code), and the hook keeps a Startup shortcut so the icon starts at every sign-in, even when only the Claude chat app is used.
- **context-meter** joins this repository as a third plugin (`context-meter@migatronix`), moved unchanged (version 0.3.1) from `AshrafSaed/context-meter`. README explains how to move existing installs to the new marketplace.
- **README**: status table — Windows plugin, macOS plugin and both manual installs verified on real machines.
- **Plugins**: the repository becomes the `migatronix` marketplace with `usage-meter-mac` and `usage-meter-windows`. A `SessionStart` hook keeps the status line configured, copies updated scripts into `~/.claude/usage-meter/`, rebuilds or restarts the menu-bar / tray app when its code changes, and starts it when Claude Code opens. Auto-update follows every commit.
- **Windows**: no-Git install, fixes found while testing (run from the `windows` folder, `Unblock-File`, normal user instead of Administrator).

## 2026-10-17

- First release: status-line script and menu-bar app for macOS, status-line script and tray app for Windows, manual installers, README with illustrations.
