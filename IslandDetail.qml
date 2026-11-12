import QtQuick
import Quickshell
import Quickshell.Io

// A detail view living *inside* the island. Opening one slides the card row
// out and this in; Escape or the back affordance reverses it. The island never
// hands a detail off to a popup outside its own surface.
//
// Every pane is sized to the content it actually has (IslandTokens.detailHeightFor)
// and carries only the facts the panel is for — the earlier version padded all
// five to the tallest one and filled the space with rows that were usually "—".
Item {
  id: detail

  required property var tk
  required property var sys
  // IslandStatus: the notification history for the Notifications pane.
  property var status: null
  property string kind: ""
  property bool revealed: false

  signal back()
  // A pane asking for another pane (Control Center -> Network, Sound ...).
  signal openDetail(string kind)
  // Fold the whole island away (the record pane starts a capture after this,
  // so the island is not in the recording or over the region picker).
  signal closeRequested()
  // Island style row in the Display pane: Black (false) or Glass (true).
  signal setIslandGlass(bool on)

  function runAfterClose(argv) {
    detail.closeRequested()
    detailDeferred.argv = argv
    detailDeferred.restart()
  }
  Timer {
    id: detailDeferred
    property var argv: []
    interval: detail.tk.collapseDuration + 60
    onTriggered: Quickshell.execDetached(argv)
  }

  // ------------------------------------------------------------ record state
  // The same choices as Omarchy's Screenrecord menu (omarchy-menu.jsonc).
  // The capture tool asks for a region or window (or the whole screen) first.
  property bool recWebcam: false
  Process {
    id: webcamProbe
    command: ["omarchy-hw-webcam"]
    running: detail.kind === "record"
    onExited: function(code) { detail.recWebcam = code === 0 }
  }
  readonly property var recOptions: {
    var base = ["omarchy-capture-screenrecording"]
    var fs = []
    var out = [
      { glyph: "󰝟", title: "No audio",      note: "Video only",
        argv: base.concat(fs) },
      { glyph: "󰕾", title: "Desktop audio", note: "System sound",
        argv: base.concat(["--with-desktop-audio"], fs) },
      { glyph: "󰍬", title: "Desktop + mic", note: "Sound and voice",
        argv: base.concat(["--with-desktop-audio", "--with-microphone-audio"], fs) }
    ]
    if (recWebcam)
      out.push({ glyph: "󰖠", title: "With webcam", note: "Sound, voice, camera",
                 argv: base.concat(["--with-desktop-audio", "--with-microphone-audio", "--with-webcam"], fs) })
    return out
  }

  // The Wi-Fi password field needs real keyboard focus, which only the bar's
  // own layer surface can take. Bar.qml watches this and asks the compositor
  // for the keyboard exactly while it is true.
  readonly property bool keyboardWanted: revealed && ((kind === "network" && sys.promptActive)
                                                      || (kind === "shanshui" && shanHexFocused))
  // A Shan Shui hex field is being typed in.
  property bool shanHexFocused: false

  // Diagnostics for the password field: whether it holds focus and how much has
  // been typed. Never the text itself — the probe that reads this is a shell
  // command, and a password has no business on a terminal.
  property bool promptFieldFocused: false
  property int promptFieldLength: 0

  // ------------------------------------------------------------- components
  // A small pill button. Inline so the island keeps its file count.
  component ActionChip: Rectangle {
    id: chip
    required property var tk
    property string label: ""
    property string glyph: ""
    property bool danger: false
    property bool enabledChip: true
    property bool selected: false
    signal clicked()

    implicitWidth: chipRow.implicitWidth + chip.tk.px(20)
    implicitHeight: chip.tk.px(24)
    radius: height / 2
    opacity: enabledChip ? 1 : 0.35
    color: chipMouse.pressed ? chip.tk.cardPressed
      : (chipMouse.containsMouse || chip.selected ? chip.tk.cardHover : chip.tk.fieldBg)
    border.width: chip.selected ? 1 : 0
    border.color: chip.tk.accent
    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: chip.tk.px(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: chip.glyph !== ""
        text: chip.glyph
        font.family: chip.tk.fontFamily
        font.pixelSize: chip.tk.tileLabelSize
        color: chip.danger ? chip.tk.danger : chip.tk.textDim
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.label
        font.family: chip.tk.fontFamily
        font.pixelSize: chip.tk.tileLabelSize
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
        color: chip.danger ? chip.tk.danger : chip.tk.text
      }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: chip.enabledChip
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  // A labelled row of option chips (Shan Shui settings).
  component OptionRow: Row {
    id: optRow
    required property var tk
    required property string label
    property alias chips: chipRow.data
    spacing: tk.px(10)
    height: tk.px(24)

    Text {
      width: optRow.tk.px(64)
      anchors.verticalCenter: parent.verticalCenter
      text: optRow.label
      font.family: optRow.tk.fontFamily
      font.pixelSize: optRow.tk.cardTitleSize
      font.letterSpacing: 0.8
      color: optRow.tk.textFaint
    }
    Row {
      id: chipRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: optRow.tk.px(6)
    }
  }

  // A round colour swatch (Shan Shui ink / paper).
  component Swatch: Rectangle {
    id: sw
    required property var tk
    required property string hex
    property string name: ""
    property bool selected: false
    signal picked(string hex)
    width: tk.px(20)
    height: width
    radius: width / 2
    color: hex
    border.width: selected ? 2 : 1
    border.color: selected ? tk.accent : (swMouse.containsMouse ? tk.text : tk.line)
    MouseArea {
      id: swMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sw.picked(sw.hex)
    }
  }

  // A rainbow strip: click or drag anywhere to pick that hue.
  component HueBar: Rectangle {
    id: hue
    required property var tk
    property real saturation: 0.62
    property real lightness: 0.62
    signal picked(string hex)
    width: tk.px(120)
    height: tk.px(14)
    radius: height / 2
    border.width: 1
    border.color: tk.line
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.000; color: Qt.hsla(0.000, hue.saturation, hue.lightness, 1) }
      GradientStop { position: 0.167; color: Qt.hsla(0.167, hue.saturation, hue.lightness, 1) }
      GradientStop { position: 0.333; color: Qt.hsla(0.333, hue.saturation, hue.lightness, 1) }
      GradientStop { position: 0.500; color: Qt.hsla(0.500, hue.saturation, hue.lightness, 1) }
      GradientStop { position: 0.667; color: Qt.hsla(0.667, hue.saturation, hue.lightness, 1) }
      GradientStop { position: 0.833; color: Qt.hsla(0.833, hue.saturation, hue.lightness, 1) }
      GradientStop { position: 1.000; color: Qt.hsla(0.999, hue.saturation, hue.lightness, 1) }
    }
    function pickAt(x) {
      var h = Math.max(0, Math.min(0.999, x / width))
      var c = Qt.hsla(h, saturation, lightness, 1)
      function two(v) { var t = Math.round(v * 255).toString(16); return t.length < 2 ? "0" + t : t }
      picked("#" + two(c.r) + two(c.g) + two(c.b))
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.CrossCursor
      onPressed: function(m) { hue.pickAt(m.x) }
      onPositionChanged: function(m) { if (pressed) hue.pickAt(m.x) }
    }
  }

  // "#rrggbb" entry; Enter applies. Any colour in the world.
  component HexField: Rectangle {
    id: hf
    required property var tk
    property string current: ""
    signal picked(string hex)
    signal focusChanged2(bool focused)
    width: tk.px(84)
    height: tk.px(22)
    radius: height / 2
    color: tk.fieldBg
    border.width: 1
    border.color: field.activeFocus ? tk.accent : "transparent"
    TextInput {
      id: field
      anchors.fill: parent
      anchors.leftMargin: hf.tk.px(10)
      anchors.rightMargin: hf.tk.px(8)
      verticalAlignment: TextInput.AlignVCenter
      maximumLength: 7
      selectByMouse: true
      clip: true
      font.family: hf.tk.fontFamily
      font.pixelSize: hf.tk.tileLabelSize
      color: /^#?[0-9a-fA-F]{6}$/.test(text) || text === "" ? hf.tk.text : hf.tk.danger
      selectionColor: hf.tk.accent
      onActiveFocusChanged: { hf.focusChanged2(activeFocus); if (activeFocus) selectAll() }
      onAccepted: {
        var t = text.trim()
        if (t.charAt(0) !== "#") t = "#" + t
        if (/^#[0-9a-fA-F]{6}$/.test(t)) { hf.picked(t.toLowerCase()); field.focus = false }
      }
      Keys.onEscapePressed: { text = ""; field.focus = false }
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: field.text === "" && !field.activeFocus
        text: hf.current !== "" ? hf.current : "#hex"
        font: field.font
        color: hf.tk.textFaint
      }
    }
  }

  // A section heading inside a card.
  component CardTitle: Text {
    required property var tk
    font.family: tk.fontFamily
    font.pixelSize: tk.cardTitleSize
    font.letterSpacing: 0.8
    color: tk.textFaint
  }

  // The one line at the foot of a panel that says what just happened. An error
  // outranks a notice, and a connection in flight outranks both.
  component FeedbackLine: Text {
    required property var tk
    property string error: ""
    property string notice: ""
    property string busy: ""
    text: busy !== "" ? busy : (error !== "" ? error : notice)
    visible: text !== ""
    elide: Text.ElideRight
    textFormat: Text.PlainText
    font.family: tk.fontFamily
    font.pixelSize: tk.tileLabelSize
    renderType: Text.NativeRendering
    color: busy !== "" ? tk.textDim : (error !== "" ? tk.danger : tk.textDim)
  }

  // ------------------------------------------------------------- header
  Item {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: detail.tk.px(20)

    Row {
      id: backRow
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: detail.tk.px(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ""   // chevron-left
        font.family: detail.tk.fontFamily
        font.pixelSize: detail.tk.tileLabelSize
        color: backMouse.containsMouse ? detail.tk.text : detail.tk.textFaint
        Behavior on color { ColorAnimation { duration: 120 } }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: detail.title
        font.family: detail.tk.fontFamily
        font.pixelSize: detail.tk.detailTitleSize
        font.weight: Font.DemiBold
        font.letterSpacing: 0.4
        renderType: Text.NativeRendering
        color: detail.tk.text
      }
    }

    MouseArea {
      id: backMouse
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: backRow.width + detail.tk.px(12)
      height: parent.height
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: detail.back()
    }

    // Right of the header: whatever the panel is currently doing, else ESC.
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: detail.headerNote
      font.family: detail.tk.fontFamily
      font.pixelSize: detail.tk.tileLabelSize
      font.letterSpacing: detail.headerNote === "ESC" ? 1.0 : 0.0
      color: detail.tk.textFaint
    }
  }

  readonly property string title: {
    if (kind === "network") return sys.netKind === "ethernet" ? "Ethernet" : "Wi-Fi"
    if (kind === "bluetooth") return "Bluetooth"
    if (kind === "audio") return "Sound"
    if (kind === "battery") return "Battery"
    if (kind === "claude") return "Claude Code"
    if (kind === "shanshui") return "山  Shan Shui"
    if (kind === "display") return "Display"
    if (kind === "record") return "Screen Recording"
    if (kind === "notifications") return "Notifications"
    if (kind === "activity") return "Activity"
    if (kind === "controlcenter") return "Control Center"
    return ""
  }

  readonly property string headerNote: {
    if (kind === "network" && sys.wifiDevice && sys.wifiDevice.scannerEnabled) return "scanning"
    if (kind === "bluetooth" && sys.btScanning) return "scanning"
    if (kind === "claude" && sys.claudeAge !== "") return sys.claudeAge
    if (kind === "shanshui") return shan.statusText
    if (kind === "display" && disp.mirroring) return "mirroring"
    return "ESC"
  }

  // -------------------------------------------------------------- body
  Loader {
    id: body
    anchors.top: header.bottom
    anchors.topMargin: detail.tk.px(12)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    sourceComponent: detail.kind === "network" ? networkBody
      : detail.kind === "bluetooth" ? bluetoothBody
      : detail.kind === "audio" ? audioBody
      : detail.kind === "battery" ? batteryBody
      : detail.kind === "claude" ? claudeBody
      : detail.kind === "shanshui" ? shanshuiBody
      : detail.kind === "display" ? displayBody
      : detail.kind === "record" ? recordBody
      : detail.kind === "notifications" ? notificationsBody
      : detail.kind === "activity" ? activityBody
      : detail.kind === "controlcenter" ? controlCenterBody : null
  }


  // ------------------------------------------------------------ display state
  // Read from island-display.sh while the Display pane is open; every action
  // goes through the same script so it can be run and checked by hand.
  QtObject {
    id: disp
    readonly property string script: Qt.resolvedUrl("island-display.sh").toString().replace("file://", "")
    property var monitors: []
    property int brightness: -1
    property int textSize: 12
    property bool mirroring: false
    // Shown while dragging so the slider does not jump back between polls.
    property int pendingBrightness: -1
    readonly property var primary: {
      for (var i = 0; i < monitors.length; i++) if (monitors[i].focused) return monitors[i]
      return monitors.length > 0 ? monitors[0] : null
    }

    // Resolution / refresh picker in the right card: "" | "res" | "hz".
    property string picker: ""
    // A mode change waiting for "Keep" (the script reverts it on its own).
    property real confirmDeadline: 0
    property int confirmLeft: 0
    function tickConfirm() {
      confirmLeft = confirmDeadline > 0 ? Math.max(0, Math.ceil((confirmDeadline - Date.now()) / 1000)) : 0
    }

    readonly property var modes: primary && primary.modes ? primary.modes : []
    // Unique resolutions, largest first.
    readonly property var resolutions: {
      var seen = {}, out = []
      for (var i = 0; i < modes.length; i++) {
        var k = modes[i].w + "x" + modes[i].h
        if (seen[k]) continue
        seen[k] = true
        out.push({ w: modes[i].w, h: modes[i].h })
      }
      out.sort(function(a, b) { return b.w * b.h - a.w * a.h || b.w - a.w })
      return out
    }
    // Refresh rates offered at the current resolution, fastest first.
    readonly property var rates: {
      if (!primary) return []
      var out = []
      for (var i = 0; i < modes.length; i++)
        if (modes[i].w === primary.w && modes[i].h === primary.h) out.push(modes[i])
      out.sort(function(a, b) { return b.hz - a.hz })
      var counts = {}
      for (i = 0; i < out.length; i++) counts[Math.round(out[i].hz)] = (counts[Math.round(out[i].hz)] || 0) + 1
      return out.map(function(m) {
        var r = Math.round(m.hz)
        return { raw: m.raw, hz: m.hz, label: (counts[r] > 1 ? m.hz.toFixed(2) : String(r)) + " Hz" }
      })
    }
    function isCurrentRate(m) { return !!primary && Math.abs(m.hz - primary.rate) < 0.05 }
    function setMode(raw) {
      if (!primary) return
      picker = ""
      confirmDeadline = Date.now() + 15000
      tickConfirm()
      act(["mode", primary.name, raw])
    }
    function pickResolution(r) {
      var best = null
      for (var i = 0; i < modes.length; i++)
        if (modes[i].w === r.w && modes[i].h === r.h && (!best || modes[i].hz > best.hz)) best = modes[i]
      if (best) setMode(best.raw)
    }
    function keep() { confirmDeadline = 0; tickConfirm(); act(["keep"]) }
    function revert() { confirmDeadline = 0; tickConfirm(); act(["revert"]) }

    function apply(raw) {
      try {
        var d = JSON.parse(String(raw || "{}"))
        var m = d.monitors || []
        if (JSON.stringify(m) !== JSON.stringify(monitors)) monitors = m
        if (pendingBrightness < 0) brightness = Number(d.brightness)
        textSize = Number(d.textSize || 12)
        var left = Number(d.confirmLeft || 0)
        confirmDeadline = left > 0 ? Date.now() + left * 1000 : 0
        tickConfirm()
        mirroring = !!d.mirroring
      } catch (e) { /* keep the last reading */ }
    }
    function act(args) {
      Quickshell.execDetached([script].concat(args))
      dispRefresh.restart()
    }
    function setBrightness(v) {
      v = Math.max(1, Math.min(100, Math.round(v)))
      pendingBrightness = v
      brightness = v
      dispBrightnessCommit.restart()
    }
  }

  Process {
    id: dispProbe
    command: [disp.script, "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: disp.apply(text) }
  }
  Timer {
    interval: 3000
    repeat: true
    triggeredOnStart: true
    running: detail.revealed && detail.kind === "display"
    onTriggered: if (!dispProbe.running) dispProbe.running = true
  }
  Timer {
    interval: 250
    repeat: true
    running: disp.confirmDeadline > 0
    onTriggered: {
      disp.tickConfirm()
      if (disp.confirmLeft === 0) { disp.confirmDeadline = 0; dispRefresh.restart() }
    }
  }
  Timer { id: dispRefresh; interval: 700; onTriggered: if (!dispProbe.running) dispProbe.running = true }
  // DDC is slow (~0.5s a write), so the level is sent once the drag settles.
  Timer {
    id: dispBrightnessCommit
    interval: 250
    onTriggered: {
      Quickshell.execDetached([disp.script, "brightness", String(disp.pendingBrightness)])
      dispBrightnessClear.restart()
    }
  }
  Timer { id: dispBrightnessClear; interval: 1500; onTriggered: disp.pendingBrightness = -1 }

  // ------------------------------------------------------- shan shui state
  // zed.shanshui (the painted wallpaper) is driven through its own IPC and its
  // own config.json, which it watches and reloads. Polled only while this pane
  // is up.
  QtObject {
    id: shan
    property bool on: false
    property bool paused: false
    property bool covered: false
    property string error: ""
    property int scroll: 0
    property var opts: ({})
    readonly property string statusText: error === "node" ? "needs nodejs"
      : error === "rsvg" ? "needs librsvg"
      : !on ? "static wallpaper"
      : paused ? "paused · scroll " + scroll
      : covered ? "waiting (fullscreen)"
      : "painting · scroll " + scroll

    function ipc(cmd, arg) {
      var c = ["omarchy-shell", "-q", "shanshui", cmd]
      if (arg !== undefined) c.push(String(arg))
      Quickshell.execDetached(c)
      shanRefresh.restart()
    }
    function same(a, b) { return String(a || "").toLowerCase() === String(b || "").toLowerCase() }
    // Merge one change into the full option set and write config.json.
    function set(change) {
      var o = {}
      for (var k in opts) o[k] = opts[k]
      for (k in change) o[k] = change[k]
      opts = o
      shanConfig.setText(JSON.stringify(o, null, 2) + "\n")
    }
  }

  Process {
    id: shanProbe
    command: ["omarchy-shell", "shanshui", "estado"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var e = JSON.parse(text)
          shan.on = !!e.ativo
          shan.paused = !!e.pausado
          shan.covered = !!e.encoberto
          shan.error = e.erro || ""
          shan.scroll = (e.kFrente || 0) + 1
          shan.opts = e.opcoes || {}
        } catch (err) { shan.error = "plugin not running" }
      }
    }
  }
  Timer {
    interval: 1500
    repeat: true
    triggeredOnStart: true
    running: detail.revealed && detail.kind === "shanshui"
    onTriggered: if (!shanProbe.running) shanProbe.running = true
  }
  Timer { id: shanRefresh; interval: 300; onTriggered: if (!shanProbe.running) shanProbe.running = true }

  FileView {
    id: shanConfig
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/zed.shanshui/config.json"
    printErrors: false
    blockLoading: false
  }

  // --------------------------------------------------------- network
  Component {
    id: networkBody

    Item {
      anchors.fill: parent

      // ---- the password prompt takes the whole pane while it is up ----------
      // It replaces the list rather than squeezing in beside it: the network is
      // already chosen by the time this appears, and a password field wants the
      // width more than the list does.
      IslandCard {
        id: prompt
        anchors.fill: parent
        tk: detail.tk
        revealed: true
        visible: detail.sys.promptActive
        z: 2

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: detail.tk.cardPad
          anchors.rightMargin: detail.tk.cardPad
          spacing: detail.tk.px(7)

          Text {
            width: parent.width
            text: "Join “" + detail.sys.promptName + "”"
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.tileValueSize
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            color: detail.tk.text
          }

          Rectangle {
            width: parent.width
            height: detail.tk.fieldHeight
            radius: detail.tk.px(8)
            color: detail.tk.fieldBg
            border.width: 1
            border.color: password.activeFocus ? detail.tk.accent : "transparent"

            TextInput {
              id: password
              anchors.fill: parent
              anchors.leftMargin: detail.tk.px(10)
              anchors.rightMargin: eye.width + detail.tk.px(14)
              verticalAlignment: TextInput.AlignVCenter
              echoMode: reveal.checked ? TextInput.Normal : TextInput.Password
              passwordCharacter: "•"
              selectByMouse: true
              clip: true
              font.family: detail.tk.fontFamily
              font.pixelSize: detail.tk.tileValueSize
              color: detail.tk.text
              selectionColor: detail.tk.accent
              onAccepted: detail.sys.submitPassword(password.text)

              Keys.onEscapePressed: detail.sys.cancelPrompt()

              onActiveFocusChanged: detail.promptFieldFocused = activeFocus
              onTextChanged: detail.promptFieldLength = text.length

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: password.text === ""
                text: "Password"
                font: password.font
                color: detail.tk.textFaint
              }
            }

            // Show/hide, because a mistyped key is the usual reason this fails.
            Item {
              id: eye
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: detail.tk.px(28)
              height: parent.height

              QtObject { id: reveal; property bool checked: false }

              Text {
                anchors.centerIn: parent
                text: reveal.checked ? "󰛐" : "󰛑"
                font.family: detail.tk.fontFamily
                font.pixelSize: detail.tk.tileLabelSize
                color: eyeMouse.containsMouse ? detail.tk.text : detail.tk.textFaint
              }
              MouseArea {
                id: eyeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: reveal.checked = !reveal.checked
              }
            }
          }

          FeedbackLine {
            width: parent.width
            tk: detail.tk
            error: detail.sys.netError
          }

          Row {
            spacing: detail.tk.px(7)

            ActionChip {
              tk: detail.tk
              label: "Connect"
              glyph: "󰤨"
              enabledChip: password.text.length > 0
              onClicked: detail.sys.submitPassword(password.text)
            }
            ActionChip {
              tk: detail.tk
              label: "Cancel"
              onClicked: detail.sys.cancelPrompt()
            }
          }
        }

        // Focus follows the prompt appearing, so the password can be typed
        // straight away without clicking into the field first.
        Connections {
          target: detail.sys
          function onPromptNameChanged() {
            if (detail.sys.promptActive) { password.text = ""; password.forceActiveFocus() }
          }
        }
        onVisibleChanged: if (visible) { password.text = ""; password.forceActiveFocus() }
      }

      // ---- normal two-card layout -----------------------------------------
      Row {
        anchors.fill: parent
        spacing: detail.tk.cardGap
        visible: !detail.sys.promptActive

        // Left: what this connection is, and what can be done to it.
        IslandCard {
          tk: detail.tk
          revealed: true
          width: (parent.width - detail.tk.cardGap) * 0.44
          height: parent.height

          Column {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: detail.tk.cardPad
            spacing: detail.tk.px(2)

            Text {
              width: parent.width
              text: detail.sys.netValue
              elide: Text.ElideRight
              textFormat: Text.PlainText
              font.family: detail.tk.fontFamily
              font.pixelSize: detail.tk.cardValueSize
              font.weight: Font.DemiBold
              renderType: Text.NativeRendering
              color: detail.tk.text
            }
            Item { width: 1; height: detail.tk.px(5) }

            // Only the facts that change what you would do next. Adapter name,
            // gateway and band were filler on a panel this size.
            IslandRow {
              tk: detail.tk; width: parent.width; label: "Signal"
              value: detail.sys.netSignal >= 0 ? detail.sys.netSignal + "%" : ""
            }
            IslandRow {
              tk: detail.tk; width: parent.width; label: "Rate"
              value: detail.sys.netDetail2.rate || ""
            }
            IslandRow {
              tk: detail.tk; width: parent.width; label: "IP"
              value: detail.sys.netDetail2.ip || ""
            }
          }

          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: detail.tk.px(8)
            spacing: detail.tk.px(6)

            FeedbackLine {
              width: parent.width
              tk: detail.tk
              error: detail.sys.netError
              notice: detail.sys.netNotice
              busy: detail.sys.netBusyName !== "" ? "Connecting to " + detail.sys.netBusyName + "…" : ""
            }

            Row {
              spacing: detail.tk.px(6)

              ActionChip {
                tk: detail.tk
                label: detail.sys.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off"
                glyph: detail.sys.wifiEnabled ? "󰤨" : "󰖪"
                enabledChip: !detail.sys.wifiBlocked
                onClicked: detail.sys.toggleWifi()
              }
              ActionChip {
                tk: detail.tk
                label: "Disconnect"
                visible: !!detail.sys.activeWifi
                onClicked: detail.sys.disconnectNetwork(detail.sys.activeWifi)
              }
            }
          }
        }

        // Right: every network in range, live.
        IslandCard {
          tk: detail.tk
          revealed: true
          width: (parent.width - detail.tk.cardGap) * 0.56
          height: parent.height

          CardTitle {
            id: netListTitle
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: detail.tk.cardPad
            tk: detail.tk
            text: "Networks"
          }

          Text {
            anchors.centerIn: parent
            visible: detail.sys.wifiNetworks.length === 0
            text: !detail.sys.wifiEnabled ? "Wi-Fi is off" : "Looking for networks…"
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.tileLabelSize
            color: detail.tk.textFaint
          }

          ListView {
            anchors.top: netListTitle.bottom
            anchors.topMargin: detail.tk.px(5)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: detail.tk.px(4)
            anchors.rightMargin: detail.tk.px(4)
            anchors.bottomMargin: detail.tk.px(6)
            clip: true
            model: detail.sys.wifiNetworks
            boundsBehavior: Flickable.StopAtBounds

            delegate: IslandListRow {
              required property var modelData
              width: ListView.view.width
              tk: detail.tk
              glyph: detail.sys.wifiBarsFor(modelData)
              title: String(modelData.name || "")
              selected: modelData.connected
              // Every network is actionable now: an unsaved secured one opens
              // the password prompt instead of sitting inert.
              enabledRow: !detail.sys.wifiIsEnterprise(modelData.security)
              note: {
                if (detail.sys.netBusyName === String(modelData.name || "")) return "Connecting…"
                if (modelData.connected) return "Connected"
                if (modelData.stateChanging) return "…"
                if (detail.sys.wifiIsEnterprise(modelData.security)) return "802.1X"
                var pct = Math.round(modelData.signalStrength * 100) + "%"
                if (modelData.known) return "Saved · " + pct
                return detail.sys.wifiIsOpen(modelData.security) ? pct : "󰍁 " + pct
              }
              onActivated: detail.sys.activateNetwork(modelData)
              // Right-click forgets a saved profile, which is the only
              // destructive thing here and so is kept off the primary tap.
              onSecondary: if (modelData.known) detail.sys.forgetNetwork(modelData)
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------- bluetooth
  Component {
    id: bluetoothBody

    Row {
      spacing: detail.tk.cardGap

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.44
        height: parent.height

        Column {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: detail.tk.cardPad
          spacing: detail.tk.px(2)

          Text {
            width: parent.width
            text: detail.sys.btValue
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.cardValueSize
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            color: detail.sys.btEnabled ? detail.tk.text : detail.tk.textFaint
          }
          Item { width: 1; height: detail.tk.px(5) }

          IslandRow {
            tk: detail.tk; width: parent.width; label: "Paired"
            value: String(detail.sys.btDevices.length)
          }
          IslandRow {
            tk: detail.tk; width: parent.width; label: "In range"
            value: detail.sys.btScanning ? String(detail.sys.btNearby.length) : ""
          }
        }

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: detail.tk.px(8)
          spacing: detail.tk.px(6)

          FeedbackLine {
            width: parent.width
            tk: detail.tk
            error: detail.sys.btError
            notice: detail.sys.btNotice
            busy: detail.sys.btBusyVerb !== ""
              ? (detail.sys.btBusyVerb === "pair" ? "Pairing…"
                : detail.sys.btBusyVerb === "connect" ? "Connecting…" : "Disconnecting…")
              : ""
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            maximumLineCount: 3
          }

          ActionChip {
            tk: detail.tk
            label: detail.sys.btEnabled ? "Bluetooth on" : "Bluetooth off"
            glyph: detail.sys.btEnabled ? "󰂱" : "󰂲"
            enabledChip: detail.sys.btAvailable
            onClicked: detail.sys.toggleBluetooth()
          }
        }
      }

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.56
        height: parent.height

        CardTitle {
          id: btListTitle
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.margins: detail.tk.cardPad
          tk: detail.tk
          text: "Devices"
        }

        Text {
          anchors.centerIn: parent
          visible: detail.sys.btDevices.length === 0 && detail.sys.btNearby.length === 0
          text: !detail.sys.btEnabled ? "Bluetooth is off" : "Looking for devices…"
          font.family: detail.tk.fontFamily
          font.pixelSize: detail.tk.tileLabelSize
          color: detail.tk.textFaint
        }

        // Paired devices and unpaired ones in range, in one list with a
        // divider. Discovery is on while this pane is open, which is what makes
        // a never-before-seen device appear here at all.
        ListView {
          anchors.top: btListTitle.bottom
          anchors.topMargin: detail.tk.px(5)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: detail.tk.px(4)
          anchors.rightMargin: detail.tk.px(4)
          anchors.bottomMargin: detail.tk.px(6)
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          model: {
            var out = []
            var paired = detail.sys.btDevices
            for (var i = 0; i < paired.length; i++) out.push({ device: paired[i], header: "" })
            var near = detail.sys.btNearby
            for (var j = 0; j < near.length; j++)
              out.push({ device: near[j], header: j === 0 ? "IN RANGE" : "" })
            return out
          }

          delegate: Column {
            required property var modelData
            width: ListView.view.width
            spacing: 0

            CardTitle {
              visible: modelData.header !== ""
              tk: detail.tk
              text: modelData.header
              topPadding: detail.tk.px(6)
              leftPadding: detail.tk.px(8)
              bottomPadding: detail.tk.px(2)
            }

            IslandListRow {
              width: parent.width
              tk: detail.tk
              glyph: detail.sys.btGlyphFor(modelData.device)
              title: detail.sys.btLabel(modelData.device)
              selected: modelData.device.connected
              enabledRow: !detail.sys.btBusyAddress
                || detail.sys.btIsBusy(modelData.device)
              note: {
                var d = modelData.device
                if (detail.sys.btIsBusy(d))
                  return detail.sys.btBusyVerb === "pair" ? "Pairing…"
                    : detail.sys.btBusyVerb === "connect" ? "Connecting…" : "…"
                if (d.pairing) return "Pairing…"
                if (d.connected)
                  return d.batteryAvailable ? Math.round(d.battery * 100) + "%" : "Connected"
                if (!d.paired && !d.bonded) return "Tap to pair"
                return ""
              }
              onActivated: detail.sys.activateDevice(modelData.device)
              // Right-click removes the pairing — destructive, so never the tap.
              onSecondary: if (modelData.device.paired || modelData.device.bonded)
                detail.sys.forgetDevice(modelData.device)
            }
          }
        }
      }
    }
  }

  // ----------------------------------------------------------- audio
  Component {
    id: audioBody

    Row {
      spacing: detail.tk.cardGap

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.44
        height: parent.height

        Column {
          anchors.fill: parent
          anchors.margins: detail.tk.cardPad
          spacing: detail.tk.px(2)

          Text {
            text: detail.sys.muted ? "Muted" : detail.sys.volumePercent + "%"
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.cardValueSize
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            color: detail.sys.muted ? detail.tk.textFaint : detail.tk.text
          }

          Item { width: 1; height: detail.tk.px(8) }

          // Drag or click anywhere on the track to set the level.
          Rectangle {
            id: track
            width: parent.width
            height: detail.tk.px(6)
            radius: height / 2
            color: detail.tk.meterTrack

            Rectangle {
              width: parent.width * Math.max(0, Math.min(1, detail.sys.volume))
              height: parent.height
              radius: parent.radius
              color: detail.sys.muted ? detail.tk.textFaint : detail.tk.text
              Behavior on width { NumberAnimation { duration: 90 } }
            }

            MouseArea {
              anchors.fill: parent
              anchors.margins: -detail.tk.px(7)
              cursorShape: Qt.PointingHandCursor
              function apply(x) { detail.sys.setVolume(x / track.width) }
              onPressed: function(mouse) { apply(mouse.x) }
              onPositionChanged: function(mouse) { if (pressed) apply(mouse.x) }
              onWheel: function(wheel) {
                detail.sys.setVolume(detail.sys.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
              }
            }
          }

          Item { width: 1; height: detail.tk.px(8) }

          IslandListRow {
            width: parent.width
            tk: detail.tk
            glyph: detail.sys.muted ? "󰝟" : "󰕾"
            title: detail.sys.muted ? "Unmute" : "Mute"
            onActivated: detail.sys.toggleMute()
          }
        }
      }

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.56
        height: parent.height

        CardTitle {
          id: sinkTitle
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.margins: detail.tk.cardPad
          tk: detail.tk
          text: "Output"
        }

        ListView {
          anchors.top: sinkTitle.bottom
          anchors.topMargin: detail.tk.px(5)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: detail.tk.px(4)
          anchors.rightMargin: detail.tk.px(4)
          anchors.bottomMargin: detail.tk.px(6)
          clip: true
          model: detail.sys.sinks
          boundsBehavior: Flickable.StopAtBounds

          delegate: IslandListRow {
            required property var modelData
            width: ListView.view.width
            tk: detail.tk
            glyph: modelData === detail.sys.sink ? "󰕾" : "󰘄"
            title: detail.sys.sinkLabel(modelData)
            selected: modelData === detail.sys.sink
            note: modelData === detail.sys.sink ? "Active" : ""
            onActivated: detail.sys.selectSink(modelData)
          }
        }
      }
    }
  }

  // --------------------------------------------------- control center
  Component {
    id: controlCenterBody
    IslandControlCenter {
      tk: detail.tk
      sys: detail.sys
      status: detail.status
      revealed: detail.revealed
      onOpenDetail: function(kind) { detail.openDetail(kind) }
      onCloseRequested: detail.closeRequested()
    }
  }

  // -------------------------------------------------------- activity
  // Top processes and network throughput, read only while on screen.
  Component {
    id: activityBody
    IslandActivity {
      tk: detail.tk
      revealed: detail.revealed
      onCloseRequested: detail.closeRequested()
    }
  }

  // --------------------------------------------------------- battery
  // The shortest pane of the five: a level, a bar, and the five numbers UPower
  // actually reports for this battery. They come from the physical device now,
  // not from UPower's synthetic display device, which carried no model, no
  // health and no charge rate — that is why most of this read "—".
  Component {
    id: batteryBody

    Row {
      spacing: detail.tk.cardGap

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.44
        height: parent.height

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: detail.tk.cardPad
          anchors.rightMargin: detail.tk.cardPad
          spacing: detail.tk.px(8)

          Text {
            text: detail.sys.batteryValue
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.cardValueSize
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            color: detail.sys.batteryLow ? detail.tk.crit : detail.tk.text
          }

          Rectangle {
            width: parent.width
            height: detail.tk.px(6)
            radius: height / 2
            color: detail.tk.meterTrack

            Rectangle {
              width: parent.width * Math.max(0, Math.min(1, detail.sys.batteryPercent / 100))
              height: parent.height
              radius: parent.radius
              color: detail.sys.batteryLow ? detail.tk.crit : detail.tk.text
              Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: detail.tk.springCurve } }
            }
          }

          Text {
            width: parent.width
            text: detail.sys.batteryDetail
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.tileLabelSize
            renderType: Text.NativeRendering
            color: detail.tk.textDim
          }
        }
      }

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.56
        height: parent.height

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: detail.tk.cardPad
          anchors.rightMargin: detail.tk.cardPad
          spacing: detail.tk.px(1)

          IslandRow {
            tk: detail.tk; width: parent.width; label: "State"
            value: detail.sys.batteryState
          }
          IslandRow {
            tk: detail.tk; width: parent.width
            label: detail.sys.charging ? "Time to full" : "Time left"
            value: detail.sys.batteryTime
          }
          IslandRow { tk: detail.tk; width: parent.width; label: "Draw"; value: detail.sys.batteryRate }
          IslandRow {
            tk: detail.tk; width: parent.width; label: "Health"
            value: detail.sys.batteryHealth >= 0 ? detail.sys.batteryHealth + "%" : ""
          }
          IslandRow { tk: detail.tk; width: parent.width; label: "Capacity"; value: detail.sys.batteryCapacity }
          IslandRow { tk: detail.tk; width: parent.width; label: "Cell"; value: detail.sys.batteryModel }
        }
      }
    }
  }

  // ---------------------------------------------------------- claude
  Component {
    id: claudeBody

    Row {
      spacing: detail.tk.cardGap

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.44
        height: parent.height

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: detail.tk.cardPad
          anchors.rightMargin: detail.tk.cardPad
          spacing: detail.tk.px(10)

          IslandMeter {
            width: parent.width
            tk: detail.tk
            label: detail.sys.claudeSessionLabel
            percent: detail.sys.claudePercent
            reset: detail.sys.claudeSessionReset
          }
          IslandMeter {
            width: parent.width
            visible: detail.sys.claudeHasWeekly
            tk: detail.tk
            label: detail.sys.claudeWeeklyLabel
            percent: detail.sys.claudeWeeklyPercent
            reset: detail.sys.claudeWeeklyReset
          }
        }
      }

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.56
        height: parent.height

        Column {
          id: claudeStats
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: detail.tk.cardPad
          spacing: detail.tk.px(1)

          CardTitle { tk: detail.tk; text: "Today" }
          Item { width: 1; height: detail.tk.px(3) }
          IslandRow { tk: detail.tk; width: parent.width; label: "Prompts"; value: String(detail.sys.claudeTodayPrompts) }
          IslandRow { tk: detail.tk; width: parent.width; label: "Tokens"; value: detail.sys.compactNumber(detail.sys.claudeTodayTokens) }
        }

        // Seven days of token volume, each bar scaled to the busiest day.
        Row {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: detail.tk.cardPad
          height: detail.tk.px(30)
          spacing: detail.tk.px(5)

          Repeater {
            model: detail.sys.claudeRecentDays

            delegate: Item {
              required property var modelData
              required property int index
              width: (parent.width - detail.tk.px(5) * 6) / 7
              height: parent.height

              readonly property real ratio: detail.sys.claudePeakDay > 0
                ? Number(modelData.messageCount || 0) / detail.sys.claudePeakDay : 0
              readonly property bool today: index === detail.sys.claudeRecentDays.length - 1

              Rectangle {
                anchors.bottom: dayLabel.top
                anchors.bottomMargin: detail.tk.px(3)
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                height: Math.max(detail.tk.px(2), (parent.height - detail.tk.px(13)) * parent.ratio)
                radius: detail.tk.px(2)
                color: parent.today ? detail.tk.text : detail.tk.meterTrack
                Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: detail.tk.springCurve } }
              }

              Text {
                id: dayLabel
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(new Date(String(modelData.date)), "ddd").charAt(0)
                font.family: detail.tk.fontFamily
                font.pixelSize: detail.tk.tileLabelSize
                color: parent.today ? detail.tk.textDim : detail.tk.textFaint
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------- shan shui
  Component {
    id: shanshuiBody

    Item {
      anchors.fill: parent

      Column {
        anchors.fill: parent
        spacing: detail.tk.px(8)

        // Playback and the wallpaper switch.
        Row {
          spacing: detail.tk.px(6)

          ActionChip {
            tk: detail.tk
            glyph: shan.on ? "󰸉" : "󰋩"
            label: shan.on ? "Static wallpaper" : "Paint wallpaper"
            onClicked: shan.ipc(shan.on ? "desligar" : "ligar")
          }
          ActionChip {
            tk: detail.tk
            enabledChip: shan.on
            glyph: shan.paused ? "󰐊" : "󰏤"
            label: shan.paused ? "Resume" : "Pause"
            onClicked: shan.ipc(shan.paused ? "continuar" : "pausar")
          }
          ActionChip {
            tk: detail.tk
            enabledChip: shan.on
            glyph: "󰒭"
            label: "Skip ahead"
            onClicked: shan.ipc("pular", 0.5)
          }
          ActionChip {
            tk: detail.tk
            enabledChip: shan.on
            glyph: "󰑓"
            label: "New landscape"
            onClicked: shan.ipc("nova")
          }
        }

        OptionRow {
          tk: detail.tk
          label: "SPEED"
          chips: Repeater {
            model: [{ v: 10, l: "10 min" }, { v: 5, l: "5 min" }, { v: 2, l: "2 min" },
                    { v: 1, l: "1 min" }, { v: 0.5, l: "30 s" }, { v: 0.25, l: "15 s" }]
            ActionChip {
              required property var modelData
              tk: detail.tk
              label: modelData.l
              selected: Number(shan.opts.minPorTela) === modelData.v
              onClicked: shan.set({ minPorTela: modelData.v })
            }
          }
        }

        OptionRow {
          tk: detail.tk
          label: "MOTION"
          chips: Repeater {
            model: [{ v: 6, l: "Light" }, { v: 12, l: "Normal" }, { v: 24, l: "Smooth" }]
            ActionChip {
              required property var modelData
              tk: detail.tk
              label: modelData.l
              selected: Number(shan.opts.fps) === modelData.v
              onClicked: shan.set({ fps: modelData.v })
            }
          }
        }

        // Curated looks: ink on paper. The OLED ones keep the paper truly
        // black, so most of the panel stays switched off.
        OptionRow {
          tk: detail.tk
          label: "LOOK"
          chips: [
            Repeater {
              model: [{ l: "Theme", t: "foreground", p: "background" },
                      { l: "Night silk", t: "#e8dcc4", p: "#000000" },
                      { l: "Cinnabar", t: "#e0503c", p: "#000000" },
                      { l: "Jade", t: "#6fbf9a", p: "#000000" },
                      { l: "Rice paper", t: "#2b2b2b", p: "#f2e8d5" }]
              ActionChip {
                required property var modelData
                tk: detail.tk
                label: modelData.l
                selected: shan.same(shan.opts.tinta, modelData.t) && shan.same(shan.opts.papel, modelData.p)
                onClicked: shan.set({ tinta: modelData.t, papel: modelData.p, inverter: false })
              }
            },
            ActionChip {
              tk: detail.tk
              glyph: "󰌁"
              label: "Invert"
              selected: shan.opts.inverter === true
              onClicked: shan.set({ inverter: !(shan.opts.inverter === true) })
            }
          ]
        }

        OptionRow {
          tk: detail.tk
          label: "INK"
          chips: [
            Repeater {
              model: ["#f2efe8", "#e8dcc4", "#c9955c", "#e6c15a", "#e0503c", "#e8a0b4", "#6fbf9a", "#7da6e8"]
              Swatch {
                required property string modelData
                tk: detail.tk
                hex: modelData
                selected: shan.same(shan.opts.tinta, modelData)
                onPicked: function(h) { shan.set({ tinta: h }) }
              }
            },
            HueBar {
              tk: detail.tk
              onPicked: function(h) { shan.set({ tinta: h }) }
            },
            HexField {
              tk: detail.tk
              current: /^#/.test(String(shan.opts.tinta)) ? shan.opts.tinta : ""
              onPicked: function(h) { shan.set({ tinta: h }) }
              onFocusChanged2: function(f) { detail.shanHexFocused = f }
            }
          ]
        }

        OptionRow {
          tk: detail.tk
          label: "PAPER"
          chips: [
            Repeater {
              model: ["#000000", "#0b0a08", "#10141f", "#1f150c", "#3a1414", "#e9dfc9", "#f2e8d5", "#f7f5f0"]
              Swatch {
                required property string modelData
                tk: detail.tk
                hex: modelData
                selected: shan.same(shan.opts.papel, modelData)
                onPicked: function(h) { shan.set({ papel: h }) }
              }
            },
            HueBar {
              tk: detail.tk
              saturation: 0.45
              lightness: 0.12
              onPicked: function(h) { shan.set({ papel: h }) }
            },
            HexField {
              tk: detail.tk
              current: /^#/.test(String(shan.opts.papel)) ? shan.opts.papel : ""
              onPicked: function(h) { shan.set({ papel: h }) }
              onFocusChanged2: function(f) { detail.shanHexFocused = f }
            }
          ]
        }

        // Where the front sits and how soft the brush is: the two knobs the
        // plugin's own menu does not expose.
        OptionRow {
          tk: detail.tk
          label: "BRUSH"
          chips: Repeater {
            model: [{ l: "Crisp", s: 20, g: 0.03 }, { l: "Ink", s: 40, g: 0.06 }, { l: "Wash", s: 90, g: 0.10 }]
            ActionChip {
              required property var modelData
              tk: detail.tk
              label: modelData.l
              selected: Number(shan.opts.suave) === modelData.s && Number(shan.opts.grao) === modelData.g
              onClicked: shan.set({ suave: modelData.s, grao: modelData.g })
            }
          }
        }
      }
    }
  }

  // --------------------------------------------------------- display
  // Left: the screen you are on, its brightness and the system text size.
  // Right: send the picture somewhere else — cast, mirror — and the config.
  // ---------------------------------------------------------------- record
  // One tile per audio choice; pick one to start. Laid out on the island's
  // spacing scale: 12 between tiles, 16 inside them.
  Component {
    id: recordBody

    Column {
      spacing: detail.tk.spaceMd

      Row {
        id: recTiles
        width: parent.width
        height: parent.height
        spacing: detail.tk.spaceMd
        readonly property int count: detail.recOptions.length

        Repeater {
          model: detail.recOptions
          delegate: Rectangle {
            required property var modelData
            width: (recTiles.width - recTiles.spacing * (recTiles.count - 1)) / recTiles.count
            height: recTiles.height
            radius: detail.tk.cardRadius
            color: tileMouse.pressed ? detail.tk.cardPressed
                 : tileMouse.containsMouse ? detail.tk.cardHover : detail.tk.card
            scale: tileMouse.pressed ? 0.97 : 1
            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

            Column {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: detail.tk.spaceLg
              anchors.rightMargin: detail.tk.spaceLg
              spacing: detail.tk.spaceMd

              // Red disc with the audio glyph: the record colour, softened.
              Rectangle {
                width: detail.tk.px(36)
                height: width
                radius: width / 2
                color: Qt.alpha(detail.tk.crit, tileMouse.containsMouse ? 0.28 : 0.18)
                Behavior on color { ColorAnimation { duration: 140 } }
                Text {
                  anchors.centerIn: parent
                  text: modelData.glyph
                  font.family: detail.tk.iconFamily
                  font.pixelSize: detail.tk.iconSize
                  color: detail.tk.crit
                }
              }

              Column {
                width: parent.width
                spacing: detail.tk.spaceXs / 2
                Text {
                  width: parent.width
                  text: modelData.title
                  elide: Text.ElideRight
                  font.family: detail.tk.fontFamily
                  font.pixelSize: detail.tk.tileValueSize
                  font.weight: Font.DemiBold
                  renderType: Text.NativeRendering
                  color: detail.tk.text
                }
                Text {
                  width: parent.width
                  text: modelData.note
                  elide: Text.ElideRight
                  font.family: detail.tk.fontFamily
                  font.pixelSize: detail.tk.tileLabelSize
                  renderType: Text.NativeRendering
                  color: detail.tk.textDim
                }
              }
            }

            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: detail.runAfterClose(modelData.argv)
            }
          }
        }
      }
    }
  }

  // --------------------------------------------------------- notifications
  // Recent notifications, grouped by app (the app whose newest message is most
  // recent comes first), newest first inside each group. Click a row to open
  // it, × to remove it, Clear all to empty the history.
  function notifAppLabel(e) {
    var a = String(e && e.app || "")
    return a === "" || a === "notify-send" || a === "omarchy-action" ? "System" : a
  }
  function notifAgo(ts) {
    var s = Math.max(0, Math.floor((Date.now() - Number(ts || 0)) / 1000))
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    return Math.floor(s / 86400) + "d"
  }
  function notifIcon(e) {
    var img = String(e && e.image || "")
    if (img.indexOf("file://") === 0 || img.indexOf("image://") === 0) return img
    if (img.charAt(0) === "/") return "file://" + img
    var icon = String(e && e.appIcon || "")
    if (icon.charAt(0) === "/") return "file://" + icon
    return icon !== "" ? Quickshell.iconPath(icon, true) : ""
  }
  readonly property var notifGrouped: {
    var list = status ? status.notifHistory : []
    var groups = {}, order = []
    for (var i = 0; i < list.length; i++) {
      var g = notifAppLabel(list[i])
      if (!groups[g]) { groups[g] = []; order.push(g) }   // list is newest first
      groups[g].push(list[i])
    }
    var out = []
    for (var j = 0; j < order.length; j++) {
      var rows = groups[order[j]]
      for (var k = 0; k < rows.length; k++)
        out.push(Object.assign({}, rows[k], { group: order[j] + "  ·  " + rows.length }))
    }
    return out
  }
  // Re-render the "5m" labels once a minute while the pane is open.
  property int notifTick: 0
  Timer {
    interval: 60000
    repeat: true
    running: detail.kind === "notifications" && detail.revealed
    onTriggered: detail.notifTick++
  }

  // What is using the microphone, camera or screen right now (the pill's
  // dots, in full): one row per app and device, with how long it has been
  // going and which process it is.
  property int privTick: 0
  Timer {
    interval: 5000
    repeat: true
    running: detail.kind === "notifications" && detail.revealed
    onTriggered: detail.privTick++
  }
  function privSince(ms) {
    var s = Math.max(0, Math.floor((Date.now() - Number(ms || Date.now())) / 1000))
    if (s < 60) return "just now"
    if (s < 3600) return "for " + Math.floor(s / 60) + "m"
    return "for " + Math.floor(s / 3600) + "h " + Math.floor((s % 3600) / 60) + "m"
  }
  readonly property var privacyRows: {
    var s = status, out = []
    if (!s) return out
    var tick = privTick   // re-evaluate the "for 4m" labels
    if (s.recording) out.push({ key: "rec", tint: tk.crit, glyph: "󰑊", title: "Screen recording",
                                detail: "gpu-screen-recorder  ·  saving to Videos" })
    var names = { mic: "Microphone", camera: "Camera", screen: "Screen sharing" }
    var glyphs = { mic: "󰍬", camera: "󰄀", screen: "󰍹" }
    var tints = { mic: tk.orange, camera: tk.green, screen: tk.accent }
    var order = ["mic", "camera", "screen"]
    var uses = s.privacyUses || []
    for (var k = 0; k < order.length; k++) {
      for (var i = 0; i < uses.length; i++) {
        var u = uses[i]
        if (u.kind !== order[k]) continue
        var bits = [names[u.kind]]
        if (u.device && u.device !== "Screen") bits.push(u.device)
        if (u.media) bits.push("\u201c" + u.media + "\u201d")
        bits.push(privSince(u.since))
        if (u.pid) bits.push("pid " + u.pid)
        out.push({ key: u.kind, tint: tints[u.kind], glyph: glyphs[u.kind],
                   title: u.app, detail: bits.join("  ·  ") })
      }
    }
    if (s.dictating) out.push({ key: "dict", tint: tk.accent, glyph: "󰍬", title: "Dictation",
                                detail: s.dictation === "transcribing" ? "Transcribing" : "Listening" })
    return out
  }

  Component {
    id: notificationsBody

    Item {
      // In use: the privacy indicators with full detail.
      Column {
        id: privacyBlock
        width: parent.width
        visible: detail.privacyRows.length > 0
        height: visible ? implicitHeight + detail.tk.spaceSm : 0
        spacing: detail.tk.spaceXs

        Text {
          leftPadding: detail.tk.px(4)
          text: "In use  ·  " + detail.privacyRows.length
          font.family: detail.tk.fontFamily
          font.pixelSize: detail.tk.cardTitleSize
          font.weight: Font.DemiBold
          font.letterSpacing: 0.6
          color: detail.tk.textFaint
        }

        Repeater {
          model: detail.privacyRows
          delegate: Rectangle {
            id: prow
            required property var modelData
            width: privacyBlock.width
            height: detail.tk.px(48)
            radius: detail.tk.spaceMd
            color: detail.tk.card

            // The sensor's icon on a disc of its colour.
            Rectangle {
              id: pdisc
              anchors.left: parent.left
              anchors.leftMargin: detail.tk.spaceMd
              anchors.verticalCenter: parent.verticalCenter
              width: detail.tk.px(30); height: width; radius: width / 2
              color: Qt.alpha(prow.modelData.tint, 0.20)
              Text {
                anchors.centerIn: parent
                text: prow.modelData.glyph
                font.family: detail.tk.iconFamily
                font.pixelSize: detail.tk.glyphSize - 1
                color: prow.modelData.tint
              }
            }
            Column {
              anchors.left: pdisc.right
              anchors.leftMargin: detail.tk.spaceMd
              anchors.right: pstop.visible ? pstop.left : parent.right
              anchors.rightMargin: detail.tk.spaceMd
              anchors.verticalCenter: parent.verticalCenter
              spacing: detail.tk.px(2)
              Text {
                width: parent.width
                text: prow.modelData.title
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: detail.tk.fontFamily
                font.pixelSize: detail.tk.tileValueSize
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
                color: detail.tk.text
              }
              Text {
                width: parent.width
                text: prow.modelData.detail
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: detail.tk.fontFamily
                font.pixelSize: detail.tk.tileLabelSize
                renderType: Text.NativeRendering
                color: Qt.tint(detail.tk.textDim, Qt.rgba(prow.modelData.tint.r, prow.modelData.tint.g, prow.modelData.tint.b, 0.30))
              }
            }
            ActionChip {
              id: pstop
              visible: prow.modelData.key === "rec"
              anchors.right: parent.right
              anchors.rightMargin: detail.tk.spaceMd
              anchors.verticalCenter: parent.verticalCenter
              tk: detail.tk
              label: "Stop"
              glyph: "󰓛"
              danger: true
              onClicked: Quickshell.execDetached(["omarchy-capture-screenrecording", "--stop-recording"])
            }
          }
        }
      }

      // Count and Clear all.
      Item {
        id: notifTop
        anchors.top: privacyBlock.bottom
        width: parent.width
        height: detail.tk.px(26)
        Text {
          anchors.left: parent.left
          anchors.leftMargin: detail.tk.px(4)
          anchors.verticalCenter: parent.verticalCenter
          text: detail.notifGrouped.length === 0 ? ""
            : detail.notifGrouped.length + (detail.notifGrouped.length === 1 ? " notification" : " notifications")
          font.family: detail.tk.fontFamily
          font.pixelSize: detail.tk.tileLabelSize
          color: detail.tk.textFaint
        }
        ActionChip {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          tk: detail.tk
          visible: detail.notifGrouped.length > 0
          label: "Clear all"
          glyph: "󰎟"
          onClicked: detail.status.clearHistory()
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: notifList.verticalCenter
        visible: detail.notifGrouped.length === 0
        text: "No notifications"
        font.family: detail.tk.fontFamily
        font.pixelSize: detail.tk.tileValueSize
        color: detail.tk.textFaint
      }

      ListView {
        id: notifList
        anchors.top: notifTop.bottom
        anchors.topMargin: detail.tk.spaceSm
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        spacing: detail.tk.spaceXs
        boundsBehavior: Flickable.StopAtBounds
        model: detail.notifGrouped

        section.property: "group"
        section.delegate: Item {
          required property string section
          width: notifList.width
          height: detail.tk.px(24)
          Text {
            anchors.left: parent.left
            anchors.leftMargin: detail.tk.px(4)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: detail.tk.px(4)
            text: section
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.cardTitleSize
            font.weight: Font.DemiBold
            font.letterSpacing: 0.6
            color: detail.tk.textFaint
          }
        }

        delegate: Rectangle {
          id: nrow
          required property var modelData
          width: notifList.width
          height: detail.tk.px(52)
          radius: detail.tk.spaceMd
          color: nrowMouse.pressed ? detail.tk.cardPressed : nrowMouse.containsMouse ? detail.tk.cardHover : detail.tk.card
          Behavior on color { ColorAnimation { duration: 120 } }

          // Icon: the notification's image or the app's icon, else a bell.
          Item {
            id: nicon
            anchors.left: parent.left
            anchors.leftMargin: detail.tk.spaceMd
            anchors.verticalCenter: parent.verticalCenter
            width: detail.tk.px(30)
            height: width
            Image {
              id: nimg
              anchors.fill: parent
              source: detail.notifIcon(nrow.modelData)
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              visible: status === Image.Ready
            }
            Rectangle {
              anchors.fill: parent
              radius: width / 2
              visible: nimg.status !== Image.Ready
              color: Qt.alpha(detail.tk.text, 0.12)
              Text {
                anchors.centerIn: parent
                text: String(nrow.modelData.glyph || "") !== "" ? nrow.modelData.glyph : "󰂚"
                font.family: detail.tk.iconFamily
                font.pixelSize: detail.tk.glyphSize - 1
                color: Number(nrow.modelData.urgency) === 2 ? detail.tk.crit : detail.tk.textDim
              }
            }
          }

          Column {
            anchors.left: nicon.right
            anchors.leftMargin: detail.tk.spaceMd
            anchors.right: ntrail.left
            anchors.rightMargin: detail.tk.spaceSm
            anchors.verticalCenter: parent.verticalCenter
            spacing: detail.tk.px(2)
            Text {
              width: parent.width
              text: detail.status ? detail.status.cleanBody(nrow.modelData.summary) : ""
              elide: Text.ElideRight
              textFormat: Text.PlainText
              font.family: detail.tk.fontFamily
              font.pixelSize: detail.tk.tileValueSize
              font.weight: Font.DemiBold
              renderType: Text.NativeRendering
              color: Number(nrow.modelData.urgency) === 2 ? detail.tk.crit : detail.tk.text
            }
            Text {
              width: parent.width
              visible: text !== ""
              text: detail.status ? detail.status.cleanBody(nrow.modelData.body) : ""
              elide: Text.ElideRight
              textFormat: Text.PlainText
              font.family: detail.tk.fontFamily
              font.pixelSize: detail.tk.tileLabelSize
              renderType: Text.NativeRendering
              color: detail.tk.textDim
            }
          }

          // Time, or × while hovered.
          Item {
            id: ntrail
            anchors.right: parent.right
            anchors.rightMargin: detail.tk.spaceSm
            anchors.verticalCenter: parent.verticalCenter
            width: detail.tk.px(30)
            height: width
            Text {
              anchors.centerIn: parent
              visible: !nrowMouse.containsMouse
              text: detail.notifTick >= 0 ? detail.notifAgo(nrow.modelData.timestamp) : ""
              font.family: detail.tk.fontFamily
              font.pixelSize: detail.tk.tileLabelSize
              color: detail.tk.textFaint
            }
            Rectangle {
              anchors.fill: parent
              radius: width / 2
              visible: nrowMouse.containsMouse
              color: xMouse.containsMouse ? Qt.alpha(detail.tk.danger, 0.25) : Qt.alpha(detail.tk.text, 0.10)
              Text {
                anchors.centerIn: parent
                text: "󰅖"
                font.family: detail.tk.iconFamily
                font.pixelSize: detail.tk.tileValueSize
                color: xMouse.containsMouse ? detail.tk.danger : detail.tk.textDim
              }
            }
          }

          MouseArea {
            id: nrowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              detail.status.openHistoryEntry(nrow.modelData)
              detail.closeRequested()
            }
          }
          // × sits above the row's own click area.
          MouseArea {
            id: xMouse
            anchors.fill: ntrail
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: detail.status.deleteHistoryEntry(nrow.modelData)
          }
        }
      }
    }
  }

  Component {
    id: displayBody

    Row {
      spacing: detail.tk.cardGap

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.5
        height: parent.height

        Column {
          anchors.fill: parent
          anchors.margins: detail.tk.cardPad
          spacing: detail.tk.px(2)

          Text {
            width: parent.width
            text: disp.primary ? disp.primary.model || disp.primary.name : "No display"
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.tileValueSize
            font.weight: Font.DemiBold
            color: detail.tk.text
          }
          Item { width: 1; height: detail.tk.px(4) }

          Text {
            width: parent.width
            text: disp.monitors.length > 1 ? disp.monitors.length + " displays connected"
                                           : (disp.primary ? disp.primary.name : "")
            elide: Text.ElideRight
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.tileLabelSize
            color: detail.tk.textDim
          }

          Item { width: 1; height: detail.tk.px(16) }

          // Brightness: sun glyph, track, value. Drag, click or scroll.
          Row {
            width: parent.width
            spacing: detail.tk.px(10)
            visible: disp.brightness >= 0
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰃠"
              font.family: detail.tk.iconFamily
              font.pixelSize: detail.tk.iconSize - 1
              color: detail.tk.textDim
            }
            Rectangle {
              id: brightTrack
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - detail.tk.px(10) * 2 - detail.tk.px(16) - detail.tk.px(34)
              height: detail.tk.px(6)
              radius: height / 2
              color: detail.tk.meterTrack
              Rectangle {
                width: parent.width * Math.max(0, Math.min(1, disp.brightness / 100))
                height: parent.height
                radius: parent.radius
                color: detail.tk.text
                Behavior on width { NumberAnimation { duration: 90 } }
              }
              MouseArea {
                anchors.fill: parent
                anchors.margins: -detail.tk.px(8)
                cursorShape: Qt.PointingHandCursor
                function apply(x) { disp.setBrightness(100 * Math.max(0, Math.min(1, x / brightTrack.width))) }
                onPressed: function(mouse) { apply(mouse.x - detail.tk.px(8)) }
                onPositionChanged: function(mouse) { if (pressed) apply(mouse.x - detail.tk.px(8)) }
                onWheel: function(wheel) { disp.setBrightness(disp.brightness + (wheel.angleDelta.y > 0 ? 5 : -5)) }
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: detail.tk.px(34)
              horizontalAlignment: Text.AlignRight
              text: disp.brightness + "%"
              font.family: detail.tk.fontFamily
              font.pixelSize: detail.tk.tileLabelSize
              color: detail.tk.textDim
            }
          }
          Text {
            visible: disp.brightness < 0
            text: "Brightness isn't adjustable on this display"
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.tileLabelSize
            color: detail.tk.textFaint
          }

          Item { width: 1; height: detail.tk.px(12) }

          // Text size, system-wide (omarchy display text size).
          Row {
            width: parent.width
            spacing: detail.tk.px(8)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - detail.tk.px(8) * 3 - detail.tk.px(28) * 2 - detail.tk.px(30)
              text: "Text size"
              font.family: detail.tk.fontFamily
              font.pixelSize: detail.tk.tileValueSize
              color: detail.tk.text
            }
            Repeater {
              model: [{ g: "−", a: "-" }, { g: "", a: "" }, { g: "+", a: "+" }]
              delegate: Item {
                required property var modelData
                width: modelData.a === "" ? detail.tk.px(30) : detail.tk.px(28)
                height: detail.tk.px(28)
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                  anchors.fill: parent
                  visible: modelData.a !== ""
                  radius: width / 2
                  color: tsMouse.pressed ? detail.tk.cardPressed : (tsMouse.containsMouse ? detail.tk.cardHover : detail.tk.fieldBg)
                }
                Text {
                  anchors.centerIn: parent
                  text: modelData.a === "" ? String(disp.textSize) : modelData.g
                  font.family: detail.tk.fontFamily
                  font.pixelSize: modelData.a === "" ? detail.tk.tileValueSize : detail.tk.tileValueSize + 2
                  font.weight: Font.DemiBold
                  color: detail.tk.text
                }
                MouseArea {
                  id: tsMouse
                  anchors.fill: parent
                  enabled: modelData.a !== ""
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    disp.textSize = Math.max(9, Math.min(20, disp.textSize + (modelData.a === "+" ? 1 : -1)))
                    disp.act(["text", modelData.a])
                  }
                }
              }
            }
          }
        }
      }

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.5
        height: parent.height

        CardTitle {
          id: castTitle
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.margins: detail.tk.cardPad
          tk: detail.tk
          visible: disp.confirmLeft === 0
          text: disp.picker === "res" ? "Resolution" : disp.picker === "hz" ? "Refresh Rate" : "Screen"
        }
        Text {
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: detail.tk.cardPad
          visible: disp.picker !== "" && disp.confirmLeft === 0
          text: "Done"
          font.family: detail.tk.fontFamily
          font.pixelSize: detail.tk.cardTitleSize
          font.weight: Font.DemiBold
          color: detail.tk.accent
          MouseArea {
            anchors.fill: parent
            anchors.margins: -detail.tk.px(6)
            cursorShape: Qt.PointingHandCursor
            onClicked: disp.picker = ""
          }
        }

        // "Keep this display setting?" — the script reverts on its own if
        // this is never answered.
        Column {
          anchors.centerIn: parent
          width: parent.width - detail.tk.cardPad * 2
          spacing: detail.tk.px(6)
          visible: disp.confirmLeft > 0
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Keep this display setting?"
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.tileValueSize
            font.weight: Font.DemiBold
            color: detail.tk.text
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Reverting in " + disp.confirmLeft + "s"
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.tileLabelSize
            color: detail.tk.textDim
          }
          Item { width: 1; height: detail.tk.px(4) }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: detail.tk.px(8)
            ActionChip { tk: detail.tk; label: "Revert"; onClicked: disp.revert() }
            Rectangle {
              implicitWidth: keepText.implicitWidth + detail.tk.px(28)
              width: implicitWidth
              height: detail.tk.px(24)
              radius: height / 2
              color: keepMouse.pressed ? Qt.darker(detail.tk.accent, 1.2) : detail.tk.accent
              Text {
                id: keepText
                anchors.centerIn: parent
                text: "Keep"
                font.family: detail.tk.fontFamily
                font.pixelSize: detail.tk.tileLabelSize
                font.weight: Font.DemiBold
                color: "#FFFFFF"
              }
              MouseArea { id: keepMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: disp.keep() }
            }
          }
        }

        ListView {
          anchors.top: castTitle.bottom
          anchors.topMargin: detail.tk.px(5)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: detail.tk.px(4)
          anchors.rightMargin: detail.tk.px(4)
          anchors.bottomMargin: detail.tk.px(6)
          visible: disp.picker !== "" && disp.confirmLeft === 0
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: disp.picker === "res" ? disp.resolutions : disp.picker === "hz" ? disp.rates : []
          delegate: IslandListRow {
            required property var modelData
            readonly property bool current: disp.picker === "res"
              ? (!!disp.primary && modelData.w === disp.primary.w && modelData.h === disp.primary.h)
              : disp.isCurrentRate(modelData)
            width: ListView.view.width
            tk: detail.tk
            glyph: current ? "󰄬" : ""
            title: disp.picker === "res" ? modelData.w + " × " + modelData.h : modelData.label
            selected: current
            note: current ? "Current" : ""
            onActivated: if (!current) {
              if (disp.picker === "res") disp.pickResolution(modelData)
              else disp.setMode(modelData.raw)
            }
          }
        }

        // macOS Displays style: label on the left, value and chevron on the
        // right, hairlines between rows. A row opens its list in this card.
        Column {
          visible: disp.picker === "" && disp.confirmLeft === 0
          anchors.top: castTitle.bottom
          anchors.topMargin: detail.tk.px(6)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: detail.tk.px(4)
          anchors.rightMargin: detail.tk.px(4)

          Repeater {
            model: [
              { key: "res", label: "Resolution",
                value: disp.primary ? disp.primary.w + " × " + disp.primary.h : "—",
                enabled: disp.resolutions.length > 1 },
              { key: "hz", label: "Refresh Rate",
                value: disp.primary ? disp.primary.hz + " Hz" : "—",
                enabled: disp.rates.length > 1 },
              { key: "mirror", label: "Mirror Display",
                value: disp.monitors.length > 1 || disp.mirroring ? "" : "No second display",
                enabled: disp.mirroring || disp.monitors.length > 1 },
              { key: "style", label: "Island style", value: "", enabled: true }
            ]
            delegate: Item {
              id: setRow
              required property var modelData
              required property int index
              readonly property bool isSwitch: modelData.key === "mirror"
              readonly property bool isStyle: modelData.key === "style"
              width: parent.width
              height: detail.tk.px(36)

              Rectangle {
                anchors.fill: parent
                radius: detail.tk.px(10)
                color: srMouse.pressed && setRow.modelData.enabled ? detail.tk.cardPressed
                  : (srMouse.containsMouse && setRow.modelData.enabled ? detail.tk.cardHover : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }
              }
              // hairline under every row but the last
              Rectangle {
                visible: setRow.index < 3
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: detail.tk.px(10)
                anchors.rightMargin: detail.tk.px(10)
                height: 1
                color: Qt.alpha(detail.tk.text, 0.08)
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: detail.tk.px(10)
                anchors.verticalCenter: parent.verticalCenter
                text: setRow.modelData.label
                font.family: detail.tk.fontFamily
                font.pixelSize: detail.tk.tileValueSize
                color: setRow.modelData.enabled ? detail.tk.text : detail.tk.textDim
              }

              Row {
                anchors.right: parent.right
                anchors.rightMargin: detail.tk.px(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: detail.tk.px(6)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: setRow.modelData.value !== ""
                  text: setRow.modelData.value
                  font.family: detail.tk.fontFamily
                  font.pixelSize: detail.tk.tileValueSize
                  color: detail.tk.textDim
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !setRow.isSwitch && !setRow.isStyle && setRow.modelData.enabled
                  text: "\uf054"   // chevron-right
                  font.family: detail.tk.iconFamily
                  font.pixelSize: detail.tk.tileLabelSize
                  color: detail.tk.textFaint
                }
                // Island style: Black | Glass, a segmented control.
                Rectangle {
                  id: styleSeg
                  visible: setRow.isStyle
                  anchors.verticalCenter: parent.verticalCenter
                  readonly property real segW: detail.tk.px(54)
                  width: segW * 2 + detail.tk.px(4)
                  height: detail.tk.px(24)
                  radius: height / 2
                  color: Qt.alpha(detail.tk.text, 0.10)
                  // the sliding "selected" pill
                  Rectangle {
                    y: detail.tk.px(2)
                    x: detail.tk.openGlass ? detail.tk.px(2) + styleSeg.segW : detail.tk.px(2)
                    width: styleSeg.segW
                    height: parent.height - detail.tk.px(4)
                    radius: height / 2
                    color: Qt.alpha(detail.tk.text, 0.22)
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                  }
                  Row {
                    x: detail.tk.px(2)
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                      model: [{ label: "Black", glass: false }, { label: "Glass", glass: true }]
                      delegate: Item {
                        required property var modelData
                        width: styleSeg.segW
                        height: styleSeg.height
                        Text {
                          anchors.centerIn: parent
                          text: modelData.label
                          font.family: detail.tk.fontFamily
                          font.pixelSize: detail.tk.tileLabelSize
                          font.weight: detail.tk.openGlass === modelData.glass ? Font.DemiBold : Font.Normal
                          color: detail.tk.openGlass === modelData.glass ? detail.tk.text : detail.tk.textDim
                        }
                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: detail.setIslandGlass(modelData.glass)
                        }
                      }
                    }
                  }
                }
                // iOS switch for mirroring
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: setRow.isSwitch && setRow.modelData.enabled
                  width: detail.tk.px(34); height: detail.tk.px(20); radius: height / 2
                  color: disp.mirroring ? detail.tk.green : Qt.alpha(detail.tk.text, 0.18)
                  Behavior on color { ColorAnimation { duration: 180 } }
                  Rectangle {
                    width: parent.height - 4; height: width; radius: width / 2; y: 2
                    x: disp.mirroring ? parent.width - width - 2 : 2
                    color: "#FFFFFF"
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                  }
                }
              }

              MouseArea {
                id: srMouse
                anchors.fill: parent
                hoverEnabled: true
                // The Island style row is driven by its own segmented control;
                // a click anywhere else on that row flips it.
                enabled: setRow.modelData.enabled
                cursorShape: Qt.PointingHandCursor
                z: setRow.isStyle ? -1 : 0
                onClicked: {
                  if (setRow.isStyle) detail.setIslandGlass(!detail.tk.openGlass)
                  else if (setRow.isSwitch) disp.act(["mirror"])
                  else disp.picker = setRow.modelData.key
                }
              }
            }
          }
        }
      }
    }
  }
}
