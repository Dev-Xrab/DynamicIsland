#!/bin/bash
# Streams Unity Editor events as JSON lines, from the open project's
# Logs/Editor.log (falls back to ~/.config/unity3d/Editor.log):
#   {"ev":"compile"}                         script compilation started
#   {"ev":"compiled","ok":true,"secs":"1.2"}  compilation finished
#   {"ev":"error","msg":"Assets/X.cs(3,4): error CS1002: ; expected"}
#   {"ev":"reload"} / {"ev":"reloaded","ms":4166}   domain reload
#   {"ev":"build","result":"Succeeded","secs":"12"}  player build finished
#   {"ev":"project","name":"Last Light"}     the editor (re)opened a project
#   {"ev":"closed"}                          no editor running
set -uo pipefail
current=""; tailpid=""
cleanup() { [[ -n $tailpid ]] && { pkill -P "$tailpid" 2>/dev/null; kill "$tailpid" 2>/dev/null; }; }
trap cleanup EXIT
trap 'exit 0' TERM INT HUP
logfor() {
  local pid proj
  pid=$(pgrep -f -- '/Editor/Unity( |$)' | head -n1)
  [[ -n $pid ]] || return 1
  proj=$(tr '\0' '\n' < /proc/$pid/cmdline | awk 'f{print; exit} tolower($0)=="-projectpath"{f=1}')
  if [[ -n $proj && -f $proj/Logs/Editor.log ]]; then printf '%s\n' "$proj/Logs/Editor.log"
  else printf '%s\n' "$HOME/.config/unity3d/Editor.log"; fi
}
parse() {
  awk -v q='"' '
    function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, " ", s); return s }
    /^Starting: .*bee_backend/                 { print "{\"ev\":\"compile\"}"; fflush(); next }
    /^\*\*\* Tundra build (success|failed)/    { ok = ($0 ~ /success/) ? "true" : "false"
                                                 s = $0; sub(/.*\(/, "", s); sub(/ seconds.*/, "", s)
                                                 print "{\"ev\":\"compiled\",\"ok\":" ok ",\"secs\":\"" esc(s) "\"}"; fflush(); next }
    /: error CS[0-9]+:/                         { print "{\"ev\":\"error\",\"msg\":\"" esc(substr($0, 1, 300)) "\"}"; fflush(); next }
    /^Begin MonoManager ReloadAssembly/         { print "{\"ev\":\"reload\"}"; fflush(); next }
    /^Domain Reload Profiling: [0-9]+ms/        { m = $4; sub(/ms/, "", m); print "{\"ev\":\"reloaded\",\"ms\":" m+0 "}"; fflush(); next }
    /Build completed with a result of/          { r = $0; sub(/.*result of .?/, "", r); sub(/.? in .*/, "", r)
                                                 s = $0; sub(/.* in /, "", s); sub(/ second.*/, "", s)
                                                 print "{\"ev\":\"build\",\"result\":\"" esc(r) "\",\"secs\":\"" esc(s) "\"}"; fflush(); next }
  '
}
while :; do
  log=$(logfor) || log=""
  if [[ $log != "$current" ]]; then
    cleanup; tailpid=""
    current=$log
    if [[ -n $log ]]; then
      proj=$(basename "$(dirname "$(dirname "$log")")")
      [[ $log == "$HOME/.config/unity3d/Editor.log" ]] && proj="Unity"
      printf '{"ev":"project","name":"%s"}\n' "${proj//\"/}"
      # --pid: the tail goes away with this script even if it is killed hard.
      ( tail -n0 -F --pid=$$ "$log" 2>/dev/null | parse ) &
      tailpid=$!
    else
      echo '{"ev":"closed"}'
    fi
  fi
  sleep 5
done
