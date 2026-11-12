import QtQuick
import QtQuick.Layouts

// One control tile in the open island, after Panacea's quick-settings tile
// (ControlsView.qml `tile`): a round icon disc, the name in bold and the state
// muted under it. When the thing is on the whole tile fills with ink and the
// disc turns to the surface colour, so on/off reads from across the room.
IslandCard {
  id: tile

  property string glyph: ""
  property string value: ""       // title (network, device, level …)
  property string label: ""       // kept for callers; Panacea shows no caption
  property string detail: ""      // muted line under the title
  property bool attention: false
  property bool dimmed: false
  property bool on: false

  readonly property bool solid: on && !attention
  // Control Center: the module stays dark; only the icon disc lights up blue.
  readonly property color ink: tk.text

  interactive: true
  hot: mouse.containsMouse
  down: mouse.pressed
  radius: tk.cardRadius
  color: down ? tk.cardPressed : (hot ? tk.cardHover : tk.card)
  border.color: hot ? tk.cardPressed : tk.line

  signal activated()
  signal scrolled(int steps)

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: 9
    anchors.rightMargin: 10
    spacing: 8

    Rectangle {
      id: disc
      Layout.preferredWidth: 36
      Layout.preferredHeight: 36
      Layout.alignment: Qt.AlignVCenter
      radius: 18
      color: tile.solid ? tile.tk.accent : Qt.alpha(tile.tk.text, 0.14)
      Behavior on color { ColorAnimation { duration: 180 } }
      scale: mouse.pressed ? 0.9 : (mouse.containsMouse ? 1.07 : 1.0)
      Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }

      Text {
        anchors.centerIn: parent
        text: tile.glyph
        font.family: tile.tk.iconFamily
        font.pixelSize: tile.tk.iconSize
        color: tile.attention ? tile.tk.crit : (tile.dimmed ? tile.tk.textDim : tile.tk.text)
        Behavior on color { ColorAnimation { duration: 180 } }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: 1

      Text {
        Layout.fillWidth: true
        text: tile.value
        elide: Text.ElideRight
        textFormat: Text.PlainText
        font.family: tile.tk.fontFamily
        font.pixelSize: tile.tk.fontSize - 2
        font.weight: Font.DemiBold
        color: tile.attention ? tile.tk.crit : tile.ink
        Behavior on color { ColorAnimation { duration: 180 } }
      }
      Text {
        Layout.fillWidth: true
        visible: tile.detail !== ""
        text: tile.detail
        elide: Text.ElideRight
        textFormat: Text.PlainText
        font.family: tile.tk.fontFamily
        font.pixelSize: tile.tk.fontSize - 4
        color: tile.tk.textDim
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton
    onClicked: tile.activated()
    onWheel: function(wheel) {
      var steps = wheel.angleDelta.y > 0 ? 1 : (wheel.angleDelta.y < 0 ? -1 : 0)
      if (steps !== 0) tile.scrolled(steps)
    }
  }
}
