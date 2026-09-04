import QtQuick
import qs.Commons

// Bar mark: outlined squircle with cut-out eyes. Theme fill only.
Item {
  id: root
  property real iconSize: Style.bar.iconCanvas
  property bool lively: false
  property color holeColor: Color.bar.background

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  Avatar {
    anchors.fill: parent
    shape: "squircle"
    outlined: true
    cutoutEyes: true
    fill: root.lively ? Color.foreground : Color.muted
    face: root.lively ? "neutral" : "drowsy"
    animate: root.lively
  }
}
