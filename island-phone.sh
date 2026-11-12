#!/bin/bash
# The first paired KDE Connect phone as one JSON line:
#   {"id","name","reachable","charge","charging"}   or {} when there is none.
set -uo pipefail
svc=org.kde.kdeconnect
get() { busctl --user get-property "$svc" "$1" "$2" "$3" 2>/dev/null | cut -d' ' -f2-; }
id=$(busctl --user call "$svc" /modules/kdeconnect org.kde.kdeconnect.daemon devices bb false true 2>/dev/null \
     | grep -o '"[^"]*"' | head -n1 | tr -d '"')
[[ -n $id ]] || { echo '{}'; exit 0; }
dev=/modules/kdeconnect/devices/$id
name=$(get "$dev" org.kde.kdeconnect.device name | sed 's/^"//; s/"$//')
reach=$(get "$dev" org.kde.kdeconnect.device isReachable)
charge=$(get "$dev/battery" org.kde.kdeconnect.device.battery charge)
charging=$(get "$dev/battery" org.kde.kdeconnect.device.battery isCharging)
jq -cn --arg id "$id" --arg name "$name" --arg r "${reach:-false}" --arg c "${charge:--1}" --arg ch "${charging:-false}" \
  '{id:$id, name:$name, reachable:($r=="true"), charge:($c|tonumber? // -1), charging:($ch=="true")}'
