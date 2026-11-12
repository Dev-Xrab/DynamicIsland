import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// The island's second page: Claude Code usage, what the machine is doing, and
// the six things you reach for most. Everything here is live and clickable.
//
//   ┌ Claude Code ─ session + weekly allowance ──────────────┬ System ───────┐
//   │                                                       │ CPU  MEM      │
//   │                                                       │ TEMP DISK     │
//   ├───────────────────────────────────────────────────────┴───────────────┤
//   │ Silent · Night Light · Stay Awake · Screenshot · Record · Lock        │
//   └───────────────────────────────────────────────────────────────────────┘
Item {
  id: extras

  required property var tk
  required property var status          // IslandStatus: silent, nightLight, stayAwake, recording
  required property var sys             // IslandSystem: Claude usage
  property bool revealed: false
  // Two pages share this file: "controls" (toggle and action tiles, laid out
  // like page one's grid) and "stats" (Claude Code and System, full height).
  property string mode: "controls"

  // One stat on the Stats page: label and value on a line, a bar, and a small
  // note under it. Both cards (Claude Code, System) are built from these in
  // the same two equal rows, so their bars line up across the page.
  readonly property int statTop: tk.px(26)   // below each card's title row
  component StatCell: Item {
    id: cell
    property string label: ""
    property string value: "—"
    property real pct: -1
    property int warn: 85
    property string note: ""
    readonly property color fill: pct >= warn ? extras.tk.orange : extras.tk.text
    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: extras.tk.px(6)
      Item {
        width: parent.width
        height: cellValue.implicitHeight
        Text {
          anchors.left: parent.left
          anchors.baseline: cellValue.baseline
          text: cell.label
          font.family: extras.tk.fontFamily
          font.pixelSize: extras.tk.cardTitleSize
          font.letterSpacing: 0.6
          color: extras.tk.textFaint
        }
        Text {
          id: cellValue
          anchors.right: parent.right
          text: cell.value
          font.family: extras.tk.fontFamily
          font.pixelSize: extras.tk.fontSize
          font.weight: Font.DemiBold
          font.features: { "tnum": 1 }
          color: cell.pct >= cell.warn ? extras.tk.orange : extras.tk.text
        }
      }
      Rectangle {
        width: parent.width
        height: extras.tk.px(5)
        radius: height / 2
        color: extras.tk.meterTrack
        Rectangle {
          height: parent.height
          radius: parent.radius
          width: parent.width * Math.max(0, Math.min(100, cell.pct)) / 100
          color: cell.fill
          Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
      }
      // Always takes a line, even when empty, so every cell is the same height.
      Text {
        width: parent.width
        text: cell.note === "" ? " " : cell.note
        elide: Text.ElideRight
        font.family: extras.tk.fontFamily
        font.pixelSize: extras.tk.tileLabelSize
        color: extras.tk.textFaint
      }
    }
  }

  // Asks the bar to fold the island away before an action that needs the
  // screen (a screenshot, a lock, a terminal).
  signal closeRequested()
  signal openDetail(string kind)

  function run(argv) { Quickshell.execDetached(argv) }
  // Run once the island has folded out of the way, so it is not in a
  // screenshot or covering a region picker.
  function runAfterClose(argv) {
    extras.closeRequested()
    deferred.argv = argv
    deferred.restart()
  }
  Timer {
    id: deferred
    property var argv: []
    interval: extras.tk.collapseDuration + 60
    onTriggered: Quickshell.execDetached(argv)
  }

  // ------------------------------------------------------------ live stats
  // Polled only while the island is open; closed, it costs nothing.
  property var stats: ({ cpu: -1, memPct: -1, memUsed: "", memTotal: "", temp: -1, diskPct: -1, diskFree: 0, up: "" })

  Process {
    id: statsProc
    command: [Qt.resolvedUrl("island-stats.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { extras.stats = JSON.parse(String(text || "").trim()) } catch (e) {}
      }
    }
  }
  Timer {
    interval: 2000
    repeat: true
    running: extras.revealed && extras.mode === "stats"
    triggeredOnStart: true
    onTriggered: if (!statsProc.running) statsProc.running = true
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: extras.tk.cardGap

    RowLayout {
      id: cardRow
      visible: extras.mode === "stats"
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: extras.tk.cardGap
      // Two equal halves, fixed: sharing by content width let the System card
      // grow with its numbers and squeeze the Claude card's text under it.
      readonly property real half: Math.max(0, Math.floor((extras.width - spacing) / 2))

      // --- Claude Code -------------------------------------------------------
      IslandCard {
        tk: extras.tk
        index: 5
        revealed: extras.revealed
        interactive: true
        hot: claudeMouse.containsMouse
        down: claudeMouse.pressed
        Layout.preferredWidth: cardRow.half
        Layout.maximumWidth: cardRow.half
        Layout.fillHeight: true
        clip: true

        Item {
          anchors.fill: parent
          anchors.margins: extras.tk.cardPad

          Row {
            id: claudeHead
            anchors.top: parent.top
            anchors.left: parent.left
            spacing: extras.tk.px(7)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: extras.sys.claudeGlyph
              font.family: extras.tk.fontFamily
              font.pixelSize: extras.tk.tileIconSize
              color: extras.tk.textDim
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Claude Code"
              font.family: extras.tk.fontFamily
              font.pixelSize: extras.tk.cardTitleSize
              font.letterSpacing: 0.8
              color: extras.tk.textFaint
            }
          }

          Text {
            anchors.right: parent.right
            anchors.top: parent.top
            text: extras.sys.claudeTier
            font.family: extras.tk.fontFamily
            font.pixelSize: extras.tk.cardTitleSize
            font.letterSpacing: 0.8
            color: extras.tk.textFaint
          }

          // Both allowances the usage record carries, in two equal rows under
          // the title (the same rows as the System card, so the bars align).
          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: extras.statTop
            anchors.bottom: parent.bottom
            visible: extras.sys.claudeHasLimits
            StatCell {
              width: parent.width
              height: parent.height / 2
              label: extras.sys.claudeSessionLabel
              pct: extras.sys.claudePercent
              value: extras.sys.claudePercent >= 0 ? extras.sys.claudePercent + "%" : "—"
              warn: 80
              note: extras.sys.claudeSessionReset
            }
            StatCell {
              width: parent.width
              height: parent.height / 2
              visible: extras.sys.claudeHasWeekly
              label: extras.sys.claudeWeeklyLabel
              pct: extras.sys.claudeWeeklyPercent
              value: extras.sys.claudeWeeklyPercent >= 0 ? extras.sys.claudeWeeklyPercent + "%" : "—"
              warn: 80
              note: extras.sys.claudeWeeklyReset
            }
          }

          // Without a signed-in CLI the record carries no limits at all, so
          // say that rather than drawing two empty bars.
          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: extras.statTop
            visible: !extras.sys.claudeHasLimits
            text: extras.sys.claudeDetail
            wrapMode: Text.WordWrap
            font.family: extras.tk.fontFamily
            font.pixelSize: extras.tk.tileLabelSize
            color: extras.tk.textDim
          }
        }

        MouseArea {
          id: claudeMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: extras.openDetail("claude")
        }
      }

      // --- System -----------------------------------------------------------
      IslandCard {
        tk: extras.tk
        index: 6
        revealed: extras.revealed
        interactive: true
        hot: sysMouse.containsMouse
        down: sysMouse.pressed
        Layout.preferredWidth: cardRow.half
        Layout.maximumWidth: cardRow.half
        Layout.fillHeight: true
        clip: true

        Item {
          anchors.fill: parent
          anchors.margins: extras.tk.cardPad

          Text {
            id: sysHead
            anchors.left: parent.left
            anchors.top: parent.top
            text: "System"
            font.family: extras.tk.fontFamily
            font.pixelSize: extras.tk.cardTitleSize
            font.letterSpacing: 0.8
            color: extras.tk.textFaint
          }
          Text {
            anchors.right: parent.right
            anchors.baseline: sysHead.baseline
            text: extras.stats.up !== "" ? "up " + extras.stats.up : ""
            font.family: extras.tk.fontFamily
            font.pixelSize: extras.tk.cardTitleSize
            color: extras.tk.textFaint
          }

          // Two equal rows under the title, like the Claude Code card.
          Grid {
            id: sysGrid
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: extras.statTop
            anchors.bottom: parent.bottom
            columns: 2
            columnSpacing: extras.tk.spaceLg
            rowSpacing: 0

            Repeater {
              model: [
                { label: "CPU",  pct: extras.stats.cpu,     text: extras.stats.cpu >= 0 ? extras.stats.cpu + "%" : "—", warn: 85, note: "" },
                { label: "MEM",  pct: extras.stats.memPct,  text: extras.stats.memUsed !== "" ? extras.stats.memUsed + "/" + extras.stats.memTotal + "G" : "—", warn: 85,
                  note: extras.stats.memPct >= 0 ? extras.stats.memPct + "% used" : "" },
                { label: "TEMP", pct: extras.stats.temp,    text: extras.stats.temp >= 0 ? extras.stats.temp + "°C" : "—", warn: 85, note: "" },
                { label: "DISK", pct: extras.stats.diskPct, text: extras.stats.diskPct >= 0 ? extras.stats.diskFree + "G free" : "—", warn: 90,
                  note: extras.stats.diskPct >= 0 ? extras.stats.diskPct + "% used" : "" }
              ]
              delegate: StatCell {
                required property var modelData
                width: (sysGrid.width - extras.tk.spaceLg) / 2
                height: sysGrid.height / 2
                label: modelData.label
                value: modelData.text
                pct: modelData.pct
                warn: modelData.warn
                note: modelData.note
              }
            }
          }
        }

        MouseArea {
          id: sysMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          // Drill into the Activity pane (top processes, network); btop is
          // one click further from there.
          onClicked: extras.openDetail("activity")
        }
      }
    }

    // --- Controls page: two 2x2 grids of tiles, the same tile and spacing
    // as page one. Toggles on the left (lit disc = on), actions on the right.
    RowLayout {
      visible: extras.mode === "controls"
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: extras.tk.cardGap

      GridLayout {
        Layout.preferredWidth: 1
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: 2
        rowSpacing: extras.tk.cardGap
        columnSpacing: extras.tk.cardGap

        IslandTile {
          tk: extras.tk; index: 1; revealed: extras.revealed
          Layout.fillWidth: true; Layout.fillHeight: true
          glyph: extras.status.stayAwake ? "󰅶" : "󰛊"
          value: "Stay awake"
          detail: extras.status.stayAwake ? "On" : "Off"
          on: extras.status.stayAwake
          onActivated: extras.run(["omarchy-toggle-idle"])
        }
        IslandTile {
          tk: extras.tk; index: 2; revealed: extras.revealed
          Layout.fillWidth: true; Layout.fillHeight: true
          glyph: extras.status.silent ? "󰂛" : "󰂚"
          value: "Silent"
          detail: extras.status.silent ? "On" : "Off"
          on: extras.status.silent
          onActivated: extras.run(["omarchy-shell", "-q", "notifications", "toggleDnd"])
        }
        IslandTile {
          tk: extras.tk; index: 3; revealed: extras.revealed
          Layout.fillWidth: true; Layout.fillHeight: true
          glyph: "󰔎"
          value: "Night light"
          detail: extras.status.nightLight ? "On" : "Off"
          on: extras.status.nightLight
          onActivated: extras.run(["omarchy-toggle-nightlight"])
        }
        IslandTile {
          tk: extras.tk; index: 4; revealed: extras.revealed
          Layout.fillWidth: true; Layout.fillHeight: true
          glyph: "󰍹"
          value: "Display"
          detail: "Brightness"
          onActivated: extras.openDetail("display")
        }
      }

      GridLayout {
        Layout.preferredWidth: 1
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: 2
        rowSpacing: extras.tk.cardGap
        columnSpacing: extras.tk.cardGap

        IslandTile {
          tk: extras.tk; index: 5; revealed: extras.revealed
          Layout.fillWidth: true; Layout.fillHeight: true
          glyph: "󰄀"
          value: "Screenshot"
          detail: "Select area"
          onActivated: extras.runAfterClose(["omarchy-capture-screenshot"])
        }
        IslandTile {
          tk: extras.tk; index: 6; revealed: extras.revealed
          Layout.fillWidth: true; Layout.fillHeight: true
          glyph: "󰻃"
          value: extras.status.recording ? "Stop" : "Record"
          detail: extras.status.recording ? "Recording now" : "Screen video"
          attention: extras.status.recording
          // Not recording: pick audio in the Screen Recording pane.
          onActivated: extras.status.recording
            ? extras.run(["omarchy-capture-screenrecording", "--stop-recording"])
            : extras.openDetail("record")
        }
        IslandTile {
          tk: extras.tk; index: 7; revealed: extras.revealed
          Layout.fillWidth: true; Layout.fillHeight: true
          glyph: "󰌾"
          value: "Lock"
          detail: "Lock screen"
          onActivated: extras.runAfterClose(["omarchy-system-lock"])
        }
        IslandTile {
          tk: extras.tk; index: 8; revealed: extras.revealed
          Layout.fillWidth: true; Layout.fillHeight: true
          glyph: "󰂚"
          value: "Notifications"
          detail: extras.status.missedCount > 0 ? extras.status.missedCount + " missed"
            : extras.status.notifHistory.length > 0 ? extras.status.notifHistory.length + " recent" : "None"
          on: extras.status.missedCount > 0
          onActivated: extras.openDetail("notifications")
        }
      }
    }
  }
}
