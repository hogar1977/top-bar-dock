import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "io.github.hogar1977.top-bar-dock"

  readonly property string shelfWorkspace: "special:omarchy-minimized"
  readonly property int maxTitleLength: Math.max(4, Number(root.setting("maxTitleLength", 18)))
  readonly property int previewDelay: Math.max(0, Number(root.setting("previewDelay", 350)))
  readonly property string pinnedFilePath: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.hogar1977.top-bar-dock/pinned.json"

  readonly property var taskbarWindows: Hyprland.toplevels.values
  readonly property var activeWindow: Hyprland.activeToplevel
  readonly property var currentWorkspace: Hyprland.focusedWorkspace
  readonly property int currentWorkspaceId: currentWorkspace ? currentWorkspace.id : -1
  property var pinnedIds: []
  property var entryIndex: null
  property var snapshotByAddress: ({})
  property var liveWindows: []
  property var pseudoByAddress: ({})
  property int appVersion: 0
  property var dockCache: ({ sig: "__init__", entries: [] })
  property var dragOrder: null
  property var dragOriginal: null
  property string dragId: ""
  property int dragTarget: -1
  property int dragCurrent: -1
  property int dragGap: -1
  property real dragOriginX: 0
  property real dragOriginY: 0
  readonly property real dragDeadzone: 10
  readonly property var dockEntries: buildDockEntries(root.liveWindows, pinnedIds, appVersion)

  property var previewToplevel: null
  property Item previewAnchor: null
  property var pendingPreviewToplevel: null
  property Item pendingPreviewAnchor: null
  property var hoverChip: null
  property var lastToggleByAddress: ({})
  readonly property int toggleGraceMs: 1000
  property string cachedGapsOut: ""
  property string cachedGapsIn: ""
  property bool gapOpPending: false
  property var menuEntry: null
  property Item menuAnchor: null

  implicitWidth: chipRow.implicitWidth
  implicitHeight: chipRow.implicitHeight

  function isMinimized(toplevel) {
    return toplevel !== null && toplevel.workspace !== null
      && toplevel.workspace.name === shelfWorkspace
  }

  function isFloatingWindow(toplevel) {
    if (!toplevel) return false
    return toplevel.floating === true
      || (toplevel.lastIpcObject && Number(toplevel.lastIpcObject.floating) === 1)
  }

  function identitySnapshot(toplevel) {
    var addr = normalizedAddress(toplevel)
    if (!addr) return null
    return root.snapshotByAddress[addr] || null
  }

  function windowClass(toplevel) {
    var ipc = toplevel && toplevel.lastIpcObject
    if (ipc && ipc.class) return String(ipc.class)
    var snap = root.identitySnapshot(toplevel)
    var sipc = snap && snap.lastIpcObject
    if (sipc && sipc.class) return String(sipc.class)
    return ""
  }

  function isRelevantWindow(toplevel) {
    if (!toplevel) return false
    var ipc = toplevel.lastIpcObject || null
    var title = String(toplevel.title || "").trim()
    var cls = root.windowClass(toplevel).trim()
    if (toplevel.hidden === true || (ipc && Number(ipc.hidden) === 1)) return false
    var workspace = toplevel.workspace || null
    if (workspace && String(workspace.name || "").indexOf("special:") === 0
        && String(workspace.name || "") !== root.shelfWorkspace) return false
    if (!cls) return false
    if (cls === "steam" && !title) return false
    if (cls === "steam" && root.isFloatingWindow(toplevel)) return false
    if (root.isFloatingWindow(toplevel) && !title) return false
    if (root.isFloatingWindow(toplevel)
        && /^(launching|loading|preparing|configuring|updating|checking|starting)/i.test(title)) return false
    return true
  }

  function steamAppIdOf(toplevel) {
    var candidates = windowIdentityCandidates(toplevel)
    for (var i = 0; i < candidates.length; i++) {
      var m = String(candidates[i] || "").trim().match(/^steam[_ -]?app[_ -]?(\d+)$/i)
      if (m) return m[1]
    }
    return ""
  }

  function entryForAppId(appid) {
    if (!appid) return null
    var index = root.entryIndex
    if (!index) return null
    for (var i = 0; i < index.length; i++) {
      if (index[i].execText && index[i].execText.indexOf("rungameid " + appid) !== -1) {
        return index[i].entry
      }
    }
    return null
  }

  function steamSurfaceId(toplevel) {
    var title = String(toplevel.title || "").toLowerCase()
    if (title.indexOf("friends list") === 0 || title.indexOf("friends & chat") === 0) {
      return "steam-friends"
    }
    if (title.indexOf("settings") !== -1) return "steam-settings"
    return ""
  }

  function normalizedAddress(toplevel) {
    if (!toplevel || !toplevel.address) return ""
    var address = String(toplevel.address)
    return address.indexOf("0x") === 0 ? address : "0x" + address
  }

  function moveRequest(toplevel, workspace, follow) {
    var address = normalizedAddress(toplevel)
    if (!address || !workspace) return ""
    return "hl.dsp.window.move({ workspace = " + JSON.stringify(workspace)
      + ", window = " + JSON.stringify("address:" + address)
      + ", follow = " + (follow ? "true" : "false") + " })"
  }

  function moveWindow(toplevel, workspace, follow) {
    var request = moveRequest(toplevel, workspace, follow)
    if (!request) return
    Quickshell.execDetached(["hyprctl", "dispatch", request])
  }

  function windowFloatRequest(toplevel, action) {
    var address = normalizedAddress(toplevel)
    if (!address) return ""
    return "hl.dsp.window.float({ action = " + JSON.stringify(action)
      + ", window = " + JSON.stringify("address:" + address) + " })"
  }

  function windowFullscreenRequest(toplevel, fullscreenMode) {
    var address = normalizedAddress(toplevel)
    if (!address || fullscreenMode <= 0) return ""
    var mode = fullscreenMode === 1 ? "maximized" : "fullscreen"
    return "hl.dsp.window.fullscreen({ mode = " + JSON.stringify(mode)
      + ", window = " + JSON.stringify("address:" + address) + " })"
  }

  function windowCloseRequest(toplevel) {
    var address = normalizedAddress(toplevel)
    if (!address) return ""
    return "hl.dsp.window.close({ window = " + JSON.stringify("address:" + address) + " })"
  }

  function restore(toplevel) {
    var workspace = Hyprland.focusedWorkspace
    var destination = workspace && String(workspace.name).indexOf("special:") !== 0
      ? workspace.name : "1"
    restoreTiled(toplevel, destination)
  }

  function gapLiteral(css) {
    var m = String(css || "").trim().match(/-?\d+(?:\.\d+)?/g)
    if (!m || m.length === 0) return ""
    if (m.length === 1) return m[0]
    if (m.length === 4) {
      if (m[0] === m[1] && m[1] === m[2] && m[2] === m[3]) return m[0]
      return "{ top = " + m[0] + ", right = " + m[1]
        + ", bottom = " + m[2] + ", left = " + m[3] + " }"
    }
    return ""
  }

  function gapSetExpr(gapsOut, gapsIn) {
    var general = []
    var out = gapLiteral(gapsOut)
    var inlit = gapLiteral(gapsIn)
    if (out) general.push("gaps_out = " + out)
    if (inlit) general.push("gaps_in = " + inlit)
    return general.length
      ? "hyprctl eval 'hl.config({ general = { " + general.join(", ") + " } })'" : ""
  }

  function gapRestoreExpr() {
    var general = []
    var out = gapLiteral(root.cachedGapsOut)
    var inlit = gapLiteral(root.cachedGapsIn)
    if (out) general.push("gaps_out = " + out)
    if (inlit) general.push("gaps_in = " + inlit)
    var parts = []
    if (general.length) parts.push("general = { " + general.join(", ") + " }")
    parts.push("cursor = { no_warps = false }")
    return "hyprctl eval 'hl.config({ " + parts.join(", ") + " })'"
  }

  function restoreTiled(toplevel, destination) {
    var address = normalizedAddress(toplevel)
    var moveExpr = moveRequest(toplevel, destination, false)
    if (!address || !moveExpr) return
    var focusExpr = "hl.dsp.focus({ window = " + JSON.stringify("address:" + address) + " })"
    var floatOffExpr = windowFloatRequest(toplevel, "off")
    var steps = [
      "hyprctl eval 'hl.config({ general = { gaps_out = 0, gaps_in = 0 }, cursor = { no_warps = true } })'",
      "hyprctl dispatch '" + moveExpr + "'",
      "hyprctl dispatch '" + focusExpr + "'"
    ]
    if (floatOffExpr) steps.push("hyprctl dispatch '" + floatOffExpr + "'")
    var ipc = toplevel.lastIpcObject || null
    if (ipc && Number(ipc.fullscreen) === 1) {
      var unmaximizeExpr = windowFullscreenRequest(toplevel, 1)
      if (unmaximizeExpr) steps.push("hyprctl dispatch '" + unmaximizeExpr + "'")
    }
    root.gapOpPending = true
    gapOpClearTimer.restart()
    var restoreExpr = gapRestoreExpr()
    if (restoreExpr) steps.push(restoreExpr)
    Quickshell.execDetached(["sh", "-c", "(" + steps.join(" ; ") + ")"])
  }

  function anyOtherWindowVisible(excluding) {
    for (var i = 0; i < root.liveWindows.length; i++) {
      var candidate = root.liveWindows[i]
      if (candidate === excluding || !root.isRelevantWindow(candidate) || isMinimized(candidate)) continue
      return true
    }
    return false
  }

  function isElsewhere(toplevel) {
    if (!toplevel || isMinimized(toplevel)) return false
    var workspace = toplevel.workspace
    var focused = Hyprland.focusedWorkspace
    return workspace !== null && focused !== null && workspace.id !== focused.id
  }

  function focusWindow(toplevel) {
    var address = normalizedAddress(toplevel)
    if (!address) return
    var focusExpr = "hl.dsp.focus({ window = " + JSON.stringify("address:" + address) + " })"
    Quickshell.execDetached(["hyprctl", "dispatch", focusExpr])
  }

  function toggleWindow(toplevel) {
    var addr = normalizedAddress(toplevel)
    var now = Date.now()
    var since = root.lastToggleByAddress[addr]
    var recent = since && (now - since.ts) < root.toggleGraceMs
    if (recent && since.action === "minimize") {
      root.lastToggleByAddress[addr] = { action: "restore", ts: now }
      root.restore(toplevel)
      return
    }
    if (recent && since.action === "restore") {
      root.lastToggleByAddress[addr] = { action: "minimize", ts: now }
      root.minimize(toplevel)
      return
    }
    if (isMinimized(toplevel)) {
      root.lastToggleByAddress[addr] = { action: "restore", ts: now }
      restore(toplevel)
    } else if (isElsewhere(toplevel)) {
      root.lastToggleByAddress[addr] = { action: "focus", ts: now }
      focusWindow(toplevel)
    } else {
      root.lastToggleByAddress[addr] = { action: "minimize", ts: now }
      minimize(toplevel)
    }
  }

  function minimize(toplevel) {
    moveWindow(toplevel, shelfWorkspace, false)
    if (!anyOtherWindowVisible(toplevel)) {
      var setExpr = gapSetExpr(root.cachedGapsOut, root.cachedGapsIn)
      if (setExpr) Quickshell.execDetached(["sh", "-c", setExpr])
    }
  }

  function maximizeWindow(toplevel) {
    var address = normalizedAddress(toplevel)
    var fsExpr = windowFullscreenRequest(toplevel, 1)
    if (!address || !fsExpr) return
    var focusExpr = "hl.dsp.focus({ window = " + JSON.stringify("address:" + address) + " })"
    var steps = ["hyprctl eval 'hl.config({ general = { gaps_out = 0, gaps_in = 0 }, cursor = { no_warps = true } })'"]
    if (isMinimized(toplevel)) {
      var workspace = Hyprland.focusedWorkspace
      var destination = workspace && String(workspace.name).indexOf("special:") !== 0
        ? workspace.name : "1"
      var moveExpr = moveRequest(toplevel, destination, false)
      if (moveExpr) steps.push("hyprctl dispatch '" + moveExpr + "'")
    }
    steps.push("hyprctl dispatch '" + focusExpr + "'")
    steps.push("hyprctl dispatch '" + fsExpr + "'")
    root.gapOpPending = true
    gapOpClearTimer.restart()
    var restoreExpr = gapRestoreExpr()
    if (restoreExpr) steps.push(restoreExpr)
    Quickshell.execDetached(["sh", "-c", "(" + steps.join(" ; ") + ")"])
  }

  function closeWindow(toplevel) {
    var expr = windowCloseRequest(toplevel)
    if (!expr) return
    Quickshell.execDetached(["hyprctl", "dispatch", expr])
  }

  function windowTitle(toplevel) {
    var title = String(toplevel && toplevel.title ? toplevel.title : "Window").trim()
    if (title.length <= maxTitleLength) return title
    return title.substring(0, maxTitleLength - 3) + "..."
  }

  function verticalLabel(toplevel) {
    var ipc = toplevel ? toplevel.lastIpcObject : null
    var app = String(ipc && ipc.class ? ipc.class : windowTitle(toplevel)).trim()
    return app.length > 0 ? app.charAt(0).toUpperCase() : "W"
  }

  function windowIdentityCandidates(toplevel) {
    if (!toplevel) return []
    var ipc = toplevel.lastIpcObject || null
    var wayland = toplevel.wayland || null
    var snap = root.identitySnapshot(toplevel)
    var snapIpc = snap ? (snap.lastIpcObject || null) : null
    var candidates = [
      wayland && wayland.appId ? wayland.appId : "",
      ipc && ipc.class ? ipc.class : "",
      ipc && ipc.initialClass ? ipc.initialClass : "",
      snapIpc && snapIpc.class ? snapIpc.class : "",
      snapIpc && snapIpc.initialClass ? snapIpc.initialClass : ""
    ]
    var cleaned = []
    for (var i = 0; i < candidates.length; i++) {
      var value = String(candidates[i] || "").trim()
      if (value && cleaned.indexOf(value) === -1) cleaned.push(value)
    }
    return cleaned
  }

  function idTokens(value) {
    return String(value || "").toLowerCase().split(/[^a-z0-9]+/)
      .filter(function(t) { return t.length > 0 })
  }

  function heuristicEntryFor(name) {
    name = String(name || "")
    var direct = DesktopEntries.heuristicLookup(name)
    if (direct) return direct
    var tokens = idTokens(name)
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i].length < 3) continue
      var check = DesktopEntries.heuristicLookup(tokens[i])
      if (check) return check
    }
    return null
  }

  function normalizedText(value) {
    return String(value || "").toLowerCase()
      .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
      .replace(/[^a-z0-9]+/g, " ")
      .trim()
  }

  function isStopToken(token) {
    return /^(org|com|net|io|dev|app|www|https|http|desktop|default|co|uk|edu|gov|exe)$/.test(token)
  }

  function fieldTokens(value) {
    return normalizedText(value).split(" ")
      .filter(function(t) { return t.length > 0 })
  }

  function meaningfulTokens(value) {
    return fieldTokens(value).filter(function(t) { return !root.isStopToken(t) && t.length >= 3 })
  }

  function rebuildEntryIndex() {
    var apps = DesktopEntries.applications
    var values = apps ? apps.values : []
    var index = []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e) continue
      index.push({
        entry: e,
        idText: normalizedText(e.id),
        startupClassText: normalizedText(e.startupClass),
        execText: normalizedText(e.execString),
        nameTokens: meaningfulTokens(e.name),
        idTokens: meaningfulTokens(e.id),
        genericTokens: meaningfulTokens(e.genericName),
        commentTokens: meaningfulTokens(e.comment),
        execTokens: meaningfulTokens(e.execString)
      })
    }
    root.entryIndex = index
  }

  function rowScore(row, candidate) {
    var c = normalizedText(candidate)
    if (!c) return 0
    var cTokens = meaningfulTokens(c)
    var score = 0
    if (row.startupClassText && row.startupClassText === c) score += 100000
    else if (row.idText === c) score += 60000
    if (c.length >= 4 && row.startupClassText.indexOf(c) !== -1) score += 30000
    if (c.length >= 4 && row.execText.indexOf(c) !== -1) score += 20000
    var nameHits = row.nameTokens.filter(function(nt) { return cTokens.indexOf(nt) !== -1 })
    if (nameHits.length > 0 && nameHits.length === row.nameTokens.length) score += 3000
    for (var t = 0; t < cTokens.length; t++) {
      var tok = cTokens[t]
      if (row.nameTokens.indexOf(tok) !== -1) score += 900
      if (row.idTokens.indexOf(tok) !== -1) score += 500
      if (row.execTokens.indexOf(tok) !== -1) score += 300
      if (row.genericTokens.indexOf(tok) !== -1) score += 150
      if (row.commentTokens.indexOf(tok) !== -1) score += 120
    }
    return score
  }

  function scoredDesktopEntry(candidates) {
    var index = root.entryIndex
    if (!index || index.length === 0) return null
    var domains = []
    for (var d = 0; d < candidates.length; d++) {
      var dm = String(candidates[d] || "").trim()
        .match(/([a-z0-9]+\.(?:[a-z]{2,})(?:\.[a-z]{2,})?)/i)
      if (dm && domains.indexOf(dm[1].toLowerCase()) === -1) {
        domains.push(dm[1].toLowerCase())
      }
    }
    var best = null
    var bestScore = 0
    for (var i = 0; i < candidates.length; i++) {
      var c = String(candidates[i] || "").trim()
      if (!c) continue
      for (var j = 0; j < index.length; j++) {
        var score = root.rowScore(index[j], c)
        if (domains.length) {
          var execRaw = String(index[j].entry && index[j].entry.execString || "").toLowerCase()
          var hasUrl = execRaw.indexOf("://") !== -1
          for (var dd = 0; dd < domains.length; dd++) {
            if (hasUrl && execRaw.indexOf(domains[dd]) !== -1) {
              score += 300000
              break
            }
          }
        }
        if (score > bestScore) {
          bestScore = score
          best = index[j].entry
        }
      }
    }
    return bestScore >= 2500 ? best : null
  }

  function looksLikeWebappClass(candidate) {
    var c = String(candidate || "")
    if (c.indexOf("__") !== -1) return true
    return /\.webview$/i.test(c)
  }

  function desktopEntry(toplevel) {
    var candidates = windowIdentityCandidates(toplevel)
    var appid = root.steamAppIdOf(toplevel)
    if (appid) {
      var appEntry = root.entryForAppId(appid)
      if (appEntry) return appEntry
      return null
    }
    for (var i = 0; i < candidates.length; i++) {
      if (root.looksLikeWebappClass(candidates[i])) continue
      var direct = DesktopEntries.heuristicLookup(candidates[i])
      if (direct) return direct
    }
    var scored = scoredDesktopEntry(candidates)
    if (scored) return scored
    for (var h = 0; h < candidates.length; h++) {
      var viaToken = heuristicEntryFor(candidates[h])
      if (viaToken) return viaToken
    }
    var withTitle = candidates.concat([String(toplevel.title || "")])
    return scoredDesktopEntry(withTitle)
  }

  function entryForId(pinId) {
    if (!pinId) return null
    var steamMatch = String(pinId).match(/^steam-app-(\d+)$/)
    if (steamMatch) return root.entryForAppId(steamMatch[1])
    var direct = DesktopEntries.byId(pinId)
    if (direct) return direct
    return heuristicEntryFor(pinId)
  }

  function fallbackPinId(toplevel) {
    var candidates = windowIdentityCandidates(toplevel)
    return candidates.length > 0 ? candidates[0] : ""
  }

  function windowPinId(toplevel) {
    var appid = root.steamAppIdOf(toplevel)
    if (appid) {
      var appEntry = root.entryForAppId(appid)
      return appEntry && appEntry.id ? appEntry.id : "steam-app-" + appid
    }
    var entry = desktopEntry(toplevel)
    if (entry && entry.id) {
      if (entry.id === "steam") {
        var surface = steamSurfaceId(toplevel)
        if (surface) return surface
      }
      return entry.id
    }
    return fallbackPinId(toplevel)
  }

  function isActiveToplevel(toplevel) {
    var active = root.activeWindow
    if (!active || !toplevel) return false
    var ta = normalizedAddress(toplevel)
    var aa = normalizedAddress(active)
    if (ta && aa) return ta === aa
    return toplevel === active
  }

  function applySnapshot(clients) {
    var byAddr = {}
    for (var i = 0; i < clients.length; i++) {
      var c = clients[i]
      if (!c || c.mapped !== true) continue
      var addr = String(c.address || c.unsafeAddress || "")
      if (addr.indexOf("0x") !== 0) addr = "0x" + addr
      if (!addr || addr === "0x") continue
      var ws = c.workspace || {}
      var cls = String(c.class || c.initialClass || "")
      byAddr[addr] = {
        address: addr,
        title: String(c.title || ""),
        lastIpcObject: {
          class: cls,
          initialClass: String(c.initialClass || cls || ""),
          address: addr,
          floating: c.floating === true ? 1 : 0,
          hidden: c.hidden === true ? 1 : 0,
          mapped: 1,
          fullscreen: c.fullscreen === true ? 1 : 0,
          workspace: { name: String(ws.name || ""), id: Number(ws.id || 0) }
        },
        wayland: null,
        workspace: { name: String(ws.name || ""), id: Number(ws.id || 0) },
        floating: c.floating === true,
        hidden: c.hidden === true,
        mapped: true,
        fullscreen: c.fullscreen === true,
        pid: Number(c.pid || 0),
        real: null
      }
    }
    root.snapshotByAddress = byAddr
    root.rebuildLiveWindows()
  }

  function rebuildLiveWindows() {
    var byAddr = root.snapshotByAddress
    var hasSnapshot = Object.keys(byAddr).length > 0
    var list = []
    if (hasSnapshot) {
      var backrefs = {}
      for (var j = 0; j < root.taskbarWindows.length; j++) {
        var modelWindow = root.taskbarWindows[j]
        var maddr = normalizedAddress(modelWindow)
        if (maddr && !(maddr in backrefs)) backrefs[maddr] = modelWindow
      }
      for (var key in byAddr) {
        var snap = byAddr[key]
        var real = backrefs[key]
        if (real) {
          list.push(real)
        } else {
          var pseudo = root.pseudoByAddress[key]
          if (!pseudo) {
            pseudo = {}
            root.pseudoByAddress[key] = pseudo
          }
          pseudo.address = snap.address
          pseudo.title = snap.title
          pseudo.lastIpcObject = snap.lastIpcObject
          pseudo.wayland = snap.wayland || (real ? real.wayland : null)
          pseudo.workspace = snap.workspace
          pseudo.floating = snap.floating
          pseudo.hidden = snap.hidden
          pseudo.mapped = true
          pseudo.fullscreen = snap.fullscreen
          pseudo.pid = snap.pid
          pseudo.real = real || null
          list.push(pseudo)
        }
      }
    } else {
      for (var i = 0; i < root.taskbarWindows.length; i++) {
        if (!normalizedAddress(root.taskbarWindows[i])) continue
        list.push(root.taskbarWindows[i])
      }
    }
    if (sameWindowList(root.liveWindows, list)) return
    root.liveWindows = list
    root.appVersion++
  }

  function sameWindowList(a, b) {
    if (!a || !b || a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) return false
    }
    return true
  }

  function pinMatchesWindow(pinId, toplevel) {
    if (!pinId || !toplevel || !root.isRelevantWindow(toplevel)) return false
    var low = String(pinId).toLowerCase()
    if (low.indexOf("steam-app-") === 0) {
      var appMatch = low.match(/^steam-app-(\d+)$/)
      var winId = root.windowPinId(toplevel)
      if (low === winId) return true
      if (appMatch) {
        var appEntry = root.entryForAppId(appMatch[1])
        if (appEntry && appEntry.id && appEntry.id === winId) return true
      }
      return false
    }
    if (low.indexOf("steam-") === 0) return low === root.windowPinId(toplevel)
    var entry = desktopEntry(toplevel)
    if (entry && entry.id && entry.id.toLowerCase() === low) return true
    var candidates = windowIdentityCandidates(toplevel)
    for (var i = 0; i < candidates.length; i++) {
      if (candidates[i].toLowerCase() === low) return true
    }
    var pinTokens = root.meaningfulTokens(pinId)
    if (pinTokens.length) {
      var shared = {}
      for (var wc = 0; wc < candidates.length; wc++) {
        var winTokens = root.meaningfulTokens(candidates[wc])
        for (var wt = 0; wt < winTokens.length; wt++) {
          if (pinTokens.indexOf(winTokens[wt]) !== -1) shared[winTokens[wt]] = true
        }
      }
      var titleTokens = root.meaningfulTokens(String(toplevel.title || ""))
      for (var tl = 0; tl < titleTokens.length; tl++) {
        if (pinTokens.indexOf(titleTokens[tl]) !== -1) shared[titleTokens[tl]] = true
      }
      var sharedCount = 0
      for (var sk in shared) sharedCount++
      if (sharedCount >= 2) return true
    }
    return false
  }

  function prettyPinName(pinId) {
    var value = String(pinId || "")
    if (value === "steam") return "Steam"
    if (value === "steam-friends") return "Steam Friends"
    if (value === "steam-settings") return "Steam Settings"
    var steamMatch = value.match(/^steam-app-(\d+)$/)
    if (steamMatch) {
      var appEntry = root.entryForAppId(steamMatch[1])
      return appEntry && appEntry.name ? appEntry.name : "Steam App " + steamMatch[1]
    }
    value = value.replace(/__.*$/, "")
    var tokens = value.split(/[^A-Za-z0-9]+/).filter(function(t) { return t.length > 0 })
    if (tokens.length === 0) return value || ""
    var useful = tokens.filter(function(t) {
      return !/^(org|com|net|io|app|www|default)$/i.test(t)
    })
    var pick = useful.length > 0 ? useful[useful.length - 1] : tokens[tokens.length - 1]
    return pick.charAt(0).toUpperCase() + pick.slice(1)
  }

  function iconFromEntry(entry) {
    var icon = String(entry && entry.icon ? entry.icon : "")
    if (icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0) return icon
    if (icon.charAt(0) === "/") return Util.fileUrl(icon)
    return Quickshell.iconPath(icon || "application-x-executable", true)
  }

  function iconFromId(pinId, entry) {
    var steamMatch = String(pinId || "").match(/^steam-app-(\d+)$/)
    if (steamMatch) return Quickshell.iconPath("steam_icon_" + steamMatch[1], true)
    if (entry) {
      var found = iconFromEntry(entry)
      if (found) return found
    }
    var cleaned = String(pinId || "").replace(/[^A-Za-z0-9]/g, "").toLowerCase()
    if (cleaned.length >= 3) return Quickshell.iconPath(cleaned, true)
    return ""
  }

  function windowIcon(toplevel) {
    var entry = desktopEntry(toplevel)
    if (!entry) return ""
    return iconFromEntry(entry)
  }

  FileView {
    id: pinnedFile
    path: root.pinnedFilePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parsePinned(text())
    onLoadFailed: root.pinnedIds = []
  }

  function parsePinned(content) {
    try {
      var parsed = JSON.parse(String(content || "{}"))
      root.pinnedIds = Array.isArray(parsed.pinned)
        ? parsed.pinned.filter(function(v) { return typeof v === "string" }) : []
    } catch (e) {
      root.pinnedIds = []
    }
  }

  function writePinned(list) {
    var json = JSON.stringify({ pinned: list }, null, 2)
    Quickshell.execDetached(["sh", "-c",
      "mkdir -p '" + Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.hogar1977.top-bar-dock' && "
      + "cat > '" + root.pinnedFilePath + "' <<'TASKBAR_PINNED_EOF'\n" + json + "\nTASKBAR_PINNED_EOF"])
  }

  function isPinned(entryId) {
    return !!entryId && root.pinnedIds.indexOf(entryId) !== -1
  }

  function togglePin(entryId) {
    if (!entryId) return
    var next = isPinned(entryId)
      ? pinnedIds.filter(function(p) { return p !== entryId })
      : pinnedIds.concat([entryId])
    writePinned(next)
  }

  function movePin(list, entryId, target) {
    var out = []
    for (var i = 0; i < (list ? list.length : 0); i++) {
      if (list[i] !== entryId) out.push(list[i])
    }
    if (target < 0) target = 0
    else if (target > out.length) target = out.length
    out.splice(target, 0, entryId)
    return out
  }

  function pinIndexAt(inX, inY) {
    var size = root.barSize
    var spacing = Style.space(1)
    var advance = size + spacing
    var offset = root.vertical ? inY : inX
    var idx = Math.round((offset - size / 2) / advance)
    idx = Math.max(0, Math.min(idx, root.dockEntries.length))
    idx = Math.min(idx, root.pinnedIds.length)
    return idx
  }

  function dropGapIndex(target) {
    var gap = target <= root.dragCurrent ? target : target + 1
    return Math.max(0, Math.min(gap, root.pinnedIds.length))
  }

  function dropOffset(gap) {
    var size = root.barSize
    var spacing = Style.space(1)
    var advance = size + spacing
    var bar = Style.space(2)
    if (gap === 0) return 0
    return gap * advance - (spacing + bar) / 2
  }

  function commitDrag(targetIndex) {
    var source = root.dragOrder !== null ? root.dragOrder : root.pinnedIds
    var baseline = root.dragOriginal !== null ? root.dragOriginal : root.pinnedIds
    if (targetIndex === source.indexOf(root.dragId)) {
      root.dragOrder = null
      root.dragOriginal = null
      root.dragId = ""
      root.dragTarget = -1
      root.dragCurrent = -1
      root.dragGap = -1
      root.dragOriginX = 0
      root.dragOriginY = 0
      return
    }
    var next = root.movePin(source, root.dragId, targetIndex)
    if (next.join(",") !== baseline.join(",")) {
      root.pinnedIds = next
      root.writePinned(next)
    }
    root.dragOrder = null
    root.dragOriginal = null
    root.dragId = ""
    root.dragTarget = -1
    root.dragCurrent = -1
    root.dragGap = -1
    root.dragOriginX = 0
    root.dragOriginY = 0
  }

  function stepPin(entryId, delta) {
    var from = root.pinnedIds.indexOf(entryId)
    if (from === -1) return
    var to = from + delta
    if (to < 0 || to >= root.pinnedIds.length) return
    var next = root.movePin(root.pinnedIds, entryId, to)
    root.pinnedIds = next
    root.writePinned(next)
  }

  function moveMenuItems(entryId) {
    var idx = root.pinnedIds.indexOf(entryId)
    if (idx === -1) return []
    var items = []
    if (idx > 0) {
      items.push({ label: "Move left", action: function(e) { root.stepPin(entryId, -1) } })
    }
    if (idx < root.pinnedIds.length - 1) {
      items.push({ label: "Move right", action: function(e) { root.stepPin(entryId, 1) } })
    }
    return items
  }

  function buildDockEntries(windows, pinned, appVersion) {
    var entries = []
    var placed = {}
    var _ = appVersion
    var order = root.dragOrder !== null ? root.dragOrder : pinned
    for (var i = 0; i < order.length; i++) {
      var pid = order[i]
      var win = null
      for (var w = 0; w < windows.length; w++) {
        var addr2 = normalizedAddress(windows[w])
        if (placed[addr2] || !root.isRelevantWindow(windows[w]) || !pinMatchesWindow(pid, windows[w])) continue
        win = windows[w]
        break
      }
      if (win) {
        entries.push({ kind: "window", pinId: pid, toplevel: win, entryId: null, entry: null })
        placed[normalizedAddress(win)] = true
      } else {
        entries.push({ kind: "pinned", pinId: pid, entryId: pid, entry: entryForId(pid), toplevel: null })
      }
    }
    for (var j = 0; j < windows.length; j++) {
      var jaddr = normalizedAddress(windows[j])
      if (placed[jaddr] || !root.isRelevantWindow(windows[j])) continue
      entries.push({ kind: "window", toplevel: windows[j], entryId: null, entry: null })
    }
    var sig = ""
    for (var s = 0; s < entries.length; s++) {
      var e = entries[s]
      if (e.kind === "pinned") sig += "p:" + e.entryId + ";"
      else {
        var ea = normalizedAddress(e.toplevel)
        sig += "w:" + ea + ";"
        if (root.pseudoByAddress[ea] === e.toplevel) {
          var ews = (e.toplevel && e.toplevel.workspace && e.toplevel.workspace.name) || ""
          sig += "s:" + ews + ";"
        }
      }
    }
    if (sig === root.dockCache.sig && root.dockCache.entries.length === entries.length) {
      return root.dockCache.entries
    }
    root.dockCache.sig = sig
    root.dockCache.entries = entries
    root.cancelAllPreviews()
    return entries
  }

  function launchEntryById(entryId) {
    if (!entryId) return
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", entryId + ".desktop"])
  }

  function launchPinned(entryId) {
    if (!entryId) return
    var steamMatch = String(entryId).match(/^steam-app-(\d+)$/)
    if (steamMatch) {
      Quickshell.execDetached(["sh", "-c", "steam steam://rungameid/" + steamMatch[1]])
      return
    }
    if (entryId === "steam-friends") {
      Quickshell.execDetached(["sh", "-c", "steam steam://open/friends"])
      return
    }
    if (entryId === "steam-settings") {
      Quickshell.execDetached(["sh", "-c", "steam steam://open/settings"])
      return
    }
    var entry = entryForId(entryId)
    root.launchEntryById(entry ? entry.id : entryId)
  }

  function openMenu(anchorItem, entryObj) {
    root.menuAnchor = anchorItem
    root.menuEntry = entryObj
  }

  function close() {
    root.menuEntry = null
    root.menuAnchor = null
  }

  function menuItemsFor(entryObj) {
    if (!entryObj) return []
    if (entryObj.kind === "pinned") {
      var items = []
      items.push({ label: "Open", action: function(e) { root.launchPinned(e.entryId) } })
      items = items.concat(root.moveMenuItems(entryObj.entryId))
      items.push({ label: "Unpin from dock", action: function(e) { root.togglePin(e.entryId) } })
      return items
    }
    var toplevel = entryObj.toplevel
    var pinId = root.windowPinId(toplevel)
    var launchId = (function(t) {
      var e = root.desktopEntry(t)
      return e ? e.id : ""
    })(toplevel)
    var items = []
    if (launchId) items.push({ label: "Open new instance", action: function(e) { root.launchEntryById(launchId) } })
    items = items.concat(root.moveMenuItems(entryObj.pinId || ""))
    items.push(
      { label: "Maximize", action: function(e) { root.maximizeWindow(e.toplevel) } },
      { label: root.isMinimized(toplevel) ? "Restore" : "Minimize",
        action: function(e) { root.toggleWindow(e.toplevel) } }
    )
    if (pinId) {
      items.push({
        label: root.isPinned(pinId) ? "Unpin from dock" : "Pin to dock",
        action: function(e) { root.togglePin(pinId) }
      })
    }
    items.push({ label: "Close", destructive: true, action: function(e) { root.closeWindow(e.toplevel) } })
    return items
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.rebuildEntryIndex()
      root.appVersion++
    }
  }

  Component.onCompleted: {
    root.rebuildEntryIndex()
    gapsOutProcess.running = true
    gapsInProcess.running = true
  }

  onTaskbarWindowsChanged: {
    root.rebuildLiveWindows()
    if (previewToplevel && root.liveWindows.indexOf(previewToplevel) === -1) {
      cancelPreview(previewToplevel)
    }
  }

  onCurrentWorkspaceIdChanged: {
    root.cancelAllPreviews()
  }

  function requestPreview(anchor, toplevel) {
    if (!toplevel) return
    pendingPreviewAnchor = anchor
    pendingPreviewToplevel = toplevel
    previewTimer.restart()
  }

  function cancelPreview(toplevel) {
    if (pendingPreviewToplevel === toplevel) {
      previewTimer.stop()
      pendingPreviewAnchor = null
      pendingPreviewToplevel = null
    }
    if (previewToplevel === toplevel) {
      previewToplevel = null
      previewAnchor = null
    }
  }

  function cancelAllPreviews() {
    previewTimer.stop()
    pendingPreviewAnchor = null
    pendingPreviewToplevel = null
    previewToplevel = null
    previewAnchor = null
  }

  Timer {
    id: previewTimer
    interval: root.previewDelay
    onTriggered: {
      root.previewAnchor = root.pendingPreviewAnchor
      root.previewToplevel = root.pendingPreviewToplevel
      root.pendingPreviewAnchor = null
      root.pendingPreviewToplevel = null
    }
  }

  Process {
    id: snapshotProcess
    command: ["/usr/bin/hyprctl", "-j", "clients"]
    stdout: StdioCollector { id: snapshotOutput; waitForEnd: true }
    stderr: StdioCollector { id: snapshotError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0 && snapshotOutput.text) {
        try {
          root.applySnapshot(JSON.parse(snapshotOutput.text))
        } catch (err) {
          snapshotOutput.text = ""
        }
      }
    }
  }

  Timer {
    id: snapshotTimer
    interval: 700
    repeat: true
    running: true
    onTriggered: {
      snapshotProcess.running = true
    }
  }

  function applyGapOption(raw, which) {
    try {
      var json = JSON.parse(raw || "{}")
      var css = String(json.css || "").trim()
      if (css === "" || root.gapOpPending) return
      if (which === "out") root.cachedGapsOut = css
      else root.cachedGapsIn = css
    } catch (err) {
      // hyprctl missing / Hyprland not running — keep the previous value.
    }
  }

  Process {
    id: gapsOutProcess
    command: ["/usr/bin/hyprctl", "-j", "getoption", "general:gaps_out"]
    stdout: StdioCollector { id: gapsOutOutput; waitForEnd: true }
    stderr: StdioCollector { id: gapsOutError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0 && gapsOutOutput.text) {
        root.applyGapOption(gapsOutOutput.text, "out")
      }
    }
  }

  Process {
    id: gapsInProcess
    command: ["/usr/bin/hyprctl", "-j", "getoption", "general:gaps_in"]
    stdout: StdioCollector { id: gapsInOutput; waitForEnd: true }
    stderr: StdioCollector { id: gapsInError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0 && gapsInOutput.text) {
        root.applyGapOption(gapsInOutput.text, "in")
      }
    }
  }

  Timer {
    id: gapOptionsTimer
    interval: 1500
    repeat: true
    running: true
    onTriggered: {
      gapsOutProcess.running = true
      gapsInProcess.running = true
    }
  }

  Timer {
    id: gapOpClearTimer
    interval: 1000
    onTriggered: {
      root.gapOpPending = false
    }
  }

  GridLayout {
    id: chipRow
    columns: root.vertical ? 1 : Math.max(1, root.dockEntries.length)
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(1) : 0

    Repeater {
      model: root.dockEntries

      WidgetButton {
        id: chip

        required property var modelData
        readonly property bool pinnedSlot: modelData.kind === "pinned"
        readonly property var toplevel: modelData.toplevel
        readonly property int iconExtent: Style.space(15)
        readonly property string iconSource: pinnedSlot
          ? root.iconFromId(modelData.entryId, modelData.entry) : root.windowIcon(toplevel)
        readonly property bool minimized: !pinnedSlot && root.isMinimized(toplevel)
        readonly property bool focused: !pinnedSlot && root.isActiveToplevel(toplevel) && !minimized
        readonly property bool elsewhere: !pinnedSlot && !minimized && toplevel
          && toplevel.workspace !== null && toplevel.workspace.id !== root.currentWorkspaceId
        readonly property string pinHost: pinnedSlot ? modelData.entryId : (modelData.pinId || "")
        readonly property bool draggedPin: root.dragOrder !== null && chip.pinHost === root.dragId

        bar: root.bar
        text: ""
        keepSpace: true
        hasVisualContent: true
        labelVisible: false
        fixedWidth: root.barSize
        fixedHeight: root.barSize
        clip: true
        dimmed: chip.draggedPin
        tooltipText: pinnedSlot
          ? (modelData.entry && modelData.entry.name
              ? modelData.entry.name : root.prettyPinName(modelData.entryId))
          : ""
        onTooltipHoveredChanged: {
          if (tooltipHovered) {
            root.hoverChip = chip
            if (!pinnedSlot) root.requestPreview(chip, toplevel)
          } else if (root.hoverChip === chip) {
            root.hoverChip = null
          }
        }
        onPressed: function(button) {
          root.cancelAllPreviews()
          if (button === Qt.LeftButton) {
            if (pinnedSlot) {
              root.launchPinned(modelData.entryId)
            } else {
              root.toggleWindow(toplevel)
            }
          } else if (button === Qt.RightButton) {
            root.openMenu(chip, modelData)
          }
        }

        MouseArea {
          id: chipDrag
          anchors.fill: parent
          acceptedButtons: Qt.MiddleButton
          preventStealing: true
          enabled: chip.pinHost !== ""

          onPressed: {
            if (root.dragOrder !== null) return
            root.close()
            root.cancelAllPreviews()
            chip.hideOwnTooltip()
            root.dragOrder = root.pinnedIds.slice()
            root.dragOriginal = root.pinnedIds.slice()
            root.dragId = chip.pinHost
            var pinIndex = root.pinnedIds.indexOf(chip.pinHost)
            root.dragTarget = pinIndex
            root.dragCurrent = pinIndex
            root.dragGap = -1
            root.dragOriginX = mouse.x
            root.dragOriginY = mouse.y
          }
          onPositionChanged: {
            if (root.dragOrder === null) return
            var dx = mouse.x - root.dragOriginX
            var dy = mouse.y - root.dragOriginY
            if (dx * dx + dy * dy < root.dragDeadzone * root.dragDeadzone) return
            var p = chipDrag.mapToItem(chipRow, mouse.x, mouse.y)
            var target = root.pinIndexAt(p.x, p.y)
            root.dragTarget = target
            root.dragGap = root.dropGapIndex(target)
          }
          onReleased: {
            if (root.dragOrder === null) return
            root.commitDrag(root.dragTarget)
          }
          onCanceled: {
            root.dragOrder = null
            root.dragOriginal = null
            root.dragId = ""
            root.dragTarget = -1
            root.dragCurrent = -1
            root.dragGap = -1
            root.dragOriginX = 0
            root.dragOriginY = 0
          }
        }

        Item {
          anchors.centerIn: parent
          width: chip.iconExtent
          height: chip.iconExtent

          Image {
            id: appIcon
            anchors.fill: parent
            source: chip.iconSource
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }

          Text {
            anchors.centerIn: parent
            visible: appIcon.status === Image.Error || appIcon.source.toString() === ""
            text: chip.pinnedSlot
              ? (chip.modelData.entry && chip.modelData.entry.name
                  ? chip.modelData.entry.name.charAt(0).toUpperCase()
                  : root.prettyPinName(chip.modelData.entryId).charAt(0) || "?")
              : root.verticalLabel(chip.toplevel)
            color: root.bar ? root.bar.barForeground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          Rectangle {
            visible: !chip.pinnedSlot && !chip.minimized
            width: parent.width
            height: Style.space(2)
            radius: 0
            color: chip.focused ? Color.accent : Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.5)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
          }

          Text {
            id: wsBadge
            visible: chip.elsewhere
            text: chip.toplevel && chip.toplevel.workspace && Number(chip.toplevel.workspace.id) > 0 ? String(chip.toplevel.workspace.id) : ""
            color: root.bar ? root.bar.barForeground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Math.max(6, Style.font.caption - 3)
            style: Text.Outline
            styleColor: Util.alpha(root.bar ? root.bar.background : Color.background, 0.7)
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: -Style.space(3)
            anchors.rightMargin: -Style.space(3)
          }
        }

        Component.onDestruction: {
          var tp = chip.toplevel
          if (root.hoverChip === chip) root.hoverChip = null
          if (root.dragOrder !== null && root.dragId === chip.pinHost) {
            root.dragOrder = null
            root.dragOriginal = null
            root.dragId = ""
            root.dragTarget = -1
            root.dragCurrent = -1
            root.dragGap = -1
          }
          if (root.menuAnchor === chip) {
            root.menuAnchor = null
            root.menuEntry = null
          }
          if (root.pendingPreviewAnchor === chip || (tp && root.pendingPreviewToplevel === tp)) {
            root.previewTimer.stop()
            root.pendingPreviewAnchor = null
            root.pendingPreviewToplevel = null
          }
          if (root.previewAnchor === chip || (tp && root.previewToplevel === tp)) {
            root.previewAnchor = null
            root.previewToplevel = null
          }
        }
      }
    }
  }

  Rectangle {
    id: dropBar
    visible: root.dragOrder !== null && root.dragGap >= 0
    width: root.vertical ? chipRow.width : Style.space(2)
    height: root.vertical ? Style.space(2) : chipRow.height
    radius: Style.space(2)
    color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.5)
    x: root.vertical ? chipRow.x : (chipRow.x + root.dropOffset(root.dragGap))
    y: root.vertical ? (chipRow.y + root.dropOffset(root.dragGap)) : (chipRow.y + (chipRow.height - height) / 2)
  }

  PopupCard {
    id: previewCard

    anchorItem: root.previewAnchor || root
    bar: root.bar
    triggerMode: "hover"
    open: root.previewToplevel !== null && root.previewAnchor !== null
      && (root.hoverChip === root.previewAnchor || previewCard.containsMouse)
    contentWidth: Style.space(320)
    contentHeight: Style.space(220)
    padding: Style.space(8)

    Item {
      anchors.fill: parent

      Item {
        id: previewFrame
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: previewTitle.top
        anchors.bottomMargin: Style.space(7)
        clip: true

        Image {
          width: Style.space(48)
          height: width
          anchors.centerIn: parent
          source: root.previewToplevel ? root.windowIcon(root.previewToplevel) : ""
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          opacity: previewView.hasContent ? 0 : 0.5
        }

        ScreencopyView {
          id: previewView
          anchors.fill: parent
          captureSource: root.previewToplevel
            ? (root.previewToplevel.wayland
                || (root.previewToplevel.real && root.previewToplevel.real.wayland)) : null
          live: previewCard.open
          paintCursor: false
        }
      }

      Text {
        id: previewTitle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: root.previewToplevel ? String(root.previewToplevel.title || "Window") : ""
        textFormat: Text.PlainText
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }

  QtObject {
    id: menuOwner
    function close() { root.close() }
  }

  PopupCard {
    id: menuCard

    anchorItem: root.menuAnchor || root
    bar: root.bar
    owner: menuOwner
    triggerMode: "click"
    open: root.menuEntry !== null
    contentWidth: menuCard.fittedContentWidth(Style.space(170))
    contentHeight: menuCard.fittedContentHeight(menuColumn.implicitHeight)
    padding: Style.space(6)

    Column {
      id: menuColumn
      width: parent.width
      spacing: Style.space(2)

      Repeater {
        model: root.menuItemsFor(root.menuEntry)

        Rectangle {
          id: menuRow
          required property var modelData
          width: menuColumn.width
          height: Style.space(26)
          radius: Style.space(4)
          color: itemHover.hovered
            ? Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.12) : "transparent"

          Behavior on color {
            ColorAnimation { duration: 100 }
          }

          HoverHandler { id: itemHover }

          TapHandler {
            onTapped: {
              var entry = root.menuEntry
              var action = menuRow.modelData.action
              root.close()
              if (entry && action) action(entry)
            }
          }

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: menuRow.modelData.label
            textFormat: Text.PlainText
            color: menuRow.modelData.destructive ? Color.urgent
              : (root.bar ? root.bar.barForeground : Color.foreground)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}