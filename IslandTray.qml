import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// The open island.
//
//   ┌ strip: weather ─────────────────────────────────────────┐
//   │ page 0: IslandControlCenter (macOS Control Center layout) │
//   └──────────────────────────────────────────────────────────┘
//   page 0: IslandHome — Now Playing + Control Center / Notifications
//   page 1 (Tab): IslandExtras stats — Claude Code · system
//   (the old quick-toggle page lives in Control Center now)
//
// The clock is deliberately absent: opening the island replaces the time
// rather than demoting it. The strip carries weather and nothing else — the
// per-device glyphs that used to sit on the right are the cards' job, and
// repeating them there only made the strip noisy.
//
// Clicking a card swaps this whole surface for that card's detail view, in
// place. Nothing about the island ever opens outside the island.
Item {
  id: tray

  required property var tk
  required property var sys
  property var status: null
  property bool revealed: false
  // Which page is showing: 0 = overview (now playing and the four device
  // cards), 1 = Claude Code, system load and quick toggles. Tab / Shift+Tab
  // (the island submap) or the dots in the strip switch it.
  property int page: 0
  readonly property int pageCount: 2

  signal openDetail(string kind)
  signal nudgeVolume(int steps)
  signal closeRequested()
  signal pageRequested(int page)
  signal openApp(string kind)
  signal openNotificationCenter()

  // Everything fades as one group; the cards stagger within it.
  visible: opacity > 0
  // Explicit in/out animations: a Behavior that reads `revealed` for its
  // timing races the change itself and sometimes faded out on the slow
  // fade-in timing, leaving the old content showing under the new.
  opacity: 0
  Component.onCompleted: opacity = revealed ? 1 : 0
  onRevealedChanged: {
    trayIn.stop(); trayOut.stop()
    trayPause.duration = tray.tk.inDelay()
    if (revealed) trayIn.start(); else trayOut.start()
  }
  SequentialAnimation {
    id: trayIn
    PauseAnimation { id: trayPause }
    NumberAnimation {
      target: tray; property: "opacity"; to: 1
      duration: tray.tk.contentInDuration
      easing.type: Easing.BezierSpline; easing.bezierCurve: tray.tk.fadeCurve
    }
  }
  NumberAnimation {
    id: trayOut
    target: tray; property: "opacity"; to: 0
    duration: tray.tk.contentOutDuration
    easing.type: Easing.BezierSpline; easing.bezierCurve: tray.tk.fadeCurve
  }

  // ---------------------------------------------------------- status strip
  Row {
    id: strip
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.leftMargin: tray.tk.px(4)
    height: tray.tk.px(20)
    spacing: tray.tk.px(7)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: tray.sys.weatherGlyph
      font.family: tray.tk.fontFamily
      font.pixelSize: tray.tk.glyphSize
      color: tray.tk.textDim
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: tray.sys.weatherValue
      font.family: tray.tk.fontFamily
      font.pixelSize: tray.tk.statSize
      font.weight: Font.DemiBold
      renderType: Text.NativeRendering
      color: tray.tk.text
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: tray.sys.hasWeather
        ? tray.sys.weather.condition + (tray.sys.weatherPlace !== "" ? "  ·  " + tray.sys.weatherPlace : "")
        : "Weather unavailable"
      font.family: tray.tk.fontFamily
      font.pixelSize: tray.tk.tileLabelSize
      color: tray.tk.textFaint
    }
  }

  // ------------------------------------------------------------ app pills
  // The strip's right edge: WhatsApp always, and Shan Shui only while the
  // painted wallpaper is on. With the static wallpaper the strip is exactly
  // the plain one. State comes from zed.shanshui's own state file, re-read
  // only while the island is open.
  // The WhatsApp pill only appears when the OmaWhatsApp plugin is installed.
  property bool hasWhatsapp: false
  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
          + "/omarchy/plugins/io.github.moizibnyousaf.omawhatsapp/manifest.json"
    printErrors: false
    onLoaded: tray.hasWhatsapp = true
    onLoadFailed: tray.hasWhatsapp = false
  }

  property bool shanshuiOn: false
  property bool shanshuiPaused: false

  FileView {
    id: shanshuiState
    path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/zed.shanshui/estado.json"
    printErrors: false
    onLoaded: {
      try {
        var s = JSON.parse(text())
        tray.shanshuiOn = s.ativo !== false
        tray.shanshuiPaused = !!s.pausado
      } catch (e) { tray.shanshuiOn = false }
    }
    onLoadFailed: tray.shanshuiOn = false
  }
  Timer {
    interval: 1500
    running: tray.revealed
    repeat: true
    triggeredOnStart: true
    onTriggered: shanshuiState.reload()
  }
  function shanshui(cmd) {
    Quickshell.execDetached(["omarchy-shell", "-q", "shanshui", cmd])
    shanshuiRefresh.restart()
  }
  Timer { id: shanshuiRefresh; interval: 250; onTriggered: shanshuiState.reload() }

  IslandCard {
    id: shanshuiPill
    tk: tray.tk
    index: 0
    revealed: tray.revealed
    interactive: true
    hot: shanshuiMouse.containsMouse
    down: shanshuiMouse.pressed
    visible: tray.shanshuiOn
    anchors.right: whatsapp.visible ? whatsapp.left : parent.right
    anchors.rightMargin: tray.tk.px(6)
    anchors.verticalCenter: strip.verticalCenter
    height: strip.height
    width: shanshuiRow.implicitWidth + tray.tk.px(16)

    Row {
      id: shanshuiRow
      anchors.centerIn: parent
      spacing: tray.tk.px(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "山"
        font.pixelSize: tray.tk.glyphSize
        color: tray.shanshuiPaused ? tray.tk.textFaint : tray.tk.textDim
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        // Left click: settings (in-island). Middle: pause / resume. Right:
        // back to the static wallpaper (the pill then disappears).
        text: shanshuiMouse.containsMouse ? "SETTINGS"
                                          : (tray.shanshuiPaused ? "PAUSED" : "PAINTING")
        font.family: tray.tk.fontFamily
        font.pixelSize: tray.tk.cardTitleSize
        font.letterSpacing: 0.8
        color: tray.tk.textFaint
      }
    }

    MouseArea {
      id: shanshuiMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) tray.shanshui("desligar")
        else if (mouse.button === Qt.MiddleButton) tray.shanshui(tray.shanshuiPaused ? "continuar" : "pausar")
        else tray.openDetail("shanshui")
      }
    }
  }

  // An app launcher, not a status glyph. The island closes as the app opens.
  IslandCard {
    id: whatsapp
    tk: tray.tk
    index: 0
    visible: tray.hasWhatsapp
    revealed: tray.revealed
    interactive: true
    hot: whatsappMouse.containsMouse
    down: whatsappMouse.pressed
    anchors.right: parent.right
    anchors.verticalCenter: strip.verticalCenter
    height: strip.height
    width: whatsappRow.implicitWidth + tray.tk.px(16)

    Row {
      id: whatsappRow
      anchors.centerIn: parent
      spacing: tray.tk.px(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        font.family: tray.tk.fontFamily
        font.pixelSize: tray.tk.glyphSize
        color: tray.tk.textDim
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "WhatsApp"
        font.family: tray.tk.fontFamily
        font.pixelSize: tray.tk.cardTitleSize
        font.letterSpacing: 0.8
        color: tray.tk.textFaint
      }
    }

    MouseArea {
      id: whatsappMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tray.openApp("whatsapp")
    }
  }

  // ----------------------------------------------------------------- pages
  // Both pages are laid out once at full size, side by side, and slid under a
  // clip; switching never re-runs a layout mid-animation.
  Item {
    id: pager
    anchors.top: strip.bottom
    anchors.topMargin: tray.tk.px(8)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true

    readonly property real stride: width + tray.tk.cardGap * 2

    Item {
      id: page0
      width: pager.width
      height: pager.height
      x: (0 - tray.page) * pager.stride
      Behavior on x {
        NumberAnimation { duration: tray.tk.expandDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: tray.tk.springCurve }
      }

      // Now Playing, and the doors to Control Center / Notification Center.
      IslandHome {
        anchors.fill: parent
        tk: tray.tk
        sys: tray.sys
        status: tray.status
        revealed: tray.revealed && tray.page === 0
        onOpenControlCenter: tray.openDetail("controlcenter")
        onOpenNotificationCenter: tray.openNotificationCenter()
      }
    }

    Item {
      id: page1
      width: pager.width
      height: pager.height
      x: (1 - tray.page) * pager.stride
      Behavior on x {
        NumberAnimation { duration: tray.tk.expandDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: tray.tk.springCurve }
      }

      IslandExtras {
        anchors.fill: parent
        tk: tray.tk
        status: tray.status
        sys: tray.sys
        mode: "stats"
        revealed: tray.revealed && tray.page === 1
        onCloseRequested: tray.closeRequested()
        onOpenDetail: function(kind) { tray.openDetail(kind) }
      }
    }
  }

  // Page dots, centred in the strip. Click one to jump to it. Each dot sits in
  // its own 22x24 target (the dot itself is only 6px), touching its
  // neighbours so there is no dead gap and no overlap between them.
  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: strip.verticalCenter
    spacing: 0

    Repeater {
      model: tray.pageCount
      delegate: Item {
        id: dotCell
        required property int index
        readonly property bool current: index === tray.page
        width: Math.max(tray.tk.px(22), dot.width + tray.tk.px(10))
        height: tray.tk.px(24)

        Rectangle {
          id: dot
          anchors.centerIn: parent
          width: dotCell.current ? tray.tk.px(18) : tray.tk.px(6)
          height: tray.tk.px(6)
          radius: height / 2
          color: dotCell.current ? tray.tk.text : (dotMouse.containsMouse ? tray.tk.textDim : tray.tk.textFaint)
          scale: dotMouse.containsMouse && !dotCell.current ? 1.35 : 1
          Behavior on width { NumberAnimation { duration: tray.tk.radiusDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: tray.tk.springCurve } }
          Behavior on color { ColorAnimation { duration: tray.tk.colorDuration } }
          Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        MouseArea {
          id: dotMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: tray.pageRequested(dotCell.index)
        }
      }
    }
  }
}
