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
  property var sections: []
  property var counts: ({})
  property var appInfo: ({})
  property int schema: 1
  property real generatedAt: 0
  property string lastError: ""
  property bool refreshing: false
  property bool hasClient: false
  property bool demoMode: false
  property bool redact: false
  property int cursor: 0
  property int greetSeed: 0
  property var flourishDeck: []
  property int lastFlourish: -1

  signal greetRequested(bool everyone)
  signal barGreeted()

  readonly property var barMetrics: ["avatars", "count", "none"]
  property string barMetric: {
    var v = String(setting("barMetric", "avatars"))
    return barMetrics.indexOf(v) >= 0 ? v : "avatars"
  }
  readonly property var orderings: ["attention", "channels", "flat"]
  property string ordering: {
    var v = String(setting("ordering", "attention"))
    return orderings.indexOf(v) >= 0 ? v : "attention"
  }
  property bool groupBySection: String(setting("groupBySection", "true")) !== "false"
  readonly property int maxBarAvatars: Math.max(1, Math.min(6, Number(setting("maxBarAvatars", 3)) || 3))

  readonly property int unreadCount: Number((counts && counts.unread) || 0)
  readonly property int awaitingCount: Number((counts && counts.awaiting) || 0)
  readonly property int workingCount: Number((counts && counts.working) || 0)
  readonly property bool anyBusy: workingCount > 0
  readonly property bool lively: unreadCount > 0 || awaitingCount > 0 || anyBusy
  readonly property bool writerAlive: generatedAt > 0 && ((Date.now() / 1000) - generatedAt) < 120
  readonly property bool appRunning: appInfo && appInfo.running === true
  readonly property bool markDim: appInfo.running === false || (hasClient && !writerAlive && !demoMode)
  readonly property int rowH: Style.space(46)
  readonly property int listH: orderedRows.length === 0 ? Style.space(88) : Math.min(rowH * 8, rowH * orderedRows.length)
  readonly property int markSize: Math.round(Style.bar.iconCanvas * 0.82)
  readonly property int barAvatarSize: {
    var s = Math.round(Style.font.caption * 1.15)
    return (s % 2) === (markSize % 2) ? s : s + 1
  }
  readonly property int barPull: Style.space(3)

  readonly property var palette: ({
    red: "#FF263C", orange: "#FF6700", yellow: "#FF9800", green: "#00C972",
    cyan: "#00BCA6", blue: "#1084FE", violet: "#9159FE", magenta: "#FF309B",
    brown: "#936439", gray: "#777777"
  })

  readonly property var orderedRows: root.orderRows()
  readonly property var barBots: root.wantedForBar()

  implicitWidth: Math.max(Style.bar.iconCanvas, barRow.implicitWidth)
  implicitHeight: button.implicitHeight
  readonly property real openPanelIndicatorWidth: barRow.width
  // Combined bar-widget+panel: this root *is* the slot identity PluginBarApi
  // registers. Nested-panel plugins must use hostWidget instead.
  readonly property var barIdentity: root

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  property bool openedFromHotkey: false

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) close()
    else openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

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
      return "no bots in the roster yet"
    return "start the snapshot writer (grokbot-tui inbox --local --watch) to see your bots"
  }

  function cycleBarMetric(persist) {
    barMetric = barMetrics[(barMetrics.indexOf(barMetric) + 1) % barMetrics.length]
    if (persist !== false)
      Quickshell.execDetached(["omarchy", "bar", "set", "pixbroker.grokbot", "barMetric", barMetric])
  }

  function cycleOrdering(persist) {
    ordering = orderings[(orderings.indexOf(ordering) + 1) % orderings.length]
    cursor = firstBotRow()
    if (persist !== false)
      Quickshell.execDetached(["omarchy", "bar", "set", "pixbroker.grokbot", "ordering", ordering])
  }

  function toggleGrouping() {
    groupBySection = !groupBySection
    cursor = firstBotRow()
    Quickshell.execDetached(["omarchy", "bar", "set", "pixbroker.grokbot", "groupBySection", groupBySection ? "true" : "false"])
  }

  function botFill(b) {
    if (b && typeof b.hex === "string" && b.hex.charAt(0) === "#")
      return b.hex
    var n = String((b && b.color) || "").toLowerCase()
    return palette[n] || "#777777"
  }

  function botImage(b) {
    var p = b && b.avatar ? String(b.avatar) : ""
    if (p === "" || p.indexOf("..") >= 0)
      return ""
    if (p.indexOf("file://") === 0)
      return p
    if (p.charAt(0) === "/")
      return "file://" + p
    return ""
  }

  function botFace(b) {
    if (!b) return "neutral"
    if (b.awaiting) return "attentive"
    var n = Number(b.unreadCount || 0)
    if (n > 1) return "excited"
    if (n === 1 || b.unread) return "curious"
    if (b.updatedAt && (Date.now() - Number(b.updatedAt)) > 7 * 24 * 3600 * 1000)
      return "drowsy"
    return "neutral"
  }

  function botNews(b) {
    return !!(b && (b.awaiting || b.unread || Number(b.unreadCount || 0) > 0))
  }

  function noise(text) {
    var glyphs = "░▒▓█▓▒"
    var h = 2166136261
    text = String(text || "")
    for (var i = 0; i < text.length; i++) {
      h = h ^ text.charCodeAt(i)
      h = ((h * 16777619) >>> 0)
    }
    var out = ""
    for (var j = 0; j < text.length; j++) {
      if (text.charAt(j) === " ") {
        out += " "
        continue
      }
      h = (h ^ ((h << 13) >>> 0)) >>> 0
      h = (h ^ (h >>> 17)) >>> 0
      h = (h ^ ((h << 5) >>> 0)) >>> 0
      out += glyphs.charAt(h % 6)
    }
    return out
  }

  function show(s) {
    return root.redact ? root.noise(s) : String(s || "")
  }

  function headerTitle() {
    if (demoMode)
      return "GROK BOT · demo roster"
    if (appInfo.running === false)
      return "GROK BOT · not running"
    var v = appInfo && appInfo.version ? String(appInfo.version) : ""
    return v !== "" ? ("GROK BOT " + v) : "GROK BOT"
  }

  function countsLine() {
    var parts = []
    var n = Number((counts && counts.bots) || bots.length)
    if (n) parts.push(n + " bots")
    if (awaitingCount) parts.push(awaitingCount + " waiting on you")
    if (workingCount) parts.push(workingCount + " working")
    if (unreadCount) parts.push(unreadCount + " unread")
    var g = Number((counts && counts.groups) || 0)
    if (g) parts.push(g + " groups")
    return parts.join(" · ")
  }

  function wantedForBar() {
    var wanted = []
    for (var i = 0; i < bots.length; i++) {
      if (root.botNews(bots[i]) || (bots[i] && bots[i].busy))
        wanted.push(bots[i])
    }
    wanted.sort(function(a, b) {
      function rank(x) {
        if (x.awaiting) return 0
        if (x.busy) return 1
        if (x.unread || Number(x.unreadCount || 0) > 0) return 2
        return 3
      }
      var d = rank(a) - rank(b)
      if (d !== 0) return d
      return Number(b.updatedAt || 0) - Number(a.updatedAt || 0)
    })
    var out = []
    for (var j = 0; j < wanted.length && j < root.maxBarAvatars; j++)
      out.push(wanted[j])
    return out
  }

  function findBot(id) {
    for (var i = 0; i < bots.length; i++)
      if (bots[i].id === id) return bots[i]
    return null
  }

  function orderRows() {
    var rows = []
    if (!bots.length)
      return rows
    if (ordering === "channels" && sections && sections.length) {
      for (var s = 0; s < sections.length; s++) {
        var sec = sections[s]
        var ids = sec.botIds || []
        if (ids.length === 0)
          continue
        if (root.groupBySection)
          rows.push({ kind: "section", id: sec.id, name: sec.name, count: ids.length })
        for (var i = 0; i < ids.length; i++) {
          var bot = root.findBot(ids[i])
          if (bot) rows.push({ kind: "bot", bot: bot })
        }
      }
      return rows
    }
    if (ordering === "attention") {
      var want = []
      var rest = []
      for (var a = 0; a < bots.length; a++) {
        if (root.botNews(bots[a])) want.push(bots[a])
        else rest.push(bots[a])
      }
      want.sort(function(x, y) { return Number(x.updatedAt || 0) - Number(y.updatedAt || 0) })
      rest.sort(function(x, y) { return Number(y.updatedAt || 0) - Number(x.updatedAt || 0) })
      for (var w = 0; w < want.length; w++) rows.push({ kind: "bot", bot: want[w] })
      if (want.length && rest.length)
        rows.push({ kind: "rule" })
      for (var r = 0; r < rest.length; r++) rows.push({ kind: "bot", bot: rest[r] })
      return rows
    }
    var flat = []
    for (var f = 0; f < bots.length; f++) flat.push(bots[f])
    flat.sort(function(x, y) { return Number(y.updatedAt || 0) - Number(x.updatedAt || 0) })
    for (var k = 0; k < flat.length; k++) rows.push({ kind: "bot", bot: flat[k] })
    return rows
  }

  function firstBotRow() {
    for (var i = 0; i < orderedRows.length; i++)
      if (orderedRows[i].kind === "bot") return i
    return 0
  }

  function moveCursor(delta) {
    var idxs = []
    for (var i = 0; i < orderedRows.length; i++)
      if (orderedRows[i].kind === "bot") idxs.push(i)
    if (!idxs.length) return
    var at = idxs.indexOf(cursor)
    if (at < 0) { cursor = idxs[0]; return }
    cursor = idxs[Math.max(0, Math.min(idxs.length - 1, at + delta))]
  }

  function dealFlourishes() {
    var deck = []
    for (var i = 0; i < 6; i++) deck.push(i)
    for (var j = deck.length - 1; j > 0; j--) {
      var k = Math.floor(Math.random() * (j + 1))
      var t = deck[j]; deck[j] = deck[k]; deck[k] = t
    }
    if (deck.length > 1 && deck[deck.length - 1] === lastFlourish) {
      var swap = deck[0]; deck[0] = deck[deck.length - 1]; deck[deck.length - 1] = swap
    }
    flourishDeck = deck
  }

  function nextFlourish() {
    if (!flourishDeck || flourishDeck.length === 0)
      dealFlourishes()
    var deck = flourishDeck.slice()
    var pick = deck.pop()
    flourishDeck = deck
    lastFlourish = pick
    return pick
  }

  function requestGreeting(everyone) {
    dealFlourishes()
    greetSeed += 1
    greetOnOpen.greetEveryone = !!everyone
    greetOnOpen.restart()
  }

  function fmtAgoMins(mins) {
    var s = mins * 60
    if (s < 90) return "now"
    if (mins < 60) return mins + "m"
    var h = Math.floor(mins / 60)
    if (h < 24) return h + "h"
    var d = Math.floor(h / 24)
    return d < 7 ? (d + "d") : (Math.floor(d / 7) + "w")
  }

  function demoBot(id, name, title, shape, color, hex, unread, awaiting, mins, text, now) {
    return {
      id: id, name: name, title: title, preview: text,
      unread: unread > 0, unreadCount: unread, awaiting: awaiting, busy: false,
      when: root.fmtAgoMins(mins),
      color: color, hex: hex, shape: shape, updatedAt: now - mins * 60000
    }
  }

  function toggleDemo() {
    demoMode = !demoMode
    cursor = 0
    if (demoMode) {
      var now = Date.now()
      var d = function(id, name, title, shape, color, hex, unread, awaiting, mins, text) {
        return root.demoBot(id, name, title, shape, color, hex, unread, awaiting, mins, text, now)
      }
      bots = root.sanitizeBots([
        d("d1", "Chief of Staff", "Operations", "squircle", "red", "#FF263C", 0, true, 34, "Your Thursday is triple-booked. Shall I move the Vercel sync to Friday?"),
        d("d2", "Account Health", "Customer Success", "hex", "violet", "#9159FE", 3, false, 12, "Northwind's ingest dropped 60% this week - worth a call before renewal."),
        d("d3", "Bug Reproduction", "Engineering", "gem", "orange", "#FF6700", 1, false, 5, "Reproduced #4812 on Firefox only. Trace and a failing test are attached."),
        d("d4", "Sales Outbound", "Revenue", "tablet", "green", "#00C972", 0, false, 88, "42 accounts scored overnight; 9 drafts are waiting for your voice check."),
        d("d5", "Expense Manager", "Finance", "capsule", "cyan", "#00BCA6", 0, false, 210, "August close is done. Two receipts still missing from the Berlin trip."),
        d("d6", "Talent Scout", "People", "leaf", "yellow", "#FF9800", 0, false, 400, "Shortlisted 6 for the platform role. Two have Rust plus Wayland experience."),
        d("d7", "Paid Media", "Growth", "shield", "blue", "#1084FE", 0, false, 1500, "CAC is flat at $180. I paused the two worst ad groups."),
        d("d8", "Release Notes", "Engineering", "pebble", "cyan", "#00BCA6", 0, false, 46, "0.42 is tagged. Draft covers the scrolling layout and two crash fixes."),
        d("d9", "Inbox Triage", "Operations", "arch", "gray", "#777777", 0, false, 150, "Cleared 214 overnight. Four need you: all of them are contracts."),
        d("d10", "Competitor Watch", "Strategy", "crystal", "blue", "#1084FE", 0, false, 700, "Two pricing pages changed this week. Both moved usage under a seat minimum."),
        d("p1", "Trip Planner", "Personal", "cloud", "magenta", "#FF309B", 0, false, 2600, "Held two flights to Lisbon for March. Neither needs paying until Friday."),
        d("p2", "Reading Pile", "Personal", "teardrop", "brown", "#936439", 0, false, 11000, "Six saved articles this week. Two are the same paper with different headlines."),
        d("p3", "Home Lab", "Personal", "dome", "green", "#00C972", 0, false, 3400, "The NAS finished its scrub with no errors. Backups are four days behind."),
        d("p4", "Recipe Box", "Personal", "bean", "orange", "#FF6700", 0, false, 20000, "Saved the miso aubergine one. It wants an hour you have not had lately.")
      ])
      counts = { bots: 14, awaiting: 1, working: 0, unread: 2, unreadMessages: 4, groups: 0 }
      sections = [
        { id: "ACME", name: "ACME", botIds: ["d1", "d2", "d3", "d4", "d5", "d6", "d7", "d8", "d9", "d10"] },
        { id: "Personal", name: "Personal", botIds: ["p1", "p2", "p3", "p4"] }
      ]
      hasClient = true
      generatedAt = Date.now() / 1000
      appInfo = { running: true, version: "demo" }
      lastError = ""
      requestGreeting(false)
    } else {
      refresh()
    }
  }

  function launchTui() {
    var cmd = root.cliBin
    var app = root.appId
    if (cmd === "" || app === "" || launchProc.running)
      return
    launchProc.command = ["omarchy-launch-or-focus-tui", "--app-id=" + app, cmd]
    launchTimeout.restart()
    launchProc.running = true
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
      var avatar = String(b.avatar || "")
      if (avatar.indexOf("..") >= 0 || (avatar !== "" && avatar.charAt(0) !== "/"))
        avatar = ""
      var unreadCount = Math.max(0, Number(b.unreadCount || 0) || 0)
      out.push({
        id: id,
        name: root.clip(b.name, 80),
        title: root.clip(b.title, 80),
        preview: root.clip(b.preview, 140),
        unread: b.unread === true || unreadCount > 0,
        unreadCount: unreadCount,
        awaiting: b.awaiting === true,
        busy: b.busy === true,
        activity: root.clip(b.activity, 40),
        when: root.clip(b.when, 16),
        color: root.clip(b.color, 24),
        hex: root.clip(b.hex, 16),
        shape: root.clip(b.shape, 24) || "squircle",
        avatar: avatar,
        group: b.group === true,
        members: Math.max(0, Number(b.members || 0) || 0),
        focused: b.focused === true,
        pinned: b.pinned === true,
        updatedAt: Number(b.updatedAt || 0) || 0
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
      if (root.opened) {
        if (!root.demoMode)
          root.refresh()
        root.requestGreeting(false)
      }
    }
  }

  Timer {
    id: greetOnOpen
    interval: 260
    property bool greetEveryone: false
    onTriggered: root.greetRequested(greetEveryone)
  }

  function triggerPress(button) {
    openTimer.restart()
  }

  function barPressed(buttonCode) {
    if (buttonCode === Qt.MiddleButton) {
      root.cycleBarMetric()
      return
    }
    if (buttonCode === Qt.RightButton) {
      root.launchTui()
      return
    }
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
    if (root.demoMode)
      return
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
      root.schema = Number(data.schema || 1) || 1
      root.generatedAt = Number(data.generatedAt || 0) || 0
      root.appInfo = data.app && typeof data.app === "object" ? data.app : {}
      root.counts = data.counts && typeof data.counts === "object" ? data.counts : {}
      root.sections = Array.isArray(data.sections) ? data.sections : []
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
    // Measuring copies must not steal the IPC name from the mounted widget.
    enabled: root.bar !== null
    target: "pixbroker.grokbot"
    function open(): void { root.open(); if (!root.demoMode) root.refresh(); root.requestGreeting(false) }
    function close(): void { root.close() }
    function show(): void { root.open(); if (!root.demoMode) root.refresh(); root.requestGreeting(false) }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle(); if (root.opened) { if (!root.demoMode) root.refresh(); root.requestGreeting(false) } }
    function refresh(): string { root.refresh(); return "ok" }
    function scrub(): string { root.redact = !root.redact; return root.redact ? "scrubbed" : "clear" }
    function group(): string { root.cycleOrdering(false); return root.ordering }
    function order(mode: string): string {
      if (root.orderings.indexOf(mode) >= 0) root.ordering = mode
      else root.cycleOrdering(false)
      root.cursor = root.firstBotRow()
      return root.ordering
    }
    function demo(): string {
      root.toggleDemo()
      if (root.demoMode && !root.opened) root.open()
      return root.demoMode ? "demo roster" : "live roster"
    }
    function greet(): string {
      if (!root.opened) root.open()
      root.requestGreeting(true)
      root.greetSeed += 1
      root.barGreeted()
      return "greeting"
    }
    function geometry(): string {
      var origin = panel.cardOrigin || { x: 0, y: 0 }
      return JSON.stringify({ x: origin.x, y: origin.y, w: panel.contentWidth, h: panel.contentHeight })
    }
    function metric(): string { root.cycleBarMetric(false); return root.barMetric }
    function look(x: int, y: int): string { keyCatcher.pointerAt(x, y); return x + "," + y }
    function away(): string { keyCatcher.pointerGone(); return "away" }
    function state(): string {
      return JSON.stringify({ counts: root.counts, app: root.appInfo, bots: root.bots.length })
    }
  }

  Row {
    id: barRow
    anchors.centerIn: parent
    spacing: -root.barPull

    BarIconButton {
      id: button
      bar: root.bar
      tooltipText: {
        var line = root.countsLine()
        var ver = root.appInfo && root.appInfo.version ? ("Grok Bot v" + root.appInfo.version) : "Grok Bot"
        return line !== "" ? (line + " · " + ver) : ver
      }
      iconComponent: Component {
        Avatar {
          width: root.markSize
          height: root.markSize
          anchors.centerIn: parent
          shape: "squircle"
          fill: root.foreground
          outlined: true
          cutoutEyes: true
          animate: false
          opacity: root.markDim ? 0.45 : 1
        }
      }
      onPressed: function(buttonCode) { root.barPressed(buttonCode) }
    }

    Repeater {
      model: root.barMetric === "avatars" ? root.barBots : []
      Avatar {
        id: barAvatar
        required property var modelData
        required property int index
        width: root.barAvatarSize
        height: root.barAvatarSize
        anchors.verticalCenter: parent.verticalCenter
        shape: modelData.shape || "squircle"
        fill: root.botFill(modelData)
        face: root.botFace(modelData)
        image: root.botImage(modelData)
        animate: true
        looking: barHover.containsMouse
        followX: width / 2
        followY: -height
        Connections {
          target: root
          function onBarGreeted() { barGreet.restart() }
        }
        Timer {
          id: barGreet
          interval: 30 + barAvatar.index * 90
          onTriggered: barAvatar.playBold(barAvatar.index + root.greetSeed)
        }
      }
    }

    Text {
      visible: root.barMetric === "count" && (root.awaitingCount + root.unreadCount + root.workingCount) > 0
      anchors.verticalCenter: parent.verticalCenter
      text: String(root.awaitingCount + root.unreadCount + root.workingCount)
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  MouseArea {
    id: barHover
    anchors.fill: barRow
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: function(mouse) { root.barPressed(mouse.button) }
    onEntered: {
      root.greetSeed += 1
      root.barGreeted()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: 420
    contentHeight: 460

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      property real pointerX: -1
      property real pointerY: -1

      function pointerAt(x, y) {
        pointerLeave.stop()
        pointerX = x
        pointerY = y
      }
      function pointerGone() { pointerLeave.restart() }

      Timer {
        id: pointerLeave
        interval: 260
        onTriggered: { keyCatcher.pointerX = -1; keyCatcher.pointerY = -1 }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        onPositionChanged: function(mouse) { keyCatcher.pointerAt(mouse.x, mouse.y) }
        onExited: keyCatcher.pointerGone()
      }

      Keys.onPressed: function(ev) {
        if (ev.key === Qt.Key_J || ev.key === Qt.Key_Down) {
          root.moveCursor(1)
          ev.accepted = true
        } else if (ev.key === Qt.Key_K || ev.key === Qt.Key_Up) {
          root.moveCursor(-1)
          ev.accepted = true
        } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
          var row = root.orderedRows[root.cursor]
          if (row && row.kind === "bot") {
            root.launchBot(row.bot.id)
            root.close()
          }
          ev.accepted = true
        } else if (ev.key === Qt.Key_G) {
          root.cycleOrdering()
          ev.accepted = true
        } else if (ev.key === Qt.Key_H) {
          root.redact = !root.redact
          ev.accepted = true
        } else if (ev.key === Qt.Key_R) {
          root.cycleBarMetric()
          ev.accepted = true
        }
      }

      Column {
        anchors.fill: parent
        spacing: 0

        Item {
          width: parent.width
          height: Style.space(40)

          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
              textFormat: Text.PlainText
              text: root.headerTitle()
              color: foreground
              font.family: fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              visible: root.countsLine() !== ""
              textFormat: Text.PlainText
              text: root.countsLine()
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
            }
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
              model: root.orderedRows

              Item {
                id: row
                required property var modelData
                required property int index
                width: listCol.width
                height: modelData.kind === "bot" ? root.rowH
                      : modelData.kind === "rule" ? Style.space(13) : Style.space(26)

                Rectangle {
                  visible: modelData.kind === "rule"
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  height: 2
                  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.34)
                }

                Text {
                  visible: modelData.kind === "section"
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(4)
                  anchors.leftMargin: Style.space(8)
                  textFormat: Text.PlainText
                  text: root.show(modelData.name || "").toUpperCase() + (modelData.count ? ("  " + modelData.count) : "")
                  color: dim
                  font.family: fontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  visible: modelData.kind === "bot"
                  anchors.fill: parent
                  color: (rowMouse.containsMouse || root.cursor === row.index)
                    ? Style.selectedFillFor(foreground, Color.accent)
                    : "transparent"
                }

                MouseArea {
                  id: rowMouse
                  visible: modelData.kind === "bot"
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.launchBot(String(row.modelData.bot.id || ""))
                    root.close()
                  }
                  onEntered: {
                    root.cursor = row.index
                    var p = mapToItem(keyCatcher, mouseX, mouseY)
                    keyCatcher.pointerAt(p.x, p.y)
                  }
                  onExited: keyCatcher.pointerGone()
                  onPositionChanged: {
                    var p = mapToItem(keyCatcher, mouseX, mouseY)
                    keyCatcher.pointerAt(p.x, p.y)
                  }
                }

                RowLayout {
                  visible: modelData.kind === "bot"
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(9)

                  Avatar {
                    id: face
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    shape: (row.modelData.bot && row.modelData.bot.shape) || "squircle"
                    fill: root.botFill(row.modelData.bot)
                    face: root.botFace(row.modelData.bot)
                    image: root.botImage(row.modelData.bot)
                    readonly property point look: mapFromItem(keyCatcher, keyCatcher.pointerX, keyCatcher.pointerY)
                    looking: keyCatcher.pointerX >= 0
                    followX: look.x
                    followY: look.y
                    property bool wasWanted: false
                    onFaceChanged: {
                      var wants = face === "attentive" || face === "excited" || face === "curious"
                      if (wants) wasWanted = true
                      else if (wasWanted) { wasWanted = false; celebrate() }
                    }
                    Connections {
                      target: root
                      function onGreetRequested(everyone) {
                        if (row.modelData.kind !== "bot") return
                        if (everyone || root.botNews(row.modelData.bot)) {
                          greetDelay.interval = 60 + 85 * row.index
                          greetDelay.start()
                        }
                      }
                    }
                    Timer {
                      id: greetDelay
                      repeat: false
                      onTriggered: face.play(root.nextFlourish())
                    }
                  }

                  Column {
                    Layout.fillWidth: true
                    spacing: 1

                    RowLayout {
                      width: parent.width
                      Text {
                        textFormat: Text.PlainText
                        text: root.show((row.modelData.bot && row.modelData.bot.name) || "Bot")
                        elide: Text.ElideRight
                        color: (row.modelData.bot && row.modelData.bot.focused) ? Color.accent : foreground
                        font.family: fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: root.botNews(row.modelData.bot)
                      }
                      Text {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: {
                          var b = row.modelData.bot
                          if (!b) return ""
                          return b.group ? ("group of " + b.members) : root.show(b.title || "")
                        }
                        elide: Text.ElideRight
                        color: dim
                        font.family: fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: {
                        var b = row.modelData.bot
                        if (!b) return ""
                        if (b.busy) return "thinking…"
                        return root.show(b.preview || "")
                      }
                      elide: Text.ElideRight
                      color: {
                        var b = row.modelData.bot
                        if (b && b.busy) return Color.accent
                        if (b && b.awaiting) return foreground
                        return dim
                      }
                      font.family: fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Column {
                    Layout.preferredWidth: 38
                    spacing: 2
                    Text {
                      anchors.right: parent.right
                      textFormat: Text.PlainText
                      text: String((row.modelData.bot && row.modelData.bot.when) || "")
                      color: dim
                      font.family: fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Rectangle {
                      anchors.right: parent.right
                      visible: row.modelData.bot && Number(row.modelData.bot.unreadCount || 0) > 0
                      implicitHeight: Style.font.caption + 4
                      implicitWidth: Math.max(14, pillText.implicitWidth + 6)
                      radius: height / 2
                      color: Color.accent
                      Text {
                        id: pillText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: String(row.modelData.bot.unreadCount)
                        color: Color.background
                        font.family: fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              padding: Style.space(10)
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
              text: "j/k move · Enter open · g order · h redact · r metric · Esc close"
            }
          }
        }
      }
    }
  }
}
