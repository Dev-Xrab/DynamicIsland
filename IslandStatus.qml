import QtQuick
import Quickshell
import Quickshell.Io
import "IslandOsdModel.js" as OsdModel

// The island's state machine for everything that is not the clock.
//
// Two independent channels:
//
//   chips   — ongoing states (recording, dictation, silent, stay awake, night
//             light, playing media). They ride alongside the clock as small
//             glyphs and stay for as long as the state is true.
//   banner  — a momentary takeover. The island morphs into a message for a
//             few seconds, then hands itself back to the clock.
//
// Only states this machine can actually observe are represented. Every source
// is either a reactive shell service, a streaming process, or a file watch;
// the single exception is screen recording, noted at its declaration.
Item {
  id: status
  visible: false

  required property var tk
  // The bar's plugin shell API. Bar-kind plugins are handed narrow proxies for
  // the first-party services, which is where the toggles' real state lives.
  property var shell: null
  property var sys: null
  // ~/.config/omarchy/island.json, handed down by the bar. Keys read here:
  //   silentAllow  apps (or phone apps, e.g. "Messenger") that still pop up
  //                in Silent mode; default ["KDE Connect"]
  //   phoneStatus  phone connect / battery pops (KDE Connect), default on
  //   unityStatus  Unity compile / build progress, default on
  property var settings: ({})
  readonly property var silentAllow: Array.isArray(settings.silentAllow) ? settings.silentAllow : ["KDE Connect"]
  readonly property bool phoneStatus: settings.phoneStatus !== false
  readonly property bool unityStatus: settings.unityStatus !== false
  // IslandFocus, so a DND flip made by a focus phase change stays quiet.
  property var focusTimer: null
  function focusQuiet() { return !!focusTimer && Date.now() - focusTimer.flippedAt < 4000 }

  readonly property var notifications: shell ? shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property var idle:          shell ? shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property var nightlight:    shell ? shell.firstPartyServiceFor("omarchy.nightlight") : null
  readonly property var media:         shell ? shell.firstPartyServiceFor("omarchy.media") : null

  readonly property bool silent:     notifications ? notifications.doNotDisturb : false
  readonly property bool stayAwake:  idle ? idle.stayAwake : false
  readonly property bool nightLight: nightlight ? nightlight.enabled : false
  // The bar is handed a narrow proxy of each first-party service, not the
  // service itself: for media that is `activePlayer` and nothing else, so the
  // track fields are read off the player rather than the service.
  readonly property var player: media ? media.activePlayer : null
  readonly property bool playing: !!player
  readonly property string trackTitle:  player ? String(player.trackTitle || "") : ""
  readonly property string trackArtist: player ? String(player.trackArtist || "") : ""

  // gpu-screen-recorder publishes no signal and writes its marker file into
  // /tmp, where a watch on a not-yet-existing path is unreliable. A four
  // second probe is the honest cost of knowing; nothing else here polls.
  property bool recording: false

  // omarchy-voxtype-status streams a line per state change, so dictation is
  // genuinely event-driven. Without voxtype installed the process never emits
  // and the state stays idle.
  property string dictation: "idle"
  readonly property bool dictating: dictation === "recording" || dictation === "transcribing"

  // Which apps hold the microphone, the camera or a screen share, read from
  // PipeWire by island-privacy.sh (about 20ms a run, every 2.5s). Shown in the
  // collapsed pill as iOS-style dots: orange mic, green camera, blue screen.
  property var micApps: []
  property var cameraApps: []
  property var screenApps: []
  readonly property bool micInUse: micApps.length > 0
  readonly property bool cameraInUse: cameraApps.length > 0
  readonly property bool screenShared: screenApps.length > 0

  readonly property string privacyScript:
    Qt.resolvedUrl("island-privacy.sh").toString().replace("file://", "")
  function applyPrivacy(raw) {
    try {
      var d = JSON.parse(String(raw || "{}"))
      function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
      if (!same(d.mic || [], micApps)) micApps = d.mic || []
      if (!same(d.camera || [], cameraApps)) cameraApps = d.camera || []
      if (!same(d.screen || [], screenApps)) screenApps = d.screen || []
      // Full detail per use, each stamped with when it was first seen.
      var uses = d.uses || [], seen = {}, out = []
      for (var i = 0; i < uses.length; i++) {
        var u = uses[i]
        var key = [u.kind, u.app, u.pid, u.device].join("|")
        seen[key] = privacySince[key] || Date.now()
        out.push(Object.assign({ since: seen[key] }, u))
      }
      privacySince = seen
      if (!same(out, privacyUses)) privacyUses = out
    } catch (e) { /* keep the last reading */ }
  }
  // [{kind, app, bin, pid, device, media, since}] — read by the Notifications
  // pane's In use section.
  property var privacyUses: []
  property var privacySince: ({})
  Process {
    id: privacyProbe
    command: [status.privacyScript]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: status.applyPrivacy(text) }
  }
  Timer {
    interval: 2500
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!privacyProbe.running) privacyProbe.running = true
  }

  // ------------------------------------------------------------------ chips
  // Ordered by how much the user needs to know it right now.
  readonly property var chips: {
    var out = []
    if (recording)  out.push({ key: "recording",  glyph: "󰻂", tint: tk.crit })
    if (dictating)  out.push({ key: "dictation",  glyph: dictation === "transcribing" ? "󰔟" : "󰍬", tint: tk.accent })
    if (playing)    out.push({ key: "media",      glyph: "󰝚", tint: tk.textDim })
    if (silent)     out.push({ key: "silent",     glyph: "󰂛", tint: tk.textDim })
    if (stayAwake)  out.push({ key: "stayAwake",  glyph: "󰅶", tint: tk.textDim })
    if (nightLight) out.push({ key: "nightLight", glyph: "󰔎", tint: tk.textDim })
    return out
  }

  // The states that also tint the glass. Only those that warrant colouring the
  // whole surface qualify — a chip is enough for the rest.
  readonly property string surfaceState: recording ? "recording" : (dictating ? "dictation" : "")
  readonly property color surfaceTint: surfaceState === "recording" ? tk.crit : tk.accent
  readonly property real surfaceTintStrength: surfaceState === "recording" ? 0.14
    : surfaceState === "dictation" ? 0.13 : 0.0

  // ----------------------------------------------------------------- banner
  property string bannerKind: ""
  property string bannerGlyph: ""
  property string bannerTitle: ""
  property string bannerDetail: ""
  property color bannerTint: tk.text
  // "plain" | "osd" | "notification" — which IslandBanner layout to use.
  property string bannerMode: "plain"
  property int bannerProgress: -1
  property string bannerApp: ""
  property string bannerImage: ""
  property string bannerAppIcon: ""
  property int bannerUrgency: 1
  readonly property bool bannerActive: bannerKind !== ""

  // The newest live toast (its state-file JSON) and how many are live. The
  // notification banner is held for exactly as long as a toast is live, and
  // comes back after anything momentary (a volume change) interrupts it.
  property var liveNotification: null
  property int notificationCount: 0
  readonly property string liveNotificationId:
    liveNotification ? String(liveNotification.originalId) : ""

  // Manual interaction always outranks an automatic one: while the user holds
  // the island open, banners are dropped rather than queued, so nothing pops
  // up behind their back and nothing arrives stale afterwards.
  property bool suppressed: false

  // Nothing announces itself during startup, when every watcher reports its
  // initial value at once.
  property bool armed: false

  signal bannerShown(string kind)

  function show(kind, glyph, title, detail, tint, ms) {
    if (!armed || suppressed || !tk.autoExpandOnEvents) return
    present(kind, "plain", glyph, title, detail, tint, ms)
  }

  function present(kind, mode, glyph, title, detail, tint, ms) {
    bannerKind = kind
    bannerMode = mode
    bannerGlyph = glyph
    bannerTitle = title
    bannerDetail = detail || ""
    bannerTint = tint || tk.text
    if (mode !== "osd" && mode !== "charge") bannerProgress = -1
    // ms === 0 holds until something ends it (a live notification).
    if (ms === 0) holdTimer.stop()
    else {
      holdTimer.interval = ms || tk.bannerDuration
      holdTimer.restart()
    }
    bannerShown(kind)
  }

  // A momentary banner ending hands the island back to a still-live
  // notification instead of the clock.
  function bannerEnded() {
    bannerKind = ""
    lingering = false
    pausedHold = false
    if (liveNotification && notificationCount > 0 && !suppressed) presentNotification()
  }

  // `omarchy-shell omarchy.bar island demo:charge` — preview the plug-in banner.
  // `omarchy-shell` ... island demo:shot — the screenshot banner with the
  // plugin's preview image. No file behind it, so Copy/Edit/Delete do nothing.
  function demoShot() {
    shotPath = ""
    bannerImage = Qt.resolvedUrl("preview.png").toString()
    present("notification", "screenshot", "", "Screenshot", "", tk.text, 6000)
  }

  // ------------------------------------------------------- bluetooth pops
  property var btKnown: ({})      // address -> { name, glyph } last seen connected
  property bool btPrimed: false   // the first reading is the starting point, not news
  function btChanged() {
    var now = {}, list = sys ? sys.btConnected : []
    for (var i = 0; i < list.length; i++) {
      var d = list[i]
      now[String(d.address)] = { name: String(d.deviceName || d.name || "Device"),
                                 glyph: sys.btDeviceGlyph(d), dev: d }
    }
    if (btPrimed) {
      for (var a in now) if (!btKnown[a]) { btPop(now[a], true); break }
      for (var b in btKnown) if (!now[b]) { btPop(btKnown[b], false); break }
    }
    btKnown = now
    btPrimed = true
  }
  function btPop(entry, connected) {
    var level = connected && entry.dev && entry.dev.batteryAvailable
      ? Math.round(Number(entry.dev.battery) * 100) : -1
    show("bluetooth", entry.glyph, entry.name,
         connected ? (level >= 0 ? "Connected  ·  " + level + "%" : "Connected") : "Disconnected",
         connected ? tk.accent : tk.textDim)
  }
  // island demo:bt — the connect pop for the first connected device.
  function demoBt() {
    var list = sys ? sys.btConnected : []
    var d = list.length > 0 ? list[0] : null
    btPop({ name: d ? String(d.deviceName || d.name) : "AirPods Pro", glyph: d ? sys.btDeviceGlyph(d) : "󰋋", dev: d }, true)
  }

  function demoCharge() {
    bannerProgress = sys && sys.batteryPercent >= 0 ? sys.batteryPercent : 64
    present("battery", "charge", "", "Charging", sys ? sys.batteryDetail : "", tk.green, 3400)
  }

  function dismiss() {
    holdTimer.stop()
    bannerKind = ""
  }

  Timer {
    id: holdTimer
    interval: status.tk.bannerDuration
    onTriggered: status.bannerEnded()
  }

  onSuppressedChanged: {
    if (suppressed) dismiss()
    else if (liveNotification && notificationCount > 0) presentNotification()
  }

  // ------------------------------------------------------------------- osd
  // The stock omarchy.osd plugin is disabled, so its two entry points land
  // here and the level shows inside the island: scripts call
  // `omarchy-shell osd show <json>` (the IPC target below), and the shell's own
  // volume and brightness keys summon omarchy.osd in process, which the
  // osd/ companion plugin forwards to this function. Both must keep working.
  function showOsd(payloadJson) {
    var p = {}
    try { p = JSON.parse(payloadJson || "{}") } catch (e) { return }
    var s = OsdModel.stateForShow(p.icon || "", p.message || "",
      p.value === undefined ? "" : String(p.value),
      p.max === undefined ? "100" : String(p.max),
      p.progressText || "",
      p.duration === undefined || p.duration === "" ? "1400" : String(p.duration))
    if (suppressed) return
    bannerProgress = s.hasProgress ? Math.round(s.value * 100 / s.maxValue) : -1
    present("osd", s.hasProgress ? "osd" : "plain", s.icon, s.message, "",
            tk.text, s.duration > 0 ? Math.max(1100, s.duration) : 0)
  }

  function closeOsd() {
    if (bannerKind === "osd") bannerEnded()
  }

  IpcHandler {
    target: "osd"
    function show(payloadJson: string): string { status.showOsd(payloadJson); return "ok" }
    function close(): string { status.closeOsd(); return "ok" }
    function state(): string { return status.bannerKind === "osd" ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  // --------------------------------------------------------- shell toggles
  Connections {
    target: status
    function onSilentChanged() {
      if (status.focusQuiet()) return
      status.show("silent", status.silent ? "󰂛" : "󰂟",
                  status.silent ? "Silent" : "Notifications on",
                  status.silent ? "Do not disturb" : "", status.tk.text)
    }
    function onStayAwakeChanged() {
      if (status.focusQuiet()) return
      status.show("stayAwake", "󰅶", status.stayAwake ? "Stay Awake" : "Idle allowed",
                  status.stayAwake ? "Screen will not sleep" : "", status.tk.text)
    }
    function onNightLightChanged() {
      if (status.focusQuiet()) return
      status.show("nightLight", "󰔎", status.nightLight ? "Night Light" : "Day Light", "", status.tk.text)
    }
    function onRecordingChanged() {
      status.show("recording", status.recording ? "󰑊" : "󰙧", status.recording ? "Recording" : "Recording stopped",
                  status.recording ? "Screen capture is live" : "Saved to Videos",
                  status.recording ? status.tk.crit : status.tk.textDim)
    }
    function onDictatingChanged() {
      if (!status.dictating) return
      status.show("dictation", status.dictation === "transcribing" ? "󰔟" : "󰍬",
                  status.dictation === "transcribing" ? "Transcribing" : "Listening", "", status.tk.accent)
    }
    // Not shown straight away: a feed of autoplaying videos (Facebook,
    // YouTube Shorts) changes "track" every few seconds while you scroll,
    // and each change used to pop the island open.
    function onTrackTitleChanged() { trackSettle.restart() }
  }

  property string lastTrack: ""
  property real lastTrackBannerAt: 0
  // A track gets its banner only once it has played for 2s unchanged, and at
  // most one track banner every 10s.
  Timer {
    id: trackSettle
    interval: 2000
    onTriggered: {
      if (!status.player || !status.player.isPlaying || status.trackTitle === "") return
      // No artist: a website's video (a feed clip titled "Facebook"), not a
      // song. Those never get a banner.
      if (status.trackArtist === "") return
      var sig = status.trackTitle + "\u0000" + status.trackArtist
      if (sig === status.lastTrack) return
      status.lastTrack = sig
      if (Date.now() - status.lastTrackBannerAt < 10000) return
      status.lastTrackBannerAt = Date.now()
      if (!status.armed || status.suppressed || !status.tk.autoExpandOnEvents) return
      status.bannerImage = String(status.player.trackArtUrl || "")
      status.present("media", "media", "󰝚", status.trackTitle, status.trackArtist, status.tk.text)
    }
  }
  property var claudeBands: ({ session: -1, weekly: -1 })

  function claudeBand(which, pct, reset) {
    if (pct < 0) return
    var band = pct >= 95 ? 2 : pct >= 80 ? 1 : 0
    var prev = claudeBands[which]
    var next = Object.assign({}, claudeBands)
    next[which] = band
    claudeBands = next
    if (prev < 0 || band <= prev) return
    var label = which === "session" ? "5-hour limit" : "Weekly limit"
    status.show("claude", sys.claudeGlyph,
      "Claude " + pct + "% used",
      label + (reset !== "" ? "  ·  resets " + reset : ""),
      band === 2 ? tk.danger : tk.accent, 6000)
  }
  property string lastNetKind: ""

  // ---------------------------------------------------------- system events
  Connections {
    target: status.sys
    ignoreUnknownSignals: true

    function onChargingChanged() {
      if (!status.sys.hasBattery) return
      if (status.sys.charging) {
        if (!status.armed || status.suppressed || !status.tk.autoExpandOnEvents) return
        status.bannerProgress = status.sys.batteryPercent
        status.present("battery", "charge", status.sys.batteryGlyph, "Charging",
                       status.sys.batteryDetail, status.tk.green, 3400)
        return
      }
      status.show("battery", status.sys.batteryGlyph,
                  status.sys.charging ? "Charging" : "On battery",
                  status.sys.batteryDetail, status.tk.text)
    }
    function onBatteryLowChanged() {
      if (!status.sys.batteryLow) return
      status.show("battery", "󰂃", "Low battery",
                  status.sys.batteryPercent + "% remaining", status.tk.crit, 6000)
    }
    function onNetKindChanged() {
      // The first probe resolving "unknown" into a real state is not a change
      // the user made; only transitions between two known states announce.
      var previous = status.lastNetKind
      status.lastNetKind = status.sys.netKind
      if (previous === "" || status.sys.netKind === "") return
      status.show("network", status.sys.netGlyph,
                  status.sys.netKind === "disconnected" ? "Offline" : status.sys.netValue,
                  status.sys.netDetail, status.tk.text)
    }
    // A short pop when a device connects or disconnects (nothing stays in
    // the pill). Compared by address, so a rename or battery update is quiet.
    function onBtConnectedChanged() { status.btChanged() }
    function onVolumeChanged() {
      if (!status.tk.volumeBanners) return
      status.show("volume", status.sys.audioGlyph, status.sys.audioValue, "", status.tk.text, 1400)
    }
    // Claude Code usage: one heads-up as each allowance crosses 80% and
    // again at 95%. The first value read only sets the baseline, so a shell
    // restart at 85% does not announce anything.
    function onClaudePercentChanged() {
      status.claudeBand("session", status.sys.claudePercent, status.sys.claudeSessionReset)
    }
    function onClaudeWeeklyPercentChanged() {
      status.claudeBand("weekly", status.sys.claudeWeeklyPercent, status.sys.claudeWeeklyReset)
    }
    function onMutedChanged() {
      if (!status.tk.volumeBanners) return
      status.show("volume", status.sys.audioGlyph,
                  status.sys.muted ? "Muted" : status.sys.audioValue, "", status.tk.text, 1400)
    }
  }

  // ----------------------------------------------------------- notifications
  // The daemon owns delivery, history and DND; the island only mirrors the
  // newest toast it has put on screen, so this is not a second notification
  // system. The proxy the bar is handed does not expose the popup model, but
  // the daemon keeps one file per visible toast, which a directory watch turns
  // into an event.
  property real lastNotificationAt: 0

  FileView {
    path: status.popupDir
    watchChanges: true
    printErrors: false
    onFileChanged: notificationProbe.restart()
  }

  readonly property string popupDir:
    (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/notifications"

  Timer {
    id: notificationProbe
    interval: 120   // the daemon writes the file, then its image; read once
    onTriggered: if (!notificationRead.running) notificationRead.running = true
  }

  Process {
    id: notificationRead
    command: [Qt.resolvedUrl("island-notification.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") return
        var state
        try { state = JSON.parse(raw) } catch (e) { return /* half-written; re-read on next change */ }
        status.distinctCount = Number(state.distinct === undefined ? state.count : state.distinct) || 0
        status.applyNotifications(state.newest, Number(state.count || 0), Number(state.group || 1))
      }
    }
  }

  function cleanBody(s) {
    return String(s || "")
      .replace(/<br\s*\/?>/gi, " ")
      .replace(/<[^>]*>/g, "")
      .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
      .replace(/&quot;/g, "\"").replace(/&#39;/g, "'")
      .replace(/\s+/g, " ").trim()
  }

  function applyNotifications(newest, count, group) {
    notificationCount = count
    groupCount = Math.max(1, group || 1)
    if (!newest || count === 0) {
      liveNotification = null
      if (bannerKind === "notification") lingerOrEnd()
      return
    }
    var at = Number(newest.timestamp || 0)
    var key = notifKey(newest)
    var fresh = at > lastNotificationAt
    var changed = !liveNotification
      || String(liveNotification.originalId) !== String(newest.originalId)
      || liveNotification.summary !== newest.summary
      || liveNotification.body !== newest.body
    liveNotification = newest
    if (fresh) lastNotificationAt = at
    // The one on screen was updated in place (or only the count changed,
    // which the badge picks up by itself): swap the text, no new pop.
    if (bannerKind === "notification" && shownKey === key) {
      if (changed) presentNotification()
      return
    }
    // Already popped up once (the newer one on top of it just left): never
    // replay it. It is in the Notifications pane if needed.
    if (shownTs[key]) {
      // A swallowed duplicate of what is on screen is not "the one on top
      // left": keep showing it.
      var sameText = shownNote && noteSig(shownNote) === noteSig(newest)
      if (bannerKind === "notification" && !lingering && !sameText) dismiss()
      return
    }
    // The same message again within a few seconds (KDE Connect often sends
    // one twice): counts as shown, never pops a second time.
    if (isDuplicate(newest)) {
      markShown(newest)
      return
    }
    if (armed && !suppressed) {
      presentNotification()
      shownKey = key
      markShown(newest)
    }
  }
  property string shownKey: ""

  function presentNotification(entry, ms) {
    var n = entry || liveNotification
    if (!n) return
    // A different toast from the one on screen restarts the reading clock;
    // an in-place update of the same one does not.
    if (!shownNote || notifKey(shownNote) !== notifKey(n)) {
      shownNoteAt = Date.now()
      endNow = false
      checkReply(n)
    }
    shownNote = n
    lingering = false
    rememberSig(n)
    // A level change on screen keeps its few hundred ms; the notification
    // returns via bannerEnded() as soon as it is done.
    if (bannerKind === "osd" && holdTimer.running) return
    bannerApp = String(n.app === "notify-send" || n.app === "omarchy-action" ? "" : (n.app || ""))
    bannerImage = String(n.image || "")
    bannerAppIcon = String(n.appIcon || "")
    bannerUrgency = Number(n.urgency === undefined ? 1 : n.urgency)
    var summary = cleanBody(n.summary)
    // Omarchy's screenshot toast gets its own layout: thumbnail + actions.
    // Its image hint does not survive into the state file, but the click
    // command (`tensaku-edit <path>`, a JSON string) carries the file itself.
    if (/^Screenshot saved/i.test(summary)) {
      var argv = n.execArgv || []
      if (typeof argv === "string") { try { argv = JSON.parse(argv) } catch (e) { argv = [] } }
      var path = argv.length > 1 ? String(argv[argv.length - 1]) : ""
      // Any app can send a toast titled "Screenshot saved", and the banner's
      // Delete button removes this path, so only accept an image directly
      // inside the folder omarchy-capture-screenshot saves to.
      if (status.isScreenshotFile(path)) {
        shotPath = path
        bannerImage = "file://" + path
        present("notification", "screenshot", "", "Screenshot", "", tk.text, 0)
        return
      }
    }
    present("notification", "notification", String(n.glyph || ""),
            summary !== "" ? summary : (n.app || "Notification"),
            cleanBody(n.body), tk.text, ms || 0)
  }

  // ------------------------------------------------- reading time and hover
  // The daemon drops a toast after ~8s whatever its length. The island keeps
  // it a little longer when there is more to read, and never takes it away
  // while the pointer is on it.
  property var shownNote: null        // the toast on the island (live or lingering)
  property real shownNoteAt: 0
  property bool lingering: false      // still shown after the daemon let it go
  property bool endNow: false         // the user dismissed or opened it
  property bool bannerHovered: false
  property bool pausedHold: false
  property int groupCount: 1          // live toasts sharing the app and title
  property int distinctCount: 0       // live toasts, duplicates counted once
  property bool bannerCanReply: false

  function readMs(n) {
    var len = cleanBody(n && n.summary).length + cleanBody(n && n.body).length
    return Math.max(5000, Math.min(20000, 3500 + len * 55))
  }

  function lingerOrEnd() {
    if (bannerHovered && !endNow) { holdTimer.stop(); lingering = true; return }
    var left = shownNote ? shownNoteAt + readMs(shownNote) - Date.now() : 0
    if (!endNow && left > 400) {
      lingering = true
      holdTimer.interval = left
      holdTimer.restart()
    } else {
      lingering = false
      dismiss()
    }
  }

  onBannerHoveredChanged: {
    if (bannerKind !== "notification") return
    if (bannerHovered) {
      if (holdTimer.running) { holdTimer.stop(); pausedHold = true }
    } else if (pausedHold || lingering) {
      pausedHold = false
      holdTimer.interval = 2500
      holdTimer.restart()
    }
  }

  // ------------------------------------------------------------ duplicates
  property var recentSigs: ({})
  function noteSig(n) { return [n.app, cleanBody(n.summary), cleanBody(n.body)].join("\u0001") }
  function isDuplicate(n) {
    var t = recentSigs[noteSig(n)]
    return !!t && Date.now() - t < 15000
  }
  function rememberSig(n) {
    var now = Date.now(), next = ({})
    for (var k in recentSigs) if (now - recentSigs[k] < 60000) next[k] = recentSigs[k]
    next[noteSig(n)] = now
    recentSigs = next
  }

  // ------------------------------------------------------ silent allow list
  function allowedInSilent(e) {
    var app = String(e.app || ""), summary = cleanBody(e.summary)
    for (var i = 0; i < silentAllow.length; i++) {
      var a = String(silentAllow[i])
      if (a === app || a === summary) return true
    }
    return false
  }
  // Silenced toasts go straight to history; the allowed ones pop up from
  // there, for their reading time, since there is no live toast to hold on.
  function checkSilentAllowed() {
    if (!silent || !armed || suppressed || !tk.autoExpandOnEvents) return
    var now = Date.now(), pick = null
    for (var i = 0; i < notifHistory.length; i++) {
      var e = notifHistory[i]
      var ts = Number(e.timestamp || 0)
      if (ts < now - 30000 || shownTs[notifKey(e)] || !allowedInSilent(e)) continue
      if (isDuplicate(e)) { markShown(e); continue }
      if (!pick) pick = e
      markShown(e)
    }
    if (!pick) return
    if (bannerKind === "osd" && holdTimer.running) return
    groupCount = 1
    presentNotification(pick, readMs(pick))
    lingering = true
  }

  // ----------------------------------------------------------------- reply
  // KDE Connect messages that the phone lets you answer get a Reply button.
  readonly property string replyScript: Qt.resolvedUrl("island-phone-reply.sh").toString().replace("file://", "")
  Process {
    id: replyCheck
    property string forKey: ""
    onExited: function(code) {
      if (status.shownNote && status.notifKey(status.shownNote) === forKey)
        status.bannerCanReply = code === 0
    }
  }
  function checkReply(n) {
    bannerCanReply = false
    if (String(n.app || "") !== "KDE Connect") return
    replyCheck.running = false
    replyCheck.forKey = notifKey(n)
    replyCheck.command = ["bash", replyScript, "check", cleanBody(n.summary), cleanBody(n.body)]
    replyCheck.running = true
  }
  function replyNotification() {
    var n = shownNote
    if (!n) return
    Quickshell.execDetached(["bash", replyScript, "send", cleanBody(n.summary), cleanBody(n.body)])
    endNow = true
    dismissNotification()
  }

  // Act on the toast the island is showing. The daemon moves its state file
  // out of the live directory, which the watch above turns into the island
  // moving on to the next toast, or back to the clock.
  // The file behind the screenshot banner.
  property string shotPath: ""

  readonly property string screenshotDir: String(Quickshell.env("OMARCHY_SCREENSHOT_DIR")
    || Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")).replace(/\/+$/, "")

  function isScreenshotFile(path) {
    var p = String(path || "")
    var prefix = screenshotDir + "/"
    if (p.indexOf(prefix) !== 0) return false
    var name = p.slice(prefix.length)
    return name.length > 0 && name.indexOf("/") < 0 && name.charAt(0) !== "."
      && /\.(png|jpe?g|webp)$/i.test(name)
  }

  function screenshotAction(act) {
    if (shotPath === "") return
    if (act === "copy")
      Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", shotPath])
    else if (act === "edit") {
      // Run the editor straight from the toast's own command (tensaku-edit
      // <path>), so it works even if the toast has already timed out.
      var argv = parseArgv(liveNotification ? liveNotification.execArgv : "")
      if (argv.length > 0) Quickshell.execDetached(argv)
      else Quickshell.execDetached(["tensaku-edit", shotPath])
      dismissNotification()
    }
    else if (act === "delete") {
      Quickshell.execDetached(["rm", "-f", "--", shotPath])
      dismissNotification()
    }
  }

  function invokeNotification() {
    endNow = true
    if (liveNotificationId === "" || (shownNote && notifKey(shownNote) !== notifKey(liveNotification))) {
      // Gone from the daemon already (lingering, or a Silent-mode pop):
      // open it from history, or bring its app forward.
      var e = shownNote
      for (var i = 0; e && i < notifHistory.length; i++)
        if (notifKey(notifHistory[i]) === notifKey(e)) { e = notifHistory[i]; break }
      if (e) openHistoryEntry(e)
      dismiss()
      return
    }
    notifAction.command = ["omarchy-shell", "-q", "notifications", "invokeOriginal", liveNotificationId]
    notifAction.running = true
  }

  function dismissNotification() {
    endNow = true
    lingering = false
    if (liveNotificationId === "" || (shownNote && notifKey(shownNote) !== notifKey(liveNotification))) { dismiss(); return }
    notifAction.command = ["omarchy-shell", "-q", "notifications", "dismissOriginal", liveNotificationId]
    notifAction.running = true
  }

  Process { id: notifAction }

  function parseArgv(v) {
    if (!v) return []
    if (typeof v === "string") { try { v = JSON.parse(v) } catch (e) { return [] } }
    return Array.isArray(v) ? v.map(String) : []
  }

  // ------------------------------------------------- history and "missed"
  // The daemon moves every toast into history/ when it leaves the screen, and
  // writes ones silenced by Do Not Disturb straight there. "Missed" = newer
  // than the last time the Notifications pane was opened, and never popped up
  // in the island (silenced, or arrived while the island was held open).
  readonly property string historyDir: popupDir + "/history"
  readonly property string seenPath:
    (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/island-notifications.json"
  property var notifHistory: []
  property real seenAt: 0
  property var shownTs: ({})
  readonly property int missedCount: {
    var n = 0
    for (var i = 0; i < notifHistory.length; i++) {
      var e = notifHistory[i]
      if (Number(e.timestamp || 0) > seenAt && !shownTs[notifKey(e)]) n++
    }
    return n
  }
  function notifKey(n) { return String(n && n.timestamp || 0) }

  function markShown(n) {
    var k = notifKey(n)
    if (shownTs[k]) return
    var next = Object.assign({}, shownTs)
    next[k] = true
    var keys = Object.keys(next).sort()
    while (keys.length > 300) delete next[keys.shift()]
    shownTs = next
    saveSeen()
  }
  function markSeen() { seenAt = Date.now(); saveSeen() }
  function saveSeen() { seenFile.setText(JSON.stringify({ seenAt: seenAt, shown: Object.keys(shownTs) }) + "\n") }

  FileView {
    id: seenFile
    path: status.seenPath
    printErrors: false
    onLoaded: {
      try {
        var d = JSON.parse(text())
        status.seenAt = Number(d.seenAt || 0)
        var m = {}
        var list = d.shown || []
        for (var i = 0; i < list.length; i++) m[String(list[i])] = true
        status.shownTs = m
      } catch (e) { status.markSeen() }
    }
    // First run: everything already in history counts as seen.
    onLoadFailed: status.markSeen()
  }

  FileView {
    path: status.historyDir
    watchChanges: true
    printErrors: false
    onFileChanged: historyProbe.restart()
  }
  Timer {
    id: historyProbe
    interval: 200
    onTriggered: if (!historyRead.running) historyRead.running = true
  }
  // The directory watch can miss a burst; a slow poll keeps the count honest.
  Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true; onTriggered: historyProbe.restart() }
  Process {
    id: historyRead
    command: [Qt.resolvedUrl("island-notif-history.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { status.notifHistory = JSON.parse(String(text || "[]")) } catch (e) { /* keep last */ }
        status.checkSilentAllowed()
      }
    }
  }

  // Click on a history row: its own command if it has one (screenshots open
  // the editor), otherwise bring the sending app's window forward.
  function openHistoryEntry(e) {
    if (!e) return
    var argv = parseArgv(e.execArgv)
    if (argv.length > 0) Quickshell.execDetached(argv)
    else if (e.app && e.app !== "notify-send" && e.app !== "omarchy-action")
      Quickshell.execDetached(["omarchy-hyprland-focus-app", String(e.app)])
    deleteHistoryEntry(e)
  }
  function deleteHistoryEntry(e) {
    if (!e || !e.file) return
    var f = String(e.file)
    if (f.indexOf(historyDir + "/") !== 0 || f.indexOf("..") >= 0) return
    Quickshell.execDetached(["rm", "-f", "--", f])
    notifHistory = notifHistory.filter(function(x) { return x.file !== f })
  }
  function clearHistory() {
    Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "clear"])
    notifHistory = []
  }

  // ------------------------------------------------------------- recording
  Process {
    id: recordingProc
    command: ["pgrep", "--quiet", "-f", "^gpu-screen-recorder"]
    onExited: function(code) { status.recording = code === 0 }
  }

  Timer {
    interval: 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!recordingProc.running) recordingProc.running = true
  }

  // ------------------------------------------------------------- dictation
  Process {
    command: ["omarchy-voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var d = JSON.parse(String(line))
          status.dictation = String(d.alt || d.class || "idle")
        } catch (e) { status.dictation = "idle" }
      }
    }
  }

  // ----------------------------------------------------------------- phone
  // The KDE Connect phone: a pop when it connects or drops, starts charging,
  // is full, or runs low (20% and again at 10%).
  property var phone: ({})
  property bool phonePrimed: false
  Process {
    id: phoneProbe
    command: [Qt.resolvedUrl("island-phone.sh").toString().replace("file://", "")]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: status.applyPhone(text) }
  }
  Timer {
    interval: 20000
    repeat: true
    running: status.phoneStatus
    triggeredOnStart: true
    onTriggered: if (!phoneProbe.running) phoneProbe.running = true
  }
  function applyPhone(raw) {
    var d
    try { d = JSON.parse(String(raw || "{}")) } catch (e) { return }
    var p = phone
    phone = d
    if (!phonePrimed || !armed) { phonePrimed = true; return }
    if (!d.id || p.id !== d.id) return
    var name = String(d.name || "Phone"), pct = Number(d.charge)
    if (d.reachable !== p.reachable)
      show("phone", "󰄜", name, d.reachable ? (pct >= 0 ? "Connected  ·  " + pct + "%" : "Connected") : "Disconnected",
           d.reachable ? tk.accent : tk.textDim)
    else if (!d.reachable || pct < 0) return
    else if (d.charging && !p.charging)
      show("phone", "󰂄", name, "Charging  ·  " + pct + "%", tk.green)
    else if (d.charging && pct >= 100 && Number(p.charge) < 100)
      show("phone", "󰁹", name, "Fully charged", tk.green)
    else if (!d.charging && ((pct <= 20 && Number(p.charge) > 20) || (pct <= 10 && Number(p.charge) > 10)))
      show("phone", "󰁺", "Phone battery low", pct + "%  ·  " + name, tk.crit, 6000)
  }

  // ----------------------------------------------------------------- unity
  // Unity compile / reload / build progress from the editor log
  // (island-unity.sh). Fast compiles stay quiet; slow ones show while they
  // run, failures say why.
  property string unityProject: ""
  property string unityPhase: ""        // "" | compile | reload
  property real unityStart: 0
  property var unityErrors: []
  property bool unityShown: false
  Process {
    command: [Qt.resolvedUrl("island-unity.sh").toString().replace("file://", "")]
    running: status.unityStatus
    stdout: SplitParser { onRead: function(line) { status.unityEvent(line) } }
  }
  Timer {
    id: unityShowDelay
    interval: 900
    onTriggered: status.unityBanner()
  }
  function unityAllowed() { return armed && !suppressed && tk.autoExpandOnEvents && bannerKind !== "notification" }
  function unityBanner() {
    if (unityPhase === "" || !unityAllowed()) return
    unityShown = true
    present("unity", "plain", "󰔟", unityPhase === "compile" ? "Compiling scripts" : "Reloading scripts",
            unityProject, tk.accent, 0)
  }
  function unityEnd(glyph, title, detail, tint, ms) {
    unityPhase = ""
    unityShowDelay.stop()
    var wasShown = unityShown
    unityShown = false
    if (ms === 0) { if (bannerKind === "unity") dismiss(); return }
    if (!unityAllowed() && bannerKind !== "unity") return
    if (!wasShown && ms < 3000) { if (bannerKind === "unity") dismiss(); return }
    present("unity", "plain", glyph, title, detail, tint, ms)
  }
  function unityEvent(line) {
    var e
    try { e = JSON.parse(String(line)) } catch (x) { return }
    if (e.ev === "project") { unityProject = String(e.name || ""); return }
    if (e.ev === "closed") { unityProject = ""; unityEnd("", "", "", tk.text, 0); return }
    if (e.ev === "compile") {
      unityErrors = []
      unityPhase = "compile"
      unityStart = Date.now()
      unityShowDelay.restart()
    } else if (e.ev === "error") {
      if (unityErrors.length < 50) unityErrors = unityErrors.concat([String(e.msg)])
    } else if (e.ev === "compiled") {
      if (e.ok) {
        unityPhase = "reload"
        if (unityShown) unityBanner()
      } else {
        var first = unityErrors.length > 0 ? unityErrors[0] : ""
        // "Assets/Scripts/Foo.cs(12,5): error CS1002: ; expected" ->
        // "Foo.cs:12  ; expected"
        var m = /([^\/]+\.cs)\((\d+),\d+\): error CS\d+: (.*)$/.exec(first)
        var detail = m ? m[1] + ":" + m[2] + "  " + m[3] : (first || unityProject)
        if (unityErrors.length > 1) detail += "  ·  " + unityErrors.length + " errors"
        unityEnd("󰅚", "Compile failed", detail, tk.danger, 8000)
      }
    } else if (e.ev === "reload") {
      if (unityPhase === "") return     // play mode, not a script change
      unityPhase = "reload"
      if (unityShown) unityBanner()
      else if (!unityShowDelay.running) unityShowDelay.restart()
    } else if (e.ev === "reloaded") {
      if (unityPhase === "") return
      var secs = ((Date.now() - unityStart) / 1000).toFixed(1)
      unityEnd("󰄬", "Scripts ready", secs + "s  ·  " + unityProject, tk.green, 1800)
    } else if (e.ev === "build") {
      var ok = String(e.result) === "Succeeded"
      unityPhase = "compile"   // let unityEnd show it even if nothing was on screen
      unityShown = true
      unityEnd(ok ? "󰚯" : "󰅚", ok ? "Build succeeded" : "Build " + String(e.result).toLowerCase(),
               (e.secs ? e.secs + "s  ·  " : "") + unityProject, ok ? tk.green : tk.danger, 6000)
    }
  }

  // ----------------------------------------------------------------- arming
  Timer {
    interval: 2500
    running: true
    onTriggered: {
      status.lastNotificationAt = Date.now()
      status.lastTrack = status.trackTitle + "\u0000" + status.trackArtist
      status.armed = true
    }
  }
}
