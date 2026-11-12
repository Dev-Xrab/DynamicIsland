import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Activity pane (System card -> Activity): what is running right now.
//
//   ┌ Network ─────────┬ Top processes ─────────────────────────┐
//   │ ↓ 1.2 MB/s       │ quickshell   ▬▬▬▬▬▬▬     12%   380 MB  │
//   │ ↑ 30 KB/s        │ chrome       ▬▬▬          6%   560 MB  │
//   │ Load · Tasks     │ …                                      │
//   │ [ Open btop ]    │                                        │
//   └──────────────────┴────────────────────────────────────────┘
//
// Read from island-activity.sh every 2.5s, only while the pane is on screen.
Item {
  id: act

  required property var tk
  property bool revealed: false
  signal closeRequested()

  property var procs: []
  property int count: 0
  property string load: ""
  property real rxRate: -1
  property real txRate: -1
  property real lastRx: -1
  property real lastTx: -1
  property real lastAt: 0
  property string error: ""

  readonly property string script: Qt.resolvedUrl("island-activity.sh").toString().replace("file://", "")

  function rate(bps) {
    if (bps < 0) return "—"
    if (bps >= 1048576) return (bps / 1048576).toFixed(1) + " MB/s"
    if (bps >= 1024) return Math.round(bps / 1024) + " KB/s"
    return Math.round(bps) + " B/s"
  }
  function mem(mib) {
    return mib >= 1024 ? (mib / 1024).toFixed(1) + " GB" : Math.round(mib) + " MB"
  }

  Process {
    id: proc
    command: [act.script]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d
        try { d = JSON.parse(String(text || "").trim()) }
        catch (e) { act.error = "Could not read processes"; console.warn("island activity:", e); return }
        act.error = ""
        act.procs = d.procs || []
        act.count = Number(d.count) || 0
        act.load = String(d.load || "").split(" ")[0] || ""
        var now = Date.now()
        if (act.lastAt > 0 && now > act.lastAt) {
          var dt = (now - act.lastAt) / 1000
          act.rxRate = Math.max(0, (Number(d.rx) - act.lastRx) / dt)
          act.txRate = Math.max(0, (Number(d.tx) - act.lastTx) / dt)
        }
        act.lastRx = Number(d.rx); act.lastTx = Number(d.tx); act.lastAt = now
      }
    }
  }
  Timer {
    interval: 2500
    repeat: true
    running: act.revealed
    triggeredOnStart: true
    onTriggered: if (!proc.running) proc.running = true
  }

  component Label: Text {
    font.family: act.tk.fontFamily
    font.pixelSize: act.tk.cardTitleSize
    font.letterSpacing: 0.6
    color: act.tk.textFaint
  }
  component Value: Text {
    font.family: act.tk.fontFamily
    font.pixelSize: act.tk.fontSize - 1
    font.weight: Font.DemiBold
    font.features: { "tnum": 1 }
    color: act.tk.text
  }

  RowLayout {
    anchors.fill: parent
    spacing: act.tk.cardGap

    IslandCard {
      tk: act.tk; index: 0; revealed: act.revealed
      Layout.preferredWidth: act.tk.px(170)
      Layout.fillHeight: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: act.tk.cardPad
        spacing: act.tk.px(3)

        Label { text: "NETWORK" }
        Value { text: "↓  " + act.rate(act.rxRate) }
        Value { text: "↑  " + act.rate(act.txRate) }
        Item { Layout.fillHeight: true }
        Text {
          Layout.fillWidth: true
          elide: Text.ElideRight
          text: "Load " + (act.load || "—") + "  ·  " + act.count + " tasks"
          font.family: act.tk.fontFamily
          font.pixelSize: act.tk.fontSize - 4
          color: act.tk.textDim
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: act.tk.buttonHeight
          radius: height / 2
          color: btopMouse.pressed ? act.tk.cardPressed : (btopMouse.containsMouse ? act.tk.cardHover : act.tk.card)
          Behavior on color { ColorAnimation { duration: 120 } }
          Text {
            anchors.centerIn: parent
            text: "Open btop"
            font.family: act.tk.fontFamily
            font.pixelSize: act.tk.fontSize - 3
            font.weight: Font.DemiBold
            color: act.tk.text
          }
          MouseArea {
            id: btopMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              act.closeRequested()
              Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
            }
          }
        }
      }
    }

    IslandCard {
      tk: act.tk; index: 1; revealed: act.revealed
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: act.tk.cardPad
        spacing: act.tk.px(5)

        RowLayout {
          Layout.fillWidth: true
          Label { text: "TOP PROCESSES"; Layout.fillWidth: true }
          Label { text: "CPU"; Layout.preferredWidth: act.tk.px(44); horizontalAlignment: Text.AlignRight }
          Label { text: "MEM"; Layout.preferredWidth: act.tk.px(58); horizontalAlignment: Text.AlignRight }
        }

        Text {
          visible: act.error !== "" || act.procs.length === 0
          text: act.error !== "" ? act.error : "Reading…"
          font.family: act.tk.fontFamily
          font.pixelSize: act.tk.fontSize - 3
          color: act.error !== "" ? act.tk.danger : act.tk.textDim
        }

        Repeater {
          model: act.procs.slice(0, 6)
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: act.tk.px(8)

            Text {
              Layout.preferredWidth: act.tk.px(120)
              text: modelData.name
              elide: Text.ElideRight
              textFormat: Text.PlainText
              font.family: act.tk.fontFamily
              font.pixelSize: act.tk.fontSize - 3
              color: act.tk.text
            }
            // CPU bar, relative to one core.
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: act.tk.px(4)
              radius: height / 2
              color: act.tk.meterTrack
              Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.min(1, modelData.cpu / 100)
                color: modelData.cpu >= 80 ? act.tk.orange : act.tk.text
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
              }
            }
            Text {
              Layout.preferredWidth: act.tk.px(44)
              horizontalAlignment: Text.AlignRight
              text: Math.round(modelData.cpu) + "%"
              font.family: act.tk.fontFamily
              font.pixelSize: act.tk.fontSize - 3
              font.features: { "tnum": 1 }
              color: modelData.cpu >= 80 ? act.tk.orange : act.tk.textDim
            }
            Text {
              Layout.preferredWidth: act.tk.px(58)
              horizontalAlignment: Text.AlignRight
              text: act.mem(modelData.mem)
              font.family: act.tk.fontFamily
              font.pixelSize: act.tk.fontSize - 3
              font.features: { "tnum": 1 }
              color: act.tk.textDim
            }
          }
        }
        Item { Layout.fillHeight: true }
      }
    }
  }
}
