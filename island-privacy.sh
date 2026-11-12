#!/bin/bash
# Which apps are using the microphone, the camera, or sharing the screen.
#
#   island-privacy.sh            -> {"mic":["Discord"],"camera":[],"screen":["Google Chrome"],
#                                    "uses":[{"kind":"mic","app":"Discord","bin":"Discord","pid":1234,
#                                             "device":"Built-in Audio Analog Stereo","media":"…"}, …]}
#   island-privacy.sh FILE.json  -> same, read from a saved `pw-dump` (for testing)
#
# Read from PipeWire's graph: a capture stream counts only while it is running
# and linked to a real device, so audio visualisers that listen to the speaker
# output (sink monitors) and level meters do not light the mic dot. Programs
# that open /dev/video* directly (not through PipeWire) are found with fuser.

src=${1:-}
if [[ -n $src ]]; then dump=$(cat "$src"); else dump=$(pw-dump 2>/dev/null || echo '[]'); fi

direct_cam='[]'
if [[ -z $src ]] && compgen -G "/dev/video*" >/dev/null; then
  direct_cam=$(
    fuser /dev/video* 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | sort -u |
      while read -r pid; do
        comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
        case $comm in pipewire|wireplumber|pipewire-media-session) continue ;; esac
        dev=""
        for v in /proc/$pid/fd/*; do
          t=$(readlink "$v" 2>/dev/null) || continue
          [[ $t == /dev/video* ]] || continue
          dev=$(cat "/sys/class/video4linux/${t#/dev/}/name" 2>/dev/null || echo "$t"); break
        done
        jq -nc --arg app "$comm" --argjson pid "$pid" --arg dev "$dev" \
          '{kind:"camera", app:$app, bin:$app, pid:$pid, device:$dev, media:""}'
      done | jq -sc '.'
  )
fi

jq -c --argjson direct "$direct_cam" '
  def props: .info.props // {};
  def appname: props as $p
    | ($p["application.name"] // $p["application.process.binary"] // $p["node.description"] // $p["node.name"] // "App")
    | sub(" (input|output)$"; "");
  def devname: props as $p | ($p["node.description"] // $p["node.nick"] // $p["node.name"] // "");
  # Stream names that say nothing ("RecordStream") are dropped.
  def medianame: (props["media.name"] // "") as $m
    | if ($m | test("^(RecordStream|record|Recording|capture|Capture|Playback|playback|input|ALSA Capture)$")) then "" else $m end;

  [ .[] | select(.type == "PipeWire:Interface:Node") ] as $nodes
  | ($nodes | map({key: (.id | tostring), value: .}) | from_entries) as $byId
  | [ .[] | select(.type == "PipeWire:Interface:Link") | .info ] as $links
  | def sources($id): [ $links[] | select(.["input-node-id"] == $id) | $byId[(.["output-node-id"] | tostring)] // empty ];

  [ $nodes[]
    | select((props["media.class"] // "") | startswith("Stream/Input/"))
    | select(.info.state == "running")
    | select((props["stream.monitor"] // false) | not)
    | . as $s
    | sources($s.id) as $src
    | ($src | map(props["media.class"] // "")) as $cls
    | {app: appname, bin: (props["application.process.binary"] // ""),
       pid: (props["application.process.id"] // 0), media: medianame} as $base
    | if (props["media.class"] == "Stream/Input/Audio") and any($cls[]; startswith("Audio/Source") or . == "Audio/Duplex") then
        $base + {kind: "mic", device: ([$src[] | select((props["media.class"] // "") | startswith("Audio/Source") or . == "Audio/Duplex") | devname][0] // "")}
      elif props["media.class"] == "Stream/Input/Video" then
        if any($src[]; ((props["device.api"] // "") | test("v4l2|libcamera")) or (props["media.role"] // "") == "Camera")
        then $base + {kind: "camera", device: ([$src[] | devname][0] // "")}
        elif ($src | length) > 0 then $base + {kind: "screen", device: "Screen"}
        else empty end
      else empty end
  ] as $pw
  | ($pw + $direct) as $uses
  | {
      mic:    [ $uses[] | select(.kind == "mic")    | .app ] | unique,
      camera: [ $uses[] | select(.kind == "camera") | .app ] | unique,
      screen: [ $uses[] | select(.kind == "screen") | .app ] | unique,
      uses:   ($uses | unique_by([.kind, .app, .pid, .device]))
    }
' <<<"$dump" 2>/dev/null || echo '{"mic":[],"camera":[],"screen":[],"uses":[]}'
