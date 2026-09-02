# Identity fixtures

These rows must stay green. The matcher lives in `Identity.js`; do not replace
it with AppSearch / heuristicLookup-only.

| Window (Hyprland) | Must resolve to | Must not resolve to |
|---|---|---|
| Vivaldi browser, class `vivaldi-stable` | `vivaldi-stable` | Photocrowd, YouTube, Gemini |
| Photocrowd web-app (`__` / `.webview` / photocrowd class or title) | Photocrowd pin / desktop id | `vivaldi-stable` |
| YouTube web-app | YouTube pin / desktop id | `vivaldi-stable` |
| Gemini web-app | Gemini pin / desktop id | `vivaldi-stable` |
| Steam client | `steam` | `steam-friends`, `steam-app-*` |
| Friends List / Friends & Chat | `steam-friends` | `steam` |
| Steam Settings | `steam-settings` | `steam` |
| `steam_app_<id>` game | that game / `steam-app-<id>` | `steam` |
| Steam "Launching…" or untitled floating helper | not relevant | any chip |
| Two windows of one desktop id | one chip | two chips |
