// Window-list helpers. Identity does not live here.
// shelfWorkspace is always "special:omarchy-minimized".

function normalizedAddress(toplevel) {
  if (!toplevel || !toplevel.address) return ""
  var address = String(toplevel.address)
  return address.indexOf("0x") === 0 ? address : "0x" + address
}

function isMinimized(toplevel, shelfWorkspace) {
  return toplevel !== null && toplevel.workspace !== null
    && toplevel.workspace.name === shelfWorkspace
}

function isFloatingWindow(toplevel) {
  if (!toplevel) return false
  return toplevel.floating === true
    || (toplevel.lastIpcObject && Number(toplevel.lastIpcObject.floating) === 1)
}

function identitySnapshot(snapshotByAddress, toplevel) {
  var addr = normalizedAddress(toplevel)
  if (!addr) return null
  return snapshotByAddress[addr] || null
}

function windowClass(snapshotByAddress, toplevel) {
  var ipc = toplevel && toplevel.lastIpcObject
  if (ipc && ipc.class) return String(ipc.class)
  var snap = identitySnapshot(snapshotByAddress, toplevel)
  var sipc = snap && snap.lastIpcObject
  if (sipc && sipc.class) return String(sipc.class)
  return ""
}

function isWineSystemClass(cls) {
  var low = String(cls || "").toLowerCase()
  return /^(explorer|services|winedevice|plugplay|svchost|rundll32|wineboot|winebrowser|tabtip)\.exe$/i.test(low)
}

function isWineSystemTitle(title) {
  var low = String(title || "").toLowerCase()
  return /^(wine system tray|default ime|gdi\+ window|msaa hook|wine gecko)$/i.test(low)
}

function isSteamSystemWindow(cls, title, isFloating) {
  var lowCls = String(cls || "").toLowerCase()
  var lowTitle = String(title || "").toLowerCase()
  if (lowCls === "steamwebhelper") return true
  if (lowCls === "steam") {
    if (!title) return true
    if (lowTitle.indexOf("friends list") === 0 || lowTitle.indexOf("friends & chat") === 0) return false
    if (lowTitle.indexOf("settings") !== -1) return false
    if (isFloating) return true
  }
  return false
}

function isTransientProgressWindow(title, isFloating) {
  if (!title) return false
  var low = String(title).trim()
  if (isFloating) {
    if (/^(launching|loading|preparing|configuring|updating|checking|starting|connecting|installing)/i.test(low)) return true
    if (/microsoft visual c\+\+/i.test(low)) return true
    if (/directx/i.test(low)) return true
  }
  return false
}

function isRelevantWindow(snapshotByAddress, shelfWorkspace, toplevel) {
  if (!toplevel) return false
  var ipc = toplevel.lastIpcObject || null
  var title = String(toplevel.title || "").trim()
  var cls = windowClass(snapshotByAddress, toplevel).trim()
  if (toplevel.hidden === true || (ipc && Number(ipc.hidden) === 1)) return false
  var workspace = toplevel.workspace || null
  if (workspace && String(workspace.name || "").indexOf("special:") === 0
      && String(workspace.name || "") !== shelfWorkspace) return false
  if (!cls) return false
  if (isWineSystemClass(cls) || isWineSystemTitle(title)) return false
  var floating = isFloatingWindow(toplevel)
  if (isSteamSystemWindow(cls, title, floating)) return false
  if (floating && !title) return false
  if (isTransientProgressWindow(title, floating)) return false
  return true
}

function isElsewhere(toplevel, shelfWorkspace, focusedWorkspace) {
  if (!toplevel || isMinimized(toplevel, shelfWorkspace)) return false
  var workspace = toplevel.workspace
  return workspace !== null && focusedWorkspace !== null && workspace.id !== focusedWorkspace.id
}

function isActiveToplevel(toplevel, activeWindow) {
  if (!activeWindow || !toplevel) return false
  var ta = normalizedAddress(toplevel)
  var aa = normalizedAddress(activeWindow)
  if (ta && aa) return ta === aa
  return toplevel === activeWindow
}

function windowTitle(toplevel, maxTitleLength) {
  var title = String(toplevel && toplevel.title ? toplevel.title : "Window").trim()
  if (title.length <= maxTitleLength) return title
  return title.substring(0, maxTitleLength - 3) + "..."
}

function verticalLabel(toplevel, maxTitleLength) {
  var ipc = toplevel ? toplevel.lastIpcObject : null
  var app = String(ipc && ipc.class ? ipc.class : windowTitle(toplevel, maxTitleLength)).trim()
  return app.length > 0 ? app.charAt(0).toUpperCase() : "W"
}

function anyOtherWindowVisible(liveWindows, snapshotByAddress, shelfWorkspace, excluding) {
  for (var i = 0; i < liveWindows.length; i++) {
    var candidate = liveWindows[i]
    if (candidate === excluding) continue
    if (!isRelevantWindow(snapshotByAddress, shelfWorkspace, candidate)) continue
    if (isMinimized(candidate, shelfWorkspace)) continue
    return true
  }
  return false
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
  return byAddr
}

function sameWindowList(a, b) {
  if (!a || !b || a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false
  }
  return true
}

function rebuildLiveWindows(snapshotByAddress, taskbarWindows, liveWindows, pseudoByAddress) {
  var byAddr = snapshotByAddress
  var hasSnapshot = Object.keys(byAddr).length > 0
  var list = []
  if (hasSnapshot) {
    var backrefs = {}
    for (var j = 0; j < taskbarWindows.length; j++) {
      var modelWindow = taskbarWindows[j]
      var maddr = normalizedAddress(modelWindow)
      if (maddr && !(maddr in backrefs)) backrefs[maddr] = modelWindow
    }
    for (var key in byAddr) {
      var snap = byAddr[key]
      var real = backrefs[key]
      if (real) {
        list.push(real)
      } else {
        var pseudo = pseudoByAddress[key]
        if (!pseudo) {
          pseudo = {}
          pseudoByAddress[key] = pseudo
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
    for (var i = 0; i < taskbarWindows.length; i++) {
      if (!normalizedAddress(taskbarWindows[i])) continue
      list.push(taskbarWindows[i])
    }
  }
  if (sameWindowList(liveWindows, list)) return { list: liveWindows, changed: false }
  return { list: list, changed: true }
}

function liveAddresses(windows) {
  var set = {}
  for (var i = 0; i < windows.length; i++) {
    var addr = normalizedAddress(windows[i])
    if (addr) set[addr] = true
  }
  return set
}

function pruneMap(map, keep) {
  if (!map) return
  for (var key in map) {
    if (!keep[key]) delete map[key]
  }
}

function pruneWindowMaps(maps, windows) {
  var keep = liveAddresses(windows)
  for (var i = 0; i < maps.length; i++) pruneMap(maps[i], keep)
}
