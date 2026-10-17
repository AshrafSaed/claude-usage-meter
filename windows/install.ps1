# Installs the Claude usage status line and tray app for the current Windows user.
# Run from this folder:  powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
# Options: -NoTray (status line only), -NoStartup (do not start the tray app at sign-in)
param([switch]$NoTray, [switch]$NoStartup)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false

$src      = Split-Path -Parent $MyInvocation.MyCommand.Path
$claude   = Join-Path $HOME '.claude'
$dest     = Join-Path $claude 'usage-meter'
$settings = Join-Path $claude 'settings.json'

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Force (Join-Path $src 'statusline-usage.ps1') $dest
Copy-Item -Force (Join-Path $src 'ClaudeUsageTray.ps1') $dest

if (-not (Test-Path $settings)) { [IO.File]::WriteAllText($settings, '{}', $utf8) }
$backup = "$settings.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $settings $backup

$config = Get-Content -Raw -Path $settings | ConvertFrom-Json
if ($null -eq $config) { $config = New-Object PSObject }
if ($config.PSObject.Properties.Name -contains 'statusLine') {
    Write-Host "Note: an existing statusLine was replaced (old copy in $backup)."
    $config.PSObject.Properties.Remove('statusLine')
}

# Forward slashes: Claude Code may run the command through Git Bash, which strips backslashes.
$scriptPath = (Join-Path $dest 'statusline-usage.ps1') -replace '\\', '/'
$statusLine = [ordered]@{
    type            = 'command'
    command         = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    refreshInterval = 30
}
$config | Add-Member -NotePropertyName statusLine -NotePropertyValue ([PSCustomObject]$statusLine)
[IO.File]::WriteAllText($settings, ($config | ConvertTo-Json -Depth 32), $utf8)

Write-Host "Installed status line: $scriptPath"
Write-Host "Settings updated: $settings  (backup: $backup)"

if (-not $NoTray) {
    $tray = Join-Path $dest 'ClaudeUsageTray.ps1'
    $psArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tray`""

    if (-not $NoStartup) {
        $startup = [Environment]::GetFolderPath('Startup')
        $lnkPath = Join-Path $startup 'ClaudeUsageTray.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($lnkPath)
        $lnk.TargetPath = Join-Path $PSHOME 'powershell.exe'
        $lnk.Arguments = $psArgs
        $lnk.WorkingDirectory = $dest
        $lnk.WindowStyle = 7
        $lnk.Description = 'Claude usage tray (MIGATRONIX)'
        $lnk.Save()
        Write-Host "Start at sign-in: $lnkPath"
    }

    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $psArgs -WindowStyle Hidden
    Write-Host 'Tray app started (look for the ring icon near the clock; it may be under the ^ overflow arrow).'
}

Write-Host 'Start a new Claude Code session and send one message to see usage.'
