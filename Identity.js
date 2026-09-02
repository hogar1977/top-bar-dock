// Identity engine: keep Vivaldi web-apps and Steam surfaces as separate dock entities.
// Scoring weights must stay: 100000, 60000, 30000, 20000, 3000, 900, 500, 300, 150, 120, 300000, 2500.
//
// Fixtures (window → pinId / relevant):
//   vivaldi-stable browser          → vivaldi-stable          ≠ Photocrowd/YouTube/Gemini
//   Photocrowd / YouTube / Gemini   → that web-app pin        ≠ vivaldi-stable
//   Steam client                    → steam                   ≠ steam-friends / steam-app-*
//   Friends List / Friends & Chat   → steam-friends           ≠ steam
//   Steam Settings                  → steam-settings          ≠ steam
//   steam_app_<id> game             → steam-app-<id> or game  ≠ steam
//   Steam "Launching…"/untitled float → not relevant
//   Two windows of one desktop id   → one chip

function normalizedAddress(toplevel) {
  if (!toplevel || !toplevel.address) return ""
  var address = String(toplevel.address)
  return address.indexOf("0x") === 0 ? address : "0x" + address
}

function identitySnapshot(ctx, toplevel) {
  var addr = normalizedAddress(toplevel)
  if (!addr) return null
  return ctx.snapshotByAddress[addr] || null
}

function windowIdentityCandidates(ctx, toplevel) {
  if (!toplevel) return []
  var ipc = toplevel.lastIpcObject || null
  var wayland = toplevel.wayland || null
  var snap = identitySnapshot(ctx, toplevel)
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

function identityFingerprint(ctx, toplevel) {
  return windowIdentityCandidates(ctx, toplevel).join("|") + "\0" + String(toplevel && toplevel.title ? toplevel.title : "")
}

function cachedRecord(ctx, toplevel) {
  var addr = normalizedAddress(toplevel)
  var fp = identityFingerprint(ctx, toplevel)
  if (addr && ctx.identityCache) {
    var hit = ctx.identityCache[addr]
    if (hit && hit.generation === ctx.identityGeneration && hit.fp === fp) return hit
  }
  var rec = computeRecord(ctx, toplevel)
  rec.generation = ctx.identityGeneration
  rec.fp = fp
  if (addr && ctx.identityCache) ctx.identityCache[addr] = rec
  return rec
}

function computeRecord(ctx, toplevel) {
  var candidates = windowIdentityCandidates(ctx, toplevel)
  var steamAppId = steamAppIdFromCandidates(candidates)
  var steamSurface = steamSurfaceId(toplevel)
  var entry = computeDesktopEntry(ctx, toplevel, candidates, steamAppId)
  var pinId = ""
  if (steamAppId) {
    pinId = entry && entry.id ? entry.id : "steam-app-" + steamAppId
  } else if (entry && entry.id) {
    if (entry.id === "steam" && steamSurface) pinId = steamSurface
    else pinId = entry.id
  } else {
    pinId = candidates.length > 0 ? candidates[0] : ""
  }
  return {
    candidates: candidates,
    entry: entry,
    pinId: pinId,
    steamAppId: steamAppId,
    steamSurface: steamSurface
  }
}

function steamAppIdFromCandidates(candidates) {
  for (var i = 0; i < candidates.length; i++) {
    var m = String(candidates[i] || "").trim().match(/^steam[_ -]?app[_ -]?(\d+)$/i)
    if (m) return m[1]
  }
  return ""
}

function steamAppIdOf(ctx, toplevel) {
  return cachedRecord(ctx, toplevel).steamAppId
}

function steamSurfaceId(toplevel) {
  var title = String(toplevel && toplevel.title ? toplevel.title : "").toLowerCase()
  if (title.indexOf("friends list") === 0 || title.indexOf("friends & chat") === 0) {
    return "steam-friends"
  }
  if (title.indexOf("settings") !== -1) return "steam-settings"
  return ""
}

function entryForAppId(ctx, appid) {
  if (!appid) return null
  var index = ctx.entryIndex
  if (!index) return null
  for (var i = 0; i < index.length; i++) {
    if (index[i].execText && index[i].execText.indexOf("rungameid " + appid) !== -1) {
      return index[i].entry
    }
  }
  return null
}

function idTokens(value) {
  return String(value || "").toLowerCase().split(/[^a-z0-9]+/)
    .filter(function(t) { return t.length > 0 })
}

function heuristicEntryFor(ctx, name) {
  name = String(name || "")
  var desktop = ctx.desktop
  var direct = desktop.heuristicLookup(name)
  if (direct) return direct
  var tokens = idTokens(name)
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].length < 3) continue
    var check = desktop.heuristicLookup(tokens[i])
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
  return fieldTokens(value).filter(function(t) { return !isStopToken(t) && t.length >= 3 })
}

function rebuildEntryIndex(desktop) {
  var apps = desktop.applications
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
  return index
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

function scoredDesktopEntry(ctx, candidates) {
  var index = ctx.entryIndex
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
      var score = rowScore(index[j], c)
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

function computeDesktopEntry(ctx, toplevel, candidates, appid) {
  if (appid) {
    var appEntry = entryForAppId(ctx, appid)
    if (appEntry) return appEntry
    return null
  }
  var desktop = ctx.desktop
  for (var i = 0; i < candidates.length; i++) {
    if (looksLikeWebappClass(candidates[i])) continue
    var direct = desktop.heuristicLookup(candidates[i])
    if (direct) return direct
  }
  var scored = scoredDesktopEntry(ctx, candidates)
  if (scored) return scored
  for (var h = 0; h < candidates.length; h++) {
    var viaToken = heuristicEntryFor(ctx, candidates[h])
    if (viaToken) return viaToken
  }
  var withTitle = candidates.concat([String(toplevel && toplevel.title ? toplevel.title : "")])
  return scoredDesktopEntry(ctx, withTitle)
}

function desktopEntry(ctx, toplevel) {
  return cachedRecord(ctx, toplevel).entry
}

function windowPinId(ctx, toplevel) {
  return cachedRecord(ctx, toplevel).pinId
}

function entryForId(ctx, pinId) {
  if (!pinId) return null
  var steamMatch = String(pinId).match(/^steam-app-(\d+)$/)
  if (steamMatch) return entryForAppId(ctx, steamMatch[1])
  var direct = ctx.desktop.byId(pinId)
  if (direct) return direct
  return heuristicEntryFor(ctx, pinId)
}

function fallbackPinId(ctx, toplevel) {
  var candidates = windowIdentityCandidates(ctx, toplevel)
  return candidates.length > 0 ? candidates[0] : ""
}

function pinMatchesWindow(ctx, isRelevant, pinId, toplevel) {
  if (!pinId || !toplevel || !isRelevant(toplevel)) return false
  var low = String(pinId).toLowerCase()
  if (low.indexOf("steam-app-") === 0) {
    var appMatch = low.match(/^steam-app-(\d+)$/)
    var winId = windowPinId(ctx, toplevel)
    if (low === winId) return true
    if (appMatch) {
      var appEntry = entryForAppId(ctx, appMatch[1])
      if (appEntry && appEntry.id && appEntry.id === winId) return true
    }
    return false
  }
  if (low.indexOf("steam-") === 0) return low === windowPinId(ctx, toplevel)
  var entry = desktopEntry(ctx, toplevel)
  if (entry && entry.id && entry.id.toLowerCase() === low) return true
  var candidates = windowIdentityCandidates(ctx, toplevel)
  for (var i = 0; i < candidates.length; i++) {
    if (candidates[i].toLowerCase() === low) return true
  }
  var pinTokens = meaningfulTokens(pinId)
  if (pinTokens.length) {
    var shared = {}
    for (var wc = 0; wc < candidates.length; wc++) {
      var winTokens = meaningfulTokens(candidates[wc])
      for (var wt = 0; wt < winTokens.length; wt++) {
        if (pinTokens.indexOf(winTokens[wt]) !== -1) shared[winTokens[wt]] = true
      }
    }
    var titleTokens = meaningfulTokens(String(toplevel.title || ""))
    for (var tl = 0; tl < titleTokens.length; tl++) {
      if (pinTokens.indexOf(titleTokens[tl]) !== -1) shared[titleTokens[tl]] = true
    }
    var sharedCount = 0
    for (var sk in shared) sharedCount++
    if (sharedCount >= 2) return true
  }
  return false
}

function prettyPinName(ctx, pinId) {
  var value = String(pinId || "")
  if (value === "steam") return "Steam"
  if (value === "steam-friends") return "Steam Friends"
  if (value === "steam-settings") return "Steam Settings"
  var steamMatch = value.match(/^steam-app-(\d+)$/)
  if (steamMatch) {
    var appEntry = entryForAppId(ctx, steamMatch[1])
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

function bumpIdentityGeneration(ctx) {
  ctx.identityGeneration = (ctx.identityGeneration || 0) + 1
  ctx.identityCache = {}
}
