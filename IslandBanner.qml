import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons

// The island carrying something momentary. Three layouts share one surface so
// a short state ("Silent"), a level ("Volume 40%") and a notification all read
// as the same object changing shape:
//
//   plain         glyph, headline, optional second line (system states)
//   osd           glyph, level track, readout   (volume, brightness, mic, ...)
//   notification  icon, app · time, summary, two lines of body, "+N" badge
//   charge        pulsing bolt, a battery that fills copper to the level, readout
//   screenshot    the capture as a thumbnail, with Copy · Edit · Delete
//
// Sized to its content; the pane grows only as far as the message needs.
Item {
  id: banner

  required property var tk
  property string mode: "plain"
  property string glyph: ""
  property string title: ""
  property string detail: ""
  property color tint: tk.text
  property bool revealed: false

  // osd
  property int progress: -1          // 0..100, or -1 for no track

  // notification
  property string app: ""
  property string image: ""          // file:// / image:// / absolute path
  property string appIcon: ""        // themed icon name or path
  property int count: 0              // toasts live, including this one
  property int group: 1              // of those, how many share this app + title
  property bool canReply: false      // a phone message that can be answered
  signal replyClicked()
  property int urgency: 1

  readonly property bool isOsd: mode === "osd" && progress >= 0
  readonly property bool isNotification: mode === "notification"
  readonly property bool isCharge: mode === "charge" && progress >= 0
  readonly property bool isShot: mode === "screenshot"
  // Now playing: cover art, title over artist, a waveform at the end.
  readonly property bool isMedia: mode === "media"
  readonly property bool hasCover: isMedia && image !== "" && coverImage.status === Image.Ready
  // Longest a plain banner's title/subtitle may run before "…". Now playing
  // is kept compact: live-recording titles can run to a hundred characters.
  readonly property real textCap: isMedia ? tk.px(280) : tk.bannerMaxWidth - tk.px(80)

  // Copy / Edit / Delete on the screenshot banner.
  signal shotAction(string action)
  // One optional button on a plain banner (e.g. "Stop" while recording).
  property string actionLabel: ""
  signal action()
  property bool shotCopied: false
  onIsShotChanged: shotCopied = false

  readonly property int preferredHeight: isNotification
    ? Math.max(tk.collapsedHeight, Math.ceil(noteBox.contentHeight) + tk.notificationPadY * 2)
    : isShot ? Math.ceil(shotRow.implicitHeight) + tk.bannerPadY * 2
    : isOsd || isCharge ? tk.bannerHeight
    : Math.max(tk.bannerHeight, Math.ceil(plainRow.implicitHeight) + tk.spaceMd * 2)

  implicitWidth: isNotification ? noteBox.contentWidth
    : isOsd ? osdRow.implicitWidth
    : isCharge ? chargeRow.implicitWidth
    : isShot ? shotRow.implicitWidth
    : plainRow.implicitWidth
  implicitHeight: isNotification ? Math.ceil(noteBox.contentHeight)
    : isShot ? Math.ceil(shotRow.implicitHeight)
    : isOsd || isCharge ? preferredHeight - tk.px(16)
    : Math.ceil(plainRow.implicitHeight)

  // Explicit in/out animations: a Behavior that reads `revealed` for its
  // timing races the change itself and sometimes faded out on the slow
  // fade-in timing, leaving the old content showing under the new.
  opacity: 0
  Component.onCompleted: opacity = revealed ? 1 : 0
  onRevealedChanged: {
    bannerIn.stop(); bannerOut.stop()
    bannerPause.duration = banner.tk.inDelay()
    if (revealed) bannerIn.start(); else bannerOut.start()
    if (revealed && isCharge) chargeFill.restart()
  }
  SequentialAnimation {
    id: bannerIn
    PauseAnimation { id: bannerPause }
    NumberAnimation {
      target: banner; property: "opacity"; to: 1
      duration: banner.tk.contentInDuration
      easing.type: Easing.BezierSpline; easing.bezierCurve: banner.tk.fadeCurve
    }
  }
  NumberAnimation {
    id: bannerOut
    target: banner; property: "opacity"; to: 0
    duration: banner.tk.contentOutDuration
    easing.type: Easing.BezierSpline; easing.bezierCurve: banner.tk.fadeCurve
  }

  // Content settles in from slightly above, like it dropped out of the notch.
  transform: Translate {
    y: banner.revealed ? 0 : -banner.tk.px(6)
    Behavior on y {
      NumberAnimation {
        duration: banner.tk.contentInDuration + banner.tk.contentInDelay
        easing.type: Easing.BezierSpline
        easing.bezierCurve: banner.tk.springCurve
      }
    }
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    var themed = Quickshell.iconPath(value, true)
    if (themed !== "") return themed
    // Apps that only ship a hicolor PNG (WhatsApp) are missed by the theme lookup.
    return "file:///usr/share/icons/hicolor/256x256/apps/" + value + ".png"
  }

  // ----------------------------------------------------------------- plain
  Row {
    id: plainRow
    anchors.centerIn: parent
    visible: !banner.isOsd && !banner.isNotification && !banner.isCharge && !banner.isShot
    spacing: banner.tk.spaceMd

    // Now playing: the cover, rounded like an app icon.
    Item {
      visible: banner.hasCover
      anchors.verticalCenter: parent.verticalCenter
      width: banner.tk.px(36)
      height: width
      Image {
        id: coverImage
        anchors.fill: parent
        source: banner.isMedia ? banner.image : ""
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
      }
      Rectangle {
        id: coverShape
        anchors.fill: parent
        radius: banner.tk.px(9)
        visible: false
        layer.enabled: true
      }
      MultiEffect {
        anchors.fill: parent
        source: coverImage
        maskEnabled: true
        maskSource: coverShape
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
    }

    // The glyph on a soft disc of its own colour, as iOS draws status icons.
    Rectangle {
      visible: !banner.hasCover
      anchors.verticalCenter: parent.verticalCenter
      width: banner.tk.px(30)
      height: width
      radius: width / 2
      color: Qt.alpha(banner.tint, 0.20)
      Behavior on color { ColorAnimation { duration: banner.tk.colorDuration } }
      Text {
        anchors.centerIn: parent
        text: banner.glyph
        font.family: banner.tk.iconFamily
        font.pixelSize: banner.tk.glyphSize
        color: banner.tint
        Behavior on color { ColorAnimation { duration: banner.tk.colorDuration } }
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: banner.tk.px(1)

      Text {
        text: banner.title
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        width: Math.min(implicitWidth, banner.textCap)
        font.family: banner.tk.fontFamily
        font.pixelSize: banner.tk.bannerSize
        font.weight: Font.DemiBold
        font.letterSpacing: 0.3
        renderType: Text.NativeRendering
        color: banner.tk.text
      }

      Text {
        visible: banner.detail !== ""
        text: banner.detail
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        width: Math.min(implicitWidth, banner.textCap)
        font.family: banner.tk.fontFamily
        font.pixelSize: banner.tk.tileLabelSize
        renderType: Text.NativeRendering
        color: banner.tk.textDim
      }
    }

    // Waveform for now playing, in the same green as the pill's.
    Row {
      id: bannerWave
      visible: banner.isMedia
      anchors.verticalCenter: parent.verticalCenter
      spacing: banner.tk.px(2)
      height: banner.tk.px(16)
      Repeater {
        model: [430, 310, 520, 370]
        Rectangle {
          required property int modelData
          width: banner.tk.px(3)
          radius: width / 2
          anchors.bottom: parent.bottom
          color: banner.tk.green
          height: bannerWave.height * 0.4
          SequentialAnimation on height {
            running: bannerWave.visible && banner.revealed
            loops: Animation.Infinite
            NumberAnimation { to: bannerWave.height;        duration: modelData;       easing.type: Easing.InOutSine }
            NumberAnimation { to: bannerWave.height * 0.3;  duration: modelData * 0.8; easing.type: Easing.InOutSine }
            NumberAnimation { to: bannerWave.height * 0.7;  duration: modelData * 0.6; easing.type: Easing.InOutSine }
            NumberAnimation { to: bannerWave.height * 0.4;  duration: modelData * 0.7; easing.type: Easing.InOutSine }
          }
        }
      }
    }

    Rectangle {
      id: plainAction
      visible: banner.actionLabel !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: plainActionText.implicitWidth + banner.tk.buttonPadX * 2
      height: banner.tk.buttonHeight
      radius: height / 2
      color: paMouse.pressed ? banner.tk.cardPressed : paMouse.containsMouse ? banner.tk.cardHover : banner.tk.card
      Behavior on color { ColorAnimation { duration: 120 } }
      Text {
        id: plainActionText
        anchors.centerIn: parent
        text: banner.actionLabel
        font.family: banner.tk.fontFamily
        font.pixelSize: banner.tk.tileValueSize
        font.weight: Font.Medium
        renderType: Text.NativeRendering
        color: banner.tk.text
      }
      MouseArea {
        id: paMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: banner.action()
      }
    }
  }

  // ---------------------------------------------------------------- charge
  // Plugging in: the battery fills from empty up to the real level, a soft
  // highlight sweeps across it once, and the bolt pulses.
  property real chargeShown: 0
  // (onRevealedChanged above also restarts the charge fill)
  onIsChargeChanged: if (revealed && isCharge) chargeFill.restart()

  SequentialAnimation {
    id: chargeFill
    PropertyAction { target: banner; property: "chargeShown"; value: 0 }
    PauseAnimation { duration: banner.tk.contentInDelay + 60 }
    NumberAnimation {
      target: banner; property: "chargeShown"
      to: Math.max(4, Math.min(100, banner.progress))
      duration: 900; easing.type: Easing.OutCubic
    }
    NumberAnimation { target: sweep; property: "x"; from: -sweep.width; to: battery.width; duration: 650; easing.type: Easing.InOutQuad }
  }

  Row {
    id: chargeRow
    anchors.centerIn: parent
    visible: banner.isCharge
    spacing: banner.tk.px(12)

    Text {
      id: bolt
      anchors.verticalCenter: parent.verticalCenter
      width: banner.tk.px(18)
      horizontalAlignment: Text.AlignHCenter
      text: "󱐋"
      font.family: banner.tk.fontFamily
      font.pixelSize: banner.tk.glyphSize + 2
      color: banner.tk.green
      SequentialAnimation on scale {
        running: banner.revealed && banner.isCharge
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 1.22; duration: 420; easing.type: Easing.OutQuad }
        NumberAnimation { from: 1.22; to: 1; duration: 520; easing.type: Easing.InOutQuad }
        PauseAnimation { duration: 500 }
      }
    }

    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: battery.width + cap.width + banner.tk.px(1)
      height: battery.height

      Rectangle {
        id: battery
        width: banner.tk.px(44)
        height: banner.tk.px(20)
        radius: banner.tk.px(5)
        color: "transparent"
        border.width: Math.max(1, banner.tk.px(1.5))
        border.color: banner.tk.textDim

        Item {
          anchors.fill: parent
          anchors.margins: banner.tk.px(3)
          clip: true

          Rectangle {
            height: parent.height
            radius: banner.tk.px(2.5)
            width: parent.width * banner.chargeShown / 100
            color: banner.tk.green
          }
          Rectangle {
            id: sweep
            x: -width
            width: parent.width * 0.45
            height: parent.height
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: "transparent" }
              GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.45) }
              GradientStop { position: 1; color: "transparent" }
            }
          }
        }
      }
      Rectangle {
        id: cap
        anchors.left: battery.right
        anchors.leftMargin: banner.tk.px(1)
        anchors.verticalCenter: battery.verticalCenter
        width: banner.tk.px(3)
        height: banner.tk.px(8)
        radius: width / 2
        color: banner.tk.textDim
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: banner.tk.px(1)
      Row {
        spacing: banner.tk.px(8)
        Text {
          text: banner.title
          font.family: banner.tk.fontFamily
          font.pixelSize: banner.tk.bannerSize
          font.weight: Font.DemiBold
          renderType: Text.NativeRendering
          color: banner.tk.text
        }
        // Fixed width so the island does not widen as the number counts up.
        Text {
          width: pctMetrics.advanceWidth
          horizontalAlignment: Text.AlignRight
          text: Math.round(banner.chargeShown) + "%"
          font.family: banner.tk.fontFamily
          font.pixelSize: banner.tk.bannerSize
          font.weight: Font.DemiBold
          font.features: { "tnum": 1 }
          renderType: Text.NativeRendering
          color: banner.tk.green
        }
        TextMetrics {
          id: pctMetrics
          text: "100%"
          font.family: banner.tk.fontFamily
          font.pixelSize: banner.tk.bannerSize
          font.weight: Font.DemiBold
        }
      }
      Text {
        visible: banner.detail !== "" && banner.detail.toLowerCase() !== banner.title.toLowerCase()
        text: banner.detail
        font.family: banner.tk.fontFamily
        font.pixelSize: banner.tk.tileLabelSize
        renderType: Text.NativeRendering
        color: banner.tk.textDim
      }
    }
  }

  // ------------------------------------------------------------ screenshot
  Row {
    id: shotRow
    anchors.centerIn: parent
    visible: banner.isShot
    spacing: banner.tk.spaceLg

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: banner.tk.shotThumbW
      height: banner.tk.shotThumbH
      radius: banner.tk.spaceMd
      color: banner.tk.card
      clip: true
      border.width: Math.max(1, banner.tk.px(1))
      border.color: Qt.alpha(banner.tk.text, 0.18)

      Image {
        anchors.fill: parent
        anchors.margins: parent.border.width
        source: banner.isShot ? banner.iconSource(banner.image) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize.width: width * 2
        sourceSize.height: height * 2
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: banner.tk.spaceMd

      Column {
        spacing: banner.tk.spaceXs / 2
        Text {
          text: "Screenshot"
          font.family: banner.tk.fontFamily
          font.pixelSize: banner.tk.bannerSize
          font.weight: Font.DemiBold
          renderType: Text.NativeRendering
          color: banner.tk.text
        }
        Text {
          text: banner.shotCopied ? "Copied again" : "On the clipboard  ·  saved to Pictures"
          font.family: banner.tk.fontFamily
          font.pixelSize: banner.tk.tileLabelSize
          renderType: Text.NativeRendering
          color: banner.shotCopied ? banner.tk.accent : banner.tk.textDim
        }
      }

      Row {
        spacing: banner.tk.spaceSm
        Repeater {
          model: [
            { act: "copy",   glyph: banner.shotCopied ? "󰄬" : "󰆏", label: "Copy" },
            { act: "edit",   glyph: "󰏫", label: "Edit" },
            { act: "delete", glyph: "󰆴", label: "Delete" }
          ]
          delegate: Rectangle {
            required property var modelData
            width: shotBtn.implicitWidth + banner.tk.buttonPadX * 2
            height: banner.tk.buttonHeight
            radius: height / 2
            color: sbm.pressed ? banner.tk.cardPressed : sbm.containsMouse ? banner.tk.cardHover : banner.tk.card
            Behavior on color { ColorAnimation { duration: 120 } }
            Row {
              id: shotBtn
              anchors.centerIn: parent
              spacing: banner.tk.spaceXs + banner.tk.px(2)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.glyph
                font.family: banner.tk.fontFamily
                font.pixelSize: banner.tk.tileLabelSize + 1
                color: modelData.act === "delete" && sbm.containsMouse ? banner.tk.danger : banner.tk.accent
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                font.family: banner.tk.fontFamily
                font.pixelSize: banner.tk.tileValueSize
                font.weight: Font.Medium
                color: banner.tk.text
              }
            }
            MouseArea {
              id: sbm
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (modelData.act === "copy") banner.shotCopied = true
                banner.shotAction(modelData.act)
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------------- osd
  Row {
    id: osdRow
    anchors.centerIn: parent
    visible: banner.isOsd
    spacing: banner.tk.px(12)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: banner.tk.px(20)
      horizontalAlignment: Text.AlignHCenter
      text: banner.glyph
      font.family: banner.tk.fontFamily
      font.pixelSize: banner.tk.glyphSize
      color: banner.tint
    }

    Rectangle {
      id: track
      anchors.verticalCenter: parent.verticalCenter
      width: banner.tk.osdTrackWidth
      height: banner.tk.px(6)
      radius: height / 2
      color: banner.tk.meterTrack

      Rectangle {
        height: parent.height
        radius: parent.radius
        color: banner.tk.text
        width: parent.width * Math.max(0, Math.min(100, banner.progress)) / 100
        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: banner.tk.px(34)
      horizontalAlignment: Text.AlignRight
      text: banner.title
      font.family: banner.tk.fontFamily
      font.pixelSize: banner.tk.statSize
      font.weight: Font.DemiBold
      font.features: { "tnum": 1 }
      renderType: Text.NativeRendering
      color: banner.tk.text
    }
  }

  // ---------------------------------------------------------- notification
  // [icon]  Title  ·  App · now                       [+N]
  //         The whole message, wrapped, nothing cut off.
  Item {
    id: noteBox
    anchors.fill: parent
    visible: banner.isNotification

    readonly property string iconUrl: banner.image !== "" ? banner.iconSource(banner.image)
                                                          : banner.iconSource(banner.appIcon)
    readonly property int iconSize: banner.tk.notificationIcon
    readonly property bool isWhatsApp: /whatsapp/i.test(banner.app)
    readonly property int gap: banner.tk.px(9)
    readonly property real badgeSpace: noteSide.visible ? noteSide.implicitWidth + banner.tk.px(12) : 0
    // The text column's width: as wide as the longest line wants, within limits.
    readonly property real textMax: banner.tk.notificationWidth - banner.tk.notificationPadX * 2
                                    - iconSize - gap - badgeSpace
    readonly property real textMin: banner.tk.notificationMinWidth - banner.tk.notificationPadX * 2
                                    - iconSize - gap - badgeSpace
    readonly property real textWidth: Math.ceil(Math.max(textMin, Math.min(textMax,
      Math.max(headMetrics.width + banner.tk.px(2), bodyMetrics.width + banner.tk.px(2)))))
    readonly property real contentWidth: iconSize + gap + textWidth + badgeSpace
    readonly property real contentHeight: Math.max(iconSize, noteColumn.implicitHeight)

    TextMetrics {
      id: headMetrics
      font: noteTitle.font
      text: noteTitle.text + "   " + noteMeta.text
    }
    TextMetrics {
      id: bodyMetrics
      font: noteBody.font
      text: banner.detail
    }

    Rectangle {
      id: iconWell
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.topMargin: noteColumn.implicitHeight > noteBox.iconSize * 1.6
        ? banner.tk.px(1) : (noteBox.contentHeight - noteBox.iconSize) / 2
      width: noteBox.iconSize
      height: noteBox.iconSize
      radius: banner.tk.px(9)
      color: banner.tk.card
      clip: true

      Image {
        id: noteIcon
        anchors.fill: parent
        anchors.margins: banner.image !== "" ? 0 : banner.tk.px(4)
        source: noteBox.iconUrl
        sourceSize.width: noteBox.iconSize * 2
        sourceSize.height: noteBox.iconSize * 2
        fillMode: banner.image !== "" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: noteIcon.status !== Image.Ready
        text: banner.glyph !== "" ? banner.glyph : (noteBox.isWhatsApp ? "\uf232" : "󰂚")
        font.family: banner.tk.fontFamily
        font.pixelSize: banner.tk.glyphSize + 6
        color: banner.urgency === 2 ? banner.tk.danger : banner.tk.text
      }
    }

    Column {
      id: noteColumn
      x: noteBox.iconSize + noteBox.gap
      y: (noteBox.contentHeight - implicitHeight) / 2
      width: noteBox.textWidth
      spacing: 0

      Row {
        width: parent.width
        spacing: banner.tk.px(7)

        Text {
          id: noteTitle
          width: Math.min(implicitWidth, parent.width - noteMeta.implicitWidth - parent.spacing)
          anchors.baseline: noteMeta.baseline
          text: banner.title
          textFormat: Text.PlainText
          elide: Text.ElideRight
          maximumLineCount: 1
          font.family: banner.tk.fontFamily
          font.pixelSize: banner.tk.notificationTitleSize
          font.weight: Font.DemiBold
          renderType: Text.NativeRendering
          color: banner.urgency === 2 ? banner.tk.danger : banner.tk.text
        }

        Text {
          id: noteMeta
          readonly property string appName: noteBox.isWhatsApp ? "WhatsApp" : banner.app
          text: (appName !== "" && appName !== banner.title ? appName + " · " : "")
            + (banner.group > 1 ? banner.group + " new" : "now")
          textFormat: Text.PlainText
          font.family: banner.tk.fontFamily
          font.pixelSize: banner.tk.notificationMetaSize
          font.letterSpacing: 0.3
          renderType: Text.NativeRendering
          color: banner.tk.textFaint
        }
      }

      Text {
        id: noteBody
        width: parent.width
        visible: banner.detail !== ""
        text: banner.detail
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        maximumLineCount: banner.tk.notificationBodyLines
        lineHeight: 1.05
        font.family: banner.tk.fontFamily
        font.pixelSize: banner.tk.notificationBodySize
        renderType: Text.NativeRendering
        color: banner.tk.textDim
      }
    }

    // Reply (phone messages), and how many more are waiting behind this one.
    Row {
      id: noteSide
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: banner.tk.px(8)
      visible: banner.canReply || banner.count > Math.max(1, banner.group)

    Rectangle {
      id: replyButton
      anchors.verticalCenter: parent.verticalCenter
      visible: banner.canReply
      width: replyText.implicitWidth + banner.tk.buttonPadX * 2
      height: banner.tk.buttonHeight
      radius: height / 2
      color: replyMouse.pressed ? banner.tk.cardPressed : replyMouse.containsMouse ? banner.tk.cardHover : banner.tk.card
      Behavior on color { ColorAnimation { duration: 120 } }
      Text {
        id: replyText
        anchors.centerIn: parent
        text: "󰑚  Reply"
        font.family: banner.tk.fontFamily
        font.pixelSize: banner.tk.tileValueSize
        font.weight: Font.Medium
        renderType: Text.NativeRendering
        color: banner.tk.text
      }
      MouseArea {
        id: replyMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: banner.replyClicked()
      }
    }

    Rectangle {
      id: badge
      anchors.verticalCenter: parent.verticalCenter
      visible: banner.count > Math.max(1, banner.group)
      height: banner.tk.px(18)
      width: Math.max(height, badgeText.implicitWidth + banner.tk.px(10))
      radius: height / 2
      color: banner.tk.card

      Text {
        id: badgeText
        anchors.centerIn: parent
        text: "+" + (banner.count - Math.max(1, banner.group))
        font.family: banner.tk.fontFamily
        font.pixelSize: banner.tk.cardTitleSize
        font.weight: Font.DemiBold
        color: banner.tk.textDim
      }
    }
    }
  }
}
