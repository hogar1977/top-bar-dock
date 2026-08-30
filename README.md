# Top Bar Dock

A pinned-app launcher dock and running-window taskbar, combined into **one Omarchy bar widget**.

Running apps appear as chips, grouping multiple windows of the same app together;
right-click to pin an app so its icon stays put as a launcher even when nothing is running.
Left-click runs/restores, middle-click+drag reorders, right-click opens an action menu,
and hovering shows live thumbnail previews — all inside your Omarchy top bar, inheriting
your theme automatically.

Built from the dock half of [OmaHarbor](https://github.com/anelcelik/omaharbor), which was
itself built on [window-shelf](https://github.com/gardnmi/window-shelf); this version has
been **heavily rewritten, hardened, and extended** (see
[Improvements over OmaHarbor](#improvements-over-omaharbor)).

---

## Features

- **Launcher and taskbar in one** — pinned apps and running windows live together in your bar. Pinned apps stay ready to launch even when closed.
- **Per-app window grouping** — multiple windows of the same app share a single icon. Hover for live previews, or click to switch to or close any window.
- **Click to launch or switch** — click to launch a pinned app, minimize/restore an open window, or instantly jump to a window on another workspace.
- **Drag to rearrange** — middle-click and drag pinned icons to reorder your dock; changes are saved automatically.
- **Right-click quick actions** — access instant actions to open a new instance, pin or unpin, maximize, minimize, or close windows.
- **Smart app matching** — web apps and Steam games appear with their own proper names and icons, separate from the browser or Steam client.
- **Status at a glance** — clean visual indicators highlight the focused app, dim minimized windows, and show workspace numbers for windows on other desktops.
- **Adapts to your setup** — matches your active Omarchy theme automatically and works smoothly on both horizontal and vertical bars.

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

Built as a standalone dock widget from the dock half of [OmaHarbor](https://github.com/anelcelik/omaharbor) (omitting the workspace switcher). Key functional additions include:

1. **Smarter app identity (Web-apps & Steam)** — a layered identity engine with domain-bonus scoring resolves web-app windows (e.g. `vivaldi-…photocrowd…`) to their own web-app desktop entry instead of the parent browser. Dedicated Steam integration matches games by App ID/title tokens and launches `steam-app-<id>` pins via `steam://rungameid`.
2. **Per-app window grouping** — multiple windows of the same app merge into a single chip featuring a multi-tile live preview grid, per-window Focus and Close actions, and a "Close all instances" option (OmaHarbor creates a separate chip per window with single previews).
3. **Direct on-bar pin reordering** — middle-click + drag pinned chips directly on the bar with a visual drop indicator, or use right-click `Move left` / `Move right` menu actions, replacing OmaHarbor's separate hamburger dock-menu popup.
4. **Compositor gap preservation** — reads and caches your live `general:gaps_out` and `gaps_in` values (including asymmetric per-edge gaps) and restores them across maximize/restore/minimize cycles, rather than snapping windows to zero gaps or hardcoded 10/5 fallbacks.

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