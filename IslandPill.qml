import QtQuick
import QtQuick.Effects

// The collapsed island's content, laid out like a live activity:
//
//   [art  Song ti… ▮▮▮]   Sat · Oct 31 · 8:05 PM   [● Discord  ● Firefox  󰂛]
//
// Left:  what is playing, kept together: cover art, a short title, waveform.
// Right: iOS-style privacy dots with
//        the app's name (orange = microphone, green = camera, blue = screen
//        share), a red REC while recording, and the quiet toggles (silent,
//        stay awake, night light) as dim glyphs.
//
// One row, only as wide as what is in it, so there is never an empty stretch
// on one side; the island stays centred on screen and grows both ways.
// `status` may be null (anshu.menu's ghost pill passes only `tk`); everything
// guards for that and falls back to the clock alone.
Item {
  id: pill

  required property var tk
  property var sys: null
  property var status: null

  readonly property var st: status
  readonly property var player: st ? st.player : null
  // What the player says right now. Browsers flip this constantly (a feed's
  // videos autoplay and stop as you scroll), so the pill does not follow it
  // directly: music shows once it has played for 1.5s, hides once it has been
  // stopped for 3s, and a new title waits 1s to be sure it stuck.
  readonly property bool rawPlaying: !!player && !!player.isPlaying && !!st && st.trackTitle !== ""
  readonly property string rawTitle: st ? st.trackTitle : ""
  readonly property string rawArt: player ? String(player.trackArtUrl || "") : ""

  property bool playing: false
  property string shownTitle: ""
  property string art: ""

  function settleTrack() { shownTitle = rawTitle; art = rawArt }
  onRawPlayingChanged: {
    if (rawPlaying) { hideTimer.stop(); if (!playing) showTimer.restart() }
    else { showTimer.stop(); if (playing) hideTimer.restart() }
  }
  onRawTitleChanged: if (playing && rawPlaying) titleTimer.restart()
  onRawArtChanged: if (playing && rawPlaying) titleTimer.restart()
  Timer { id: showTimer; interval: 1500; onTriggered: if (pill.rawPlaying) { pill.settleTrack(); pill.playing = true } }
  Timer { id: hideTimer; interval: 3000; onTriggered: if (!pill.rawPlaying) pill.playing = false }
  Timer { id: titleTimer; interval: 1000; onTriggered: if (pill.rawPlaying) pill.settleTrack() }
  Component.onCompleted: if (rawPlaying) { settleTrack(); playing = true }

  readonly property real gap: tk.px(12)
  // Anything to show right of the clock.
  signal openNotifications()
  readonly property int missed: st ? st.missedCount : 0
  readonly property bool hasRight: missed > 0 || !!st && (st.recording || st.micInUse || st.cameraInUse
    || st.screenShared || st.dictating || st.silent || st.stayAwake || st.nightLight)

  // Sized to what is there: no padding out one side to mirror the other.
  // The natural width uses the title at its cap; the title then shrinks to
  // whatever room the *live* width leaves, so while the island resizes (a new
  // track, a dot appearing) the row always fits and is never cut off.
  readonly property real titleCap: Math.min(titleText.implicitWidth, tk.px(110))
  readonly property real fixedWidth: clock.implicitWidth
    + (playing ? cover.width + wave.implicitWidth + leftSide.spacing * 2 + gap : 0)
    + (hasRight ? rightSide.implicitWidth + gap : 0)
  readonly property real titleRoom: Math.max(0, Math.min(titleCap, width - fixedWidth))
  implicitWidth: fixedWidth + (playing ? titleCap : 0)
  implicitHeight: tk.pillH

  readonly property bool hasPrivacy: !!st && (st.recording || st.micInUse || st.cameraInUse || st.screenShared)

  // The dots are shorthand ("Discord +1"); clicking them opens the
  // Notifications pane, whose In use section lists every app in full.
  MouseArea {
    visible: pill.hasPrivacy
    x: line.x + rightSide.x - pill.tk.px(6)
    width: (missedChip.visible ? missedChip.x : rightSide.width) + pill.tk.px(12)
    y: 0
    height: pill.height
    z: 1
    cursorShape: Qt.PointingHandCursor
    onClicked: pill.openNotifications()
  }

  // "Discord", or "Discord +1" when several apps share it.
  function appLabel(list) {
    if (!list || list.length === 0) return ""
    return list.length > 1 ? list[0] + " +" + (list.length - 1) : list[0]
  }

  // ---------------------------------------------------------- components
  component Dot: Rectangle {
    id: dot
    property bool pulse: false
    width: pill.tk.px(7)
    height: width
    radius: width / 2
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    SequentialAnimation on opacity {
      running: dot.pulse && dot.visible
      loops: Animation.Infinite
      onRunningChanged: if (!running) dot.opacity = 1
      NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0;  duration: 700; easing.type: Easing.InOutSine }
    }
  }

  // A coloured dot and the app's name, e.g. "● Discord".
  component Chip: Row {
    id: chip
    property color tint: "white"
    property string label: ""
    property bool pulse: false
    spacing: pill.tk.px(5)
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    Dot { color: chip.tint; pulse: chip.pulse }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, pill.tk.px(96))
      text: chip.label
      elide: Text.ElideRight
      textFormat: Text.PlainText
      font.family: pill.tk.fontFamily
      font.pixelSize: pill.tk.clockSize - 2
      font.weight: Font.Medium
      renderType: Text.NativeRendering
      color: Qt.tint(pill.tk.text, Qt.rgba(chip.tint.r, chip.tint.g, chip.tint.b, 0.35))
    }
  }

  component Glyph: Text {
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    font.family: pill.tk.iconFamily
    font.pixelSize: pill.tk.glyphSize - 1
    color: pill.tk.textFaint
  }

  Row {
    id: line
    anchors.centerIn: parent
    height: parent.height
    spacing: pill.gap

    // ---------------------------------------------------------------- left
    Row {
      id: leftSide
      anchors.verticalCenter: parent.verticalCenter
      spacing: pill.tk.px(8)
      visible: pill.playing

      Item {
        id: cover
        width: pill.tk.px(22)
        height: width
        anchors.verticalCenter: parent.verticalCenter

        Image {
          id: coverImg
          anchors.fill: parent
          source: pill.art
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          visible: false
        }
        Rectangle {
          id: coverMask
          anchors.fill: parent
          radius: pill.tk.px(6)
          visible: false
          layer.enabled: true
        }
        MultiEffect {
          anchors.fill: parent
          source: coverImg
          maskEnabled: true
          maskSource: coverMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
          visible: coverImg.status === Image.Ready
        }
        // No cover: a music note on a soft tile.
        Rectangle {
          anchors.fill: parent
          radius: pill.tk.px(6)
          color: pill.tk.card
          visible: coverImg.status !== Image.Ready
          Text {
            anchors.centerIn: parent
            text: "󰝚"
            font.family: pill.tk.iconFamily
            font.pixelSize: pill.tk.px(13)
            color: pill.tk.textDim
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        id: titleText
        width: pill.titleRoom
        text: pill.shownTitle
        elide: Text.ElideRight
        textFormat: Text.PlainText
        font.family: pill.tk.fontFamily
        font.pixelSize: pill.tk.clockSize - 1
        renderType: Text.NativeRendering
        color: pill.tk.textDim
      }

      // Waveform while music plays.
      Row {
        id: wave
        visible: pill.playing
        spacing: pill.tk.px(2)
        height: pill.tk.px(14)
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
          model: [430, 310, 520, 370]
          Rectangle {
            required property int modelData
            width: pill.tk.px(3)
            radius: width / 2
            anchors.bottom: parent.bottom
            color: pill.tk.green
            height: wave.height * 0.35
            SequentialAnimation on height {
              running: wave.visible && pill.rawPlaying
              loops: Animation.Infinite
              NumberAnimation { to: wave.height;        duration: modelData;       easing.type: Easing.InOutSine }
              NumberAnimation { to: wave.height * 0.3;  duration: modelData * 0.8; easing.type: Easing.InOutSine }
              NumberAnimation { to: wave.height * 0.7;  duration: modelData * 0.6; easing.type: Easing.InOutSine }
              NumberAnimation { to: wave.height * 0.35; duration: modelData * 0.7; easing.type: Easing.InOutSine }
            }
          }
        }
      }
    }

    IslandClock {
      id: clock
      anchors.verticalCenter: parent.verticalCenter
      tk: pill.tk
    }

    Row {
      id: rightSide
      visible: pill.hasRight
      anchors.verticalCenter: parent.verticalCenter
      spacing: pill.tk.px(10)

      Chip {
        visible: !!pill.st && pill.st.recording
        tint: pill.tk.crit
        label: "REC"
        pulse: true
      }
      Chip {
        visible: !!pill.st && pill.st.micInUse
        tint: pill.tk.orange
        label: pill.st ? pill.appLabel(pill.st.micApps) : ""
      }
      Chip {
        visible: !!pill.st && pill.st.cameraInUse
        tint: pill.tk.green
        label: pill.st ? pill.appLabel(pill.st.cameraApps) : ""
      }
      Chip {
        visible: !!pill.st && pill.st.screenShared
        tint: pill.tk.accent
        label: pill.st ? pill.appLabel(pill.st.screenApps) : ""
      }

      // Missed notifications (silenced, or arrived while the island was
      // open): a bell and the count. Click it to open the Notifications pane.
      Item {
        id: missedChip
        visible: pill.missed > 0
        width: missedRow.implicitWidth
        height: missedRow.implicitHeight
        anchors.verticalCenter: parent.verticalCenter
      Row {
        id: missedRow
        spacing: pill.tk.px(4)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰂚"
          font.family: pill.tk.iconFamily
          font.pixelSize: pill.tk.glyphSize - 1
          color: pill.tk.accent
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: pill.missed > 99 ? "99+" : String(pill.missed)
          font.family: pill.tk.fontFamily
          font.pixelSize: pill.tk.clockSize - 2
          font.weight: Font.DemiBold
          font.features: { "tnum": 1 }
          renderType: Text.NativeRendering
          color: pill.tk.text
        }
      }
        MouseArea {
          anchors.fill: parent
          anchors.margins: -pill.tk.px(8)
          cursorShape: Qt.PointingHandCursor
          onClicked: pill.openNotifications()
        }
      }

      Glyph {
        visible: !!pill.st && pill.st.dictating
        text: pill.st && pill.st.dictation === "transcribing" ? "󰔟" : "󰍬"
        color: pill.tk.accent
      }
      Glyph { visible: !!pill.st && pill.st.silent;     text: "󰂛" }
      Glyph { visible: !!pill.st && pill.st.stayAwake;  text: "󰅶" }
      Glyph { visible: !!pill.st && pill.st.nightLight; text: "󰔎" }
    }
  }
}
