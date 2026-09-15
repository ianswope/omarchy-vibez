import QtQuick
import qs.Commons

// A beamed eighth-note pair: two heads, two stems, one beam. Built from
// rectangles and a radius rather than a font glyph or a drawn path, because at
// the ~12px the bar renders, a stroked curve turns to mush and a glyph pulls in
// whatever the theme font happens to have for U+266B.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real stem: Math.max(1, Math.round(iconSize * 0.1))
  readonly property real head: Math.max(3, Math.round(iconSize * 0.34))
  readonly property real beamHeight: Math.max(1, Math.round(iconSize * 0.12))
  readonly property real span: Math.round(iconSize * 0.52)

  // Left head, sitting on the baseline.
  Rectangle {
    width: root.head
    height: Math.max(2, Math.round(root.head * 0.78))
    radius: height / 2
    x: 0
    y: root.height - height
    color: root.color
    antialiasing: true
  }

  // Right head, a little higher, the way a beamed pair is usually drawn.
  Rectangle {
    width: root.head
    height: Math.max(2, Math.round(root.head * 0.78))
    radius: height / 2
    x: root.span
    y: root.height - height - Math.round(root.iconSize * 0.1)
    color: root.color
    antialiasing: true
  }

  Rectangle {
    width: root.stem
    height: root.height - Math.max(2, Math.round(root.head * 0.78)) * 0.6
    x: root.head - root.stem
    y: 0
    color: root.color
    antialiasing: true
  }

  Rectangle {
    width: root.stem
    height: root.height - Math.max(2, Math.round(root.head * 0.78)) * 0.6 - Math.round(root.iconSize * 0.1)
    x: root.span + root.head - root.stem
    y: 0
    color: root.color
    antialiasing: true
  }

  // Beam across the top, joining the two stems.
  Rectangle {
    width: root.span + root.head - (root.head - root.stem)
    height: root.beamHeight
    x: root.head - root.stem
    y: 0
    color: root.color
    antialiasing: true
  }
}
