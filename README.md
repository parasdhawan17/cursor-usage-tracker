# Cursor Usage Tracker

A lightweight, unofficial tool for monitoring your [Cursor](https://cursor.com) plan usage. It calls the same dashboard endpoints as [cursor.com/dashboard/usage](https://cursor.com/dashboard/usage) and surfaces the numbers where you actually need them — in the menu bar, or in your terminal.

> **Unofficial.** These endpoints are not documented by Cursor and can change at any time. Use your own account only. This project is not affiliated with or endorsed by Cursor.

## Features

### macOS menu bar app

Native SwiftUI utility for **macOS 13+** (Apple Silicon and Intel). Runs as a menu bar agent — no Dock icon.

| What you get | Details |
|---|---|
| **Live usage in the menu bar** | Shows `C 32%` (or `C ∞` on unlimited plans) so you can spot usage at a glance |
| **Plan overview** | Usage %, progress bar with even-pace marker, plan name, and days left in the billing cycle |
| **Usage costs** | Billed (on-demand) vs included usage value — toggle between **Today** and **This cycle** |
| **Model split** | Breakdown of API models vs Auto models as a share of plan usage |
| **Auto-refresh** | Background updates every 1–5 minutes (configurable in the panel) |
| **Offline-friendly** | Shows cached data with a warning if a refresh fails |
| **Secure token storage** | Session token saved locally in Application Support (mode `600`); no `.env` required |

### Python CLI

Scriptable access to the same data — useful for logging, automation, or quick terminal checks.

- Usage summary (plan, billing cycle, % used)
- Recent usage events with model and cost
- Raw JSON output with `--json`

---

## Quick start (menu bar app)

**Requirements:** [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/) (`xcode-select --install`)

```bash
git clone git@github.com:parasdhawan17/cursor-usage-tracker.git
cd cursor-usage-tracker
./run-menubar.sh
```

This builds `Cursor Usage.app`, bundles it locally, and launches it. **Always launch via the `.app`** — do not run the raw binary directly, or macOS may quit the process when the panel closes.

On first launch you'll see a **gear icon** in the menu bar. Click it, paste your session token (see below), and tap **Save & connect**. The icon switches to your usage percentage once connected.

**Quit:** Right-click the menu bar item → **Quit Cursor Usage**, or press **⌘Q** when the app is focused.

---

## Session token

Both the menu bar app and CLI authenticate with your browser session cookie.

1. Open [cursor.com/dashboard/usage](https://cursor.com/dashboard/usage) and sign in
2. Open DevTools (**⌥⌘I** or **F12**) → **Application** → **Cookies** → `https://cursor.com`
3. Copy the value of **`WorkosCursorSessionToken`**
4. Paste it into the app setup panel, or into a `.env` file for the CLI (see below)

Tokens expire periodically. If you see an auth error, grab a fresh cookie from the dashboard and save it again via **Session** in the panel footer.

---

## Menu bar app details

### Panel

Click the menu bar label to open the panel:

- **Hero** — primary usage % with a color-coded progress bar and pace indicator
- **Usage costs** — billed vs included spend for today or the current billing cycle
- **Model split** — how much of your plan API vs Auto models have consumed
- **Refresh** — tap ↻ in the header, or open the panel (auto-refreshes if data is older than 30 seconds)
- **Session** — update or remove your saved token

### Auto-refresh

Choose an interval (1–5 minutes, default 1 min) in the panel footer. The menu bar label updates in the background without opening the panel.

### Token storage

The menu bar app stores your token at:

```
~/Library/Application Support/CursorUsageTracker/session_token
```

The file is written with owner-only permissions (`600`). Older installs that used Keychain or a `.env` file are migrated automatically on launch.

---

## Python CLI

### Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Add your token to `.env`:

```
CURSOR_SESSION_TOKEN=your_cookie_value_here
```

### Run

```bash
python fetch_usage.py
python fetch_usage.py --json   # include raw API response
```

Example output:

```
=== Usage summary ===
Plan:        pro
Usage:       32%
Billing:     2026-06-01 → 2026-07-01
Plan used:   320 / 1000

=== Recent events (10 of 847) ===
  ...
```

---

## Building a distributable DMG

To produce a universal (Apple Silicon + Intel) `.dmg` for macOS 13+:

```bash
./build-dmg.sh
```

Output: `dist/Cursor-Usage-1.0.6-universal.dmg`

Install by dragging **Cursor Usage** to **Applications**. If Gatekeeper blocks the first launch, right-click the app → **Open**.

---

## Project structure

```
├── macos/                          # Swift menu bar app (Swift Package Manager)
│   ├── Package.swift
│   └── Sources/CursorUsageMenuBar/
│       ├── CursorUsageMenuBarApp.swift   # App entry + auto-refresh
│       ├── StatusBarController.swift     # Menu bar icon + panel
│       ├── MenuContentView.swift         # Main panel layout
│       ├── UsageDetailViews.swift        # Costs + model split panels
│       ├── UsageFetcher.swift            # Dashboard API client
│       └── SessionTokenStore.swift       # Token persistence
├── fetch_usage.py                  # CLI entry point
├── cursor_api.py                   # Shared Python API client
├── run-menubar.sh                  # Build + launch menu bar app
├── build-dmg.sh                    # Universal DMG build
└── scripts/                        # Icon bundling, resource scripts
```

### API endpoints used

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/usage-summary` | GET | Plan usage %, billing cycle, model split |
| `/api/dashboard/get-filtered-usage-events` | POST | Cost totals and request counts |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Gear icon won't go away | Paste a valid `WorkosCursorSessionToken` and tap **Save & connect** |
| "Session expired" | Copy a fresh cookie from the dashboard and update via **Session** |
| Menu bar icon hidden (notch Macs) | Click the **›** overflow chevron in the menu bar |
| App quits immediately | Launch via `Cursor Usage.app` or `./run-menubar.sh`, not the bare binary |
| Gatekeeper blocks DMG install | Right-click → **Open**, or remove quarantine: `xattr -cr "/Applications/Cursor Usage.app"` |
| CLI returns 401 | Token in `.env` is stale — refresh from browser cookies |

---

## Team / org usage

For production team tracking across many seats, use Cursor's official [Admin API](https://cursor.com/docs/account/teams/admin-api) instead of scraping dashboard cookies.

---

## Disclaimer

This tool reads data from undocumented Cursor dashboard endpoints. Behavior may break if Cursor changes its API, authentication, or billing model. Use at your own risk, on your own account only.
