# Claude usage status line - MIGATRONIX (Windows)
# Shows plan usage (5-hour + weekly window), time to next reset, and context usage.
# Input: Claude Code status-line JSON on stdin. Compatible with Windows PowerShell 5.1 and PowerShell 7.
# Non-ASCII glyphs are built from code points so the file stays pure ASCII (PS 5.1 reads BOM-less files as ANSI).

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$raw = $input | Out-String
$data = $null
try { $data = $raw | ConvertFrom-Json } catch { }

$esc     = [char]27
$RESET   = "$esc[0m"
$DIM     = "$esc[2m"
$YELLOW  = "$esc[33m"
$MAGENTA = "$esc[1;38;2;183;0;106m"
$FULL    = [string][char]0x2593
$EMPTY   = [string][char]0x2591
$DOT     = [string][char]0x00B7
$SEP     = [string][char]0x2502

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$five = $null; $week = $null; $ctx = $null
if ($data) {
    if ($data.rate_limits) {
        $five = $data.rate_limits.five_hour
        $week = $data.rate_limits.seven_day
    }
    if ($data.context_window) { $ctx = $data.context_window.used_percentage }
}

# Shared with the ClaudeUsageTray app; percentages and timestamps only.
if ($five -or $week) {
    $cache = Join-Path (Join-Path $HOME '.claude') 'usage-cache.json'
    $obj = [ordered]@{ updated_at = $now; five_hour = $five; seven_day = $week; context_pct = $ctx }
    $json = $obj | ConvertTo-Json -Compress -Depth 4
    [IO.File]::WriteAllText("$cache.tmp", $json, (New-Object System.Text.UTF8Encoding $false))
    Move-Item -Force "$cache.tmp" $cache
}

function ColorFor([int]$p) {
    if ($p -ge 90) { return $MAGENTA }
    if ($p -ge 70) { return $YELLOW }
    return ''
}

function FmtLeft([long]$s) {
    if ($s -le 0) { return 'now' }
    $d = [math]::Floor($s / 86400); $h = [math]::Floor(($s % 86400) / 3600); $m = [math]::Floor(($s % 3600) / 60)
    if ($d -gt 0) { return ('in {0}d{1}h' -f $d, $h) }
    if ($h -gt 0) { return ('in {0}h{1:D2}m' -f $h, [int]$m) }
    return ('in {0}m' -f $m)
}

function LocalClock([long]$epoch, [string]$fmt) {
    [DateTimeOffset]::FromUnixTimeSeconds($epoch).ToLocalTime().ToString($fmt, [Globalization.CultureInfo]::InvariantCulture)
}

function Bar([int]$p) {
    $filled = [math]::Min(10, [math]::Floor(($p + 5) / 10))
    return ($FULL * $filled) + ($EMPTY * (10 - $filled))
}

$parts = @()

if ($five -and $null -ne $five.used_percentage) {
    $p = [int][math]::Round([double]$five.used_percentage)
    $c = ColorFor $p
    $seg = "5h $c$(Bar $p) $p%$RESET used $DOT $(100 - $p)% left"
    if ($five.resets_at) {
        $r = [long]$five.resets_at
        $seg += " $DOT reset $(FmtLeft ($r - $now)) $DIM($(LocalClock $r 'HH:mm'))$RESET"
    }
    $parts += $seg
}

if ($week -and $null -ne $week.used_percentage) {
    $p = [int][math]::Round([double]$week.used_percentage)
    $c = ColorFor $p
    $seg = "7d $c$p%$RESET used"
    if ($week.resets_at) {
        $r = [long]$week.resets_at
        $seg += " $DOT reset $(FmtLeft ($r - $now)) $DIM($(LocalClock $r 'ddd HH:mm'))$RESET"
    }
    $parts += $seg
}

if ($parts.Count -eq 0) { $parts += "${DIM}usage: waiting for first reply$RESET" }

if ($null -ne $ctx) {
    $p = [int][math]::Round([double]$ctx)
    $parts += "ctx $(ColorFor $p)$p%$RESET"
}

Write-Output ($parts -join " $DIM$SEP$RESET ")
