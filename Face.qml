import QtQuick
import qs.Commons

// Theme-only mark so BarWidget’s Face API still compiles.
Item {
  id: root
  property real iconSize: Style.bar.iconCanvas
  property bool lively: false
  property color holeColor: Color.bar.background
  property color fill: lively ? Color.foreground : Color.muted
  property real markOpacity: 1

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  Avatar {
    anchors.fill: parent
    shape: "squircle"
    outlined: true
    fill: root.fill
    eyeColor: root.fill
    face: root.lively ? "neutral" : "drowsy"
    animate: root.lively
    opacity: root.markOpacity
    Behavior on opacity { NumberAnimation { duration: 220 } }
  }
}
