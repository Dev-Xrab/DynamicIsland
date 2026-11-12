import QtQuick
import qs.Commons

// ---------------------------------------------------------------------------
// The Dynamic Island design system.
//
// Modelled on Atoll (github.com/Ebullioscopic/Atoll): a black notch flush with
// the top edge, square-cornered where it meets the bezel, heavily rounded
// below, with content laid out on lifted-black cards.
//
// Base values are authored against a 12px shell font (the Omarchy default);
// `u` rescales them with `[font] base-size`, which is what the rest of the
// shell scales by. Wayland hands us logical pixels, so these are already
// correct under fractional scaling and at any resolution.
// ---------------------------------------------------------------------------
QtObject {
  id: tk

  readonly property real u: Style.fontScale
  function px(v) { return Math.round(v * u) }

  // ------------------------------------------------------------- geometry
  // The island hangs off the top edge like the notch it imitates: no margin,
  // nothing floating.
  readonly property int topMargin:        0
  // Panacea's pill (EnsixD/Panacea, notch mode at the top edge): 38px tall,
  // at least 420 wide, content kept 18px in from each end.
  readonly property int pillH:            38
  readonly property int collapsedHeight:  pillH
  readonly property int collapsedPadX:    18
  readonly property int pillMinWidth:     240
  readonly property int bannerHeight:     px(46)
  readonly property int bannerPadX:       px(24)
  readonly property int bannerMaxWidth:   px(680)

  // Spacing scale (8-point, with 4/12 half steps). Banners and their buttons
  // are laid out from these so nothing is packed tighter than its neighbours:
  //   4 inside a label pair, 8 between related items, 12 between groups,
  //   16-18 around the content, more at the curved bottom edge.
  readonly property int spaceXs: px(4)
  readonly property int spaceSm: px(8)
  readonly property int spaceMd: px(12)
  readonly property int spaceLg: px(16)
  readonly property int bannerPadY:   px(18)
  // Pill buttons inside banners (Copy / Edit / Delete …): 28px tall so they
  // are an easy target, 12px either side of the label.
  readonly property int buttonHeight: px(28)
  readonly property int buttonPadX:   px(12)
  // Screenshot banner thumbnail.
  readonly property int shotThumbW:   px(112)
  readonly property int shotThumbH:   px(72)
  // Notifications are drawn only here (the daemon's corner toasts are off).
  // Compact: title + app/time on one line, the whole message wrapped under
  // it. The banner is sized to its text, up to these limits.
  // Wide rather than tall: a long message wraps onto fewer lines, and the
  // whole of it is always shown (the line cap only stops a novel).
  readonly property int notificationWidth:       px(880)   // max outer width
  readonly property int notificationMinWidth:    px(320)
  readonly property int notificationPadY:        px(16)
  readonly property int notificationPadX:        px(24)
  readonly property int notificationIcon:        px(36)
  readonly property int notificationTitleSize:   fontSize + 1
  readonly property int notificationBodySize:    fontSize - 1
  readonly property int notificationMetaSize:    fontSize - 3
  readonly property int notificationBodyLines:   10
  // Volume / brightness / mic levels (the island owns the `osd` IPC target).
  readonly property int osdTrackWidth:    px(160)
  readonly property int expandedWidth:    px(672)
  // One page at a time (Tab switches): overview cards, or IslandExtras.
  readonly property int expandedHeight:   px(223)
  readonly property int expandedPadX:     px(14)   // even: same on all four sides
  readonly property int expandedPadTop:   px(14)   // was 9: titles sat on the edge
  readonly property int expandedPadBottom: px(14)
  readonly property int minWidth:         pillMinWidth
  // A detail view replaces the card row. Each kind is sized to the content it
  // actually has rather than to the tallest one: a battery readout has five
  // rows and no list, so growing the pane to the Wi-Fi list's height left it
  // two-thirds empty. `detailHeight` stays the largest of them because the
  // surface's window and the click-away scrim are sized from it.
  // Every pane gets the extra 5px of top padding on top of its own height.
  function detailHeightFor(kind) { return detailBaseHeight(kind) + px(5) }
  // Panes are the open island's width, except Control Center, which grows
  // wider out of the same surface (one continuous morph, not a new window).
  readonly property int ccWidth:  px(540)
  function detailWidthFor(kind) { return kind === "controlcenter" ? ccWidth : expandedWidth }

  // Notification Center (right-side panel).
  readonly property int ncWidth:   px(372)
  readonly property int ncMargin:  px(10)
  readonly property int ncRadius:  px(22)
  function detailBaseHeight(kind) {
    if (kind === "network")   return px(252)
    if (kind === "bluetooth") return px(252)
    if (kind === "audio")     return px(180)   // two short cards; 206 left half of each empty
    if (kind === "battery")   return px(206)   // six rows need the room
    if (kind === "claude")    return px(192)
    if (kind === "shanshui")  return px(266)
    if (kind === "display")   return px(250)   // + Island style row
    if (kind === "record")    return px(176)
    if (kind === "notifications") return px(320)   // room for ~4 rows
    if (kind === "activity")  return px(236)   // six process rows
    if (kind === "controlcenter") return px(529)
    return px(206)
  }
  readonly property int detailHeight:     px(534)   // tallest pane (Control Center)

  // A password prompt takes over the Wi-Fi detail's lower half rather than
  // opening a window of its own.
  readonly property int fieldHeight:      px(30)
  // How far the surface is drawn above the screen's top row; see IslandGlass.
  readonly property int overscan:         2

  // Atoll's NotchShape radii. The top pair curve outward into the bezel; the
  // bottom pair are the visible rounding.
  // Panacea: the two concave corners where the pill meets the screen edge are
  // a 12px quarter circle (notchFlare), the pill's free corners are round
  // (pillH / 2) and the open panel's are 26.
  // macOS look: collapsed it is a MacBook notch (small shoulders into the
  // top edge, a rounded-rectangle bottom rather than a capsule); open it is
  // a Control Center panel (26px corners).
  readonly property int flare:                 9
  readonly property int collapsedTopRadius:    flare
  readonly property int collapsedBottomRadius: px(13)
  readonly property int expandedTopRadius:     flare
  readonly property int expandedBottomRadius:  px(26)

  readonly property int reservedHeight: topMargin + collapsedHeight
  readonly property int windowHeight: topMargin + Math.max(detailHeight, expandedHeight) + shadowBlur + px(8)

  // ---------------------------------------------------------------- color
  // Black, like the bezel it pretends to be. Drop `surfaceAlpha` below 1 and
  // re-add the `omarchy-bar` blur rule in looknfeel.lua for a glass variant.
  readonly property real surfaceAlpha: 1.0

  // Light variant: on a pitch-black backdrop (black wallpaper, or a Shan Shui
  // painting on black paper) a black island disappears, so it lifts to a soft
  // graphite that sits with the black; ink stays white. Bar.qml sets this from
  // island-backdrop.sh.
  property bool light: false
  readonly property color beige:  "#1F1F22"   // graphite on black (was silver #C7C9CD, beige #E8DCC4)
  readonly property color ink:    "#FFFFFF"   // white ink on graphite too
  // What colour a "lifted" layer is drawn in: white on black, ink on beige.
  readonly property color lift:   "#FFFFFF"

  readonly property color surface: Util.alpha(light ? beige : "#000000", surfaceAlpha)

  // Open island: Apple's dark glass. A translucent graphite over the
  // compositor's blur (the `omarchy-bar` layer rule in hypr/looknfeel.lua
  // blurs whatever is behind it), edged with a thin light rim like the
  // specular edge of Liquid Glass. The collapsed pill stays solid black.
  // Keep glassAlpha above that rule's ignore_alpha (0.2) or the blur drops out.
  // Control Center (dark): a lighter, more see-through graphite than before,
  // so the blurred wallpaper reads through it the way macOS vibrancy does.
  readonly property color glass:       Qt.rgba(0.13, 0.13, 0.14, glassAlpha)
  readonly property real  glassAlpha:  0.52
  // false = the open island is solid black, like the pill. true = glass.
  // Set from "glass" in ~/.config/omarchy/island.json (Display pane: Island style).
  property bool openGlass: false
  readonly property color glassRim:    Util.alpha("#FFFFFF", 0.17)
  readonly property color glassSheen:  Util.alpha("#FFFFFF", 0.06)

  // Cards: the surface lifted just enough to separate, with a hairline edge
  // (Panacea's card: 5% fill, 1px line, 16px radius).
  // Apple-style: borderless frosted modules, a touch lighter than the black.
  // Control Center modules: a lighter frosted plate with a hairline rim.
  readonly property color card:        Util.alpha(lift, 0.10)
  readonly property color cardHover:   Util.alpha(lift, 0.15)
  readonly property color cardPressed: Util.alpha(lift, 0.21)
  readonly property color line:        Util.alpha(lift, 0.07)
  readonly property int cardRadius:    px(16)
  readonly property int cardGap:       px(7)
  readonly property int cardPad:       px(12)

  // Panacea's Nothing palette: white ink, muted = the ink at 45%, and the
  // accent is the ink itself (Nothing highlights by brightness, not hue).
  readonly property color text:      "#FFFFFF"
  // Apple system colours (dark appearance).
  readonly property color textDim:   Util.alpha(text, 0.60)
  readonly property color textFaint: Util.alpha(text, 0.40)
  readonly property color accent:    "#0A84FF"   // systemBlue
  readonly property color green:     "#30D158"   // systemGreen
  readonly property color orange:    "#FF9F0A"   // systemOrange
  readonly property color crit:      "#FF453A"   // systemRed
  // Text drawn on a filled "on" pill (the pill is `text` at ~92%).
  readonly property color pillText:    "#000000"
  readonly property color meterTrack: Util.alpha(lift, 0.10)
  // Connection failures and refusals. Distinct from `accent`, which the meters
  // already use for "worth noticing" rather than "went wrong".
  readonly property color danger:     "#FF453A"
  readonly property color fieldBg:    Util.alpha(lift, 0.085)

  // --------------------------------------------------------------- shadow
  readonly property int  shadowBlur:    px(26)
  readonly property int  shadowOffsetY: px(7)
  // Only the open panel casts one (scaled by the glass amount in
  // IslandGlass); the notch is part of the bezel and has none.
  readonly property real shadowAlpha:   0.40

  // ----------------------------------------------------------- typography
  // A proportional sans, like SF Pro, for all text. Icon glyphs (Nerd Font
  // codepoints) still render through font fallback.
  readonly property string fontFamily: {
    var have = Qt.fontFamilies()
    var prefs = ["SF Pro Display", "SF Pro Text", "Inter", "Inter Variable", "Noto Sans"]
    for (var i = 0; i < prefs.length; i++)
      if (have.indexOf(prefs[i]) >= 0) return prefs[i]
    return Style.font.family
  }
  // Glyph-only text keeps the Nerd Font so icons never fall back to tofu.
  readonly property string iconFamily:  Style.font.family
  // Panacea: fontSize 15, iconSize 17; labels at fontSize - 2, captions - 4.
  readonly property int fontSize:       15
  readonly property int iconSize:       17
  readonly property real dotClock:      fontSize - 1    // dot-matrix clock in the pill
  readonly property real dotSmall:      fontSize - 3    // dot numbers beside icons
  readonly property int clockSize:      fontSize - 1
  readonly property real clockSpacing:  0.8
  readonly property int bannerSize:     fontSize - 1
  readonly property int statSize:       fontSize - 2
  readonly property int cardTitleSize:  fontSize - 4
  readonly property int cardValueSize:  fontSize + 3
  readonly property int tileValueSize:  fontSize - 2
  readonly property int tileLabelSize:  fontSize - 4
  readonly property int tileIconSize:   iconSize - 2
  readonly property int glyphSize:      iconSize - 2
  readonly property int detailTitleSize: Style.font.subtitle
  readonly property int rowHeight:       px(26)

  // ------------------------------------------------------------ animation
  // cubic-bezier(0.32, 0.72, 0, 1) — the curve Apple uses for island and sheet
  // transforms. Fast out of the gate, long settle, no oscillation.
  // Panacea's timeline: size and position move on InOutCubic over 230ms,
  // opacity and colour fade over 200ms, hover answers in 150ms.
  readonly property var springCurve: [0.32, 0.72, 0.0, 1.0, 1.0, 1.0]   // Apple's sheet/island curve
  readonly property var fadeCurve:   [0.33, 1.0, 0.68, 1.0, 1.0, 1.0]

  // One timing table for the whole shell (island, Control Center,
  // Notification Center). {"reducedMotion": true} in island.json turns every
  // movement into a near-instant fade.
  property bool reducedMotion: false
  function motion(ms) { return reducedMotion ? Math.min(ms, 60) : ms }
  readonly property int expandDuration:     motion(340)   // island expansion
  readonly property int collapseDuration:   motion(300)
  readonly property int radiusDuration:     motion(320)
  readonly property int hoverDuration:      motion(120)
  readonly property int pressDuration:      motion(130)   // button feedback
  readonly property int panelDuration:      motion(320)   // Notification Center slide
  // The old content clears out before the pane starts moving, and the new
  // content arrives only once the pane has committed to its size. Nothing is
  // ever on screen at a size it is not going to settle at.
  // Panacea: the open page fades in over animFast (0.52 x 230 = 120ms,
  // OutCubic) while the pane grows over it, out in 90ms; no stagger.
  readonly property int contentInDelay:     0
  // When content is *swapped* inside an already open island (a pane opening
  // over the cards, Back, a page change), the new content waits for the old
  // to finish leaving. Opening from the pill needs no wait: the pill is
  // hidden at once. Bar.qml keeps liveHeight at the surface's drawn height.
  property real liveHeight: 0
  readonly property int swapDelay: contentOutDuration + 30
  function inDelay() { return liveHeight > collapsedHeight + 1 ? swapDelay : contentInDelay }
  readonly property int contentInDuration:  motion(200)
  readonly property int contentOutDuration: motion(90)
  readonly property int stagger:            0
  // Concave corners come back this long after the pill is home (animMs + 40).
  readonly property int cornerRevealDelay:  400
  readonly property int colorDuration:      motion(160)

  // ---------------------------------------------------------- interaction
  // The island stays open until you dismiss it: click away, press Escape, or
  // hit the toggle again. Nothing times out from under you.
  readonly property int bannerDuration:       2600
  readonly property int notificationDuration: 5200

  // Master switch for automatic banners. Off means the island only ever
  // changes state because you clicked it.
  readonly property bool autoExpandOnEvents: true
  // Volume and brightness arrive through the `osd` IPC target, which the island
  // answers itself (omarchy.osd is disabled in shell.json). These watcher-
  // driven volume banners would show each change twice on top of that.
  readonly property bool volumeBanners: false
}
