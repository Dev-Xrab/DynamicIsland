#!/usr/bin/env bash
# What the machine is busy with, for the island's Activity pane.
# Prints one JSON object:
#   {"procs":[{"pid":1,"name":"x","cpu":12.3,"mem":120}],  # top by current CPU, mem in MiB
#    "count":312, "load":"0.52 0.61 0.70", "rx":123, "tx":456}   # rx/tx: total bytes, all non-loopback links
# Run only while the pane is on screen. CPU is sampled over 0.4s (top's second
# frame), so it is the current load, not the lifetime average ps reports.
set -u

procs=$(top -b -n 2 -d 0.4 -w 512 -o %CPU 2>/dev/null | awk '
  /^top -/ { frame++ ; next }
  frame == 2 && /^ *PID/ { inlist = 1; next }
  frame == 2 && inlist && NF >= 12 {
    # PID USER PR NI VIRT RES SHR S %CPU %MEM TIME+ COMMAND...
    if ($12 == "top") next
    res = $6
    if (res ~ /g$/) res = substr(res, 1, length(res) - 1) * 1024 * 1024
    else if (res ~ /m$/) res = substr(res, 1, length(res) - 1) * 1024
    name = $12
    for (i = 13; i <= NF && length(name) < 40; i++) name = name " " $i
    gsub(/\\/, "\\\\", name); gsub(/"/, "\\\"", name)
    if (n++ < 7) printf "%s{\"pid\":%d,\"name\":\"%s\",\"cpu\":%.1f,\"mem\":%d}", (n > 1 ? "," : ""), $1, name, $9, res / 1024
  }')

count=$(ls -d /proc/[0-9]* 2>/dev/null | wc -l)
read -r l1 l2 l3 _ < /proc/loadavg
read -r rx tx < <(awk -F'[: ]+' 'NR > 2 && $2 != "lo" { rx += $3; tx += $11 } END { printf "%d %d\n", rx, tx }' /proc/net/dev)

printf '{"procs":[%s],"count":%d,"load":"%s %s %s","rx":%s,"tx":%s}\n' "$procs" "$count" "$l1" "$l2" "$l3" "${rx:-0}" "${tx:-0}"
