#!/usr/bin/env bash
# Claude Code statusLine command — Horizon theme palette (pastel/airy variant)
# Static colors for structural elements:
#   git branch= pale peach    #FDD4BB
#   model     = soft pink     #F4A8D0
# Dynamic gradient (ctx%, 5h%, 7d%): each field independently interpolates
#   0%   → cyan-green  rgb(100,220,180)
#   50%  → gold-amber  rgb(220,190,80)
#   100% → coral-red   rgb(240,90,90)

input=$(cat)

# Git branch (skip optional locks to avoid contention)
branch=$(git -C "$(echo "$input" | jq -r '.cwd // empty')" --no-optional-locks \
         rev-parse --abbrev-ref HEAD 2>/dev/null)
dirty=$(git -C "$(echo "$input" | jq -r '.cwd // empty')" --no-optional-locks \
        status --porcelain 2>/dev/null | head -1)

# --- Claude Code context ---
model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# --- ANSI color helpers (truecolor) — static pastel Horizon palette ---
peach=$'\033[38;2;253;212;187m'    # #FDD4BB — git branch (pale peach)
pink=$'\033[38;2;244;168;208m'     # #F4A8D0 — model (soft pink)
reset=$'\033[0m'

# --- Gradient color function ---
# Usage: gradient_color <percentage>
# Prints an ANSI truecolor escape sequence interpolated:
#   0%  → rgb(100,220,180)  cyan-green
#   50% → rgb(220,190, 80)  gold-amber  (midpoint)
#   100%→ rgb(240, 90, 90)  coral-red
# Two-segment linear interpolation (0→50 and 50→100).
gradient_color() {
  local pct="$1"
  # Clamp to [0,100]
  pct=$(awk "BEGIN { p=$pct; if(p<0)p=0; if(p>100)p=100; print p }")
  # Two-leg interpolation via awk
  read -r r g b <<< "$(awk -v p="$pct" 'BEGIN {
    if (p <= 50) {
      t = p / 50
      r = int(100 + (220 - 100) * t)
      g = int(220 + (190 - 220) * t)
      b = int(180 + ( 80 - 180) * t)
    } else {
      t = (p - 50) / 50
      r = int(220 + (240 - 220) * t)
      g = int(190 + ( 90 - 190) * t)
      b = int( 80 + ( 90 -  80) * t)
    }
    print r, g, b
  }')"
  printf "\033[38;2;%d;%d;%dm" "$r" "$g" "$b"
}

# --- Build output ---
# git branch (peach/salmon), with * if dirty
if [ -n "$branch" ]; then
  if [ -n "$dirty" ]; then
    printf " ${peach}%s*${reset}" "$branch"
  else
    printf " ${peach}%s${reset}" "$branch"
  fi
fi

# model name (pink/magenta), if available
if [ -n "$model" ]; then
  printf " ${pink}%s${reset}" "$model"
fi

# context usage — gradient color based on ctx% value
if [ -n "$used_pct" ]; then
  clr=$(gradient_color "$used_pct")
  printf " %sctx:$(printf '%.0f' "$used_pct")%%%s" "$clr" "$reset"
fi

# 5-hour rate limit — gradient color based on 5h% value
if [ -n "$five_hour_pct" ]; then
  clr=$(gradient_color "$five_hour_pct")
  printf " %s5h:$(printf '%.0f' "$five_hour_pct")%%%s" "$clr" "$reset"
fi

# 7-day rate limit — gradient color based on 7d% value
if [ -n "$seven_day_pct" ]; then
  clr=$(gradient_color "$seven_day_pct")
  printf " %s7d:$(printf '%.0f' "$seven_day_pct")%%%s" "$clr" "$reset"
fi
