import QtQuick
import QtQuick.Controls
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
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.45)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.20)
  readonly property color divider: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.34)
  readonly property color hilite: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.09)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color eyeInk: Color.background
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

  // ---------------------------------------------------------------- settings
  property string barMetric: {
    var v = String(setting("barMetric", "avatars"))
    return barMetrics.indexOf(v) >= 0 ? v : "avatars"
  }
  readonly property var barMetrics: ["avatars", "count", "none"]
  // persist=false is session-only: writing the bar entry reloads the widget
  // and would drop the in-memory demo roster.
  function cycleBarMetric(persist) {
    barMetric = barMetrics[(barMetrics.indexOf(barMetric) + 1) % barMetrics.length]
    if (persist !== false)
      Quickshell.execDetached(["omarchy", "bar", "set", "pixbroker.grokbot", "barMetric", barMetric])
  }

  property string ordering: {
    var v = String(setting("ordering", "attention"))
    return orderings.indexOf(v) >= 0 ? v : "attention"
  }
  readonly property var orderings: ["attention", "channels", "flat"]
  function cycleOrdering() {
    ordering = orderings[(orderings.indexOf(ordering) + 1) % orderings.length]
    Quickshell.execDetached(["omarchy", "bar", "set", "pixbroker.grokbot", "ordering", ordering])
    cursor = 0
  }
  property bool groupBySection: String(setting("groupBySection", "true")) !== "false"
  function toggleGrouping() {
    groupBySection = !groupBySection
    Quickshell.execDetached(["omarchy", "bar", "set", "pixbroker.grokbot", "groupBySection", groupBySection ? "true" : "false"])
  }

  readonly property int maxBarAvatars: {
    var n = Math.floor(Number(setting("maxBarAvatars", 3)))
    if (!(n >= 1 && n <= 6)) n = 3
    return n
  }

  readonly property var palette: ({
    "red": "#FF263C", "orange": "#FF6700", "yellow": "#FF9800", "green": "#00C972",
    "cyan": "#00BCA6", "blue": "#1084FE", "violet": "#9159FE", "magenta": "#FF309B",
    "brown": "#936439", "gray": "#777777"
  })
  readonly property var shapes: ["circle", "egg", "capsule", "cylinder", "tablet", "squircle", "hex", "gem", "crystal", "wedge", "shield", "dome", "arch", "bean", "pebble", "cloud", "teardrop", "leaf", "group", "blob"]

  // ---------------------------------------------------------------- snapshot
  property var liveSnap: null
  property double inboxSeenAt: 0
  property string lastError: ""
  readonly property var snap: demoMode ? demoSnap : liveSnap
  property bool demoMode: false
  property double demoStart: 0
  property bool scrub: false
  property int cursor: 0
  property double nowMs: Date.now()
  property int lastBarButton: Qt.LeftButton

  readonly property var counts: snap && snap.counts ? snap.counts : ({})
  readonly property var bots: snap && snap.bots ? snap.bots : []
  readonly property var sections: snap && snap.sections ? snap.sections : []
  readonly property var app: snap && snap.app ? snap.app : ({})
  readonly property int schema: snap && snap.schema ? snap.schema : 1
  readonly property bool alarming: (counts.awaiting || 0) > 0
  readonly property bool attention: alarming || (counts.unread || 0) > 0
  readonly property bool anyBusy: {
    root.nowMs
    for (var i = 0; i < bots.length; i++)
      if (root.isWorking(bots[i])) return true
    return false
  }
  readonly property bool lively: attention || anyBusy

  readonly property var demoSnap: {
    var origin = root.demoStart > 0 ? root.demoStart : Date.now()
    var bot = function(id, name, title, shape, color, unread, awaiting, mins, text) {
      var hex = root.palette[color] || "#777777"
      return {
        id: id, name: name, title: title, preview: text, unread: unread > 0,
        unreadCount: unread, awaiting: awaiting, busy: false, workingSinceMs: 0,
        activity: "", updatedAtMs: origin - mins * 60000, when: "", color: color,
        hex: hex, shape: shape, avatar: "", group: false, members: 0,
        muted: false, focused: false, pinned: false
      }
    }
    var bots = [
      bot("d1", "Chief of Staff", "Operations", "squircle", "red", 0, true, 34,
          "Your Thursday is triple-booked. Shall I move the Vercel sync to Friday?"),
      bot("d2", "Account Health", "Customer Success", "hex", "violet", 3, false, 12,
          "Northwind's ingest dropped 60% this week - worth a call before renewal."),
      bot("d3", "Bug Reproduction", "Engineering", "gem", "orange", 1, false, 5,
          "Reproduced #4812 on Firefox only. Trace and a failing test are attached."),
      bot("d4", "Sales Outbound", "Revenue", "tablet", "green", 0, false, 88,
          "42 accounts scored overnight; 9 drafts are waiting for your voice check."),
      bot("d5", "Expense Manager", "Finance", "capsule", "cyan", 0, false, 210,
          "August close is done. Two receipts still missing from the Berlin trip."),
      bot("d6", "Talent Scout", "People", "leaf", "yellow", 0, false, 400,
          "Shortlisted 6 for the platform role. Two have Rust plus Wayland experience."),
      bot("d7", "Paid Media", "Growth", "shield", "blue", 0, false, 1500,
          "CAC is flat at $180. I paused the two worst ad groups."),
      bot("d8", "Release Notes", "Engineering", "pebble", "cyan", 0, false, 46,
          "0.42 is tagged. Draft covers the scrolling layout and two crash fixes."),
      bot("d9", "Inbox Triage", "Operations", "arch", "gray", 0, false, 150,
          "Cleared 214 overnight. Four need you: all of them are contracts."),
      bot("d10", "Competitor Watch", "Strategy", "crystal", "blue", 0, false, 700,
          "Two pricing pages changed this week. Both moved usage under a seat minimum."),
      bot("p1", "Trip Planner", "Personal", "cloud", "magenta", 0, false, 2600,
          "Held two flights to Lisbon for March. Neither needs paying until Friday."),
      bot("p2", "Reading Pile", "Personal", "teardrop", "brown", 0, false, 11000,
          "Six saved articles this week. Two are the same paper with different headlines."),
      bot("p3", "Home Lab", "Personal", "dome", "green", 0, false, 3400,
          "The NAS finished its scrub with no errors. Backups are four days behind."),
      bot("p4", "Recipe Box", "Personal", "bean", "orange", 0, false, 20000,
          "Saved the miso aubergine one. It wants an hour you have not had lately.")
    ]
    return {
      schema: 2,
      generatedAt: origin / 1000,
      app: { running: true, version: "0.35.0" },
      counts: { bots: bots.length, awaiting: 1, working: 0, unread: 2, unreadMessages: 4, groups: 0 },
      sections: [
        { id: "s1", name: "ACME", botIds: ["d1", "d2", "d3", "d4", "d5", "d6", "d7", "d8", "d9", "d10"] },
        { id: "s2", name: "Personal", botIds: ["p1", "p2", "p3", "p4"] }
      ],
      bots: bots
    }
  }

  function toggleDemo() {
    demoStart = Date.now()
    demoMode = !demoMode
    cursor = 0
    if (opened) requestGreeting(false)
  }

  readonly property var wanting: {
    root.nowMs
    var out = []
    for (var i = 0; i < bots.length; i++) {
      var b = bots[i]
      if (b.awaiting || root.isWorking(b) || b.unreadCount > 0) out.push(b)
    }
    var rank = function(x) { return x.awaiting ? 0 : (root.isWorking(x) ? 1 : 2) }
    out.sort(function(a, b) {
      if (rank(a) !== rank(b)) return rank(a) - rank(b)
      return (b.updatedAtMs || 0) - (a.updatedAtMs || 0)
    })
    return out
  }

  readonly property double staleAfterMs: 7 * 24 * 3600 * 1000
  function faceFor(b) {
    if (!b) return "neutral"
    if (b.awaiting) return "attentive"
    if (b.unreadCount > 1) return "excited"
    if (b.unreadCount > 0) return "curious"
    if (b.updatedAtMs && (nowMs - b.updatedAtMs) > staleAfterMs) return "drowsy"
    return "neutral"
  }
  function colorFor(b) {
    if (!b) return "#777777"
    if (b.hex) return b.hex
    var p = palette[String(b.color || "").toLowerCase()]
    return p ? p : "#777777"
  }
  function isWorking(b) {
    if (!b || !b.busy) return false
    var t = Number(b.workingSinceMs) || 0
    if (t > 0 && nowMs - t > 15 * 60 * 1000) return false
    return true
  }
  function avatarUrl(b) {
    if (!b || !b.avatar) return ""
    return "file://" + b.avatar
  }

  readonly property var rows: {
    var out = []
    if (!snap) return out
    if (ordering === "attention") {
      var wants = [], rest = []
      for (var b = 0; b < bots.length; b++) {
        var bot = bots[b]
        ;(bot.awaiting || bot.unreadCount > 0 ? wants : rest).push(bot)
      }
      wants.sort(function(x, y) { return (x.updatedAtMs || 0) - (y.updatedAtMs || 0) })
      rest.sort(function(x, y) { return (y.updatedAtMs || 0) - (x.updatedAtMs || 0) })
      for (var w = 0; w < wants.length; w++) out.push({ kind: "bot", bot: wants[w] })
      if (wants.length > 0 && rest.length > 0) out.push({ kind: "rule" })
      for (var r2 = 0; r2 < rest.length; r2++) out.push({ kind: "bot", bot: rest[r2] })
      return out
    }
    if (ordering === "channels" && sections.length > 0 && groupBySection) {
      var byId = ({})
      for (var i = 0; i < bots.length; i++) byId[bots[i].id] = bots[i]
      var seen = ({})
      for (var s = 0; s < sections.length; s++) {
        var ids = sections[s].botIds || []
        if (ids.length === 0) continue
        out.push({ kind: "section", name: sections[s].name, count: ids.length })
        for (var k = 0; k < ids.length; k++) {
          if (byId[ids[k]]) {
            out.push({ kind: "bot", bot: byId[ids[k]] })
            seen[ids[k]] = true
          }
        }
      }
      var leftover = []
      for (var u = 0; u < bots.length; u++) if (!seen[bots[u].id]) leftover.push(bots[u])
      if (leftover.length > 0) {
        leftover.sort(function(a, b) { return (b.updatedAtMs || 0) - (a.updatedAtMs || 0) })
        out.push({ kind: "section", name: "Unassigned", count: leftover.length })
        for (var L = 0; L < leftover.length; L++) out.push({ kind: "bot", bot: leftover[L] })
      }
      return out
    }
    var sorted = bots.slice().sort(function(a, b) {
      return (b.updatedAtMs || 0) - (a.updatedAtMs || 0)
    })
    for (var j = 0; j < sorted.length; j++) out.push({ kind: "bot", bot: sorted[j] })
    return out
  }
  readonly property var botRows: {
    var out = []
    for (var i = 0; i < rows.length; i++) if (rows[i].kind === "bot") out.push(i)
    return out
  }

  function snapAgeS() {
    if (demoMode) return 0
    var g = snap && snap.generatedAt ? Number(snap.generatedAt) : 0
    if (g > 0) {
      if (g > 1e11) g = g / 1000
      return nowMs / 1000 - g
    }
    if (inboxSeenAt > 0) return (nowMs - inboxSeenAt) / 1000
    return 0
  }
  readonly property bool markAlive: {
    root.nowMs
    if (demoMode) return true
    if (!snap) return false
    if (app.running === false) return false
    return snapAgeS() <= 120
  }

  Timer { interval: 15000; running: true; repeat: true; onTriggered: root.nowMs = Date.now() }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    cursor = 0
    panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    requestGreeting(false)
  }

  signal greetRequested(bool everyone)
  signal barGreeted()
  property int barGreetSeed: 0

  Timer {
    id: greetOnOpen
    interval: 260
    onTriggered: root.greetRequested(greetEveryone)
    property bool greetEveryone: false
  }
  function requestGreeting(everyone) {
    dealFlourishes()
    greetOnOpen.greetEveryone = !!everyone
    greetOnOpen.restart()
  }

  property var flourishDeck: []
  property int flourishCount: 6
  property int lastFlourish: -1
  function dealFlourishes() {
    var deck = []
    for (var i = 0; i < flourishCount; i++) deck.push(i)
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
    if (!flourishDeck || flourishDeck.length === 0) dealFlourishes()
    var deck = flourishDeck
    var pick = deck.pop()
    flourishDeck = deck
    lastFlourish = pick
    return pick
  }

  function emptyText() {
    if (lastError !== "")
      return lastError
    if (snap)
      return "no bots in the roster yet"
    return "start the snapshot writer (`grokbot-tui inbox --local --watch`) to see your bots"
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

  function allowHex(s) {
    s = String(s || "").trim()
    if (s.charAt(0) !== "#")
      return ""
    if (s.length !== 4 && s.length !== 7)
      return ""
    for (var i = 1; i < s.length; i++) {
      var ch = s.charAt(i)
      var ok = (ch >= "0" && ch <= "9") || (ch >= "A" && ch <= "F") || (ch >= "a" && ch <= "f")
      if (!ok)
        return ""
    }
    return s
  }

  function allowShape(s) {
    s = String(s || "").toLowerCase()
    return shapes.indexOf(s) >= 0 ? s : ""
  }

  function allowAvatarPath(s) {
    s = String(s || "").trim()
    if (s === "" || s.charAt(0) !== "/" || s.indexOf("..") >= 0)
      return ""
    if (root.homeDir === "" || s.substring(0, root.homeDir.length + 1) !== root.homeDir + "/")
      return ""
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i)
      var ok = (ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch === "." || ch === "_" || ch === "-" || ch === "/"
      if (!ok)
        return ""
    }
    var lower = s.toLowerCase()
    var okExt = false
    var exts = [".png", ".jpg", ".jpeg", ".webp"]
    for (var e = 0; e < exts.length; e++) {
      var ext = exts[e]
      if (lower.length >= ext.length && lower.substring(lower.length - ext.length) === ext) {
        okExt = true
        break
      }
    }
    return okExt ? s : ""
  }

  function asCount(v, cap) {
    var n = Math.floor(Number(v))
    if (!(n >= 0)) n = 0
    if (cap === undefined) cap = 9999
    return Math.min(n, cap)
  }

  function asMs(v) {
    var n = Number(v)
    if (!isFinite(n) || n <= 0) return 0
    if (n < 1e11) return n * 1000
    return n
  }

  function countsFromBots(list) {
    var awaiting = 0, working = 0, unread = 0, unreadMessages = 0, groups = 0
    for (var i = 0; i < list.length; i++) {
      var b = list[i]
      if (b.awaiting) awaiting++
      if (b.busy) working++
      if (b.unreadCount > 0) { unread++; unreadMessages += b.unreadCount }
      if (b.group) groups++
    }
    return { bots: list.length, awaiting: awaiting, working: working, unread: unread, unreadMessages: unreadMessages, groups: groups }
  }

  function sanitizeCounts(c, list) {
    if (!c || typeof c !== "object")
      return countsFromBots(list)
    return {
      bots: asCount(c.bots !== undefined ? c.bots : list.length, maxBots),
      awaiting: asCount(c.awaiting),
      working: asCount(c.working),
      unread: asCount(c.unread),
      unreadMessages: asCount(c.unreadMessages !== undefined ? c.unreadMessages : c.unread_messages),
      groups: asCount(c.groups)
    }
  }

  function sanitizeApp(a) {
    if (!a || typeof a !== "object")
      return ({})
    var out = ({})
    if (a.running === true) out.running = true
    else if (a.running === false) out.running = false
    var ver = clip(a.version, 24)
    if (ver !== "") out.version = ver
    return out
  }

  function sanitizeSections(arr) {
    var out = []
    if (!arr || arr.length === undefined)
      return out
    var n = Math.min(arr.length, 32)
    for (var i = 0; i < n; i++) {
      var s = arr[i]
      if (!s || typeof s !== "object")
        continue
      var id = allowIdent(s.id, 80)
      var name = clip(s.name, 80)
      var rawIds = s.botIds !== undefined ? s.botIds : s.bot_ids
      var botIds = []
      if (rawIds && rawIds.length !== undefined) {
        var m = Math.min(rawIds.length, maxBots)
        for (var k = 0; k < m; k++) {
          var bid = allowBotId(rawIds[k])
          if (bid !== "") botIds.push(bid)
        }
      }
      out.push({ id: id, name: name, botIds: botIds })
    }
    return out
  }

  function sanitizeBots(arr, schema2) {
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
      var unreadCount = asCount(b.unreadCount !== undefined ? b.unreadCount : b.unread_count, 999)
      if (unreadCount === 0 && b.unread === true)
        unreadCount = 1
      var shape = root.allowShape(b.shape)
      if (shape === "")
        shape = b.group === true ? "group" : (schema2 ? "squircle" : "circle")
      var busy = b.busy === true || b.working === true
      out.push({
        id: id,
        name: root.clip(b.name, 80),
        title: root.clip(b.title, 80),
        preview: root.clip(b.preview !== undefined ? b.preview : b.last_text, 140),
        unread: unreadCount > 0 || b.unread === true,
        unreadCount: unreadCount,
        awaiting: b.awaiting === true,
        busy: busy,
        workingSinceMs: root.asMs(b.workingSince !== undefined ? b.workingSince : b.working_since_ts),
        activity: root.clip(b.activity, 40),
        updatedAtMs: root.asMs(b.updatedAt !== undefined ? b.updatedAt : b.last_activity_ts),
        when: root.clip(b.when, 16),
        color: root.clip(b.color, 24),
        hex: root.allowHex(b.hex),
        shape: shape,
        avatar: root.allowAvatarPath(b.avatar),
        group: b.group === true || b.is_group === true,
        members: asCount(b.members, 999),
        muted: b.muted === true,
        focused: b.focused === true,
        pinned: b.pinned === true
      })
    }
    return out
  }

  // Bar click is delivered twice (slot triggerPress + button MouseArea) and
  // the opening click can also hit KeyboardPanel's dismiss overlay. One
  // delayed action survives both, including middle-click metric cycling.
  Timer {
    id: openTimer
    interval: 40
    onTriggered: {
      if (root.lastBarButton === Qt.RightButton)
        root.launchTui()
      else if (root.lastBarButton === Qt.MiddleButton)
        root.cycleBarMetric()
      else {
        root.toggle()
        if (root.opened) root.refresh()
      }
    }
  }

  function triggerPress(button) {
    root.barPressed(button === undefined || button === null ? Qt.LeftButton : button)
  }

  function barPressed(buttonCode) {
    root.lastBarButton = buttonCode
    openTimer.restart()
  }

  function launchArgv(extra) {
    var cmd = root.cliBin
    var app = root.appId
    if (cmd === "" || app === "")
      return
    if (launchProc.running)
      return
    var argv = ["omarchy-launch-or-focus-tui", "--app-id=" + app, cmd]
    if (extra && extra.length) {
      for (var i = 0; i < extra.length; i++)
        argv.push(extra[i])
    }
    // argv only — never bar.run() / shell concatenation
    launchProc.command = argv
    launchTimeout.restart()
    launchProc.running = true
  }

  function launchTui() {
    launchArgv([])
  }

  function launchBot(id) {
    var bot = root.allowBotId(id)
    if (bot === "")
      return
    launchArgv(["open", bot])
  }

  function activateRow() {
    if (cursor < 0 || cursor >= rows.length)
      return
    var row = rows[cursor]
    if (!row || row.kind !== "bot" || !row.bot)
      return
    root.launchBot(String(row.bot.id || ""))
    root.close()
  }

  function refresh() {
    if (inboxFile.path !== "")
      inboxFile.reload()
  }

  function applyInbox(text) {
    root.lastError = ""
    root.nowMs = Date.now()
    if (String(text || "").length > root.maxInboxBytes) {
      root.liveSnap = null
      root.lastError = "inbox snapshot too large"
      return
    }
    try {
      var data = JSON.parse(text)
      if (!data || data.ok !== true || data.client !== "grokbot-tui") {
        root.liveSnap = null
        root.lastError = "Not a grokbot-tui inbox snapshot"
        return
      }
      var schema = Math.floor(Number(data.schema) || 1)
      if (!(schema >= 1 && schema <= 9)) schema = 1
      var schema2 = schema >= 2
      var bots = root.sanitizeBots(data.bots, schema2)
      var generatedAt = Number(data.generatedAt)
      if (!isFinite(generatedAt) || generatedAt < 0) generatedAt = 0
      root.inboxSeenAt = Date.now()
      root.liveSnap = {
        schema: schema,
        generatedAt: generatedAt,
        app: root.sanitizeApp(data.app),
        counts: root.sanitizeCounts(data.counts, bots),
        sections: schema2 ? root.sanitizeSections(data.sections) : [],
        bots: bots
      }
    } catch (e) {
      root.liveSnap = null
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
      root.liveSnap = null
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
    // Omarchy instantiates a hidden measuring copy; only the mounted bar
    // copy should own the IPC name.
    enabled: root.bar !== null
    target: "pixbroker.grokbot"
    function open(): void { root.open(); root.refresh() }
    function close(): void { root.close() }
    function show(): void { root.open(); root.refresh() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle(); if (root.opened) root.refresh() }
    function refresh(): string { root.refresh(); return "ok" }
    function scrub(): string { root.scrub = !root.scrub; return root.scrub ? "scrubbed" : "clear" }
    function group(): string { root.cycleOrdering(); return root.ordering }
    function order(mode: string): string {
      var m = String(mode || "")
      if (root.orderings.indexOf(m) >= 0) root.ordering = m
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
      root.barGreetSeed += 1
      root.barGreeted()
      return "greeting"
    }
    function geometry(): string {
      return JSON.stringify({ x: panel.cardOrigin.x, y: panel.cardOrigin.y, w: panel.contentWidth, h: panel.contentHeight })
    }
    function metric(): string { root.cycleBarMetric(false); return root.barMetric }
    function look(x: int, y: int): string {
      keyCatcher.pointerAt(Number(x), Number(y))
      return x + "," + y
    }
    function away(): string { keyCatcher.pointerGone(); return "away" }
    function state(): string {
      return JSON.stringify({ counts: root.counts, app: root.app, bots: root.bots.length })
    }
  }

  function fmtAgo(ms) {
    if (!ms) return ""
    var s = Math.max(0, (nowMs - ms) / 1000)
    if (s < 90) return "now"
    var m = Math.floor(s / 60)
    if (m < 60) return m + "m"
    var h = Math.floor(m / 60)
    if (h < 24) return h + "h"
    var d = Math.floor(h / 24)
    return d < 7 ? d + "d" : Math.floor(d / 7) + "w"
  }
  function agoOf(b) {
    if (!b) return ""
    var a = fmtAgo(b.updatedAtMs)
    return a !== "" ? a : String(b.when || "")
  }
  function noise(text) {
    var glyphs = "░▒▓█▓▒", h = 2166136261, out = ""
    text = String(text || "")
    for (var i = 0; i < text.length; i++) { h ^= text.charCodeAt(i); h = (h * 16777619) >>> 0 }
    for (var j = 0; j < text.length; j++) {
      h ^= h << 13; h >>>= 0; h ^= h >>> 17; h ^= h << 5; h >>>= 0
      out += text.charAt(j) === " " ? " " : glyphs.charAt(h % glyphs.length)
    }
    return out
  }
  function label(text) { text = String(text || ""); return scrub ? noise(text) : text }

  function moveCursor(delta) {
    if (botRows.length === 0) return
    var at = botRows.indexOf(cursor)
    if (at < 0) { cursor = botRows[0]; return }
    cursor = botRows[Math.max(0, Math.min(botRows.length - 1, at + delta))]
    ensureVisible()
  }
  function ensureVisible() {
    var item = repeater.itemAt(cursor)
    if (!item) return
    if (item.y < panelFlick.contentY) panelFlick.contentY = Math.max(0, item.y - Style.space(8))
    else if (item.y + item.height > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.min(panelFlick.contentHeight - panelFlick.height,
                                     item.y + item.height - panelFlick.height + Style.space(8))
  }

  // ---------------------------------------------------------------- bar
  readonly property int wantingCount: wanting.length
  readonly property string barText: {
    if (!snap || !markAlive || vertical || barMetric !== "count") return ""
    return wantingCount > 0 ? String(wantingCount) : ""
  }
  readonly property string barTooltip: {
    if (!snap) return "Grok Bot"
    if (app.running === false) return "Grok Bot is not running"
    var c = counts
    var unread = c.unreadMessages !== undefined ? c.unreadMessages : (c.unread || 0)
    return (c.bots || 0) + " bots · " + (c.awaiting || 0) + " waiting on you · "
      + (c.working || 0) + " working · " + unread + " unread · Grok Bot "
      + (app.version ? "v" + app.version : "")
  }

  implicitWidth: row.implicitWidth
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property real openPanelIndicatorWidth: row.width

  readonly property bool vertical: !!(bar && bar.vertical)
  readonly property var barAvatars: (!snap || !markAlive || vertical || barMetric !== "avatars")
    ? [] : wanting.slice(0, maxBarAvatars)
  readonly property real markSize: Math.round(Style.bar.iconCanvas * 0.82)
  readonly property real barPull: Style.space(3)
  readonly property real barAvatarSize: {
    var h = Math.round(Style.font.caption * 1.15)
    return (h % 2) === (markSize % 2) ? h : h + 1
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: -root.barPull

    BarIconButton {
      id: button
      bar: root.bar
      tooltipText: ""
      onPressed: function(buttonCode) { root.barPressed(buttonCode) }
      iconComponent: Component {
        Item {
          Face {
            anchors.centerIn: parent
            iconSize: root.markSize
            lively: root.lively
            fill: root.bar ? root.bar.barForeground : root.foreground
            markOpacity: root.markAlive ? 1.0 : 0.45
            holeColor: Color.bar.background
          }
        }
      }
    }

    Row {
      id: avatars
      anchors.verticalCenter: button.verticalCenter
      spacing: Style.space(3)
      visible: root.barAvatars.length > 0

      Repeater {
        model: root.barAvatars
        Avatar {
          id: barAvatar
          required property var modelData
          required property int index
          width: root.barAvatarSize
          height: root.barAvatarSize
          shape: modelData.shape
          image: root.avatarUrl(modelData)
          fill: root.colorFor(modelData)
          eyeColor: root.eyeInk
          face: root.faceFor(modelData)

          Connections {
            target: root
            function onBarGreeted() { greet.restart() }
          }
          Timer {
            id: greet
            interval: 30 + barAvatar.index * 90
            onTriggered: barAvatar.playBold(barAvatar.index + root.barGreetSeed)
          }
        }
      }
    }

    Text {
      id: metric
      anchors.verticalCenter: button.verticalCenter
      visible: root.barText !== ""
      textFormat: Text.PlainText
      text: root.barText
      color: root.alarming ? root.urgent : (root.bar ? root.bar.barForeground : root.foreground)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Item {
      height: 1
      width: (avatars.visible || metric.visible)
        ? Math.round((button.width - root.markSize) / 2) + root.barPull : 0
    }
  }

  MouseArea {
    anchors.fill: row
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: function(mouse) { root.barPressed(mouse.button) }
    onEntered: {
      if (root.bar) root.bar.showTooltip(row, root.barTooltip)
      root.barGreetSeed += 1
      root.barGreeted()
    }
    onExited: if (root.bar) root.bar.hideTooltip(row)
  }

  // ---------------------------------------------------------------- panel
  KeyboardPanel {
    id: panel
    anchorItem: row
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + Style.space(16), Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx < 0) root.scrub = !root.scrub
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: root.activateRow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.cycleBarMetric()
        else if (t === "g" || t === "G") root.cycleOrdering()
        else if (t === "h" || t === "H") root.scrub = !root.scrub
      }

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
        id: pointerTracker
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        onPositionChanged: function(mouse) { keyCatcher.pointerAt(mouse.x, mouse.y) }
        onExited: keyCatcher.pointerGone()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + Style.space(8)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          x: Style.space(4)
          width: parent.width - Style.space(8)
          spacing: 0

          Item {
            width: parent.width
            height: header.implicitHeight + Style.space(10)
            Column {
              id: header
              width: parent.width
              spacing: Style.space(2)
              Text {
                textFormat: Text.PlainText
                text: {
                  if (root.demoMode) return "GROK BOT · demo roster"
                  if (!root.snap) return "GROK BOT"
                  if (root.app.running === false) return "GROK BOT · not running"
                  return "GROK BOT " + (root.app.version || "")
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                visible: !!root.snap
                textFormat: Text.PlainText
                text: {
                  var c = root.counts
                  var bits = [(c.bots || 0) + " bots"]
                  if ((c.awaiting || 0) > 0) bits.push(c.awaiting + " waiting on you")
                  if ((c.working || 0) > 0) bits.push(c.working + " working")
                  var unread = c.unreadMessages !== undefined ? c.unreadMessages : (c.unread || 0)
                  if (unread > 0) bits.push(unread + " unread")
                  if ((c.groups || 0) > 0) bits.push(c.groups + " group")
                  return bits.join(" · ")
                }
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: root.faint }

          Repeater {
            id: repeater
            model: root.rows

            Item {
              id: rowItem
              required property var modelData
              required property int index
              width: column.width
              height: modelData.kind === "section" ? Style.space(26)
                    : modelData.kind === "rule" ? Style.space(13) : Style.space(46)

              Rectangle {
                visible: modelData.kind === "rule"
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: root.divider
              }

              readonly property bool wantsGreeting: modelData.kind === "bot"
                && modelData.bot && (modelData.bot.unreadCount > 0 || modelData.bot.awaiting)

              Connections {
                target: root
                function onGreetRequested(everyone) {
                  if (rowItem.modelData.kind !== "bot") return
                  if (everyone || rowItem.wantsGreeting) rowGreet.restart()
                }
              }
              Timer {
                id: rowGreet
                interval: 60 + rowItem.index * 85
                onTriggered: if (rowAvatar) rowAvatar.playBold(root.nextFlourish())
              }

              Text {
                visible: modelData.kind === "section"
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(4)
                textFormat: Text.PlainText
                text: root.label(modelData.name).toUpperCase() + "  " + (modelData.count || "")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Rectangle {
                visible: modelData.kind === "bot"
                anchors.fill: parent
                anchors.leftMargin: -Style.space(4)
                anchors.rightMargin: -Style.space(4)
                radius: Style.space(1.5)
                color: index === root.cursor ? root.hilite : "transparent"

                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(9)

                  Avatar {
                    id: rowAvatar
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(28)
                    height: Style.space(28)
                    shape: modelData.kind === "bot" && modelData.bot ? modelData.bot.shape : "blob"
                    image: modelData.kind === "bot" ? root.avatarUrl(modelData.bot) : ""
                    fill: modelData.kind === "bot" ? root.colorFor(modelData.bot) : root.dim
                    eyeColor: root.eyeInk
                    face: modelData.kind === "bot" ? root.faceFor(modelData.bot) : "neutral"
                    Component.onCompleted: root.flourishCount = flourishCount

                    readonly property point look: mapFromItem(keyCatcher,
                      keyCatcher.pointerX, keyCatcher.pointerY)
                    looking: keyCatcher.pointerX >= 0
                    followX: look.x
                    followY: look.y

                    property bool wasWanted: false
                    onFaceChanged: {
                      var wants = face === "attentive" || face === "excited" || face === "curious"
                      if (wants) wasWanted = true
                      else if (wasWanted) { wasWanted = false; celebrate() }
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(28) - Style.space(9) - badge.width - Style.space(9)
                    spacing: Style.space(1)

                    Row {
                      spacing: Style.space(5)
                      width: parent.width
                      Text {
                        textFormat: Text.PlainText
                        text: modelData.kind === "bot" && modelData.bot ? root.label(modelData.bot.name) : ""
                        color: modelData.kind === "bot" && modelData.bot && modelData.bot.focused ? root.accent : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: modelData.kind === "bot" && modelData.bot && (modelData.bot.awaiting || modelData.bot.unreadCount > 0)
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: modelData.kind === "bot" && modelData.bot
                          ? (modelData.bot.group ? "group of " + modelData.bot.members
                                                 : root.label(modelData.bot.title))
                          : ""
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: Math.max(0, parent.width - Style.space(120))
                      }
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: modelData.kind === "bot" && modelData.bot
                        ? (root.isWorking(modelData.bot) ? "thinking…" : root.label(modelData.bot.preview))
                        : ""
                      color: modelData.kind === "bot" && modelData.bot && modelData.bot.awaiting ? root.foreground
                             : (modelData.kind === "bot" && modelData.bot && root.isWorking(modelData.bot) ? root.accent : root.dim)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }
                  }

                  Column {
                    id: badge
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(38)
                    spacing: Style.space(2)

                    Text {
                      anchors.right: parent.right
                      textFormat: Text.PlainText
                      text: modelData.kind === "bot" ? root.agoOf(modelData.bot) : ""
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Rectangle {
                      anchors.right: parent.right
                      visible: modelData.kind === "bot" && modelData.bot && modelData.bot.unreadCount > 0
                      width: Math.max(Style.space(14), unreadText.implicitWidth + Style.space(6))
                      height: Style.space(14)
                      radius: height / 2
                      color: root.accent
                      Text {
                        id: unreadText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: modelData.kind === "bot" && modelData.bot ? String(modelData.bot.unreadCount) : ""
                        color: Color.background
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    root.cursor = index
                    var e = mapToItem(keyCatcher, mouseX, mouseY)
                    keyCatcher.pointerAt(e.x, e.y)
                  }
                  onExited: keyCatcher.pointerGone()
                  onClicked: {
                    if (rowItem.modelData.kind === "bot" && rowItem.modelData.bot)
                      root.launchBot(String(rowItem.modelData.bot.id || ""))
                    root.close()
                  }
                  onPositionChanged: function(mouse) {
                    var p = mapToItem(keyCatcher, mouse.x, mouse.y)
                    keyCatcher.pointerAt(p.x, p.y)
                  }
                }
              }
            }
          }

          Text {
            visible: !root.snap || root.bots.length === 0
            width: parent.width
            topPadding: Style.space(10)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
            text: root.emptyText()
          }

          Rectangle { width: parent.width; height: 1; color: root.faint; visible: root.bots.length > 0 }

          Item {
            width: parent.width
            height: Style.space(30)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "j/k move · ⏎ open · g " + root.ordering
                    + " · h hide · r beside logo: " + root.barMetric
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
