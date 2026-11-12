import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Notification Center: the right-side panel (macOS Sequoia).
//
//   ┌ Notification Center ──────────── Clear All ┐
//   │ Saturday, November 7                       │
//   │ ┌ Calendar ─────┐ ┌ Today ───────┐         │  widgets (optional)
//   │ └───────────────┘ └──────────────┘         │
//   │ ◉ Claude · 3                    Show more ⌄│  one group per app,
//   │ ┌───────────────────────────────────────┐  │  stacked when collapsed
//   │ │ ▣ Title                          2m   │  │
//   │ │   Body…                               │  │
//   │ └───────────────────────────────────────┘  │
//   └────────────────────────────────────────────┘
//
// Not a second notification daemon: everything comes from the one the shell
// already runs (xrab.notifications). The toast on screen right now is read
// from IslandStatus.liveNotification and acted on through the daemon's IPC
// (invokeOriginal / dismissOriginal, so its default action still fires);
// everything that has left the screen is the daemon's own history folder,
// which IslandStatus already watches. Dismiss deletes that history file,
// Clear All calls the daemon's `clear`.
Item {
  id: nc

  required property var tk
  required property var sys
  required property var status
  property bool open: false
  // ~/.config/omarchy/island.json "ncWidgets": false hides the widget row.
  property bool widgets: true

  signal closeRequested()

  // --------------------------------------------------------------- data
  function appLabel(e) {
    var a = String(e && e.app || "")
    return a === "" || a === "notify-send" || a === "omarchy-action" ? "System" : a
  }
  function iconFor(e) {
    var img = String(e && e.image || "")
    if (img.indexOf("file://") === 0 || img.indexOf("image://") === 0) return img
    if (img.charAt(0) === "/") return "file://" + img
    var icon = String(e && e.appIcon || "")
    if (icon.indexOf("file://") === 0) return icon
    if (icon.charAt(0) === "/") return "file://" + icon
    return icon !== "" ? Quickshell.iconPath(icon, true) : ""
  }
  property int tick: 0
  function ago(ts) {
    var t = tick
    var s = Math.max(0, Math.floor((Date.now() - Number(ts || 0)) / 1000))
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m ago"
    if (s < 86400) return Math.floor(s / 3600) + "h ago"
    return Math.floor(s / 86400) + "d ago"
  }

  // The live toast (if any) first, then history; grouped by app, the group
  // with the newest message first.
  readonly property var entries: {
    var out = []
    var st = nc.status
    if (!st) return out
    var live = st.liveNotification
    var hist = st.notifHistory || []
    if (live && st.notificationCount > 0) {
      var dup = false
      for (var i = 0; i < hist.length; i++) if (st.notifKey(hist[i]) === st.notifKey(live)) dup = true
      if (!dup) out.push(Object.assign({}, live, { live: true }))
    }
    for (var j = 0; j < hist.length; j++) out.push(hist[j])
    return out
  }
  readonly property var groups: {
    var by = {}, order = []
    for (var i = 0; i < entries.length; i++) {
      var g = appLabel(entries[i])
      if (!by[g]) { by[g] = []; order.push(g) }
      by[g].push(entries[i])
    }
    var out = []
    for (var k = 0; k < order.length; k++) out.push({ app: order[k], items: by[order[k]] })
    return out
  }

  property var expandedGroups: ({})
  // Month name in the calendar: small widget <-> full-width calendar.
  property bool calLarge: false
  property var expandedItems: ({})
  function toggleGroup(app) {
    var n = Object.assign({}, expandedGroups); n[app] = !n[app]; expandedGroups = n
  }
  function toggleItem(key) {
    var n = Object.assign({}, expandedItems); n[key] = !n[key]; expandedItems = n
  }
  function itemKey(e) { return String(e.file || ("live:" + e.originalId)) }

  function openEntry(e) {
    if (e.live) nc.status.invokeNotification()
    else nc.status.openHistoryEntry(e)
    nc.closeRequested()
  }
  function dismissEntry(e) {
    if (e.live) nc.status.dismissNotification()
    else nc.status.deleteHistoryEntry(e)
  }
  function clearGroup(group) {
    for (var i = 0; i < group.items.length; i++) dismissEntry(group.items[i])
  }
  function clearAll() {
    if (nc.status.liveNotification && nc.status.notificationCount > 0) nc.status.dismissNotification()
    nc.status.clearHistory()
  }

  // Clock / relative times tick only while the panel is open.
  property date now: new Date()
  Timer {
    interval: 30000
    repeat: true
    running: nc.open
    triggeredOnStart: true
    onTriggered: { nc.now = new Date(); nc.tick++ }
  }

  // Mapped while open and for the slide-out after.
  property bool shown: open || hideHold.running
  onOpenChanged: if (!open) hideHold.restart()
  Timer { id: hideHold; interval: nc.tk.panelDuration + 40 }

  // ---------------------------------------------------------- components
  component Small: Text {
    font.family: nc.tk.fontFamily
    font.pixelSize: nc.tk.fontSize - 5
    color: nc.tk.textDim
    textFormat: Text.PlainText
    elide: Text.ElideRight
  }

  component PillButton: Rectangle {
    id: pb
    property string label: ""
    signal clicked()
    implicitWidth: pbText.implicitWidth + nc.tk.px(18)
    implicitHeight: nc.tk.px(24)
    radius: height / 2
    color: pbMouse.pressed ? Qt.alpha(nc.tk.text, 0.22) : (pbMouse.containsMouse ? Qt.alpha(nc.tk.text, 0.16) : Qt.alpha(nc.tk.text, 0.10))
    Behavior on color { ColorAnimation { duration: nc.tk.hoverDuration } }
    Text {
      id: pbText
      anchors.centerIn: parent
      text: pb.label
      font.family: nc.tk.fontFamily
      font.pixelSize: nc.tk.fontSize - 4
      font.weight: Font.DemiBold
      color: nc.tk.text
    }
    MouseArea {
      id: pbMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pb.clicked()
    }
  }

  component AppIcon: Item {
    id: ai
    property var entry: null
    property int size: nc.tk.px(34)
    implicitWidth: size
    implicitHeight: size
    readonly property string src: nc.iconFor(entry)
    Rectangle {
      anchors.fill: parent
      radius: nc.tk.px(9)
      color: Qt.alpha(nc.tk.text, 0.12)
      visible: img.status !== Image.Ready
      Text {
        anchors.centerIn: parent
        text: String(ai.entry && ai.entry.glyph || "") !== "" ? ai.entry.glyph : "󰂚"
        font.family: nc.tk.iconFamily
        font.pixelSize: ai.size * 0.5
        color: nc.tk.text
      }
    }
    Image {
      id: img
      anchors.fill: parent
      source: ai.src
      sourceSize.width: ai.size * 2
      sourceSize.height: ai.size * 2
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      visible: status === Image.Ready
      layer.enabled: visible
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: iconMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
    }
    Rectangle {
      id: iconMask
      anchors.fill: parent
      radius: nc.tk.px(9)
      visible: false
      layer.enabled: true
    }
  }

  // One notification.
  component NoteCard: Rectangle {
    id: card
    property var entry: null
    readonly property string key: entry ? nc.itemKey(entry) : ""
    readonly property bool full: !!nc.expandedItems[key]
    implicitHeight: noteRow.implicitHeight + nc.tk.px(22)
    radius: nc.tk.px(16)
    color: cardMouse.containsMouse ? Qt.alpha(nc.tk.text, 0.13) : Qt.alpha(nc.tk.text, 0.09)
    border.width: 1
    border.color: Qt.alpha(nc.tk.text, 0.07)
    Behavior on color { ColorAnimation { duration: nc.tk.hoverDuration } }

    MouseArea {
      id: cardMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: nc.openEntry(card.entry)
    }

    RowLayout {
      id: noteRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: nc.tk.px(11)
      spacing: nc.tk.px(10)

      AppIcon { entry: card.entry; Layout.alignment: Qt.AlignTop }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: nc.tk.px(2)
        RowLayout {
          Layout.fillWidth: true
          Text {
            Layout.fillWidth: true
            text: String(card.entry && card.entry.summary || nc.appLabel(card.entry))
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: nc.tk.fontFamily
            font.pixelSize: nc.tk.fontSize - 3
            font.weight: Font.DemiBold
            color: nc.tk.text
          }
          Small { text: card.entry && card.entry.live ? "now" : nc.ago(card.entry ? card.entry.timestamp : 0) }
        }
        Text {
          id: bodyText
          Layout.fillWidth: true
          visible: text !== ""
          text: String(card.entry && card.entry.body || "")
          wrapMode: Text.Wrap
          maximumLineCount: card.full ? 40 : 2
          elide: Text.ElideRight
          textFormat: Text.PlainText
          font.family: nc.tk.fontFamily
          font.pixelSize: nc.tk.fontSize - 4
          color: nc.tk.textDim
        }
      }
    }

    // Hover controls: × (dismiss) top-left like macOS, ⌄ (expand) right.
    Rectangle {
      x: -nc.tk.px(6); y: -nc.tk.px(6)
      width: nc.tk.px(20); height: width
      radius: width / 2
      color: closeMouse.containsMouse ? "#4A4A4E" : "#3A3A3C"
      border.width: 1
      border.color: Qt.alpha(nc.tk.text, 0.15)
      opacity: cardMouse.containsMouse || closeMouse.containsMouse || expandMouse.containsMouse ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: nc.tk.hoverDuration } }
      Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: nc.tk.px(9); color: nc.tk.text }
      MouseArea {
        id: closeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: nc.dismissEntry(card.entry)
      }
    }
    Rectangle {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: nc.tk.px(6)
      width: nc.tk.px(22); height: nc.tk.px(18)
      radius: height / 2
      visible: bodyText.truncated || card.full
      opacity: cardMouse.containsMouse || expandMouse.containsMouse ? 1 : 0
      color: expandMouse.containsMouse ? Qt.alpha(nc.tk.text, 0.18) : Qt.alpha(nc.tk.text, 0.10)
      Behavior on opacity { NumberAnimation { duration: nc.tk.hoverDuration } }
      Text {
        anchors.centerIn: parent
        text: card.full ? "⌃" : "⌄"
        font.pixelSize: nc.tk.px(11)
        color: nc.tk.text
      }
      MouseArea {
        id: expandMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: nc.toggleItem(card.key)
      }
    }
  }

  // One app's notifications: header, then a stack (collapsed) or the list.
  component Group: ColumnLayout {
    id: grp
    property var group: null
    readonly property bool many: group && group.items.length > 1
    readonly property bool expanded: group && !!nc.expandedGroups[group.app]
    spacing: nc.tk.px(6)

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: nc.tk.px(4)
      spacing: nc.tk.px(6)
      Text {
        Layout.fillWidth: true
        text: grp.group ? grp.group.app + (grp.many ? "  ·  " + grp.group.items.length : "") : ""
        elide: Text.ElideRight
        font.family: nc.tk.fontFamily
        font.pixelSize: nc.tk.fontSize - 4
        font.weight: Font.DemiBold
        color: nc.tk.textDim
      }
      PillButton {
        visible: grp.many
        label: grp.expanded ? "Show less" : "Show all"
        onClicked: nc.toggleGroup(grp.group.app)
      }
      PillButton {
        label: "✕"
        onClicked: nc.clearGroup(grp.group)
      }
    }

    // Collapsed: newest on top, two plates peeking out under it.
    Item {
      Layout.fillWidth: true
      visible: !grp.expanded
      implicitHeight: topCard.implicitHeight + (grp.many ? nc.tk.px(12) : 0)
      Rectangle {
        visible: grp.group && grp.group.items.length > 2
        x: nc.tk.px(16); width: parent.width - nc.tk.px(32)
        y: topCard.implicitHeight - nc.tk.px(16) + nc.tk.px(12)
        height: nc.tk.px(16)
        radius: nc.tk.px(10)
        color: Qt.alpha(nc.tk.text, 0.04)
      }
      Rectangle {
        visible: grp.many
        x: nc.tk.px(8); width: parent.width - nc.tk.px(16)
        y: topCard.implicitHeight - nc.tk.px(16) + nc.tk.px(6)
        height: nc.tk.px(16)
        radius: nc.tk.px(12)
        color: Qt.alpha(nc.tk.text, 0.07)
      }
      NoteCard {
        id: topCard
        width: parent.width
        height: implicitHeight
        entry: grp.group ? grp.group.items[0] : null
      }
    }

    // Expanded: every notification of the app.
    Repeater {
      model: grp.expanded ? grp.group.items : []
      delegate: NoteCard {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        entry: modelData
      }
    }
  }

  component NavButton: Rectangle {
    id: nb
    property string label: ""
    signal clicked()
    width: Math.max(nc.tk.px(20), nbText.implicitWidth + nc.tk.px(10))
    height: nc.tk.px(18)
    radius: height / 2
    color: nbMouse.pressed ? Qt.alpha(nc.tk.text, 0.22) : (nbMouse.containsMouse ? Qt.alpha(nc.tk.text, 0.14) : "transparent")
    Behavior on color { ColorAnimation { duration: nc.tk.hoverDuration } }
    Text {
      id: nbText
      anchors.centerIn: parent
      text: nb.label
      font.family: nc.tk.fontFamily
      font.pixelSize: nc.tk.fontSize - 5
      font.weight: Font.DemiBold
      color: nc.tk.text
    }
    MouseArea {
      id: nbMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: nb.clicked()
    }
  }

  // Calendar widget: a real month view. ‹ › (or the scroll wheel) change the
  // month, Today jumps back, and the month name toggles a large calendar
  // that takes the whole widget row.
  component CalendarWidget: Rectangle {
    id: cal
    radius: nc.tk.px(16)
    color: Qt.alpha(nc.tk.text, 0.09)
    border.width: 1
    border.color: Qt.alpha(nc.tk.text, 0.07)
    implicitHeight: calCol.implicitHeight + nc.tk.px(18)
    // Months away from the current one; back to 0 every time the panel opens.
    property int offset: 0
    Connections { target: nc; function onOpenChanged() { if (nc.open) cal.offset = 0 } }
    readonly property date view: new Date(nc.now.getFullYear(), nc.now.getMonth() + offset, 1)
    readonly property int year: view.getFullYear()
    readonly property int month: view.getMonth()
    readonly property bool thisMonth: year === nc.now.getFullYear() && month === nc.now.getMonth()
    readonly property int today: nc.now.getDate()
    readonly property var cells: {
      var first = new Date(year, month, 1).getDay()          // 0 = Sunday
      var days = new Date(year, month + 1, 0).getDate()
      var out = []
      for (var i = 0; i < first; i++) out.push(0)
      for (var d = 1; d <= days; d++) out.push(d)
      while (out.length % 7) out.push(0)
      return out
    }
    WheelHandler {
      onWheel: function(e) { cal.offset += e.angleDelta.y > 0 ? -1 : 1 }
    }

    ColumnLayout {
      id: calCol
      anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
      anchors.margins: nc.tk.px(9)
      spacing: nc.tk.px(3)
      RowLayout {
        Layout.fillWidth: true
        spacing: 0
        Text {
          id: monthTitle
          Layout.fillWidth: true
          text: Qt.formatDate(cal.view, cal.year === nc.now.getFullYear() ? "MMMM" : "MMM yyyy").toUpperCase()
          elide: Text.ElideRight
          font.family: nc.tk.fontFamily
          font.pixelSize: nc.tk.fontSize - 5
          font.weight: Font.Bold
          font.letterSpacing: 0.6
          font.underline: monthMouse.containsMouse
          color: nc.tk.crit
          MouseArea {
            id: monthMouse
            width: monthTitle.implicitWidth
            height: parent.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nc.calLarge = !nc.calLarge
          }
        }
        NavButton { label: "Today"; visible: !cal.thisMonth; onClicked: cal.offset = 0 }
        NavButton { label: "‹"; onClicked: cal.offset -= 1 }
        NavButton { label: "›"; onClicked: cal.offset += 1 }
      }
      GridLayout {
        Layout.fillWidth: true
        columns: 7
        rowSpacing: 1
        columnSpacing: 0
        Repeater {
          model: ["S", "M", "T", "W", "T", "F", "S"]
          delegate: Text {
            required property string modelData
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: modelData
            font.family: nc.tk.fontFamily
            font.pixelSize: nc.tk.fontSize - 6
            font.weight: Font.DemiBold
            color: nc.tk.textFaint
          }
        }
        Repeater {
          model: cal.cells
          delegate: Item {
            required property int modelData
            required property int index
            readonly property bool isToday: cal.thisMonth && modelData === cal.today
            readonly property bool weekend: index % 7 === 0 || index % 7 === 6
            Layout.fillWidth: true
            implicitHeight: nc.calLarge ? nc.tk.px(30) : nc.tk.px(17)
            Rectangle {
              anchors.centerIn: parent
              width: nc.calLarge ? nc.tk.px(26) : nc.tk.px(17); height: width
              radius: width / 2
              color: nc.tk.crit
              visible: parent.isToday
            }
            Text {
              anchors.centerIn: parent
              text: modelData > 0 ? modelData : ""
              font.family: nc.tk.fontFamily
              font.pixelSize: nc.calLarge ? nc.tk.fontSize - 3 : nc.tk.fontSize - 6
              font.weight: parent.isToday ? Font.Bold : Font.Normal
              font.features: { "tnum": 1 }
              color: parent.isToday ? nc.tk.text : (parent.weekend ? nc.tk.textFaint : nc.tk.textDim)
            }
          }
        }
      }
    }
  }

  // Today widget: the time, the date and a glance at the machine.
  component TodayWidget: Rectangle {
    radius: nc.tk.px(16)
    color: Qt.alpha(nc.tk.text, 0.09)
    border.width: 1
    border.color: Qt.alpha(nc.tk.text, 0.07)
    ColumnLayout {
      anchors.fill: parent
      anchors.margins: nc.tk.px(12)
      spacing: nc.tk.px(2)
      Text {
        text: Qt.formatTime(nc.now, Qt.locale().timeFormat(Locale.ShortFormat).indexOf("AP") >= 0 ? "h:mm" : "HH:mm")
        font.family: nc.tk.fontFamily
        font.pixelSize: nc.tk.px(30)
        font.weight: Font.Light
        font.features: { "tnum": 1 }
        color: nc.tk.text
      }
      Small { text: Qt.formatDate(nc.now, "dddd") }
      Item { Layout.fillHeight: true }
      Small { Layout.fillWidth: true; text: "󰈀  " + nc.sys.netValue }
      Small { Layout.fillWidth: true; text: (nc.sys.hasBattery ? nc.sys.batteryGlyph + "  " + nc.sys.batteryValue : "󰚥  AC power") }
      Small { Layout.fillWidth: true; text: nc.sys.audioGlyph + "  " + nc.sys.audioValue }
    }
  }

  // ----------------------------------------------------------- surfaces
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: win
        required property var modelData
        screen: modelData

        // Only on the monitor the keyboard is on (where SUPER+N was pressed).
        readonly property bool here: !Hyprland.focusedMonitor || Hyprland.focusedMonitor.name === modelData.name
        visible: nc.shown && here

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "omarchy-island-nc"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Click anywhere outside the panel: dismiss.
        MouseArea {
          anchors.fill: parent
          enabled: nc.open
          onClicked: nc.closeRequested()
        }

        Item {
          id: panel
          readonly property int panelTop: nc.tk.reservedHeight + nc.tk.ncMargin
          width: Math.min(nc.tk.ncWidth, win.width - nc.tk.ncMargin * 2)
          // As tall as its content, up to the screen: no empty glass.
          readonly property int maxHeight: win.height - panelTop - nc.tk.ncMargin
          height: Math.min(maxHeight, column.implicitHeight + nc.tk.px(24))
          Behavior on height { NumberAnimation { duration: nc.tk.panelDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: nc.tk.springCurve } }
          y: panelTop
          x: nc.open ? win.width - width - nc.tk.ncMargin : win.width + nc.tk.px(24)
          opacity: nc.open ? 1 : 0
          Behavior on x { NumberAnimation { duration: nc.tk.panelDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: nc.tk.springCurve } }
          Behavior on opacity { NumberAnimation { duration: nc.tk.panelDuration * 0.7; easing.type: Easing.OutCubic } }

          // Swallow clicks inside the panel so they never count as "outside".
          MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: {} }

          RectangularShadow {
            anchors.fill: bg
            radius: bg.radius
            blur: nc.tk.px(30)
            offset.y: nc.tk.px(8)
            color: Qt.rgba(0, 0, 0, 0.35)
          }
          Rectangle {
            id: bg
            anchors.fill: parent
            radius: nc.tk.ncRadius
            // Dark vibrancy over the compositor blur (layer rule in
            // island-keys.lua); alpha stays above its ignore_alpha.
            color: Qt.rgba(0.11, 0.11, 0.12, 0.66)
            border.width: 1
            border.color: Qt.alpha(nc.tk.text, 0.12)
          }

          Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: nc.tk.px(12)
            contentHeight: column.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: column
              width: flick.width
              spacing: nc.tk.px(10)

              // --- header
              RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0
                  Text {
                    text: "Notification Center"
                    font.family: nc.tk.fontFamily
                    font.pixelSize: nc.tk.fontSize
                    font.weight: Font.DemiBold
                    color: nc.tk.text
                  }
                  Small { text: Qt.formatDate(nc.now, "dddd, MMMM d") }
                }
                Item { Layout.fillWidth: true }
                PillButton {
                  visible: nc.entries.length > 0
                  label: "Clear All"
                  onClicked: nc.clearAll()
                }
              }

              // --- widgets
              RowLayout {
                visible: nc.widgets
                Layout.fillWidth: true
                spacing: nc.tk.px(8)
                CalendarWidget { id: calWidget; Layout.fillWidth: true; Layout.preferredWidth: 1 }
                TodayWidget {
                  visible: !nc.calLarge
                  Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.preferredHeight: calWidget.implicitHeight
                }
              }

              // --- notifications
              Text {
                visible: nc.status && nc.status.silent
                Layout.fillWidth: true
                text: "󰽥  Focus is on — notifications are arriving silently"
                font.family: nc.tk.fontFamily
                font.pixelSize: nc.tk.fontSize - 5
                color: nc.tk.textDim
                horizontalAlignment: Text.AlignHCenter
              }
              Repeater {
                model: nc.groups
                delegate: Group {
                  required property var modelData
                  Layout.fillWidth: true
                  group: modelData
                }
              }
              Item {
                visible: nc.entries.length === 0
                Layout.fillWidth: true
                implicitHeight: nc.tk.px(120)
                Column {
                  anchors.centerIn: parent
                  spacing: nc.tk.px(6)
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰂚"
                    font.family: nc.tk.iconFamily
                    font.pixelSize: nc.tk.px(26)
                    color: nc.tk.textFaint
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No Notifications"
                    font.family: nc.tk.fontFamily
                    font.pixelSize: nc.tk.fontSize - 3
                    color: nc.tk.textFaint
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
