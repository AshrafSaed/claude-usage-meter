# Claude Usage Meter

See how much of your Claude plan you have used, how much is left, and when it resets — always visible on your desktop.

- **macOS:** a menu-bar item next to the clock, plus a usage line in the Claude Code terminal.
- **Windows:** a tray icon next to the clock, plus the same usage line in the terminal.

Developed by **MIGATRONIX – Automation & Control Solutions** · Engineering & Development: Ashraf Saed

<p align="center">
  <img src="docs/images/preview-mac.svg" alt="ClaudeUsageBar on macOS: menu-bar item and popover with 5-hour and weekly rings" width="640">
</p>

<p align="center">
  <img src="docs/images/preview-statusline.svg" alt="Usage line at the bottom of Claude Code in the terminal" width="820">
</p>

<p align="center">
  <img src="docs/images/preview-windows.svg" alt="ClaudeUsageTray on Windows: tray icon, tooltip and popup window" width="640">
</p>

<sub>Images are illustrations with example values.</sub>

---

## Contents

1. [What it shows](#what-it-shows)
2. [How it works](#how-it-works)
3. [Requirements](#requirements)
4. [Install on macOS](#install-on-macos)
5. [Install on Windows](#install-on-windows)
6. [Daily use](#daily-use)
7. [Uninstall](#uninstall)
8. [Troubleshooting](#troubleshooting)
9. [Limitations](#limitations)
10. [Privacy and security](#privacy-and-security)
11. [Project layout](#project-layout)

---

## What it shows

| Item | Meaning |
|---|---|
| **5-hour** | Share of the rolling 5-hour usage window already used, what is left, and when it resets |
| **Weekly** | Share of the 7-day usage window already used and when it resets |
| **ctx** | How full the current conversation's context window is |
| **Updated** | How old the numbers are |

Colors: normal below 70 % · **amber** from 70 % · **magenta** from 90 % (almost at the limit).

The meter shows **percent used and reset time**, not a raw token count. Claude Code exposes only these two values for plan limits; a "tokens left" number is not available from any official source.

## How it works

<p align="center">
  <img src="docs/images/architecture.svg" alt="Claude Code sends JSON to the status-line script, which prints the terminal line and writes usage-cache.json; the menu-bar or tray app reads that file" width="820">
</p>

1. Claude Code runs a **status-line script** after each reply and passes it session data as JSON on stdin. For Pro and Max subscribers this includes `rate_limits.five_hour` and `rate_limits.seven_day`, each with `used_percentage` and `resets_at` ([Claude Code status line docs](https://code.claude.com/docs/en/statusline)).
2. The script prints the usage line at the bottom of Claude Code **and** saves the numbers to `~/.claude/usage-cache.json`.
3. The **menu-bar app** (macOS) or **tray app** (Windows) re-reads that file every 30 seconds and shows it next to the clock.

Nothing is sent over the network. The apps only read a local file.

## Requirements

| | macOS | Windows |
|---|---|---|
| Claude plan | Pro or Max | Pro or Max |
| Claude Code CLI | installed and signed in (`claude --version`) | installed and signed in (`claude --version`) |
| OS version | macOS 13 Ventura or later | Windows 10 / 11 |
| Tools | `jq` (included in recent macOS; otherwise `brew install jq`) and Xcode Command Line Tools (`xcode-select --install`) | Windows PowerShell 5.1 (built in) — nothing else to install |

> The `rate_limits` data appears only for Pro/Max subscribers, and only after the first reply in a session.

---

## Install on macOS

> Tested on macOS 27 (Apple Silicon), Swift 6.4, bash 3.2, jq 1.7.1.

### Quick install

```bash
git clone https://github.com/AshrafSaed/claude-usage-meter.git
cd claude-usage-meter/mac
bash setup-all.sh
```

Then open a terminal, run `claude`, and send one message. The menu-bar item fills in within 30 seconds.

### Step by step

**Step 1 — Check the tools.**

```bash
claude --version     # Claude Code is installed
jq --version         # if missing: brew install jq
swiftc --version     # if missing: xcode-select --install
```

**Step 2 — Get the files.** Clone the repository (above) or download it as ZIP from GitHub (**Code → Download ZIP**) and unzip it.

**Step 3 — Install the status line.**

```bash
cd claude-usage-meter/mac
bash install.sh
```

What this does:
- copies `statusline-usage.sh` to `~/.claude/statusline-usage.sh` and makes it executable;
- backs up `~/.claude/settings.json` to `settings.json.bak-<date>`;
- adds this block to `settings.json` (your other settings are kept):

```json
"statusLine": {
  "type": "command",
  "command": "/Users/<you>/.claude/statusline-usage.sh",
  "refreshInterval": 30
}
```

**Step 4 — Build and start the menu-bar app.**

```bash
bash build-menubar.sh
```

What this does:
- compiles `ClaudeUsageBar.swift` with `swiftc` into `~/Applications/ClaudeUsageBar.app`;
- writes its `Info.plist` (`LSUIElement` = no Dock icon);
- signs it locally (ad-hoc) and launches it.

**Step 5 — Feed it data.** Open a new terminal, run `claude`, and send any message. After the reply:
- the usage line appears at the bottom of Claude Code;
- the menu-bar item changes from `—` to something like `24% · 2h 14m`.

**Step 6 — Start at login (optional).** System Settings → General → **Login Items** → **+** → choose `ClaudeUsageBar` from the **Applications** folder inside your home folder.

---

## Install on Windows

> ⚠️ **Not yet tested on a Windows machine.** The status-line script was tested with PowerShell 7 (output identical to the macOS version) and all scripts pass the PowerShell parser, but the tray app has not been run on Windows. Please open an issue if something does not work.

### Quick install

Open **PowerShell** (Start → type `PowerShell` → Enter):

```powershell
git clone https://github.com/AshrafSaed/claude-usage-meter.git
cd claude-usage-meter\windows
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

No Git? On GitHub click **Code → Download ZIP**, unzip it, then in PowerShell `cd` into the `windows` folder and run the last line.

Then run `claude`, send one message, and look for the ring icon next to the clock.

### Step by step

**Step 1 — Check Claude Code.**

```powershell
claude --version
```

**Step 2 — Get the files.** Clone or download the repository (above).

**Step 3 — Run the installer.**

```powershell
cd claude-usage-meter\windows
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

`-ExecutionPolicy Bypass` applies to this one command only; it does not change your system policy.

What this does:
- copies `statusline-usage.ps1` and `ClaudeUsageTray.ps1` to `%USERPROFILE%\.claude\usage-meter\`;
- backs up `%USERPROFILE%\.claude\settings.json` to `settings.json.bak-<date>`;
- adds the `statusLine` block to `settings.json` (paths use forward slashes, because Claude Code may run the command through Git Bash, which drops backslashes):

```json
"statusLine": {
  "type": "command",
  "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/<you>/.claude/usage-meter/statusline-usage.ps1\"",
  "refreshInterval": 30
}
```

- creates a shortcut in your **Startup** folder so the tray app starts when you sign in;
- starts the tray app now.

Options: `-NoTray` installs only the status line; `-NoStartup` skips the Startup shortcut.

**Step 4 — Feed it data.** Open a new terminal, run `claude`, send any message.

**Step 5 — Find the icon.** A ring icon appears next to the clock. If you don't see it, click the **^** arrow (hidden icons) and drag the ring onto the taskbar.
- **Hover** → tooltip such as `Claude 5h: 24% · reset in 2h 14m`
- **Left-click** → popup with 5-hour and weekly details
- **Right-click** → Show · Reload · Quit

---

## Daily use

1. Glance at the menu bar (macOS) or the tray icon (Windows).
2. Click it for the full breakdown: percent used, percent left, time to reset, reset clock time.
3. The numbers refresh whenever Claude Code is running in a terminal. If they are older than 15 minutes, the popup shows an amber "Updated … ago" note — send a message in `claude` to refresh.

## Uninstall

**macOS**

```bash
pkill -x ClaudeUsageBar
rm -rf ~/Applications/ClaudeUsageBar.app
rm ~/.claude/statusline-usage.sh ~/.claude/usage-cache.json
# restore settings: copy back the newest backup, or delete the "statusLine" block
cp ~/.claude/settings.json.bak-<date> ~/.claude/settings.json
```

Also remove it from **Login Items** if you added it.

**Windows (PowerShell)**

```powershell
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -like '*ClaudeUsageTray.ps1*' | ForEach-Object { Stop-Process -Id $_.ProcessId }
Remove-Item "$([Environment]::GetFolderPath('Startup'))\ClaudeUsageTray.lnk"
Remove-Item -Recurse "$HOME\.claude\usage-meter"
Remove-Item "$HOME\.claude\usage-cache.json"
# restore settings: copy back the newest backup, or delete the "statusLine" block
Copy-Item "$HOME\.claude\settings.json.bak-<date>" "$HOME\.claude\settings.json"
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Menu-bar / tray shows `—` or "No data yet" | No Claude Code session has replied yet. Run `claude` and send one message. |
| Terminal line says `usage: waiting for first reply` | Normal before the first reply. If it stays after replies, your plan may not be Pro/Max, or you are signed in with an API key instead of a subscription. |
| macOS: menu-bar item not visible | Too many menu-bar items — macOS hides the overflow, especially around the camera notch. Remove some items, or quit and reopen `ClaudeUsageBar`. |
| macOS: `swiftc not found` | `xcode-select --install` |
| macOS: `jq is required` | `brew install jq` |
| Windows: icon not visible | Click **^** next to the clock; drag the ring icon onto the taskbar. |
| Windows: script blocked by policy | Run it with `powershell -NoProfile -ExecutionPolicy Bypass -File …` as shown. |
| Numbers look old | The apps only update while Claude Code runs. Chat in the Claude desktop or web app does not write the file. |

## Limitations

- **Data source:** only Claude Code (CLI) writes the numbers, so they refresh only while Claude Code runs. Using Claude only in the chat app (desktop or web) does not update the meter.
- **No token count:** Claude Code reports percent used and reset time, not tokens remaining.
- **Plans:** `rate_limits` is present only for claude.ai Pro and Max subscribers.
- **Inside the chat window:** a third-party tool cannot add UI to the Claude desktop or web app, which is why the meter lives in the menu bar / tray.
- **Windows:** not yet verified on real hardware (see the note above). A console window may flash briefly when the tray app starts.

## Privacy and security

- The cache file holds only percentages and Unix timestamps — no prompts, no account data, no tokens or keys.
- No network access: the scripts and apps read and write local files only.
- The installers back up `settings.json` before changing it and only add or replace the `statusLine` key.
- The macOS app is built and signed locally on your machine (ad-hoc), so there is no downloaded binary to trust.

## Project layout

```
claude-usage-meter/
├── mac/
│   ├── statusline-usage.sh     # status line for Claude Code + writes usage-cache.json
│   ├── ClaudeUsageBar.swift    # SwiftUI menu-bar app (macOS 13+)
│   ├── build-menubar.sh        # compiles, signs and launches ClaudeUsageBar.app
│   ├── install.sh              # installs the status line into ~/.claude
│   └── setup-all.sh            # install.sh + build-menubar.sh
├── windows/
│   ├── statusline-usage.ps1    # same status line, PowerShell 5.1+
│   ├── ClaudeUsageTray.ps1     # WinForms tray app
│   └── install.ps1             # installs status line, Startup shortcut, starts tray app
└── docs/images/                # README illustrations
```

## Disclaimer

Independent project. Not affiliated with or endorsed by Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic.

## License

[MIT](LICENSE) © 2026 Ashraf Saed | MIGATRONIX
