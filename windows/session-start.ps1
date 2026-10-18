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

# 1. Status-line script at a stable path (the plugin root changes with every update).
Copy-Item -Force (Join-Path $root 'statusline-usage.ps1') $dest

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

# 3. Tray app: a small GUI program (no console window), built here from ClaudeUsageTray.cs
#    with csc.exe, the C# compiler that is part of the .NET Framework in Windows 10 and 11.
#    Rebuilt when the source or the build recipe changes.
$BuildRecipe = 'csc-winexe-1'
$exe     = Join-Path $dest 'ClaudeUsageTray.exe'
$csSrc   = Join-Path $root 'ClaudeUsageTray.cs'
$stamp   = Join-Path $dest 'tray.sha256'
$newHash = (Get-FileHash $csSrc -Algorithm SHA256).Hash + '|' + $BuildRecipe
$oldHash = ''
if (Test-Path $stamp) { $oldHash = (Get-Content -Raw $stamp).Trim() }
$needBuild = (-not (Test-Path $exe)) -or ($newHash -ne $oldHash)

function Test-TrayRunning {
    try {
        $m = $null
        $ok = [System.Threading.Mutex]::TryOpenExisting('Local\MigatronixClaudeUsageTray', [ref]$m)
        if ($m) { $m.Dispose() }
        return $ok
    } catch { return $false }
}

# Earlier versions ran the tray as a PowerShell script inside a console; remove that copy.
$legacy = Join-Path $dest 'ClaudeUsageTray.ps1'
if (Test-Path $legacy) {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*ClaudeUsageTray.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Remove-Item -Force $legacy
    Start-Sleep -Milliseconds 500
    Write-Log 'removed PowerShell tray (replaced by ClaudeUsageTray.exe)'
}

if ($needBuild) {
    if (Test-TrayRunning) {
        Stop-Process -Name 'ClaudeUsageTray' -Force
        Start-Sleep -Milliseconds 700
        Write-Log 'tray app stopped for update'
    }
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    $tmpExe = Join-Path $dest 'ClaudeUsageTray.build.exe'
    Remove-Item -Force $tmpExe -ErrorAction SilentlyContinue
    if (-not (Test-Path $csc)) {
        Write-Log "tray app build failed: csc.exe not found under $env:WINDIR\Microsoft.NET"
    } else {
        $out = & $csc /nologo /target:winexe /optimize+ "/out:$tmpExe" `
            /r:System.Windows.Forms.dll /r:System.Drawing.dll "$csSrc" 2>&1 | Out-String
        $isExe = $false
        if (Test-Path $tmpExe) {
            $bytes = [IO.File]::ReadAllBytes($tmpExe)
            $isExe = $bytes.Length -gt 1024 -and $bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A
        }
        if ($LASTEXITCODE -eq 0 -and $isExe) {
            Move-Item -Force $tmpExe $exe
            [IO.File]::WriteAllText($stamp, $newHash, $utf8)
            Write-Log "tray app built with $csc"
        } else {
            Write-Log "tray app build failed (csc exit $LASTEXITCODE): $($out.Trim())"
        }
    }
}

# 4. Start at sign-in, independent of Claude: a Startup shortcut to the tray program.
$lnkPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeUsageTray.lnk'
if (Test-Path $exe) {
    try {
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($lnkPath)
        if (-not (Test-Path $lnkPath) -or $lnk.TargetPath -ne $exe -or $lnk.Arguments) {
            $lnk.TargetPath = $exe
            $lnk.Arguments = ''
            $lnk.WorkingDirectory = $dest
            $lnk.WindowStyle = 1
            $lnk.Description = 'Claude usage tray (MIGATRONIX)'
            $lnk.Save()
            Write-Log "startup shortcut written: $lnkPath"
        }
    } catch {
        Write-Log "startup shortcut not written: $($_.Exception.Message)"
    }

    # Start it through Explorer so it is not a child of Claude Code.
    if (-not (Test-TrayRunning)) {
        Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList "`"$exe`""
        Write-Log 'tray app started'
    }
}

exit 0
