// Pure dock-entry builder and pin-order helpers.

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

function pinIndexAt(inX, inY, barSize, spacing, dockLength, pinnedLength, vertical) {
  var advance = barSize + spacing
  var offset = vertical ? inY : inX
  var idx = Math.round((offset - barSize / 2) / advance)
  idx = Math.max(0, Math.min(idx, dockLength))
  idx = Math.min(idx, pinnedLength)
  return idx
}

function dropGapIndex(target, dragCurrent, pinnedLength) {
  var gap = target <= dragCurrent ? target : target + 1
  return Math.max(0, Math.min(gap, pinnedLength))
}

function dropOffset(gap, barSize, spacing, barPad) {
  var advance = barSize + spacing
  if (gap === 0) return 0
  return gap * advance - (spacing + barPad) / 2
}

function previewCardTitle(entry, prettyName) {
  if (!entry) return ""
  var ws = entry.windows || (entry.toplevel ? [entry.toplevel] : [])
  if (ws.length <= 1) return String(entry.toplevel ? (entry.toplevel.title || "Window") : "")
  var name = prettyName || ""
  return name ? (name + " — " + ws.length + " windows") : (ws.length + " windows")
}

function previewStillValid(previewEntry, entries) {
  if (!previewEntry || !previewEntry.windows || !entries) return false
  var placed = {}
  for (var s = 0; s < entries.length; s++) {
    var wins = entries[s].windows || []
    for (var w = 0; w < wins.length; w++) {
      var addr = optsAddress(wins[w])
      if (addr) placed[addr] = true
    }
  }
  for (var pd = 0; pd < previewEntry.windows.length; pd++) {
    var paddr = optsAddress(previewEntry.windows[pd])
    if (paddr && placed[paddr]) return true
  }
  return false
}

function optsAddress(toplevel) {
  if (!toplevel || !toplevel.address) return ""
  var address = String(toplevel.address)
  return address.indexOf("0x") === 0 ? address : "0x" + address
}

// opts: {
//   dragOrder,
//   isRelevantWindow(w),
//   pinMatchesWindow(pid, w),
//   desktopEntry(w),
//   entryForId(pid),
//   windowPinId(w),
//   normalizedAddress(w),
//   isPseudo(w)
// }
function buildEntries(windows, pinned, opts) {
  var entries = []
  var placed = {}
  var order = opts.dragOrder !== null && opts.dragOrder !== undefined ? opts.dragOrder : pinned
  for (var i = 0; i < order.length; i++) {
    var pid = order[i]
    var group = []
    for (var w = 0; w < windows.length; w++) {
      var addr2 = opts.normalizedAddress(windows[w])
      if (!addr2 || placed[addr2] || !opts.isRelevantWindow(windows[w])) continue
      if (opts.pinMatchesWindow(pid, windows[w])) group.push(windows[w])
    }
    if (group.length > 0) {
      var groupEntry = null
      for (var ge = 0; ge < group.length; ge++) {
        var candidateEntry = opts.desktopEntry(group[ge])
        if (candidateEntry && candidateEntry.id) { groupEntry = candidateEntry; break }
      }
      entries.push({
        kind: "window",
        pinId: pid,
        appKey: pid,
        toplevel: group[0],
        windows: group,
        entry: groupEntry || opts.entryForId(pid)
      })
      for (var pa = 0; pa < group.length; pa++) placed[opts.normalizedAddress(group[pa])] = true
    } else {
      entries.push({ kind: "pinned", pinId: pid, entryId: pid, entry: opts.entryForId(pid), toplevel: null })
    }
  }
  var tailGroups = []
  for (var j = 0; j < windows.length; j++) {
    var jaddr = opts.normalizedAddress(windows[j])
    if (!jaddr || placed[jaddr] || !opts.isRelevantWindow(windows[j])) continue
    var key = opts.windowPinId(windows[j])
    var bi = -1
    for (var k = 0; k < tailGroups.length; k++) {
      if (tailGroups[k].key === key) { bi = k; break }
    }
    if (bi === -1) {
      tailGroups.push({ key: key, entry: opts.desktopEntry(windows[j]), windows: [windows[j]] })
    } else {
      tailGroups[bi].windows.push(windows[j])
    }
    placed[jaddr] = true
  }
  for (var t = 0; t < tailGroups.length; t++) {
    entries.push({
      kind: "window",
      pinId: "",
      appKey: tailGroups[t].key,
      toplevel: tailGroups[t].windows[0],
      windows: tailGroups[t].windows,
      entry: tailGroups[t].entry
    })
  }
  var sig = ""
  for (var s = 0; s < entries.length; s++) {
    var e = entries[s]
    if (e.kind === "pinned") { sig += "p:" + e.entryId + ";"; continue }
    sig += (e.pinId ? "P" : "T") + ":" + e.appKey + ":"
    for (var sa = 0; sa < e.windows.length; sa++) {
      var swa = opts.normalizedAddress(e.windows[sa])
      sig += "w:" + swa
      if (opts.isPseudo(e.windows[sa])) {
        sig += "s:" + ((e.windows[sa].workspace && e.windows[sa].workspace.name) || "")
      }
      sig += ","
    }
    sig += ";"
  }
  return { entries: entries, sig: sig }
}
