#!/bin/bash
# Reply to a phone notification mirrored by KDE Connect.
#   island-phone-reply.sh check <summary> <body>   exit 0 if it can be replied to
#   island-phone-reply.sh send  <summary> <body>   ask for the text, then send it
# KDE Connect shows a phone message as summary = the app ("Messenger") and
# body = "Sender: text", so that is how the phone-side notification is found.
set -uo pipefail
mode=${1:-}; summary=${2:-}; body=${3:-}
svc=org.kde.kdeconnect
id=$(busctl --user call "$svc" /modules/kdeconnect org.kde.kdeconnect.daemon devices bb true true 2>/dev/null \
     | grep -o '"[^"]*"' | head -n1 | tr -d '"')
[[ -n $id ]] || exit 1
base=/modules/kdeconnect/devices/$id/notifications
iface=org.kde.kdeconnect.device.notifications.notification
prop() { busctl --user get-property "$svc" "$1" "$iface" "$2" 2>/dev/null | cut -d' ' -f2- | sed 's/^"//; s/"$//'; }
found=""
for n in $(busctl --user call "$svc" "$base" org.kde.kdeconnect.device.notifications activeNotifications 2>/dev/null \
           | grep -o '"[^"]*"' | tr -d '"' | tac); do
  p=$base/$n
  [[ -n $(prop "$p" replyId) ]] || continue
  app=$(prop "$p" appName); title=$(prop "$p" title)
  if [[ $app == "$summary" && ( -z $title || $body == "$title"* ) ]]; then found=$p; break; fi
done
[[ -n $found ]] || exit 2
[[ $mode == check ]] && exit 0
title=$(prop "$found" title)
text=$(zenity --entry --title="Reply" --text="Reply to ${title:-$summary}" --width=420 2>/dev/null) || exit 3
[[ -n $text ]] || exit 3
busctl --user call "$svc" "$found" "$iface" sendReply s "$text" >/dev/null
