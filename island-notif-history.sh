#!/bin/bash
# The notification history, newest first, as one JSON array (at most 60).
# Each entry is the daemon's own history file plus "file" (its path), so the
# island can delete one. The daemon moves every toast here when it leaves the
# screen, and writes notifications silenced by Do Not Disturb straight here.
set -uo pipefail
dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/notifications/history"
shopt -s nullglob
files=("$dir"/*.json)
(( ${#files[@]} > 0 )) || { echo '[]'; exit 0; }
mapfile -t recent < <(printf '%s\n' "${files[@]}" | sort -r | head -n 60)
jq -c '. + {file: input_filename}' "${recent[@]}" 2>/dev/null | jq -sc 'sort_by(-(.timestamp // 0))' 2>/dev/null || echo '[]'
