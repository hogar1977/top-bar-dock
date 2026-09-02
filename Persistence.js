// Pin file parse/serialize. Accepts v1 string arrays and v2 {id,kind,label} objects.

function parsePinned(content) {
  var ids = []
  var meta = {}
  try {
    var parsed = JSON.parse(String(content || "{}"))
    var raw = Array.isArray(parsed) ? parsed : parsed.pinned
    if (!Array.isArray(raw)) return { ids: ids, meta: meta }
    for (var i = 0; i < raw.length; i++) {
      var item = raw[i]
      if (typeof item === "string" && item) {
        ids.push(item)
        continue
      }
      if (item && typeof item === "object" && typeof item.id === "string" && item.id) {
        ids.push(item.id)
        meta[item.id] = {
          kind: typeof item.kind === "string" ? item.kind : "",
          label: typeof item.label === "string" ? item.label : ""
        }
      }
    }
  } catch (e) {
    return { ids: [], meta: {} }
  }
  return { ids: ids, meta: meta }
}

function serializePinned(ids, meta) {
  var out = []
  var table = meta || {}
  for (var i = 0; i < (ids ? ids.length : 0); i++) {
    var id = ids[i]
    if (!id) continue
    var m = table[id]
    if (m && (m.kind || m.label)) {
      var obj = { id: id }
      if (m.kind) obj.kind = m.kind
      if (m.label) obj.label = m.label
      out.push(obj)
    } else {
      out.push(id)
    }
  }
  return JSON.stringify({ version: 2, pinned: out }, null, 2) + "\n"
}

function isGenericClientId(id) {
  var low = String(id || "").toLowerCase()
  return low === "steam" || low === "vivaldi-stable"
}

function shouldUpgradePin(fromId, toId) {
  if (!fromId || !toId || fromId === toId) return false
  if (isGenericClientId(toId) && !isGenericClientId(fromId)) return false
  return true
}

function pinKindOf(id) {
  var value = String(id || "")
  if (value === "steam-friends" || value === "steam-settings") return "steam-surface"
  if (/^steam-app-\d+$/.test(value)) return "steam-app"
  return "desktop"
}
