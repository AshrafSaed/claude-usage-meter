#!/bin/bash
# Claude usage status line — MIGATRONIX
# Shows plan usage (5-hour + weekly window), time to next reset, and context usage.
# Input: Claude Code status-line JSON on stdin (rate_limits.* , context_window.*).

input=$(cat)

read -r FIVE_PCT FIVE_RESET WEEK_PCT WEEK_RESET CTX_PCT < <(
  echo "$input" | jq -r '[
    (.rate_limits.five_hour.used_percentage // "-"),
    (.rate_limits.five_hour.resets_at       // "-"),
    (.rate_limits.seven_day.used_percentage // "-"),
    (.rate_limits.seven_day.resets_at       // "-"),
    (.context_window.used_percentage        // "-")
  ] | @tsv' 2>/dev/null
)

RESET=$'\033[0m'
DIM=$'\033[2m'
YELLOW=$'\033[33m'
MAGENTA=$'\033[1;38;2;183;0;106m'

NOW=$(date +%s)

# Shared with the ClaudeUsageBar menu-bar app; percentages and timestamps only.
CACHE="$HOME/.claude/usage-cache.json"
if [ "$FIVE_PCT" != "-" ] || [ "$WEEK_PCT" != "-" ]; then
  echo "$input" | jq -c --argjson now "$NOW" '{
      updated_at: $now,
      five_hour: .rate_limits.five_hour,
      seven_day: .rate_limits.seven_day,
      context_pct: .context_window.used_percentage
    }' > "$CACHE.tmp" 2>/dev/null && mv -f "$CACHE.tmp" "$CACHE"
fi

color_for() {
  local p=$1
  if   [ "$p" -ge 90 ]; then printf '%s' "$MAGENTA"
  elif [ "$p" -ge 70 ]; then printf '%s' "$YELLOW"
  else printf ''; fi
}

# BSD date (macOS) uses -r, GNU date uses -d @
fmt_epoch() {
  date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null
}

fmt_left() {
  local s=$1 d h m
  [ "$s" -le 0 ] && { printf 'now'; return; }
  printf 'in '
  d=$(( s / 86400 )); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

bar() {
  local p=$1 filled i out=""
  filled=$(( (p + 5) / 10 )); [ "$filled" -gt 10 ] && filled=10
  for ((i = 0; i < 10; i++)); do
    if [ "$i" -lt "$filled" ]; then out+="▓"; else out+="░"; fi
  done
  printf '%s' "$out"
}

PARTS=()

if [ "$FIVE_PCT" != "-" ] && [ -n "$FIVE_PCT" ]; then
  P=$(printf '%.0f' "$FIVE_PCT")
  C=$(color_for "$P")
  SEG="5h ${C}$(bar "$P") ${P}%${RESET} used · $(( 100 - P ))% left"
  if [ "$FIVE_RESET" != "-" ]; then
    SEG+=" · reset $(fmt_left $(( FIVE_RESET - NOW ))) ${DIM}($(fmt_epoch "$FIVE_RESET" '%H:%M'))${RESET}"
  fi
  PARTS+=("$SEG")
fi

if [ "$WEEK_PCT" != "-" ] && [ -n "$WEEK_PCT" ]; then
  P=$(printf '%.0f' "$WEEK_PCT")
  C=$(color_for "$P")
  SEG="7d ${C}${P}%${RESET} used"
  if [ "$WEEK_RESET" != "-" ]; then
    SEG+=" · reset $(fmt_left $(( WEEK_RESET - NOW ))) ${DIM}($(fmt_epoch "$WEEK_RESET" '%a %H:%M'))${RESET}"
  fi
  PARTS+=("$SEG")
fi

if [ ${#PARTS[@]} -eq 0 ]; then
  PARTS+=("${DIM}usage: waiting for first reply${RESET}")
fi

if [ "$CTX_PCT" != "-" ] && [ -n "$CTX_PCT" ]; then
  P=$(printf '%.0f' "$CTX_PCT")
  PARTS+=("ctx $(color_for "$P")${P}%${RESET}")
fi

OUT=""
for p in "${PARTS[@]}"; do
  OUT+="${OUT:+ ${DIM}│${RESET} }$p"
done
printf '%s\n' "$OUT"
