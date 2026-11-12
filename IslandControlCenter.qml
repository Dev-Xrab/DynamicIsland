import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Control Center: the island's largest state (detail kind "controlcenter"),
// laid out like the macOS one — a narrow column of compact modules.
//
//   ┌ ● Ethernet     ┬ ◐ Focus          ┐
//   │ ● Bluetooth    ├────────┬─────────┤
//   │ ● VPN          │ Night  │ Mic     │
//   ├ Display ━━━━━━━━━━━━━━━━━━━━━━━━━━┤
//   ├ Sound ━━━━━━━━━━━━━━━━━━━━━━━━━━━━┤
//   ├ ⚡ · ☕ · ◎ · ⏺ · 🔒 ───────────────┤  power mode, stay awake, shot, record, lock
//   └ CPU 2% · MEM 5.6/15 · ↓ 4 KB/s ↑ ─┘
//
// Every control acts on the real system and every value is read back from
// it: Networking / Bluetooth / Pipewire / UPower are reactive Quickshell
// services; power mode, VPNs and load come from island-cc.sh, run every 2s
// only while this panel is on screen, and again right after each action.
// Hardware or services that are not there are shown as unavailable.
Item {
  id: cc

  required property var tk
  required property var sys
  property var status: null
  property bool revealed: false

  signal openDetail(string kind)
  signal closeRequested()

  // ------------------------------------------------------------- live state
  property var stats: ({})
  property string profile: ""
  property var profiles: []
  property var vpns: []
  property real rxRate: -1
  property real txRate: -1
  property real lastRx: -1
  property real lastTx: -1
  property real lastAt: 0
  readonly property string ccScript: Qt.resolvedUrl("island-cc.sh").toString().replace("file://", "")

  Process {
    id: readProc
    command: [cc.ccScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d
        try { d = JSON.parse(String(text || "").trim()) }
        catch (e) { console.warn("control center: bad state:", e); return }
        cc.stats = d.stats || {}
        cc.profile = String(d.profile || "")
        cc.profiles = d.profiles || []
        cc.vpns = d.vpns || []
        var now = Date.now()
        if (cc.lastAt > 0 && now > cc.lastAt) {
          var dt = (now - cc.lastAt) / 1000
          cc.rxRate = Math.max(0, (Number(d.rx) - cc.lastRx) / dt)
          cc.txRate = Math.max(0, (Number(d.tx) - cc.lastTx) / dt)
        }
        cc.lastRx = Number(d.rx); cc.lastTx = Number(d.tx); cc.lastAt = now
      }
    }
  }
  Timer {
    interval: 2000
    repeat: true
    running: cc.revealed
    triggeredOnStart: true
    onTriggered: if (!readProc.running) readProc.running = true
  }
  Process {
    id: actProc
    onExited: function(code) {
      if (code !== 0) console.warn("control center: action failed:", code, JSON.stringify(actProc.command))
      if (!readProc.running) readProc.running = true
    }
  }
  function act(argv) {
    if (actProc.running) return
    actProc.command = argv
    actProc.running = true
  }

  // Microphone: the default source, straight from PipeWire.
  readonly property var source: Pipewire.defaultAudioSource
  PwObjectTracker { objects: cc.source ? [cc.source] : [] }
  readonly property bool micReady: !!(source && source.audio)
  readonly property bool micMuted: micReady ? source.audio.muted : false

  // Brightness via island-display.sh (DDC / backlight), debounced writes.
  property int brightness: -1
  property int pendingBrightness: -1
  readonly property string displayScript: Qt.resolvedUrl("island-display.sh").toString().replace("file://", "")
  onRevealedChanged: if (revealed && !brightRead.running) brightRead.running = true
  Process {
    id: brightRead
    command: [cc.displayScript, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text || "").trim())
          if (cc.pendingBrightness < 0) cc.brightness = Number(d.brightness)
        } catch (e) { console.warn("control center: brightness read failed:", e) }
      }
    }
  }
  function setBrightness(v) {
    v = Math.max(1, Math.min(100, Math.round(v)))
    cc.brightness = v
    cc.pendingBrightness = v
    brightWrite.restart()
  }
  Timer {
    id: brightWrite
    interval: 120
    onTriggered: {
      Quickshell.execDetached([cc.displayScript, "brightness", String(cc.pendingBrightness)])
      cc.pendingBrightness = -1
    }
  }

  function rate(bps) {
    if (bps < 0) return "—"
    if (bps >= 1048576) return (bps / 1048576).toFixed(1) + " MB/s"
    if (bps >= 1024) return Math.round(bps / 1024) + " KB/s"
    return Math.round(bps) + " B/s"
  }

  readonly property var activeVpn: {
    for (var i = 0; i < vpns.length; i++) if (vpns[i].active) return vpns[i]
    return null
  }
  readonly property bool hasWifi: !!sys.wifiDevice

  // Power mode cycles saver -> balanced -> performance on each click.
  readonly property var profileNames: ({ "power-saver": "Low Power", "balanced": "Balanced", "performance": "Performance" })
  readonly property var profileGlyphs: ({ "power-saver": "󰌪", "balanced": "󰾅", "performance": "󰓅" })
  function nextProfile() {
    var order = ["power-saver", "balanced", "performance"].filter(function(p) { return cc.profiles.indexOf(p) >= 0 })
    if (order.length === 0) return
    var n = order[(order.indexOf(cc.profile) + 1) % order.length]
    cc.profile = n   // shown at once; the re-read confirms it
    cc.act([cc.ccScript, "profile", n])
  }

  function runAfterClose(argv) {
    cc.closeRequested()
    deferred.argv = argv
    deferred.restart()
  }
  Timer {
    id: deferred
    property var argv: []
    interval: cc.tk.collapseDuration + 60
    onTriggered: Quickshell.execDetached(argv)
  }

  // ---------------------------------------------------------- components
  // One spacing system for every tile: the same inner padding everywhere,
  // the same gap between tiles, the same space between an icon and its text.
  readonly property int discSize: tk.px(34)
  readonly property int pad: tk.px(14)       // inside every tile
  readonly property int gap: tk.px(12)       // between tiles
  readonly property int iconGap: tk.px(12)   // icon to its text

  component Label: Text {
    font.family: cc.tk.fontFamily
    font.pixelSize: cc.tk.fontSize - 1
    font.weight: Font.DemiBold
    color: cc.tk.text
    elide: Text.ElideRight
    textFormat: Text.PlainText
  }
  component Sub: Text {
    font.family: cc.tk.fontFamily
    font.pixelSize: cc.tk.fontSize - 3
    color: cc.tk.textDim
    elide: Text.ElideRight
    textFormat: Text.PlainText
  }

  // The round control: blue when on, dim when the thing is not there.
  component Disc: Rectangle {
    id: disc
    property string glyph: ""
    property bool on: false
    property bool available: true
    property bool hot: false
    property bool pressed: false
    implicitWidth: cc.discSize
    implicitHeight: cc.discSize
    radius: width / 2
    color: !available ? Qt.alpha(cc.tk.text, 0.06)
      : on ? cc.tk.accent : Qt.alpha(cc.tk.text, hot ? 0.22 : 0.15)
    Behavior on color { ColorAnimation { duration: cc.tk.colorDuration } }
    scale: pressed ? 0.9 : 1
    Behavior on scale { NumberAnimation { duration: cc.tk.pressDuration; easing.type: Easing.OutBack } }
    Text {
      anchors.centerIn: parent
      text: disc.glyph
      font.family: cc.tk.iconFamily
      font.pixelSize: cc.tk.iconSize - 1
      color: disc.available ? cc.tk.text : cc.tk.textFaint
    }
  }

  // A module: the shared rounded plate.
  component Module: IslandCard {
    tk: cc.tk
    revealed: cc.revealed
    radius: cc.tk.px(18)
  }

  // Connectivity row: the disc toggles; the name opens the detail pane.
  component ConnRow: Item {
    id: row
    property string glyph: ""
    property bool on: false
    property bool available: true
    property bool toggleable: true
    property string name: ""
    property string state: ""
    property string detailKind: ""
    signal toggled()
    Layout.fillWidth: true
    Layout.fillHeight: true

    Disc {
      id: rowDisc
      anchors.verticalCenter: parent.verticalCenter
      glyph: row.glyph; on: row.on; available: row.available
      hot: discMouse.containsMouse; pressed: discMouse.pressed
      MouseArea {
        id: discMouse
        anchors.fill: parent
        enabled: row.available && row.toggleable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.toggled()
      }
    }
    Column {
      anchors.left: rowDisc.right
      anchors.leftMargin: cc.iconGap
      spacing: cc.tk.px(1)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      Label { width: parent.width; text: row.name; color: textMouse.containsMouse ? Qt.alpha(cc.tk.text, 0.8) : cc.tk.text }
      Sub { width: parent.width; text: row.state }
    }
    MouseArea {
      id: textMouse
      anchors.left: rowDisc.right
      anchors.right: parent.right
      height: parent.height
      enabled: row.detailKind !== ""
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: cc.openDetail(row.detailKind)
    }
  }

  // A toggle module: disc + name (+ state); click anywhere.
  component ToggleModule: Module {
    id: tm
    property string glyph: ""
    property bool on: false
    property bool available: true
    property string name: ""
    property string state: ""
    signal toggled()
    interactive: available
    hot: tmMouse.containsMouse
    down: tmMouse.pressed
    MouseArea {
      id: tmMouse
      anchors.fill: parent
      enabled: tm.available
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tm.toggled()
    }
    Disc {
      id: tmDisc
      anchors.left: parent.left
      anchors.leftMargin: cc.pad
      anchors.verticalCenter: parent.verticalCenter
      glyph: tm.glyph; on: tm.on; available: tm.available
      hot: tmMouse.containsMouse; pressed: tmMouse.pressed
    }
    Column {
      anchors.left: tmDisc.right
      anchors.leftMargin: cc.iconGap
      anchors.right: parent.right
      anchors.rightMargin: cc.pad
      spacing: cc.tk.px(1)
      anchors.verticalCenter: parent.verticalCenter
      Label { width: parent.width; text: tm.name }
      Sub { width: parent.width; text: tm.state; visible: text !== "" }
    }
  }

  // Small square button: icon disc over a short caption.
  component SquareButton: Module {
    id: sq
    property string glyph: ""
    property bool on: false
    property bool available: true
    property string caption: ""
    signal activated()
    interactive: available
    hot: sqMouse.containsMouse
    down: sqMouse.pressed
    MouseArea {
      id: sqMouse
      anchors.fill: parent
      enabled: sq.available
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sq.activated()
    }
    Column {
      anchors.centerIn: parent
      width: parent.width - cc.tk.px(8)
      spacing: cc.tk.px(6)
      Disc {
        anchors.horizontalCenter: parent.horizontalCenter
        glyph: sq.glyph; on: sq.on; available: sq.available
        hot: sqMouse.containsMouse; pressed: sqMouse.pressed
      }
      Sub {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: sq.caption
        font.pixelSize: cc.tk.fontSize - 4
      }
    }
  }

  // The macOS slider: a capsule, white fill, the icon riding inside.
  component CCSlider: Item {
    id: sl
    property real value: 0
    property string glyph: ""
    property bool active: true
    signal moved(real v)
    signal stepped(int steps)
    implicitHeight: cc.tk.px(26)
    Rectangle {
      id: track
      anchors.fill: parent
      radius: height / 2
      color: Qt.alpha(cc.tk.text, 0.13)
      opacity: sl.active ? 1 : 0.45
      Rectangle {
        width: Math.max(track.height, track.width * Math.max(0, Math.min(1, sl.value)))
        height: parent.height
        radius: parent.radius
        color: Qt.alpha(cc.tk.text, 0.92)
        Behavior on width {
          enabled: !slMouse.pressed
          NumberAnimation { duration: cc.tk.colorDuration; easing.type: Easing.OutCubic }
        }
      }
      Text {
        anchors.left: parent.left
        anchors.leftMargin: cc.tk.px(7)
        anchors.verticalCenter: parent.verticalCenter
        text: sl.glyph
        font.family: cc.tk.iconFamily
        font.pixelSize: cc.tk.iconSize - 3
        color: "#3A3A3C"
      }
    }
    MouseArea {
      id: slMouse
      anchors.fill: parent
      enabled: sl.active
      cursorShape: Qt.PointingHandCursor
      preventStealing: true
      function at(x) { return Math.max(0, Math.min(1, x / width)) }
      onPressed: function(m) { sl.moved(at(m.x)) }
      onPositionChanged: function(m) { if (pressed) sl.moved(at(m.x)) }
      onWheel: function(w) { sl.stepped(w.angleDelta.y > 0 ? 1 : (w.angleDelta.y < 0 ? -1 : 0)) }
    }
  }

  // Name on the left (click: detail pane), value on the right, slider under.
  component SliderModule: Module {
    id: sm
    property string name: ""
    property string rightText: ""
    property string detailKind: ""
    default property alias content: holder.data
    Item {
      id: titleRow
      anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
      anchors.leftMargin: cc.pad; anchors.rightMargin: cc.pad; anchors.topMargin: cc.pad
      height: smTitle.implicitHeight
      Label { id: smTitle; text: sm.name }
      Sub {
        anchors.right: parent.right
        anchors.baseline: smTitle.baseline
        width: Math.min(implicitWidth, parent.width - smTitle.implicitWidth - cc.tk.px(12))
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
        text: sm.rightText + (sm.detailKind !== "" ? "  ›" : "")
        color: smMouse.containsMouse ? cc.tk.text : cc.tk.textDim
      }
      MouseArea {
        id: smMouse
        anchors.fill: parent
        enabled: sm.detailKind !== ""
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cc.openDetail(sm.detailKind)
      }
    }
    Item {
      id: holder
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      anchors.leftMargin: cc.pad; anchors.rightMargin: cc.pad; anchors.bottomMargin: cc.pad
      height: cc.tk.px(26)
    }
  }

  // ---------------------------------------------------------------- layout
  ColumnLayout {
    anchors.fill: parent
    spacing: cc.gap

    // --- Connectivity | Focus over Night Light + Microphone
    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: cc.tk.px(150)
      Layout.fillHeight: false
      spacing: cc.gap

      Module {
        index: 0
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        ColumnLayout {
          anchors.fill: parent
          anchors.leftMargin: cc.pad
          anchors.rightMargin: cc.pad
          anchors.topMargin: cc.tk.px(10)
          anchors.bottomMargin: cc.tk.px(10)
          spacing: 0
          ConnRow {
            glyph: cc.hasWifi ? cc.sys.netGlyph : "󰈀"
            name: cc.hasWifi ? "Wi-Fi" : "Ethernet"
            state: cc.sys.netValue
            on: cc.hasWifi ? cc.sys.wifiEnabled : cc.sys.netKind === "ethernet"
            // Ethernet has no radio to switch: its disc is a status light.
            toggleable: cc.hasWifi
            detailKind: "network"
            onToggled: cc.sys.toggleWifi()
          }
          ConnRow {
            glyph: cc.sys.btGlyph
            name: "Bluetooth"
            available: cc.sys.btAvailable
            state: !cc.sys.btAvailable ? "No adapter" : (!cc.sys.btEnabled ? "Off" : cc.sys.btValue)
            on: cc.sys.btEnabled
            detailKind: cc.sys.btAvailable ? "bluetooth" : ""
            onToggled: cc.sys.toggleBluetooth()
          }
          ConnRow {
            glyph: "󰦝"
            name: "VPN"
            available: cc.vpns.length > 0
            on: !!cc.activeVpn
            state: cc.vpns.length === 0 ? "Not set up"
              : (cc.activeVpn ? cc.activeVpn.name : "Off")
            onToggled: {
              var v = cc.activeVpn || cc.vpns[0]
              cc.act([cc.ccScript, "vpn", v.name, cc.activeVpn ? "down" : "up"])
            }
          }
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        spacing: cc.gap

        ToggleModule {
          index: 1
          Layout.fillWidth: true
          Layout.fillHeight: true
          glyph: "󰽥"
          name: "Focus"
          on: cc.status ? cc.status.silent : false
          state: on ? "Do Not Disturb" : ""
          onToggled: cc.act(["omarchy-shell", "notifications", "toggleDnd"])
        }
        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: cc.gap
          SquareButton {
            index: 2
            Layout.fillWidth: true; Layout.fillHeight: true
            glyph: "󰔎"
            caption: "Night Light"
            on: cc.status ? cc.status.nightLight : false
            onActivated: cc.act(["omarchy-toggle-nightlight"])
          }
          SquareButton {
            index: 3
            Layout.fillWidth: true; Layout.fillHeight: true
            glyph: cc.micMuted ? "󰍭" : "󰍬"
            caption: !cc.micReady ? "No Mic" : (cc.micMuted ? "Mic Off" : "Mic On")
            available: cc.micReady
            on: cc.micReady && !cc.micMuted
            onActivated: cc.source.audio.muted = !cc.source.audio.muted
          }
        }
      }
    }

    // --- Display
    SliderModule {
      index: 4
      Layout.fillWidth: true
      Layout.preferredHeight: cc.tk.px(76)
      name: "Display"
      detailKind: "display"
      rightText: cc.brightness >= 0 ? cc.brightness + "%" : "Unavailable"
      CCSlider {
        anchors.fill: parent
        glyph: "󰃠"
        active: cc.brightness >= 0
        value: cc.brightness / 100
        onMoved: function(v) { cc.setBrightness(v * 100) }
        onStepped: function(s) { if (cc.brightness >= 0) cc.setBrightness(cc.brightness + s * 5) }
      }
    }

    // --- Sound
    SliderModule {
      index: 5
      Layout.fillWidth: true
      Layout.preferredHeight: cc.tk.px(76)
      name: "Sound"
      detailKind: "audio"
      rightText: cc.sys.audioReady ? cc.sys.sinkLabel(cc.sys.sink) : "No output"
      CCSlider {
        anchors.fill: parent
        glyph: cc.sys.audioGlyph
        active: cc.sys.audioReady
        value: cc.sys.muted ? 0 : cc.sys.volume
        onMoved: function(v) {
          if (cc.sys.muted && v > 0) cc.sys.toggleMute()
          cc.sys.setVolume(v)
        }
        onStepped: function(s) { cc.sys.setVolume(cc.sys.volume + s * 0.05) }
      }
    }

    // --- Small buttons
    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: cc.tk.px(84)
      Layout.fillHeight: false
      spacing: cc.gap
      SquareButton {
        index: 6
        Layout.fillWidth: true; Layout.fillHeight: true
        glyph: cc.profileGlyphs[cc.profile] || "󰾅"
        caption: cc.profiles.length === 0 ? "No Profiles" : (cc.profileNames[cc.profile] || cc.profile)
        available: cc.profiles.length > 0
        on: cc.profile === "power-saver"
        onActivated: cc.nextProfile()
      }
      SquareButton {
        index: 7
        Layout.fillWidth: true; Layout.fillHeight: true
        glyph: cc.status && cc.status.stayAwake ? "󰅶" : "󰛊"
        caption: "Awake"
        on: cc.status ? cc.status.stayAwake : false
        onActivated: cc.act(["omarchy-toggle-idle"])
      }
      SquareButton {
        index: 8
        Layout.fillWidth: true; Layout.fillHeight: true
        glyph: "󰄀"
        caption: "Screenshot"
        onActivated: cc.runAfterClose(["omarchy-capture-screenshot"])
      }
      SquareButton {
        index: 9
        Layout.fillWidth: true; Layout.fillHeight: true
        glyph: "󰑊"
        caption: cc.status && cc.status.recording ? "Stop" : "Record"
        on: cc.status ? cc.status.recording : false
        // Not recording: the Screen Recording pane picks the audio first.
        onActivated: cc.status && cc.status.recording
          ? cc.act(["omarchy-capture-screenrecording", "--stop-recording"])
          : cc.openDetail("record")
      }
      SquareButton {
        index: 10
        Layout.fillWidth: true; Layout.fillHeight: true
        glyph: "󰌾"
        caption: "Lock"
        onActivated: cc.runAfterClose(["omarchy-system-lock"])
      }
    }

    // --- One line of live load
    Module {
      index: 11
      Layout.fillWidth: true
      Layout.preferredHeight: cc.tk.px(40)
      Layout.fillHeight: false
      interactive: true
      hot: loadMouse.containsMouse
      MouseArea {
        id: loadMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cc.openDetail("activity")
      }
      Sub {
        anchors.fill: parent
        anchors.leftMargin: cc.pad
        anchors.rightMargin: cc.pad
        verticalAlignment: Text.AlignVCenter
        font.features: { "tnum": 1 }
        text: "CPU " + (cc.stats.cpu !== undefined ? cc.stats.cpu + "%" : "—")
          + "   ·   Mem " + (cc.stats.memUsed ? cc.stats.memUsed + "/" + cc.stats.memTotal + " GB" : "—")
          + "   ·   ↓ " + cc.rate(cc.rxRate) + "  ↑ " + cc.rate(cc.txRate)
          + (cc.sys.hasBattery ? "   ·   " + cc.sys.batteryValue : "")
          + "   ›"
      }
    }
  }
}
