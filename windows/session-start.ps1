# SessionStart hook for the usage-meter-windows plugin - MIGATRONIX
# Runs every time Claude Code starts. Keeps the status line and the tray app
# installed and up to date with the plugin version, then makes sure the tray app is running.
# Writes nothing to stdout: SessionStart stdout is added to Claude's context, so all output goes to a log.

$ErrorActionPreference = 'SilentlyContinue'
$utf8 = New-Object System.Text.UTF8Encoding $false

$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$claude   = Join-Path $HOME '.claude'
$dest     = Join-Path $claude 'usage-meter'
$settings = Join-Path $claude 'settings.json'
$log      = Join-Path $dest 'hook.log'

New-Item -ItemType Directory -Force -Path $dest | Out-Null
if ((Test-Path $log) -and ((Get-Item $log).Length -gt 200000)) { Remove-Item $log -Force }
function Write-Log([string]$msg) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) }
Write-Log "session-start ($root)"

# 1. Scripts at a stable path (the plugin root changes with every update).
Copy-Item -Force (Join-Path $root 'statusline-usage.ps1') $dest
$traySrc = Join-Path $root 'ClaudeUsageTray.ps1'
$trayDst = Join-Path $dest 'ClaudeUsageTray.ps1'
$newHash = (Get-FileHash $traySrc -Algorithm SHA256).Hash
$oldHash = ''
if (Test-Path $trayDst) { $oldHash = (Get-FileHash $trayDst -Algorithm SHA256).Hash }
$trayChanged = $newHash -ne $oldHash
if ($trayChanged) { Copy-Item -Force $traySrc $trayDst; Write-Log 'tray script updated' }

# 2. Point settings.json at the status line - only when statusLine is unset or already one of ours.
try {
    $scriptPath = (Join-Path $dest 'statusline-usage.ps1') -replace '\\', '/'
    $want = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $config = $null
    if (Test-Path $settings) { $config = Get-Content -Raw -Path $settings -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    if ($null -eq $config) { $config = New-Object PSObject }
    $cur = $null
    if ($config.PSObject.Properties.Name -contains 'statusLine') { $cur = $config.statusLine.command }
    if ($cur -ne $want -and (-not $cur -or $cur -like '*statusline-usage*')) {
        if (Test-Path $settings) { Copy-Item $settings "$settings.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
        if ($config.PSObject.Properties.Name -contains 'statusLine') { $config.PSObject.Properties.Remove('statusLine') }
        $statusLine = [PSCustomObject][ordered]@{ type = 'command'; command = $want; refreshInterval = 30 }
        $config | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLine
        [IO.File]::WriteAllText($settings, ($config | ConvertTo-Json -Depth 32), $utf8)
        Write-Log "statusLine set to $scriptPath"
    }
} catch {
    Write-Log "settings.json not changed: $($_.Exception.Message)"
}

# 3. Tray app: restart it when the plugin ships a new version, otherwise just make sure it runs.
$running = $false
try {
    $m = $null
    $running = [System.Threading.Mutex]::TryOpenExisting('Local\MigatronixClaudeUsageTray', [ref]$m)
    if ($m) { $m.Dispose() }
} catch { }

if ($running -and $trayChanged) {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*ClaudeUsageTray.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Start-Sleep -Milliseconds 700
    $running = $false
    Write-Log 'tray app stopped for update'
}

if (-not $running) {
    $psExe = Join-Path $PSHOME 'powershell.exe'
    Start-Process -FilePath $psExe -WindowStyle Hidden `
        -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$trayDst`""
    Write-Log 'tray app started'
}

exit 0
