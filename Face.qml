import QtQuick
import qs.Commons

// 16px optical grok face. Theme-only: muted when idle/asleep,
// foreground when there is unread or a bot is working.
Item {
  id: root
  property real iconSize: Style.bar.iconCanvas
  property bool lively: false
  property color holeColor: Color.bar.background

  readonly property color bodyColor: lively ? Color.foreground : Color.muted
  property real eyeOpen: lively ? 1 : 0.12
  property real bob: 0

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  onLivelyChanged: {
    if (!lively) {
      bob = 0
      eyeOpen = 0.12
    }
  }

  SequentialAnimation on bob {
    running: root.lively
    loops: Animation.Infinite
    NumberAnimation { to: 1.1; duration: 420; easing.type: Easing.InOutSine }
    NumberAnimation { to: -1.1; duration: 420; easing.type: Easing.InOutSine }
  }

  SequentialAnimation on eyeOpen {
    running: root.lively
    loops: Animation.Infinite
    PauseAnimation { duration: 2400 }
    NumberAnimation { to: 0.08; duration: 70 }
    NumberAnimation { to: 1.0; duration: 140 }
    PauseAnimation { duration: 1800 }
    NumberAnimation { to: 0.08; duration: 70 }
    NumberAnimation { to: 1.0; duration: 110 }
    NumberAnimation { to: 0.08; duration: 70 }
    NumberAnimation { to: 1.0; duration: 140 }
  }

  Item {
    id: head
    width: Math.round(root.iconSize * 0.92)
    height: width
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.bob

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: root.bodyColor
      Behavior on color { ColorAnimation { duration: 240 } }
    }

    Row {
      anchors.centerIn: parent
      spacing: Math.max(2, Math.round(head.width * 0.16))

      Repeater {
        model: 2
        Rectangle {
          width: Math.max(2, Math.round(head.width * 0.16))
          height: Math.max(1, Math.round(head.width * 0.28 * root.eyeOpen))
          radius: width / 2
          color: root.holeColor
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }
}
