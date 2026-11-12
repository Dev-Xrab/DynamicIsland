import QtQuick
import QtQuick.Layouts

// The expanded island's first page: the current activity (Now Playing) and
// the two doors out of the island — Control Center (grows the island) and
// Notification Center (the right-side panel).
//
//   ┌ Now Playing ─────────────────────────────┬ Control Center ┐
//   │ ▣ Title · Artist         ⏮  ⏯  ⏭         │ Ethernet · 51% │
//   │ ▁▃▅▇▅▃▁▃▅▇  0:42 ──────────── 3:10       ├ Notifications ─┤
//   │                                          │ 2 new          │
//   └──────────────────────────────────────────┴────────────────┘
Item {
  id: home

  required property var tk
  required property var sys
  property var status: null
  property bool revealed: false

  signal openControlCenter()
  signal openNotificationCenter()

  component Door: IslandCard {
    id: door
    property string glyph: ""
    property string name: ""
    property string caption: ""
    property bool badge: false
    signal activated()
    tk: home.tk
    revealed: home.revealed
    interactive: true
    hot: doorMouse.containsMouse
    down: doorMouse.pressed
    Layout.fillWidth: true
    Layout.fillHeight: true

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: home.tk.px(12)
      anchors.rightMargin: home.tk.px(10)
      spacing: home.tk.px(10)
      Rectangle {
        Layout.preferredWidth: home.tk.px(32)
        Layout.preferredHeight: home.tk.px(32)
        radius: width / 2
        color: door.badge ? home.tk.accent : Qt.alpha(home.tk.text, doorMouse.containsMouse ? 0.22 : 0.16)
        Behavior on color { ColorAnimation { duration: home.tk.colorDuration } }
        scale: doorMouse.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: home.tk.pressDuration; easing.type: Easing.OutBack } }
        Text {
          anchors.centerIn: parent
          text: door.glyph
          font.family: home.tk.iconFamily
          font.pixelSize: home.tk.iconSize - 2
          color: home.tk.text
        }
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 1
        Text {
          Layout.fillWidth: true
          text: door.name
          elide: Text.ElideRight
          font.family: home.tk.fontFamily
          font.pixelSize: home.tk.fontSize - 3
          font.weight: Font.DemiBold
          color: home.tk.text
        }
        Text {
          Layout.fillWidth: true
          text: door.caption
          elide: Text.ElideRight
          textFormat: Text.PlainText
          font.family: home.tk.fontFamily
          font.pixelSize: home.tk.fontSize - 5
          color: home.tk.textDim
        }
      }
      Text {
        text: "›"
        font.family: home.tk.fontFamily
        font.pixelSize: home.tk.fontSize
        color: doorMouse.containsMouse ? home.tk.text : home.tk.textFaint
        Behavior on color { ColorAnimation { duration: home.tk.hoverDuration } }
      }
    }
    MouseArea {
      id: doorMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: door.activated()
    }
  }

  RowLayout {
    anchors.fill: parent
    spacing: home.tk.cardGap

    IslandMedia {
      tk: home.tk
      index: 0
      revealed: home.revealed
      active: home.revealed
      Layout.fillWidth: true
      Layout.fillHeight: true
    }

    ColumnLayout {
      Layout.preferredWidth: home.tk.px(196)
      Layout.maximumWidth: home.tk.px(196)
      Layout.fillWidth: false
      Layout.fillHeight: true
      spacing: home.tk.cardGap

      Door {
        index: 1
        glyph: "󰒓"
        name: "Control Center"
        caption: home.sys.netValue + "  ·  " + home.sys.audioValue
        onActivated: home.openControlCenter()
      }
      Door {
        index: 2
        readonly property int missed: home.status ? home.status.missedCount : 0
        readonly property int total: home.status ? home.status.notifHistory.length : 0
        glyph: home.status && home.status.silent ? "󰂛" : "󰂚"
        name: "Notifications"
        badge: missed > 0
        caption: home.status && home.status.silent ? "Focus on" + (missed > 0 ? "  ·  " + missed + " new" : "")
          : missed > 0 ? missed + " new"
          : total > 0 ? total + " in history" : "None"
        onActivated: home.openNotificationCenter()
      }
    }
  }
}
