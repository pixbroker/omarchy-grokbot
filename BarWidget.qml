import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// One file: bar icon + KeyboardPanel. Same shape as dropbox/HEY so the
// popup actually maps. Do not add a sibling Panel.qml — QML would resolve
// `Panel` to that file and hide the bar slot.
Panel {
  id: root
  moduleName: "pixbroker.grokbot"
  ipcTarget: "pixbroker.grokbot"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int maxInboxBytes: 65536
  readonly property int maxBots: 24
  readonly property string inboxPath: root.homeDir !== "" ? root.homeDir + "/.local/state/grok-bot-rust/inbox.json" : ""

  readonly property string homeDir: {
    var home = Quickshell.env("HOME") || ""
    return (home !== "" && home.charAt(0) === "/") ? home : ""
  }
  property bool localBinOk: false
  property bool cargoBinOk: false
  readonly property string cliBin: root.allowCli(setting("command", "grokbot-tui"))
  readonly property string appId: root.allowAppId(setting("appId", "org.omarchy.grokbot-tui"))

  property var bots: []
  property string lastError: ""
  property bool refreshing: false
  property bool hasClient: false
  readonly property int unreadCount: {
    var n = 0
    for (var i = 0; i < bots.length; i++)
      if (bots[i] && bots[i].unread) n++
    return n
  }
  readonly property bool anyBusy: {
    for (var i = 0; i < bots.length; i++)
      if (bots[i] && bots[i].busy) return true
    return false
  }
  readonly property bool lively: unreadCount > 0 || anyBusy
  readonly property int rowH: Style.space(56)
  readonly property int listH: bots.length === 0 ? Style.space(88) : Math.min(rowH * 8, rowH * bots.length)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function swatch(name) {
    var n = String(name || "").toLowerCase()
    if (n === "red" || n === "orange" || n === "brown")
      return Color.urgent
    return Color.accent
  }

  function emptyText() {
    if (lastError !== "")
      return lastError
    if (hasClient)
      return "No bots yet."
    return "Need grokbot-tui inbox --watch (see README)."
  }

  // Drop C0/C1 controls (including newline) and cap length. No regex.
  function clip(s, n) {
    s = String(s || "")
    var out = ""
    for (var i = 0; i < s.length && out.length < n; i++) {
      var c = s.charCodeAt(i)
      if (c < 32 || c === 127 || c === 0x2028 || c === 0x2029)
        continue
      out += s.charAt(i)
    }
    return out
  }

  function allowIdent(s, maxLen) {
    s = clip(String(s || "").trim(), maxLen)
    if (s.length < 1)
      return ""
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i)
      var ok = (ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch === "." || ch === "_" || ch === "-" || ch === ":"
      if (!ok)
        return ""
    }
    return s
  }

  function allowBotId(s) {
    return allowIdent(s, 80)
  }

  function allowAppId(s) {
    var id = allowIdent(s, 64)
    if (id === "")
      return "org.omarchy.grokbot-tui"
    return id
  }

  // Basename grokbot-tui, or an absolute path ending in /grokbot-tui with
  // no ".." and only [A-Za-z0-9._/-]. Never a shell string.
  function allowCli(s) {
    s = String(s || "").trim()
    if (s === "" || s === "grokbot" || s === "grokbot-tui") {
      if (root.homeDir === "")
        return "grokbot-tui"
      if (root.localBinOk)
        return root.homeDir + "/.local/bin/grokbot-tui"
      if (root.cargoBinOk)
        return root.homeDir + "/.cargo/bin/grokbot-tui"
      return root.homeDir + "/.local/bin/grokbot-tui"
    }
    if (s.charAt(0) !== "/")
      return ""
    if (s.indexOf("..") >= 0)
      return ""
    if (s.substring(s.length - 12) !== "/grokbot-tui")
      return ""
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i)
      var ok = (ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch === "." || ch === "_" || ch === "-" || ch === "/"
      if (!ok)
        return ""
    }
    return s
  }

  function sanitizeBots(arr) {
    var out = []
    if (!arr || arr.length === undefined)
      return out
    var n = Math.min(arr.length, root.maxBots)
    for (var i = 0; i < n; i++) {
      var b = arr[i]
      if (!b || typeof b !== "object")
        continue
      var id = root.allowBotId(b.id)
      if (id === "")
        continue
      out.push({
        id: id,
        name: root.clip(b.name, 80),
        preview: root.clip(b.preview, 140),
        unread: b.unread === true,
        busy: b.busy === true,
        activity: root.clip(b.activity, 40),
        when: root.clip(b.when, 16),
        color: root.clip(b.color, 24),
        group: b.group === true
      })
    }
    return out
  }

  // Bar click is delivered twice (slot triggerPress + button MouseArea) and
  // the opening click can also hit KeyboardPanel's dismiss overlay. One
  // delayed toggle survives both.
  Timer {
    id: openTimer
    interval: 40
    onTriggered: {
      root.toggle()
      if (root.opened) root.refresh()
    }
  }

  function triggerPress(button) {
    openTimer.restart()
  }

  function launchBot(id) {
    var cmd = root.cliBin
    var app = root.appId
    var bot = root.allowBotId(id)
    if (cmd === "" || app === "" || bot === "")
      return
    if (launchProc.running)
      return
    // argv only — never bar.run() / shell concatenation
    launchProc.command = ["omarchy-launch-or-focus-tui", "--app-id=" + app, cmd, "open", bot]
    launchTimeout.restart()
    launchProc.running = true
  }

  function refresh() {
    if (inboxFile.path !== "")
      inboxFile.reload()
  }

  function applyInbox(text) {
    root.refreshing = false
    root.lastError = ""
    if (String(text || "").length > root.maxInboxBytes) {
      root.hasClient = false
      root.bots = []
      root.lastError = "inbox snapshot too large"
      return
    }
    try {
      var data = JSON.parse(text)
      if (!data || data.ok !== true || data.client !== "grokbot-tui") {
        root.hasClient = false
        root.bots = []
        root.lastError = "Not a grokbot-tui inbox snapshot"
        return
      }
      root.hasClient = true
      root.bots = root.sanitizeBots(data.bots)
    } catch (e) {
      root.hasClient = false
      root.bots = []
      root.lastError = "Could not read inbox"
    }
  }

  FileView {
    id: inboxFile
    path: root.inboxPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyInbox(text())
    onFileChanged: inboxFile.reload()
    onLoadFailed: {
      root.refreshing = false
      root.hasClient = false
      root.bots = []
      root.lastError = ""
    }
  }

  Process {
    command: root.homeDir !== "" ? ["test", "-x", root.homeDir + "/.local/bin/grokbot-tui"] : ["false"]
    running: true
    onExited: function(code) { root.localBinOk = code === 0 }
  }

  Process {
    command: root.homeDir !== "" ? ["test", "-x", root.homeDir + "/.cargo/bin/grokbot-tui"] : ["false"]
    running: true
    onExited: function(code) { root.cargoBinOk = code === 0 }
  }

  Timer {
    id: launchTimeout
    interval: 8000
    onTriggered: {
      if (launchProc.running)
        launchProc.signal(15)
    }
  }

  Process {
    id: launchProc
    running: false
    onStarted: launchTimeout.restart()
    onExited: function() { launchTimeout.stop() }
  }

  IpcHandler {
    target: "pixbroker.grokbot"
    function open(): void { root.open(); root.refresh() }
    function close(): void { root.close() }
    function show(): void { root.open(); root.refresh() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle(); if (root.opened) root.refresh() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.lively
      ? (root.unreadCount > 0 ? (root.unreadCount + " unread") : "Bot working")
      : "Grok Bot — idle"
    iconComponent: Component {
      Face {
        iconSize: Style.bar.iconCanvas
        lively: root.lively
        holeColor: Color.bar.background
      }
    }
    onPressed: function(buttonCode) {
      openTimer.restart()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: 380
    contentHeight: 420

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        anchors.fill: parent
        spacing: 0

        Item {
          width: parent.width
          height: Style.space(40)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: unreadCount > 0 ? ("Bots · " + unreadCount + " unread") : "Bots"
            color: foreground
            font.family: fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: refreshing ? "..." : "reload"
            color: dim
            font.family: fontFamily
            font.pixelSize: Style.font.caption
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: root.refresh()
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
        }

        Flickable {
          width: parent.width
          height: parent.height - Style.space(40) - 1
          clip: true
          contentWidth: width
          contentHeight: listCol.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: listCol
            width: parent.width

            Text {
              visible: !refreshing && bots.length === 0
              width: parent.width
              padding: Style.space(18)
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.body
              textFormat: Text.PlainText
              text: root.emptyText()
            }

            Repeater {
              model: bots

              Item {
                id: row
                required property var modelData
                width: listCol.width
                height: root.rowH

                Rectangle {
                  anchors.fill: parent
                  color: rowMouse.containsMouse ? Style.selectedFillFor(foreground, Color.accent) : "transparent"
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.launchBot(String(row.modelData.id || ""))
                    root.close()
                  }
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(4)
                  anchors.rightMargin: Style.space(4)
                  spacing: Style.space(10)

                  Rectangle {
                    Layout.preferredWidth: Style.space(28)
                    Layout.preferredHeight: Style.space(28)
                    radius: width / 2
                    color: root.swatch(row.modelData.color)

                    Rectangle {
                      visible: row.modelData.unread === true
                      width: 7
                      height: 7
                      radius: 4
                      color: Color.urgent
                      anchors.right: parent.right
                      anchors.top: parent.top
                    }
                  }

                  Column {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                      width: parent.width
                      Text {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: String(row.modelData.name || "Bot")
                        elide: Text.ElideRight
                        color: foreground
                        font.family: fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: row.modelData.unread === true
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: String(row.modelData.when || "")
                        color: dim
                        font.family: fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: row.modelData.busy
                        ? String(row.modelData.activity || "Working")
                        : String(row.modelData.preview || "No messages yet")
                      elide: Text.ElideRight
                      color: row.modelData.busy ? Color.accent : dim
                      font.family: fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
