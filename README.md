# Cursor Usage Tracker

Fetch your Cursor usage by calling the same endpoints the [dashboard](https://cursor.com/dashboard/usage) uses.

> **Unofficial.** These endpoints are not documented by Cursor and can change anytime. Use your own account only.

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

## Get your session token (one time, refresh when expired)

1. Open [cursor.com/dashboard/usage](https://cursor.com/dashboard/usage) in your browser
2. DevTools (F12) → **Application** → **Cookies** → `https://cursor.com`
3. Copy **`WorkosCursorSessionToken`**
4. Paste into `.env`:

```
CURSOR_SESSION_TOKEN=your_cookie_value_here
```

## CLI

```bash
python fetch_usage.py
python fetch_usage.py --json   # include raw API response
```

## macOS menu bar app

Native menu bar utility (macOS 13+). Shows **usage %** in the menu bar; click for plan details, progress bar, and billing cycle.

**Requirements:** Xcode Command Line Tools (`xcode-select --install`). No `.env` file is required for the menu bar app.

```bash
./run-menubar.sh
```

On first launch the menu bar shows a **gear icon**. Click it, paste your `WorkosCursorSessionToken` (same cookie as the CLI section above), and tap **Save & connect**. The token is stored in the macOS Keychain. Use **Session** in the panel footer to update or remove it later.

This builds a `Cursor Usage.app` menu bar agent (no Dock icon) and launches it with `open`. Do **not** run the raw binary directly — it can quit when the panel closes.

To quit: Activity Monitor → CursorUsageMenuBar, or `pkill -x CursorUsageMenuBar`.

Auto-refreshes on an interval you choose (1–5 minutes, default 1 min) in the panel; use ↻ to refresh immediately. Opening the panel also refreshes if the last fetch was over 30 seconds ago.

**Quit:** Right-click the menu bar label or use Activity Monitor.

## Team admins

For production team tracking, prefer the official [Admin API](https://cursor.com/docs/account/teams/admin-api).
