# Manual installer for Windows (without the Claude Code plugin).
# Run from this folder:  powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
# Does exactly what the plugin's SessionStart hook does: installs the status line,
# builds ClaudeUsageTray.exe, adds it to Startup and starts it.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $here 'session-start.ps1')

$log = Join-Path $HOME '.claude\usage-meter\hook.log'
Get-Content $log -Tail 8
Write-Host ''
Write-Host 'Done. The tray icon shows while Claude is open (desktop app or Claude Code).'
Write-Host 'Start Claude Code and send one message to fill in the numbers.'
