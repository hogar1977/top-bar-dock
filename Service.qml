import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons

import "Identity.js" as Identity
import "Windows.js" as Windows
import "Compositor.js" as Compositor
import "Dock.js" as Dock
import "Persistence.js" as Persistence

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null

  readonly property string moduleName: "io.github.hogar1977.top-bar-dock"
  readonly property string shelfWorkspace: "special:omarchy-minimized"
  readonly property int toggleGraceMs: 1000
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string stateDir: stateHome + "/omarchy/top-bar-dock"
  readonly property string pinnedFilePath: stateDir + "/pinned.json"
  readonly property string legacyPinnedPath: home + "/.config/omarchy/plugins/io.github.hogar1977.top-bar-dock/pinned.json"

  readonly property var taskbarWindows: Hyprland.toplevels.values
  readonly property var activeWindow: Hyprland.activeToplevel
  readonly property var currentWorkspace: Hyprland.focusedWorkspace
  readonly property int currentWorkspaceId: currentWorkspace ? currentWorkspace.id : -1

  property var pinnedIds: []
  property var pinMeta: ({})
  property var entryIndex: []
  property var snapshotByAddress: ({})
  property var liveWindows: []
  property var pseudoByAddress: ({})
  property var identityCache: ({})
  property int identityGeneration: 0
  property int appVersion: 0
  property var dockCache: ({ sig: "__init__", entries: [] })
  readonly property var dockEntries: dockCache.entries
  property var dragOrder: null
  property var dragOriginal: null
  property string dragId: ""
  property int dragTarget: -1
  property int dragCurrent: -1
  property int dragGap: -1
  property real dragOriginX: 0
  property real dragOriginY: 0
  readonly property real dragDeadzone: 10
  property var lastToggleByAddress: ({})
  property var lastWorkspaceByAddress: ({})
  property bool refreshPending: false
  property bool migratedLegacy: false
  property bool persistReady: false
  property bool upgradingPins: false

  function identityCtx() {
    return {
      desktop: DesktopEntries,
      entryIndex: root.entryIndex,
      snapshotByAddress: root.snapshotByAddress,
      identityCache: root.identityCache,
      identityGeneration: root.identityGeneration
    }
  }

  function isMinimized(toplevel) {
    return Windows.isMinimized(toplevel, root.shelfWorkspace)
  }

  function isRelevantWindow(toplevel) {
    return Windows.isRelevantWindow(root.snapshotByAddress, root.shelfWorkspace, toplevel)
  }

  function isElsewhere(toplevel) {
    return Windows.isElsewhere(toplevel, root.shelfWorkspace, Hyprland.focusedWorkspace)
  }

  function isActiveToplevel(toplevel) {
    return Windows.isActiveToplevel(toplevel, root.activeWindow)
  }

  function normalizedAddress(toplevel) {
    return Windows.normalizedAddress(toplevel)
  }

  function windowTitle(toplevel, maxTitleLength) {
    return Windows.windowTitle(toplevel, maxTitleLength)
  }

  function verticalLabel(toplevel, maxTitleLength) {
    return Windows.verticalLabel(toplevel, maxTitleLength)
  }

  function desktopEntry(toplevel) {
    return Identity.desktopEntry(root.identityCtx(), toplevel)
  }

  function windowPinId(toplevel) {
    return Identity.windowPinId(root.identityCtx(), toplevel)
  }

  function entryForId(pinId) {
    return Identity.entryForId(root.identityCtx(), pinId)
  }

  function pinMatchesWindow(pinId, toplevel) {
    return Identity.pinMatchesWindow(root.identityCtx(), root.isRelevantWindow, pinId, toplevel)
  }

  function prettyPinName(pinId) {
    var meta = root.pinMeta[pinId]
    if (meta && meta.label) return meta.label
    return Identity.prettyPinName(root.identityCtx(), pinId)
  }

  function iconFromEntry(entry) {
    var icon = String(entry && entry.icon ? entry.icon : "")
    var lib = root.shell && root.shell.appLibrary
    if (lib && typeof lib.iconSource === "function") return lib.iconSource(icon)
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
    var entry = root.desktopEntry(toplevel)
    if (!entry) return ""
    return root.iconFromEntry(entry)
  }

  function previewCardTitle(entry) {
    return Dock.previewCardTitle(entry, root.prettyPinName(entry && entry.appKey ? entry.appKey : ""))
  }

  function dispatch(expr) {
    if (!expr) return
    Util.execDetached("hyprctl dispatch " + Util.shellQuote(expr))
  }

  function dispatchSteps(exprs) {
    var steps = []
    for (var i = 0; i < exprs.length; i++) {
      if (exprs[i]) steps.push("hyprctl dispatch " + Util.shellQuote(exprs[i]))
    }
    if (steps.length === 0) return
    if (steps.length === 1) {
      Util.execDetached(steps[0])
      return
    }
    Util.execDetached("(" + steps.join(" ; ") + ")")
  }

  function fallbackWorkspace() {
    var workspace = Hyprland.focusedWorkspace
    if (workspace && String(workspace.name).indexOf("special:") !== 0)
      return workspace.name
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var n = String(values[i].name || "")
      if (n && n.indexOf("special:") !== 0) return n
    }
    return "1"
  }

  function focusWindow(toplevel) {
    root.dispatch(Compositor.windowFocusRequest(toplevel))
  }

  function closeWindow(toplevel) {
    root.dispatch(Compositor.windowCloseRequest(toplevel))
  }

  function restoreTiled(toplevel, destination) {
    var moveExpr = Compositor.moveRequest(toplevel, destination, false)
    if (!moveExpr) return
    var steps = [moveExpr, Compositor.windowFocusRequest(toplevel)]
    var floatOff = Compositor.windowFloatRequest(toplevel, "off")
    if (floatOff) steps.push(floatOff)
    var ipc = toplevel.lastIpcObject || null
    if (ipc && Number(ipc.fullscreen) === 1) {
      var unmax = Compositor.windowFullscreenRequest(toplevel, 1)
      if (unmax) steps.push(unmax)
    }
    root.dispatchSteps(steps)
  }

  function restore(toplevel) {
    var addr = root.normalizedAddress(toplevel)
    var ws = addr && root.lastWorkspaceByAddress[addr]
    root.restoreTiled(toplevel, ws || root.fallbackWorkspace())
  }

  function minimize(toplevel) {
    var addr = root.normalizedAddress(toplevel)
    var workspace = toplevel.workspace
    if (addr && workspace && workspace.name) {
      root.lastWorkspaceByAddress[addr] = workspace.name
    }
    root.dispatch(Compositor.moveRequest(toplevel, root.shelfWorkspace, false))
  }

  function maximizeWindow(toplevel) {
    var fsExpr = Compositor.windowFullscreenRequest(toplevel, 1)
    if (!fsExpr) return
    var steps = []
    if (root.isMinimized(toplevel)) {
      var moveExpr = Compositor.moveRequest(toplevel, root.fallbackWorkspace(), false)
      if (moveExpr) steps.push(moveExpr)
    }
    steps.push(Compositor.windowFocusRequest(toplevel))
    steps.push(fsExpr)
    root.dispatchSteps(steps)
  }

  function toggleWindow(toplevel) {
    var addr = root.normalizedAddress(toplevel)
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
    if (root.isMinimized(toplevel)) {
      root.lastToggleByAddress[addr] = { action: "restore", ts: now }
      root.restore(toplevel)
    } else if (root.isElsewhere(toplevel)) {
      root.lastToggleByAddress[addr] = { action: "focus", ts: now }
      root.focusWindow(toplevel)
    } else {
      root.lastToggleByAddress[addr] = { action: "minimize", ts: now }
      root.minimize(toplevel)
    }
  }

  function activateTile(toplevel) {
    if (!toplevel) return
    if (root.isMinimized(toplevel)) root.restore(toplevel)
    else root.focusWindow(toplevel)
  }

  function launchDesktop(entryId, name) {
    if (!entryId) return
    var lib = root.shell && root.shell.appLibrary
    if (lib && typeof lib.launch === "function") {
      lib.launch(entryId, name)
      return
    }
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(entryId + ".desktop"))
  }

  function launchNewInstance(entry) {
    if (!entry) return
    // gtk-launch / AppLibrary.launch activate an existing D-Bus instance
    // (Nautilus just raises the current window). Run the stripped Exec=
    // line so this menu item actually starts another process.
    var exec = Compositor.launchExecCmd(entry.execString)
    if (exec) {
      Util.execArgv(["uwsm-app", "--", "sh", "-c", exec])
      return
    }
    root.launchDesktop(entry.id, entry.name)
  }

  function launchPinned(entryId) {
    if (!entryId) return
    var steamArgv = Compositor.steamLaunchArgv(entryId)
    if (steamArgv) {
      Util.execArgv(steamArgv)
      return
    }
    var entry = root.entryForId(entryId)
    root.launchDesktop(entry ? entry.id : entryId, entry ? entry.name : "")
  }

  function isPinned(entryId) {
    return !!entryId && root.pinnedIds.indexOf(entryId) !== -1
  }

  function persistPins() {
    if (!root.persistReady) return
    pinnedFile.setText(Persistence.serializePinned(root.pinnedIds, root.pinMeta))
  }

  function applyParsedPins(parsed) {
    root.pinnedIds = parsed.ids
    root.pinMeta = parsed.meta
    root.refreshDock()
  }

  function writePinned(list) {
    root.pinnedIds = list
    root.persistPins()
    root.refreshDock()
  }

  function togglePin(entryId) {
    if (!entryId) return
    var next = root.isPinned(entryId)
      ? root.pinnedIds.filter(function(p) { return p !== entryId })
      : root.pinnedIds.concat([entryId])
    if (!root.isPinned(entryId) && !root.pinMeta[entryId]) {
      var meta = {}
      for (var k in root.pinMeta) meta[k] = root.pinMeta[k]
      meta[entryId] = { kind: Persistence.pinKindOf(entryId), label: root.prettyPinName(entryId) }
      root.pinMeta = meta
    }
    root.writePinned(next)
  }

  function commitDrag(targetIndex) {
    var source = root.dragOrder !== null ? root.dragOrder : root.pinnedIds
    var baseline = root.dragOriginal !== null ? root.dragOriginal : root.pinnedIds
    if (targetIndex === source.indexOf(root.dragId)) {
      root.resetDrag()
      return
    }
    var next = Dock.movePin(source, root.dragId, targetIndex)
    if (next.join(",") !== baseline.join(",")) root.writePinned(next)
    root.resetDrag()
  }

  function stepPin(entryId, delta) {
    var from = root.pinnedIds.indexOf(entryId)
    if (from === -1) return
    var to = from + delta
    if (to < 0 || to >= root.pinnedIds.length) return
    root.writePinned(Dock.movePin(root.pinnedIds, entryId, to))
  }

  function resetDrag() {
    root.dragOrder = null
    root.dragOriginal = null
    root.dragId = ""
    root.dragTarget = -1
    root.dragCurrent = -1
    root.dragGap = -1
    root.dragOriginX = 0
    root.dragOriginY = 0
    root.refreshDock()
  }

  function beginDrag(pinHost, originX, originY) {
    if (root.dragOrder !== null || !pinHost) return
    root.dragOrder = root.pinnedIds.slice()
    root.dragOriginal = root.pinnedIds.slice()
    root.dragId = pinHost
    var pinIndex = root.pinnedIds.indexOf(pinHost)
    root.dragTarget = pinIndex
    root.dragCurrent = pinIndex
    root.dragGap = -1
    root.dragOriginX = originX
    root.dragOriginY = originY
    root.refreshDock()
  }

  function updateDrag(target) {
    root.dragTarget = target
    root.dragGap = Dock.dropGapIndex(target, root.dragCurrent, root.pinnedIds.length)
  }

  function pinIndexAt(inX, inY, barSize, spacing, vertical) {
    return Dock.pinIndexAt(inX, inY, barSize, spacing, root.dockEntries.length, root.pinnedIds.length, vertical)
  }

  function dropOffset(gap, barSize, spacing, barPad) {
    return Dock.dropOffset(gap, barSize, spacing, barPad)
  }

  function moveMenuItems(entryId) {
    var idx = root.pinnedIds.indexOf(entryId)
    if (idx === -1) return []
    var items = []
    if (idx > 0)
      items.push({ label: "Move left", action: function() { root.stepPin(entryId, -1) } })
    if (idx < root.pinnedIds.length - 1)
      items.push({ label: "Move right", action: function() { root.stepPin(entryId, 1) } })
    return items
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
    var wins = (entryObj.windows && entryObj.windows.length > 1) ? entryObj.windows : null
    var items = []
    if (launchId)
      items.push({ label: "Open new instance", action: function(e) { root.launchNewInstance(e.toplevel ? root.desktopEntry(e.toplevel) : null) } })
    if (wins) {
      for (var wi = 0; wi < wins.length; wi++) {
        items.push({
          label: "Focus/Restore — " + root.windowTitle(wins[wi], 18),
          action: (function(w) { return function() { root.activateTile(w) } })(wins[wi])
        })
        items.push({
          label: "Close — " + root.windowTitle(wins[wi], 18), destructive: true,
          action: (function(w) { return function() { root.closeWindow(w) } })(wins[wi])
        })
      }
    }
    items = items.concat(root.moveMenuItems(entryObj.pinId || ""))
    if (wins) {
      items.push({
        label: root.isPinned(entryObj.appKey) ? "Unpin from dock" : "Pin to dock",
        action: function(e) { root.togglePin(e.appKey) }
      })
      items.push({
        label: "Close all instances", destructive: true,
        action: function(e) { for (var ci = 0; ci < e.windows.length; ci++) root.closeWindow(e.windows[ci]) }
      })
      return items
    }
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

  function rebuildEntryIndex() {
    root.entryIndex = Identity.rebuildEntryIndex(DesktopEntries)
    root.identityGeneration += 1
    root.identityCache = ({})
    root.appVersion += 1
    root.refreshDock()
  }

  function applyClients(clients) {
    root.snapshotByAddress = Windows.applySnapshot(clients)
    root.rebuildLiveWindows()
  }

  function rebuildLiveWindows() {
    var result = Windows.rebuildLiveWindows(
      root.snapshotByAddress, root.taskbarWindows, root.liveWindows, root.pseudoByAddress)
    if (!result.changed) {
      root.refreshDock()
      return
    }
    root.liveWindows = result.list
    Windows.pruneWindowMaps([
      root.pseudoByAddress,
      root.lastToggleByAddress,
      root.lastWorkspaceByAddress,
      root.identityCache
    ], root.liveWindows)
    root.appVersion += 1
    root.refreshDock()
  }

  function upgradeMatchedPins(entries) {
    var next = root.pinnedIds.slice()
    var meta = {}
    for (var k in root.pinMeta) meta[k] = root.pinMeta[k]
    var changed = false
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e.kind !== "window" || !e.pinId || !e.toplevel) continue
      var resolved = root.windowPinId(e.toplevel)
      if (!Persistence.shouldUpgradePin(e.pinId, resolved)) continue
      var idx = next.indexOf(e.pinId)
      if (idx === -1) continue
      if (next.indexOf(resolved) !== -1) continue
      next[idx] = resolved
      meta[resolved] = {
        kind: Persistence.pinKindOf(resolved),
        label: meta[e.pinId] && meta[e.pinId].label ? meta[e.pinId].label : root.prettyPinName(e.pinId)
      }
      changed = true
    }
    if (!changed) return
    root.pinMeta = meta
    root.pinnedIds = next
    root.persistPins()
    if (!root.upgradingPins) {
      root.upgradingPins = true
      root.refreshDock()
      root.upgradingPins = false
    }
  }

  function refreshDock() {
    var next = Dock.buildEntries(root.liveWindows, root.pinnedIds, {
      dragOrder: root.dragOrder,
      isRelevantWindow: root.isRelevantWindow,
      pinMatchesWindow: root.pinMatchesWindow,
      desktopEntry: root.desktopEntry,
      entryForId: root.entryForId,
      windowPinId: root.windowPinId,
      normalizedAddress: root.normalizedAddress,
      isPseudo: function(w) { return !!w && root.pseudoByAddress[root.normalizedAddress(w)] === w }
    })
    if (next.sig === root.dockCache.sig && root.dockCache.entries.length === next.entries.length)
      return
    root.dockCache = { sig: next.sig, entries: next.entries }
    if (root.persistReady && root.dragOrder === null && !root.upgradingPins)
      root.upgradeMatchedPins(next.entries)
  }

  function scheduleSnapshot() {
    snapshotDebounce.restart()
  }

  function runSnapshot() {
    if (snapshotProcess.running) {
      root.refreshPending = true
      return
    }
    root.refreshPending = false
    snapshotProcess.running = true
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rebuildEntryIndex() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name === "configreloaded" || name.indexOf("window") !== -1
          || name === "workspace" || name === "focusedmon" || name === "urgent"
          || name === "changefloatingmode" || name === "fullscreen") {
        root.scheduleSnapshot()
      }
    }
  }

  onTaskbarWindowsChanged: root.rebuildLiveWindows()

  FileView {
    id: pinnedFile
    path: ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.persistReady = true
      root.applyParsedPins(Persistence.parsePinned(text()))
    }
    onLoadFailed: {
      if (!root.migratedLegacy) {
        root.migratedLegacy = true
        legacyPinnedFile.reload()
        return
      }
      root.persistReady = true
      root.pinnedIds = []
      root.pinMeta = ({})
    }
  }

  FileView {
    id: legacyPinnedFile
    path: root.legacyPinnedPath
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.applyParsedPins(Persistence.parsePinned(text()))
      root.persistReady = true
      root.persistPins()
    }
    onLoadFailed: {
      root.persistReady = true
      root.pinnedIds = []
      root.pinMeta = ({})
    }
  }

  Process {
    id: snapshotProcess
    command: ["/usr/bin/hyprctl", "-j", "clients"]
    stdout: StdioCollector { id: snapshotOutput; waitForEnd: true }
    onRunningChanged: {
      if (running) {
        stallTimer.restart()
        return
      }
      stallTimer.stop()
      if (root.refreshPending) root.runSnapshot()
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && snapshotOutput.text) {
        try {
          root.applyClients(JSON.parse(snapshotOutput.text))
        } catch (err) {
          snapshotOutput.text = ""
        }
      }
    }
  }

  Timer {
    id: snapshotDebounce
    interval: 120
    onTriggered: root.runSnapshot()
  }

  Timer {
    id: stallTimer
    interval: 5000
    onTriggered: {
      snapshotProcess.running = false
      snapshotDebounce.restart()
    }
  }

  Timer {
    id: safetySnapshot
    interval: 20000
    repeat: true
    running: true
    onTriggered: root.scheduleSnapshot()
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir]
    onExited: {
      pinnedFile.path = root.pinnedFilePath
      pinnedFile.reload()
    }
  }

  Component.onCompleted: {
    mkdirProc.running = true
    root.rebuildEntryIndex()
    root.scheduleSnapshot()
  }
}
