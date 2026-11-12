#!/bin/bash
# Prints the live notification state as one JSON line:
#   {"count": <toasts on screen>, "group": <how many of them share the newest
#    one's app and title, e.g. three Messenger messages>, "newest": ... | null}
# The notification daemon keeps exactly one file per live toast in this
# directory and moves it to history/ the moment it expires, is dismissed, or is
# acted on, so the directory *is* "what is on screen right now". The daemon's
# own toast window is hidden; the island is the only place these are drawn.
set -uo pipefail
dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/notifications"
shopt -s nullglob
files=("$dir"/*.json)
count=${#files[@]}
newest=null
group=0
if (( count > 0 )); then
  # Priority: the newest critical toast (urgency 2) wins over anything newer
  # but less urgent; otherwise simply the newest.
  f=""
  for g in $(printf '%s\n' "${files[@]}" | sort -r); do
    if [[ $(jq -r '.urgency // 1' "$g" 2>/dev/null) == 2 ]]; then f=$g; break; fi
  done
  [[ -n $f ]] || f=$(printf '%s\n' "${files[@]}" | sort | tail -n1)
  newest=$(jq -c . "$f" 2>/dev/null) || newest=null
  [[ -n $newest ]] || newest=null
  if [[ $newest != null ]]; then
    group=$(jq -s --argjson n "$newest" '[.[] | select(.app == $n.app and .summary == $n.summary)] | unique_by(.body) | length' "${files[@]}" 2>/dev/null) || group=1
  fi
fi
distinct=$count
(( count > 1 )) && distinct=$(jq -s '[.[] | [.app, .summary, .body]] | unique | length' "${files[@]}" 2>/dev/null || echo "$count")
printf '{"count":%d,"distinct":%d,"group":%d,"newest":%s}\n' "$count" "${distinct:-$count}" "${group:-1}" "$newest"
