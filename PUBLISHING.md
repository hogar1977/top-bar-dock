# Publishing checklist — io.github.hogar1977.top-bar-dock

Step-by-step plan to publish this plugin to GitHub and the Omarchy plugin marketplace.
This is exactly what was researched on 2026-08-29 (flows verified against the current
Omarchy tooling, the HANCORE marketplace guide, and Okomart).

---

## Step 0 — Prerequisites

- A GitHub account, with the GitHub CLI installed locally and authenticated once:
  ```bash
  gh auth login
  ```
- Your git identity set (your real name/email is fine here):
  ```bash
  git config --global user.name "Your Name"
  git config --global user.email "you@example.com"
  ```

## Step 1 — Finalize the files in this folder

This folder is the repository root (GitHub will also be the "plugin store" home —
`omarchy plugin add` clones the repo root and uses `manifest.json`'s `id`).

1. **Check `README.md`** — the install/update/remove commands already reference
   `io.github.hogar1977.top-bar-dock` and the URL `https://github.com/hogar1977/top-bar-dock`.
2. **Check `LICENSE`** — the copyright line says `hogar1977` (your GitHub pseudonym),
   so your real name never appears. The MIT upstream attributions (OmaHarbor /
   window-shelf) are already included and must stay.
3. **Optional: preview image** — add `preview.png` at the repo root (bar screenshot).
   The marketplace auto-generates optimized card images from it and validates
   anything up to 50 MB / 40 megapixels. Without one, the listing just has no image.
4. **Plugin id** — `io.github.hogar1977.top-bar-dock` is already set consistently
   in `manifest.json`, in `top-bar-dock.qml` (`moduleName` + `pinnedFilePath`), and as
   the local folder name. Marketplace IDs are **permanent** (can't be reused after a
   listing), so don't change it after the first submission.

## Step 2 — Validate

The exact validator the shell uses (must exit 0):

```bash
omarchy plugin validate /home/dalibor/.config/omarchy/plugins/io.github.hogar1977.top-bar-dock
```

Also double-check the widget still loads cleanly after any edits:

```bash
omarchy restart shell
```

## Step 3 — Publish to GitHub

```bash
cd /home/dalibor/.config/omarchy/plugins/io.github.hogar1977.top-bar-dock

git init -b main
git add -A                      # .gitignore keeps your personal pinned.json OUT
git commit -m "Top Bar Dock: pinned launcher + taskbar for the Omarchy bar"

gh repo create top-bar-dock --public --source=. --push --description \
  "Pinned launcher dock + running-window taskbar for the Omarchy bar (Hyprland/Quickshell)"
```

Suggested repo topics (GitHub Topics, also used by the `omarchy-plugin` topic search):
`omarchy`, `omarchy-plugin`, `quickshell`, `hyprland`, `bar-widget`, `dock`.

## Step 4 — Submit to the Omarchy plugin marketplace

Primary marketplace: **HANCORE-linux/omarchy-plugin-marketplace** (this is what most
people use; 176 stars, actively maintained). Listings are approved manually after
automated validation of a pinned commit.

Your listing metadata:

- **Category:** `Widgets`
- **Tags:** `bar`, `launcher`, `quickshell` (one to three allowed)
- **Title:** `[Plugin]: Top Bar Dock`

### Option A — via the issue form (simplest)

Open the form and fill in the repo URL, category, tags:

```
https://github.com/HANCORE-linux/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml
```

Requirement summary (all already satisfied by this repo): public GitHub repo root,
`manifest.json` at root, README with install **and removal** instructions, license,
globally-unique id, optional `preview.png`.

### Option B — via the CLI (issue body must match exactly)

```bash
cat > /tmp/omarchy-plugin-submission.md <<'EOF'
### Repository URL
https://github.com/hogar1977/top-bar-dock
### Category
Widgets
### Tags
bar, launcher, quickshell
### Suggest a missing tag
_No response_
### Maintainer notes
_No response_
### Submission checklist
- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
EOF

gh issue create \
  --repo HANCORE-linux/omarchy-plugin-marketplace \
  --title "[Plugin]: Top Bar Dock" \
  --body-file /tmp/omarchy-plugin-submission.md
```

The command above already contains the real URL — just double-check line 102 before
running (`https://github.com/hogar1977/top-bar-dock`, no trailing slash, no `/tree/main`).
Keep all six headings in order and both checklist boxes — the
bot parses the exact format, so don't reorder or reword anything. A bot then posts
validation + an Automated Security Baseline result on the issue; a maintainer applies
`approved-and-verified` and the listing goes live.

### Updating the listing later

Use the **Plugin verification** issue form, "Verify and publish a newer upstream
commit" action, with the plugin id, repo URL and the full 40-char SHA of the new HEAD.

## Step 5 — Optional: Okomart (GUI storefront)

Okomart (`brianblakely/omarchy-plugins`) is another store that lists plugins in a
plain-text catalog. To appear there, open a PR adding one line to `plugins.txt`:

```
https://github.com/hogar1977/top-bar-dock.git | hogar1977 | Pinned launcher dock + running-window taskbar for the Omarchy bar
```

## Step 6 — Version bump convention

- The `version` field lives in `manifest.json` (`1.1.0` now).
- For contributors installing from GitHub: `omarchy plugin update io.github.hogar1977.top-bar-dock`
  pulls the latest default-branch HEAD — a version bump is just a commit.
- For marketplace users: bump the manifest version, push, then use the "Plugin
  verification" form with the new commit SHA so the listing snapshot moves forward.

## Files in this repo

| File | Purpose |
|---|---|
| `manifest.json` | Omarchy plugin manifest (schema v1) |
| `top-bar-dock.qml` | The entire widget (single file) |
| `README.md` | Landing page: description, features, acknowledgements, install docs |
| `LICENSE` | MIT, with OmaHarbor / window-shelf attribution |
| `PUBLISHING.md` | This checklist |
| `.gitignore` | Keeps your personal `pinned.json` out of the repo |
| `pinned.json` | *(local only, not committed)* your personal pins |