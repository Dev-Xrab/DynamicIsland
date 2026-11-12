#!/bin/bash
# Display controls for the island's Display page.
#
#   status                 one JSON line: monitors, brightness, text size, mirror state
#   brightness <0-100>     set brightness on the focused monitor (DDC, Apple or backlight)
#   text <+|->             one step larger/smaller text everywhere (9..20 px)
#   mirror                 start/stop mirroring the focused monitor onto another one
#   mode <output> <WxH@Hz> switch resolution/refresh (saved to monitors.lua);
#                          reverts by itself after 15s unless `keep` is run
#   keep | revert          confirm or undo the last mode change
set -uo pipefail

monitors_lua="$HOME/.config/hypr/monitors.lua"
pending="${XDG_RUNTIME_DIR:-/tmp}/island-display-pending"
confirm_seconds=15

focused() { hyprctl -j monitors 2>/dev/null | jq -r '(map(select(.focused)) + .)[0].name // empty'; }

# Set the mode for one output in monitors.lua (Hyprland reloads it).
write_mode() { # output mode
  local out=$1 mode=$2
  [[ -f "$monitors_lua.island-bak" ]] || cp "$monitors_lua" "$monitors_lua.island-bak"
  if grep -qE "^hl\.monitor\(\{ *output *= *\"$out\"" "$monitors_lua"; then
    sed -i -E "/^hl\.monitor\(\{ *output *= *\"$out\"/ s/mode *= *\"[^\"]*\"/mode = \"$mode\"/" "$monitors_lua"
  else
    printf 'hl.monitor({ output = "%s", mode = "%s", position = "auto", scale = omarchy_monitor_scale })\n' \
      "$out" "$mode" >> "$monitors_lua"
  fi
  hyprctl reload >/dev/null 2>&1
}

# Run an install in a visible terminal so the user sees and confirms it.
install_in_terminal() {
  omarchy-launch-floating-terminal-with-presentation "$1" >/dev/null 2>&1 &
}

case "${1:-status}" in
status)
  mon=$(focused)
  bright=$(timeout 4 omarchy-brightness-display --no-osd --monitor "$mon" 2>/dev/null | tr -dc '0-9' | head -c 3)
  [[ $bright =~ ^[0-9]+$ ]] || bright=-1
  text=$(sed -nE 's/^text size: ([0-9]+).*/\1/p' < <(omarchy-display-text-size 2>/dev/null) | head -1)
  [[ $text =~ ^[0-9]+$ ]] || text=12
  mirroring=false; pgrep -x wl-mirror >/dev/null && mirroring=true
  left=0
  if [[ -f $pending ]]; then
    read -r _ _ deadline < "$pending"
    left=$(( deadline - $(date +%s) )); (( left < 0 )) && left=0
  fi
  hyprctl -j monitors 2>/dev/null | jq -c \
    --argjson b "$bright" --argjson t "$text" --argjson left "$left" \
    --argjson m "$mirroring" '
    { monitors: map({ name, model: ((.make // "") + " " + (.model // "") | ltrimstr(" ")),
                      w: .width, h: .height, hz: (.refreshRate | round), rate: .refreshRate, scale, focused,
                      modes: ([.availableModes[] | capture("^(?<w>[0-9]+)x(?<h>[0-9]+)@(?<hz>[0-9.]+)Hz$")
                               | {w: (.w|tonumber), h: (.h|tonumber), hz: (.hz|tonumber), raw: (.w + "x" + .h + "@" + .hz)}]
                              | unique_by(.raw)) }),
      brightness: $b, textSize: $t, mirroring: $m, confirmLeft: $left }'
  ;;

brightness)
  v=${2:-}
  [[ $v =~ ^[0-9]+$ ]] && (( v <= 100 )) || exit 1
  (( v < 1 )) && v=1
  omarchy-brightness-display --no-osd --monitor "$(focused)" "${v}%" >/dev/null 2>&1
  ;;

text)
  cur=$(sed -nE 's/^text size: ([0-9]+).*/\1/p' < <(omarchy-display-text-size 2>/dev/null) | head -1)
  [[ $cur =~ ^[0-9]+$ ]] || cur=12
  case "${2:-}" in
    +) n=$(( cur + 1 )) ;;
    -) n=$(( cur - 1 )) ;;
    *) exit 1 ;;
  esac
  (( n < 9 )) && n=9; (( n > 20 )) && n=20
  omarchy-display-text-size "$n" >/dev/null 2>&1
  ;;

mirror)
  if pgrep -x wl-mirror >/dev/null; then
    pkill -x wl-mirror
    exit 0
  fi
  if ! command -v wl-mirror >/dev/null; then
    install_in_terminal "omarchy-pkg-add wl-mirror"
    exit 0
  fi
  src=$(focused)
  dst=$(hyprctl -j monitors 2>/dev/null | jq -r --arg s "$src" 'map(select(.name != $s))[0].name // empty')
  [[ -n $dst ]] || exit 1
  setsid uwsm-app -- wl-mirror --fullscreen-output "$dst" "$src" >/dev/null 2>&1 &
  ;;

mode)
  out=${2:-}; mode=${3:-}
  [[ $out =~ ^[A-Za-z0-9-]+$ && $mode =~ ^[0-9]+x[0-9]+@[0-9.]+$ ]] || exit 1
  # Only modes the monitor itself reports.
  hyprctl -j monitors 2>/dev/null | jq -e --arg o "$out" --arg m "${mode}Hz" \
    'map(select(.name == $o))[0].availableModes | index($m)' >/dev/null || exit 1
  # Remember what to go back to (the original, if a change is already pending).
  if [[ -f $pending ]]; then
    read -r _ prev _ < "$pending"
  else
    prev=$(hyprctl -j monitors | jq -r --arg o "$out" 'map(select(.name == $o))[0]
      | "\(.width)x\(.height)@\(.refreshRate * 100 | round / 100)"')
  fi
  echo "$out $prev $(( $(date +%s) + confirm_seconds ))" > "$pending"
  write_mode "$out" "$mode"
  # Undo by itself unless confirmed — survives a shell crash or a blank screen.
  token=$(stat -c %Y.%i "$pending")
  setsid bash -c "sleep $confirm_seconds; [[ -f '$pending' && \$(stat -c %Y.%i '$pending') == '$token' ]] && '$0' revert" \
    >/dev/null 2>&1 < /dev/null &
  ;;

keep)
  rm -f "$pending"
  ;;

revert)
  [[ -f $pending ]] || exit 0
  read -r out prev _ < "$pending"
  rm -f "$pending"
  [[ $out =~ ^[A-Za-z0-9-]+$ && $prev =~ ^[0-9]+x[0-9]+@[0-9.]+$ ]] && write_mode "$out" "$prev"
  ;;

esac
exit 0
