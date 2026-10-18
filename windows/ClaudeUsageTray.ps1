# ClaudeUsageTray - MIGATRONIX (Windows)
# System-tray view of Claude plan usage, read from %USERPROFILE%\.claude\usage-cache.json
# (written by statusline-usage.ps1 whenever Claude Code refreshes its status line).
# Run hidden:  powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ClaudeUsageTray.ps1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Win32 -Name Icons -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool DestroyIcon(System.IntPtr handle);
'@

$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\MigatronixClaudeUsageTray', [ref]$created)
if (-not $created) { exit }

[System.Windows.Forms.Application]::EnableVisualStyles()

$CachePath  = Join-Path (Join-Path $HOME '.claude') 'usage-cache.json'
$StaleAfter = 15 * 60
$Magenta    = [System.Drawing.Color]::FromArgb(0xB7, 0x00, 0x6A)
$Amber      = [System.Drawing.Color]::FromArgb(0xE0, 0x9A, 0x00)
$Blue       = [System.Drawing.Color]::FromArgb(0x00, 0x5F, 0xCC)
$Grey       = [System.Drawing.Color]::FromArgb(0x88, 0x88, 0x88)
$Dot        = [string][char]0x00B7

function Get-LevelColor([double]$pct) {
    if ($pct -ge 90) { return $Magenta }
    if ($pct -ge 70) { return $Amber }
    return $Blue
}

function Format-Left([double]$seconds) {
    $s = [long][math]::Max(0, $seconds)
    $d = [math]::Floor($s / 86400); $h = [math]::Floor(($s % 86400) / 3600); $m = [math]::Floor(($s % 3600) / 60)
    if ($d -gt 0) { return ('{0}d {1}h' -f $d, $h) }
    if ($h -gt 0) { return ('{0}h {1:D2}m' -f $h, [int]$m) }
    return ('{0}m' -f $m)
}

function Format-Clock([long]$epoch, [bool]$withDay) {
    $fmt = 'HH:mm'
    if ($withDay) { $fmt = 'ddd HH:mm' }
    [DateTimeOffset]::FromUnixTimeSeconds($epoch).ToLocalTime().ToString($fmt, [Globalization.CultureInfo]::InvariantCulture)
}

function Read-Usage {
    if (-not (Test-Path $CachePath)) { return $null }
    try { return (Get-Content -Raw -Path $CachePath | ConvertFrom-Json) } catch { return $null }
}

function Get-Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$script:LastHandle = [IntPtr]::Zero
function New-RingIcon([double]$pct, [System.Drawing.Color]$color, [bool]$active) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $track = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 128, 128, 128)), 6
    $g.DrawEllipse($track, 4, 4, 24, 24)
    if ($active) {
        $pen = New-Object System.Drawing.Pen $color, 6
        $sweep = [float](360 * [math]::Min(1, [math]::Max(0.02, $pct / 100)))
        $g.DrawArc($pen, 4, 4, 24, 24, -90, $sweep)
        $pen.Dispose()
    }
    $track.Dispose(); $g.Dispose()
    $handle = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($handle)
    $bmp.Dispose()
    $script:LastHandle = $handle
    return $icon
}

# Swap the tray icon first, then free the previous GDI handle.
function Set-TrayIcon([double]$pct, [System.Drawing.Color]$color, [bool]$active) {
    $old = $script:LastHandle
    $tray.Icon = New-RingIcon $pct $color $active
    if ($old -ne [IntPtr]::Zero) { [void][Win32.Icons]::DestroyIcon($old) }
}

# ---- popup window ----
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'FixedToolWindow'
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.StartPosition = 'Manual'
$form.Text = 'Claude usage'
$form.ClientSize = New-Object System.Drawing.Size 300, 236
$form.BackColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font 'Segoe UI', 9

function New-Label([int]$x, [int]$y, [int]$w, [float]$size, [bool]$bold) {
    $l = New-Object System.Windows.Forms.Label
    $l.Location = New-Object System.Drawing.Point $x, $y
    $l.Size = New-Object System.Drawing.Size $w, ([int]($size * 2.4))
    $style = [System.Drawing.FontStyle]::Regular
    if ($bold) { $style = [System.Drawing.FontStyle]::Bold }
    $l.Font = New-Object System.Drawing.Font 'Segoe UI', $size, $style
    $form.Controls.Add($l)
    return $l
}

$lblTitle   = New-Label 14 10 270 12 $true
$lblTitle.Text = 'Claude usage'
$lbl5Head   = New-Label 14 44 270 10 $true
$lbl5Body   = New-Label 14 68 270 9 $false
$lbl5Body.Height = 36
$lblWHead   = New-Label 14 108 270 10 $true
$lblWBody   = New-Label 14 132 270 9 $false
$lblWBody.Height = 36
$lblCtx     = New-Label 14 172 270 8.5 $false
$lblUpdated = New-Label 14 192 270 8.5 $false
$lblBrand   = New-Label 14 212 140 7.5 $true
$lblBrand.Text = 'MIGATRONIX'
$lblBrand.ForeColor = $Magenta
foreach ($l in @($lblCtx, $lblUpdated)) { $l.ForeColor = $Grey }

$form.Add_Deactivate({ $form.Hide() })
$form.Add_FormClosing({
    param($sender, $e)
    if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) { $e.Cancel = $true; $form.Hide() }
})

function Set-WindowText($head, $body, [string]$title, $window, [bool]$withDay, [long]$now) {
    if (-not $window) {
        $head.Text = "$title  -"
        $head.ForeColor = $Grey
        $body.Text = 'no data'
        return
    }
    $pct = [double]$window.used_percentage
    $reset = [long]$window.resets_at
    if ($reset -le $now) {
        $head.Text = "$title  reset"
        $head.ForeColor = $Grey
        $body.Text = "reset at $(Format-Clock $reset $withDay)`r`nawaiting new data"
        return
    }
    $p = [int][math]::Round($pct)
    $head.Text = "$title  $p% used  $Dot  $(100 - $p)% left"
    $head.ForeColor = Get-LevelColor $pct
    $body.Text = "resets in $(Format-Left ($reset - $now))`r`nat $(Format-Clock $reset $withDay)"
}

# ---- tray icon ----
$tray = New-Object System.Windows.Forms.NotifyIcon
$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Show', $null, { Show-Popup })
[void]$menu.Items.Add('Reload', $null, { Update-View })
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Quit', $null, {
    $script:Quitting = $true
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$tray.ContextMenuStrip = $menu

function Update-View {
    $now = Get-Now
    $u = Read-Usage
    $five = $null; $week = $null
    if ($u) { $five = $u.five_hour; $week = $u.seven_day }

    Set-WindowText $lbl5Head $lbl5Body '5-hour' $five $false $now
    Set-WindowText $lblWHead $lblWBody 'Weekly' $week $true $now

    if ($u -and $null -ne $u.context_pct) {
        $lblCtx.Text = "Last session context: $([int][math]::Round([double]$u.context_pct))%"
    } else { $lblCtx.Text = '' }

    if ($u) {
        $age = $now - [long]$u.updated_at
        $mins = [math]::Floor($age / 60)
        $ago = 'just now'
        if ($mins -ge 1 -and $mins -lt 60) { $ago = "$mins min ago" }
        elseif ($mins -ge 60) { $ago = '{0}h {1}m ago' -f [math]::Floor($mins / 60), ($mins % 60) }
        $lblUpdated.Text = "Updated $ago"
        if ($age -gt $StaleAfter) {
            $lblUpdated.Text += ' - open Claude Code to refresh'
            $lblUpdated.ForeColor = $Amber
        } else { $lblUpdated.ForeColor = $Grey }
    } else {
        $lblUpdated.Text = 'No data yet - run claude and send one message'
        $lblUpdated.ForeColor = $Grey
    }

    # NotifyIcon.Text is limited to 63 characters on .NET Framework.
    if ($five -and [long]$five.resets_at -gt $now) {
        $p = [double]$five.used_percentage
        Set-TrayIcon $p (Get-LevelColor $p) $true
        $tray.Text = "Claude 5h: $([int][math]::Round($p))% $Dot reset in $(Format-Left ([long]$five.resets_at - $now))"
    } else {
        Set-TrayIcon 0 $Grey $false
        $tray.Text = 'Claude usage: no current data'
    }
}

function Show-Popup {
    Update-View
    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.Location = New-Object System.Drawing.Point ($area.Right - $form.Width - 12), ($area.Bottom - $form.Height - 12)
    $form.Show()
    $form.Activate()
}

$tray.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($form.Visible) { $form.Hide() } else { Show-Popup }
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30000
$timer.Add_Tick({ Update-View })

# Show the icon only while Claude is open: the desktop app (chat or Code) or Claude Code
# in a terminal, all of which run as claude.exe. Create the file
# %USERPROFILE%\.claude\usage-meter\always-show to keep the icon visible at all times.
$script:Quitting = $false
$AlwaysShowFlag = Join-Path (Join-Path (Join-Path $HOME '.claude') 'usage-meter') 'always-show'
function Update-Visibility {
    if ($script:Quitting) { return }
    $show = (Test-Path $AlwaysShowFlag) -or [bool](Get-Process -Name 'claude' -ErrorAction SilentlyContinue)
    if ($show -and -not $tray.Visible) { Update-View; $tray.Visible = $true }
    elseif (-not $show -and $tray.Visible) { $form.Hide(); $tray.Visible = $false }
}
$visTimer = New-Object System.Windows.Forms.Timer
$visTimer.Interval = 3000
$visTimer.Add_Tick({ Update-Visibility })

Update-View
Update-Visibility
$timer.Start()
$visTimer.Start()

$appContext = New-Object System.Windows.Forms.ApplicationContext
[System.Windows.Forms.Application]::Run($appContext)

$timer.Stop()
$visTimer.Stop()
if ($script:LastHandle -ne [IntPtr]::Zero) { [void][Win32.Icons]::DestroyIcon($script:LastHandle) }
$mutex.ReleaseMutex()
