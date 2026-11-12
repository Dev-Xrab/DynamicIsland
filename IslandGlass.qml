import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// The island's surface: the macOS notch shape, in black.
//
// Same outline as the Atoll `NotchShape` port it replaces — top corners curve
// *outward* into the screen edge, bottom corners are a large convex radius,
// both radii animate — but built so a resize is cheap enough to run every
// frame at 90Hz:
//
//   body     a native Rectangle with per-corner radii (no path re-tessellation)
//   fillets  two small Shapes, only ever topRadius-sized
//   shadow   RectangularShadow (an analytic SDF), not a MultiEffect blur pass
//            over the whole surface
//
// The previous version re-tessellated a full-size curved path and re-blurred
// its shadow on every frame of a morph, which is what made SUPER+B and the
// menus stutter. Original kept in ~/.config/omarchy/island-v2-backup-*/.
Item {
  id: glass

  required property var tk
  property real topRadius: tk.collapsedTopRadius
  property real bottomRadius: tk.collapsedBottomRadius
  property color tint: "transparent"
  property real tintStrength: 0
  // Panacea's concave corners (NotchCorner): hidden at once when the pill
  // leaves its edge, faded back in (animFast) once it is home again.
  property bool cornersOn: true

  // 0 = the solid black pill, 1 = open glass. Animated by the caller in step
  // with the morph, so the black melts into glass as the island grows.
  property real glassAmount: 0

  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                   a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
  }
  readonly property color baseColor: glassAmount > 0 ? mix(tk.surface, tk.glass, glassAmount) : tk.surface
  readonly property color surfaceColor: tintStrength > 0
    ? Qt.tint(baseColor, Qt.rgba(tint.r, tint.g, tint.b, tintStrength))
    : baseColor

  // Drawn from a couple of pixels above the surface so the antialiased top
  // edge never shows as a hairline of wallpaper on the screen's first row.
  readonly property int overscan: tk.overscan

  RectangularShadow {
    visible: glass.tk.shadowAlpha > 0 && glass.glassAmount > 0
    opacity: glass.glassAmount
    anchors.fill: body
    radius: Math.min(glass.bottomRadius, body.height / 2)
    blur: glass.tk.shadowBlur
    offset.y: glass.tk.shadowOffsetY
    color: Qt.rgba(0, 0, 0, glass.tk.shadowAlpha)
    cached: false
  }

  Rectangle {
    id: body
    x: glass.topRadius
    y: -glass.overscan
    width: Math.max(0, glass.width - glass.topRadius * 2)
    height: glass.height + glass.overscan
    color: glass.surfaceColor
    topLeftRadius: 0
    topRightRadius: 0
    bottomLeftRadius: Math.min(glass.bottomRadius, height / 2, width / 2)
    bottomRightRadius: bottomLeftRadius
    antialiasing: true
  }

  // Concave corners into the screen edge, one per side: Panacea's
  // NotchCorner — an r x r square with a quarter circle cut out, centred on
  // its lower outer corner.
  component Fillet: Shape {
    id: f
    property bool mirrored: false
    readonly property real r: glass.topRadius
    width: r
    height: glass.overscan + r
    y: -glass.overscan
    opacity: glass.cornersOn ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
      enabled: glass.cornersOn
      NumberAnimation { duration: glass.tk.contentInDuration }
    }
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { origin.x: f.width / 2; xScale: f.mirrored ? -1 : 1 }
    ShapePath {
      fillColor: glass.surfaceColor
      strokeWidth: -1
      startX: 0; startY: 0
      PathLine { x: f.r; y: 0 }
      PathLine { x: f.r; y: f.height }
      PathArc { x: 0; y: glass.overscan; radiusX: f.r; radiusY: f.r; direction: PathArc.Counterclockwise }
      PathLine { x: 0; y: 0 }
    }
  }

  Fillet { x: 0 }
  Fillet { x: glass.width - glass.topRadius; mirrored: true }

  // ---------------------------------------------------------- glass finish
  // Only drawn while open. A faint light falling from the top edge, and a thin
  // rim that follows the whole outline (concave corners, sides, rounded
  // bottom), brightest where the light catches the lower curve.
  Rectangle {
    visible: glass.glassAmount > 0
    opacity: glass.glassAmount
    x: body.x
    y: 0
    width: body.width
    height: glass.height
    bottomLeftRadius: body.bottomLeftRadius
    bottomRightRadius: body.bottomRightRadius
    // Nothing at the top: a highlight there covered only the body and not the
    // two concave corners beside it, which then showed as darker wedges.
    gradient: Gradient {
      GradientStop { position: 0.0; color: "transparent" }
      GradientStop { position: 0.55; color: "transparent" }
      GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.025) }
    }
  }

  Shape {
    id: rim
    anchors.fill: parent
    visible: glass.glassAmount > 0
    opacity: glass.glassAmount
    preferredRendererType: Shape.CurveRenderer
    readonly property real r: glass.topRadius
    readonly property real br: body.bottomLeftRadius
    readonly property real w: glass.width
    readonly property real h: glass.height - 0.5
    ShapePath {
      strokeWidth: 1
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.RoundJoin
      strokeColor: glass.tk.glassRim
      startX: 0; startY: 0
      // Left concave corner, down the side, round the bottom, and back up.
      PathArc { x: rim.r + 0.5; y: rim.r; radiusX: rim.r; radiusY: rim.r; direction: PathArc.Clockwise }
      PathLine { x: rim.r + 0.5; y: rim.h - rim.br }
      PathArc { x: rim.r + rim.br; y: rim.h; radiusX: rim.br; radiusY: rim.br; direction: PathArc.Counterclockwise }
      PathLine { x: rim.w - rim.r - rim.br; y: rim.h }
      PathArc { x: rim.w - rim.r - 0.5; y: rim.h - rim.br; radiusX: rim.br; radiusY: rim.br; direction: PathArc.Counterclockwise }
      PathLine { x: rim.w - rim.r - 0.5; y: rim.r }
      PathArc { x: rim.w; y: 0; radiusX: rim.r; radiusY: rim.r; direction: PathArc.Clockwise }
    }
  }
}
