# Cursor Usage Tracker — Project

## Purpose

Cursor Usage Tracker is a small, personal macOS menu-bar utility that shows how much of a Cursor plan (and, experimentally, a Codex plan) has been used, without opening a browser. It answers three questions at a glance: how much of my plan is used, how fast am I burning through it compared with the billing cycle, and what has the spend been today and this cycle.

It is an unofficial tool. It reads undocumented dashboard endpoints on cursor.com (and an internal ChatGPT endpoint for Codex) using the user's own session credentials. It is not affiliated with Cursor or OpenAI.

## Who it is for

The primary user is the author, who uses Cursor and Codex on their own accounts. The public GitHub repository (`parasdhawan17/cursor-usage-tracker`) and DMG releases exist so others can run it on their own accounts. It is not designed for team or org-wide tracking; the README points those teams to Cursor's official Admin API.

## What is in the repo

| Path | Role |
|---|---|
| `macos/` | Swift Package (macOS 13+) containing the menu-bar app, `CursorUsageMenuBar`. This is the main product. |
| `macos/Sources/CursorUsageMenuBar/` | SwiftUI and AppKit sources: app entry, status item and popover, compact and full panels, dashboard window, fetchers, stores, theme, updater. |
| `macos/Tests/` | XCTest target. Currently covers the Codex usage fetcher only. |
| `fetch_usage.py`, `cursor_api.py` | Python CLI that prints the usage summary and recent events, with optional `--json`. Shares the Cursor API client module. |
| `requirements.txt`, `.env.example` | CLI dependencies (`requests`) and the `.env` template for `CURSOR_SESSION_TOKEN`. |
| `run-menubar.sh` | Builds the Swift release binary, bundles `Cursor Usage.app`, and launches it. |
| `build-dmg.sh` | Produces a universal (arm64 + x86_64) DMG in `dist/`. |
| `scripts/` | App icon generation, resource bundling, update testing (forces an older version to exercise the in-app updater), and GitHub release creation via `gh`. |
| `AppIcon/`, `docs/screenshots/` | Icon source and README screenshots. |

## Current state

- Version 1.0.11 (see `AppVersion.swift` and `CFBundleShortVersionString` in `run-menubar.sh`).
- Cursor tracking is the stable, primary feature. Codex tracking is labelled experimental in the README and fails soft: if the Codex endpoint breaks, Cursor tracking is unaffected.
- The app is distributed as a DMG on GitHub Releases. The README notes that Gatekeeper may block the first launch, so the user may need right-click → Open.
- Recent history (last commits) focuses on the Codex dashboard, Codex daily tracking, Codex credential auto-fill, and compact menu styling.

## Features in scope

1. Menu-bar label showing the selected service's primary percentage (`C 42%`, `Codex 17%`, or `C ∞` for unlimited plans). The user can choose which service appears in the menu bar.
2. Compact popover panel with plan usage, progress bar with an even-pace marker, days left in the billing cycle, and a link to the full dashboard.
3. Full dashboard window with four pages: Overview, Cursor, Codex, Settings.
4. Cost views for on-demand (billed) spend and notional included-usage value, switchable between Today and This cycle.
5. Model split between API models and Auto models as a share of plan usage.
6. Auto-refresh every 1–5 minutes (default 1), plus manual refresh. The panel refreshes on open if the data is older than 30 seconds.
7. Offline behaviour: show cached data with a warning when a refresh fails.
8. Credential handling: the Cursor session cookie is stored locally with `600` permissions. The Codex token is read from `~/.codex/auth.json` or entered manually.
9. Launch at login, and an optional "keep awake" (caffeinate) setting.
10. In-app update check against GitHub Releases, at most every 6 hours, with a banner in the panel.
11. Python CLI for scripting and terminal checks.

## Out of scope

- Team, org, or multi-seat reporting (use the Admin API).
- Windows, Linux, or iOS clients.
- Any official or supported API contract. Behaviour may break whenever Cursor or OpenAI change their endpoints.
- Storing or syncing data off the device. Everything stays in the user's Application Support folder.

## Data sources

| Service | Endpoint | Used for |
|---|---|---|
| Cursor | `GET https://cursor.com/api/usage-summary` | Plan usage %, plan name, billing cycle, model split, status messages |
| Cursor | `POST https://cursor.com/api/dashboard/get-filtered-usage-events` | Per-event costs, summed for today and for the billing cycle, paginated |
| Codex | `GET https://chatgpt.com/backend-api/wham/usage` | Primary and secondary quota windows, credits, reset times (experimental) |
| Claude | `GET https://api.anthropic.com/api/oauth/usage` (`anthropic-beta: oauth-2025-04-20`) | 5-hour session and 7-day weekly utilization with reset times (experimental). Today's tokens come from local `~/.claude/projects/**/*.jsonl`, not the network. |
| GitHub | `GET https://api.github.com/repos/parasdhawan17/cursor-usage-tracker/releases/latest` | Update check |

## Local storage

| File | Location | Notes |
|---|---|---|
| Cursor session token | `~/Library/Application Support/CursorUsageTracker/session_token` | Mode `600`. Migrated from Keychain or a `.env` file on first launch when found. |
| Codex credentials | `…/CursorUsageTracker/codex_credentials.json` | Mode `600`. Can be auto-filled from `~/.codex/auth.json`. |
| Codex daily usage | `…/CursorUsageTracker/codex_daily_usage.json` | Mode `600`. Running total of percentage-point growth for the current day. |
| Claude credentials | `…/CursorUsageTracker/claude_credentials.json` | Mode `600`. Access token only, copied from Claude Code's Keychain item `Claude Code-credentials` (or `~/.claude/.credentials.json`) on Auto fill. Refresh token is never read. |
| Preferences | `UserDefaults` | Refresh interval, selected menu-bar service, launch-at-login, keep-awake, last update check. |

The CLI reads `CURSOR_SESSION_TOKEN` from the environment or from `.env` in the project folder. `.env` and `.auth/` are git-ignored.

## Build, run, release

- Run locally: `./run-menubar.sh`. Requires Xcode Command Line Tools. Always launch through the `.app` bundle, not the raw binary.
- Build DMG: `./build-dmg.sh`, output in `dist/Cursor-Usage-<version>-universal.dmg`.
- Publish: `scripts/create-release.sh <version>` builds the DMG if missing, tags `v<version>`, pushes the tag, and creates the GitHub release with the DMG attached. Requires `gh auth login`.
- Test the updater: `scripts/test-update.sh [older-version]`.
- Keep the version in three places in step when releasing: `AppVersion.swift`, the `CFBundleShortVersionString` and `CFBundleVersion` written by `run-menubar.sh`, and the default `VERSION` in `create-release.sh`.

## Known constraints and risks

- Unofficial endpoints. Cursor or OpenAI can change field names or auth at any time. The app must keep degrading to a clear "unavailable" or "session expired" state, never a crash.
- Session tokens expire periodically. The user must re-paste a cookie, and the app must make that path obvious.
- The Codex access token is short-lived and manually supplied or imported, so Codex tracking will go stale without warning.
- Test coverage is thin: one XCTest file covering Codex parsing. Cursor parsing and cost aggregation are untested.
- The DMG is not notarised, so Gatekeeper friction is expected.
- Versions appear in several places and must be kept in sync by hand.

## Working conventions

- Commit messages are short imperative summaries, for example "Refine compact usage menu styling and service selector".
- Never commit `.env`, `.auth/`, `dist/`, `macos/.build/`, or `Cursor Usage.app/`. These are already in `.gitignore`.
- Do not hard-code tokens, account IDs, or real usage numbers in source, fixtures, or screenshots.
- Feature work that touches the network layer should keep the "fail soft" rule: one provider failing must not blank the other.
