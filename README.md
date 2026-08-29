# Top Bar Dock

A pinned-app launcher dock and running-window taskbar, combined into **one Omarchy bar widget**.

Every open window gets its own chip; right-click to pin an app so its icon stays put
as a launcher even when nothing is running. Left-click runs/restores, middle-click+drag
reorders, right-click opens an action menu, and hovering a running window shows a live
thumbnail preview — all inside your Omarchy top bar, inheriting your theme automatically.

Built from the dock half of [OmaHarbor](https://github.com/anelcelik/omaharbor), which was
itself built on [window-shelf](https://github.com/gardnmi/window-shelf); this version has
been **heavily rewritten, hardened, and extended** (see
[Improvements over OmaHarbor](#improvements-over-omaharbor)).

---

## Features

- **Tasks + pins in one widget** — running windows appear automatically, in the same row
  as your pinned launchers. Pinned chips stay as grayed launchers when their app is closed.
- **Left-click a pinned chip** — launches the app (via `uwsm-app` / `gtk-launch`; Steam
  titles via `steam://rungameid`).
- **Left-click a running chip** — minimizes it; click again to restore and focus. If the
  window lives on another workspace, clicking switches you there and focuses it.
- **Middle-click + drag** — reorder pinned apps; a drop indicator shows where it will land.
  The new order is saved instantly.
- **Right-click context menu** — `Open new instance`, `Move left`/`Move right`,
  `Maximize`, `Minimize`/`Restore`, `Pin to dock`/`Unpin from dock`, and `Close`
  (destructive actions highlighted).
- **Live window previews** — hover a running chip to preview the window in a themed
  popup (real `ScreencopyView` thumbnail + title). Previews cancel the moment you
  switch workspaces, open a menu, or start a drag.
- **Per-window chips** — one chip per window, not grouped by app, so multiple instances
  are visible and switchable independently.
- **Window-state visuals** — accent underline on the focused window; minimized chips are
  dimmed without an underline; a small workspace-number badge marks windows that are open
  on a different workspace.
- **Minimize-to-shelf** — minimizing parks the window on the `special:omarchy-minimized`
  Hyprland workspace, keeping the taskbar tidy and predictable.
- **Gap-aware restore** — window maximize/restore (and unhide) correctly preserve your
  configured `general:gaps_out` / `gaps_in`, including asymmetric values, instead of
  snapping windows to zero gaps.
- **Rock-solid window identity** — windows are resolved through a layered identity engine
  (Wayland `appId`, `WM_CLASS`, initial class, identity snapshots, title tokens) so chips
  map to the right app and the right pin — including **web-app windows** such as
  `vivaldi-photocrowd.com__feed_-Default`, which resolve to their site entry (e.g.
  *Photocrowd*) rather than to the host browser.
- **Steam-aware** — Steam windows are identified by their app id and matched to pins
  like *"Age of Empires II Definitive Edition"* via fuzzy token matching; `steam-app-<id>`
  pins relaunch their game directly.
- **Configuration** — `maxTitleLength` and `previewDelay` are exposed as bar-widget
  settings with sensible defaults.
- **Vertical bars** — the dock rotates for vertical bar placement, with vertically
  stacked chips and rotated labels.
- **Performance** — dock layout is memoized (signature-based), the window list is built
  through a snapshot + poll pipeline, and the app-entry index rebuilds only when the
  desktop-entry catalog changes. The result updates smoothly even with many windows open.
- **Fully themed** — colors, fonts, sizes and popups all come from the active Omarchy
  theme and follow the bar, so the dock restyles itself whenever you switch themes.

## Interaction quick reference

| Gesture | Pinned chip | Running-window chip |
|---|---|---|
| Left click | Launch | Minimize / restore & focus |
| Middle click + drag | Reorder | — (drag is available from its pinned host) |
| Right click | Context menu | Context menu |
| Hover | Tooltip with app name | Live preview thumbnail |

## Install

```bash
omarchy plugin add https://github.com/hogar1977/top-bar-dock.git --enable --yes
```

Placing the widget (defaults to the **left** bar section):

```bash
omarchy bar move io.github.hogar1977.top-bar-dock --section left
# or: center / right
```

If you skipped `--enable`, enable it afterwards:

```bash
omarchy plugin enable io.github.hogar1977.top-bar-dock
```

## Update

```bash
omarchy plugin update io.github.hogar1977.top-bar-dock
```

## Remove

```bash
omarchy plugin remove io.github.hogar1977.top-bar-dock --yes
```

## Configuration

Configure from the bar widget's settings panel, or the CLI:

```bash
omarchy bar set io.github.hogar1977.top-bar-dock <key> <value>
```

| Key | Default | Description |
|---|---|---|
| `maxTitleLength` | `18` | Window titles longer than this are truncated with an ellipsis. |
| `previewDelay` | `350` | Milliseconds to hover a chip before the live preview appears. |

Your pins are stored in `~/.config/omarchy/plugins/io.github.hogar1977.top-bar-dock/pinned.json`
(created on first pin; safe to ignore in version control).

Editing anything under `~/.config/omarchy/plugins/` hot-reloads the plugin automatically.

## Requirements

- Omarchy (Hyprland + the Omarchy Quickshell bar)
- Nothing else — no extra packages.

## Improvements over OmaHarbor

The dock half of [OmaHarbor](https://github.com/anelcelik/omaharbor) was taken as the
starting point and **rebuilt, hardened, and extended**. What changed:

1. **Name and scope** — published as a standalone *dock* widget (`io.github.hogar1977.top-bar-dock`),
   split out from OmaHarbor's combined workspace-switcher + dock widget.
2. **Correct app identity** — new layered identity engine that understands wayland
   app-id / `WM_CLASS` / initial-class / snapshot candidates and resolves a window to the
   right desktop entry *and* the right pin. This is what fixed web-app windows being
   attributed to their host browser (e.g. a `vivaldi-…photocrowd…` window being claimed by
   the Vivaldi pin).
3. **Web-app (site) awareness** — scored desktop-entry matching with a domain bonus,
   so `*-<site>.<tld>.__…` and `*.webview` windows resolve to their site's entry
   (via its URL-bearing `Exec`) rather than by a shared browser token.
4. **Pin↔window exclusivity** — each pin claims at most one window and every matching
   window merges into its own pinned chip; no more duplicate claims, stray extra chips,
   or icons "flipping" between two pinned slots on each refresh.
5. **Fuzzy pin matching, tightened** — name- and title-based pins (Steam titles like
   *"Age of Empires II Definitive Edition"*) match via shared meaningful tokens, but the
   fuzzy fallback now requires **two or more** shared tokens so a generic browser name
   can't grab an unrelated window.
6. **Gap-preserving maximize/restore** — the window restore path caches the live
   `general:gaps_out` / `gaps_in` (polled, primed at startup, and guarded against reading
   the transient zero during an operation) and writes back the exact values — including
   asymmetric per-edge gaps — instead of leaving windows stuck at zero gaps.
7. **Edge-case handling** — graceful behavior for "last window minimized", minimize-from-
   another-workspace, close-vs-cancel of popups, and drag cancellation; popup state is
   cleaned up when chips are destroyed (no stranded popups).
8. **Robust context menu** — menu built from a proper items model with destructive-action
   highlighting and correct delegate data handling (no more empty menus).
9. **Startup race & ordering** — entry index and pinned state are initialized in the right
   order at load, the running-window list rebuilds only when something actually changes,
   and `dockEntries` is memoized by signature to keep the 700 ms refresh cheap and stable.
10. **Vertical bars** — chips stack and reorder vertically, and labels render rotated.
11. **Single-file design** — everything lives in one auditable `top-bar-dock.qml` with a
    minimal `manifest.json`; no split files to keep in sync.
12. **Documentation & publishing** — manifest metadata, README, license, and this
    change-list, ready for distribution.

## Acknowledgements

- **OmaHarbor** ([`anelcelik/omaharbor`](https://github.com/anelcelik/omaharbor), MIT) —
  the dock half of this plugin started as a fork of OmaHarbor's dock code.
- **window-shelf** ([`gardnmi/window-shelf`](https://github.com/gardnmi/window-shelf), MIT) —
  via OmaHarbor, which took its dock half from here ("Minimize" trick).
- **Omarchy** ([`basecamp/omarchy`](https://github.com/basecamp/omarchy), MIT) — the bar
  widget framework, popup/theming tokens, and the `omarchy` plugin tooling this runs on.
- **Quickshell** ([`outfoxxed/quickshell`](https://github.com/outfoxxed/quickshell), LGPL-3.0) —
  the shell framework everything is built with.
- **Big Pickle** — the AI engineering partner who did the heavy lifting: the identity
  rewrite, the web-app/Steam matching, the gap-preservation fix, the performance
  pass, and the polish and bug-hunting that turned the fork into something publishable. 😄

## License

[MIT](LICENSE) — the same license as OmaHarbor and Omarchy. See the LICENSE file for
copyright and the upstream attribution.