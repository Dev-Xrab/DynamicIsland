#!/usr/bin/env bash
# Live state for the island's Control Center, one JSON line. Run every 2s,
# only while Control Center is on screen.
#   cpu, memUsed, memTotal, memPct   from island-stats.sh (/proc)
#   rx, tx                           total bytes, all non-loopback links
#   profile, profiles                power-profiles-daemon ("" when not installed)
#   vpns                             NetworkManager VPN / WireGuard profiles
#
# Actions (each prints nothing; the panel re-reads right after):
#   profile <name>        powerprofilesctl set <name>
#   vpn <name> up|down    nmcli connection up|down id <name>
set -uo pipefail
here=$(dirname "$(readlink -f "$0")")

case "${1:-status}" in
profile)
  [[ ${2:-} =~ ^(power-saver|balanced|performance)$ ]] || { echo "bad profile" >&2; exit 2; }
  exec powerprofilesctl set "$2"
  ;;
vpn)
  name=${2:-}; verb=${3:-}
  [[ -n $name && $verb =~ ^(up|down)$ ]] || { echo "usage: vpn <name> up|down" >&2; exit 2; }
  exec nmcli connection "$verb" id "$name"
  ;;
esac

stats=$("$here/island-stats.sh" 2>/dev/null || echo '{}')
read -r rx tx < <(awk -F'[: ]+' 'NR > 2 && $2 != "lo" { rx += $3; tx += $11 } END { printf "%d %d\n", rx, tx }' /proc/net/dev)

profile=""; profiles="[]"
if command -v powerprofilesctl >/dev/null 2>&1; then
  profile=$(powerprofilesctl get 2>/dev/null || true)
  profiles=$(powerprofilesctl list 2>/dev/null | sed -nE 's/^[* ] *([a-z-]+):$/"\1"/p' | paste -sd, | sed 's/^/[/; s/$/]/')
  [[ $profiles == "[]" || -z $profiles ]] && profiles="[]"
fi

vpns="[]"
if command -v nmcli >/dev/null 2>&1; then
  vpns="[$(nmcli -t -f NAME,TYPE,ACTIVE connection show 2>/dev/null \
    | awk -F: '$2 ~ /^(vpn|wireguard)$/ { gsub(/"/, "\\\"", $1); printf "%s{\"name\":\"%s\",\"type\":\"%s\",\"active\":%s}", (n++ ? "," : ""), $1, $2, ($3 == "yes" ? "true" : "false") }')]"
fi

printf '{"stats":%s,"rx":%s,"tx":%s,"profile":"%s","profiles":%s,"vpns":%s}\n' \
  "$stats" "${rx:-0}" "${tx:-0}" "$profile" "$profiles" "$vpns"
