import QtQuick
import qs.Commons

// Theme-only mark so BarWidget’s Face API still compiles.
Item {
  id: root
  property real iconSize: Style.bar.iconCanvas
  property bool lively: false
  property color holeColor: Color.bar.background

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  readonly property color markColor: lively ? Color.foreground : Color.muted

  Avatar {
    anchors.fill: parent
    shape: "squircle"
    outlined: true
    fill: root.markColor
    eyeColor: root.markColor
    face: root.lively ? "neutral" : "drowsy"
    animate: root.lively
  }
}
