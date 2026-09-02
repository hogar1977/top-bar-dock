// Hyprland Lua dispatch strings. Callers spawn them via Util.shellQuote.

function moveRequest(toplevel, workspace, follow) {
  var address = addressOf(toplevel)
  if (!address || !workspace) return ""
  return "hl.dsp.window.move({ workspace = " + JSON.stringify(workspace)
    + ", window = " + JSON.stringify("address:" + address)
    + ", follow = " + (follow ? "true" : "false") + " })"
}

function windowFloatRequest(toplevel, action) {
  var address = addressOf(toplevel)
  if (!address) return ""
  return "hl.dsp.window.float({ action = " + JSON.stringify(action)
    + ", window = " + JSON.stringify("address:" + address) + " })"
}

function windowFullscreenRequest(toplevel, fullscreenMode) {
  var address = addressOf(toplevel)
  if (!address || fullscreenMode <= 0) return ""
  var mode = fullscreenMode === 1 ? "maximized" : "fullscreen"
  return "hl.dsp.window.fullscreen({ mode = " + JSON.stringify(mode)
    + ", window = " + JSON.stringify("address:" + address) + " })"
}

function windowCloseRequest(toplevel) {
  var address = addressOf(toplevel)
  if (!address) return ""
  return "hl.dsp.window.close({ window = " + JSON.stringify("address:" + address) + " })"
}

function windowFocusRequest(toplevel) {
  var address = addressOf(toplevel)
  if (!address) return ""
  return "hl.dsp.focus({ window = " + JSON.stringify("address:" + address) + " })"
}

function launchExecCmd(rawExec) {
  if (!rawExec) return ""
  return String(rawExec).replace(/%%/g, "\u0000")
    .replace(/%[UuFfDdNniIcCkKvm]/g, "")
    .replace(/\u0000/g, "%")
    .replace(/\s{2,}/g, " ")
    .trim()
}

function steamLaunchArgv(entryId) {
  var steamMatch = String(entryId || "").match(/^steam-app-(\d+)$/)
  if (steamMatch) return ["steam", "steam://rungameid/" + steamMatch[1]]
  if (entryId === "steam-friends") return ["steam", "steam://open/friends"]
  if (entryId === "steam-settings") return ["steam", "steam://open/settings"]
  return null
}

function addressOf(toplevel) {
  if (!toplevel || !toplevel.address) return ""
  var address = String(toplevel.address)
  return address.indexOf("0x") === 0 ? address : "0x" + address
}
