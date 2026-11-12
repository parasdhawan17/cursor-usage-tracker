# Cursor Usage Tracker — Design

This document describes how the app is put together and the design decisions behind it. For scope, setup, and release steps, see `project.md` and `README.md`.

## Design principles

1. **Glanceable first.** The most important number (plan usage %) lives in the menu bar. Everything else is one click away.
2. **Native, quiet macOS.** SwiftUI with AppKit where needed (status item, popover, window). It uses system colours and materials so it follows light and dark mode and Liquid Glass on macOS 26 without custom chrome.
3. **Fail soft, per provider.** Cursor and Codex are independent. A failure in one must never blank or delay the other, and stale data is shown with a warning rather than hidden.
4. **Local only.** No server, no analytics, no sync. Credentials and history stay in the user's Application Support folder with owner-only permissions.
5. **Respect undocumented APIs.** Assume responses can change shape. Parse defensively, prefer fields already in use, and surface an "unavailable" state instead of guessing.

## Architecture

The app is a single process with three layers.

**Presentation.** `StatusBarController` owns the `NSStatusItem` and an `NSPopover` hosting the compact SwiftUI panel (`CompactMenuContentView`, `MenuContentView`). `DashboardWindowController` hosts the full window (`DashboardViews`) with four pages: Overview, Cursor, Codex, and Settings. `SetupContentView` and `TokenInputField` handle first-run credential entry. `LaunchSplashWindow` covers startup.

**State.** `UsageViewModel` (in `CursorUsageMenuBarApp.swift`) is the single observable source of truth. It holds the latest `UsageSnapshot` for Cursor, the latest `CodexUsageSnapshot`, the last error per service, and the selected menu-bar service. Both status bar and windows bind to it through `objectWillChange`, so there is one refresh path and one set of data.

**Data.** Fetchers are stateless `enum`s with `async` functions: `UsageFetcher` for Cursor, `CodexUsageFetcher` for Codex. They build `URLRequest`s, map HTTP status to a typed error (`UsageFetcherError`, `CodexUsageFetcherError`), and parse JSON into value types. Parsing is off the main actor (`Task.detached` with `.utility` priority). Persistence is handled by `SessionTokenStore`, `CodexTokenStore`, and `CodexDailyUsageTracker`.

Value types (`UsageSnapshot`, `CodexUsageSnapshot`, `CodexQuotaWindow`) are immutable and `Equatable`. Derived values such as `primaryPercent`, `menuBarLabel`, and `evenPacePercent` are computed on the type, so they can be unit-tested without UI.

## Refresh model

- A timer runs at the user's chosen interval (`RefreshInterval`: 1–5 minutes, default 1). The value is stored in `UserDefaults`.
- Opening the panel triggers a refresh if the last fetch is older than 30 seconds. Manual refresh is always available.
- Cursor refresh makes one `usage-summary` call, then two event-cost queries (cycle and today) run concurrently with `async let`. A failure in the cost queries leaves the usage numbers intact and marks costs as not loaded.
- Event queries are paginated at 100 per page and capped at 500 pages as a safety stop.
- A failed refresh keeps the last good snapshot on screen and shows the error beside it. The menu bar label should keep the last good value rather than flashing to a placeholder.

## Metrics and how they are derived

**Primary percentage.** Cursor's dashboard `totalPercentUsed` is preferred because it matches the number Cursor shows. If it is missing, the app falls back to `used ÷ limit`. Values are clamped to 0–100. Unlimited plans show `∞` and are not treated as a percentage.

**Even-pace marker.** The progress bar has a secondary marker at the percentage the user would have reached by now if usage were spread evenly over the billing cycle. It is computed from `billingCycleStart` and `billingCycleEnd` at day granularity. The design intent is to let the user see whether they are ahead of or behind pace at a glance, not to forecast.

**Colour thresholds.** Usage below 70% is green, 70–89% is orange, and 90% and above is red (`Theme.usageColor`). These thresholds are used everywhere a usage value is coloured, so the same number always reads the same way.

**Cost.** Two totals are kept. *Chargeable* spend is on-demand or usage-based cost, which is what the user is actually billed. *Included value* is the notional token value of usage that is covered by the plan, which is informational only. Events are classified by `kind` and `usageBasedCosts`; `ERRORED` events are excluded, and `INCLUDED` or `FREE_CREDIT` kinds count toward included value. The cycle total and today's total use the same classifier, and "today" uses the local calendar day.

**Model split.** API and Auto percentages come straight from the plan breakdown, shown in blue and purple respectively (`Theme.apiModels`, `Theme.autoModels`). They are shares of plan usage, not separate budgets.

**Codex daily usage.** Codex reports a rolling window, not a daily total. `CodexDailyUsageTracker` therefore accumulates percentage-point increases within a calendar day. When the value drops, it is treated as a new window only if the reset timestamp changed, so a backwards jump without a reset is ignored rather than counted. The stored value is labelled as a delta (`+12 pp`), not as a percentage of quota, to avoid implying more precision than the source provides.

## Surfaces

**Menu bar label.** A compact text label, `C 42%` or `Codex 17%`, for the service the user selected. Its tooltip shows the full plan percentage and days left in the cycle. The label is deliberately text, not an icon with a badge, so it stays readable on notched Macs and in the overflow chevron.

**Compact panel.** Fixed 320 pt width. It holds the connection state for each service, the primary usage bar, cycle days left, and a shortcut to the dashboard. It is meant to answer "how am I doing" in under two seconds, so it carries no charts and no settings.

**Dashboard window.** Overview gives a side-by-side read of both services. Cursor and Codex pages carry the detail: costs, model split, quota windows, reset countdowns, and any credits. Settings holds credentials, selected menu-bar service, refresh interval, launch at login, keep awake, and update controls.

**First run.** If no credentials are saved, the app opens the dashboard on the setup content rather than the overview, so a new user has one clear next step. The gear icon is the persistent entry point to credentials.

**Update banner.** Shown at the top of the panel only when a newer GitHub release exists. Clicking it opens the DMG download, with progress shown while it downloads.

## Visual language

- **Typography.** System fonts with monospaced digits for percentages and currency so numbers do not jitter on refresh.
- **Colour.** Semantic system colours only (`Color.primary`, `.secondary`, `.accentColor`, and `NSColor` system labels and fills). Custom colour is limited to the usage traffic-light scale and the two model-split hues. Light and dark variants come from the `Theme` helpers, which provide explicit light and dark values for selector and card surfaces where system colours are not enough.
- **Surfaces.** `GlassMetrics` defines the panel radius (10), section radius (8), and control radius (6). On macOS 26 the panel uses Liquid Glass; earlier systems fall back to `.regularMaterial` with a hairline border and a soft shadow.
- **Progress bars.** A track in `progressTrack` with a fill in the usage colour and the even-pace marker drawn as a thin vertical tick (`UsageProgressBar`).
- **Icon.** A single `AppIcon` set produced from `AppIcon/source-1024.png` by `scripts/build-app-icon.sh`.
- **Motion.** Minimal. The popover animates in and out with the system default. The splash window is a brief launch affordance, not a loading state.

Copy is short and plain. Error messages name the next action ("Save a new token in Session", "Sign in to Codex first") rather than describing the failure.

## Security and privacy

- Session cookies and access tokens live only on the device, in `~/Library/Application Support/CursorUsageTracker/` with `600` permissions. Keychain is read once to migrate older installs and never prompts.
- Tokens are sent only to the provider's own domain (`cursor.com`, `chatgpt.com`) and to nothing else. The GitHub call sends no credentials.
- Logs and error strings must not include token values. Error messages describe status codes, not request contents.
- The Codex importer reads `~/.codex/auth.json` only when the user asks for auto-fill and does not write back to it.
- The Claude importer reads Claude Code's Keychain item (`Claude Code-credentials`), falling back to `~/.claude/.credentials.json`, only when the user presses Auto fill. It copies `accessToken` only, never the refresh token. This is the one place the app reads the Keychain, and macOS may prompt for access. Claude local usage is read from `~/.claude/projects` JSONL files and never leaves the device.
- Screenshots and documentation use placeholder values, never real account data.

## Error handling

| Condition | Behaviour |
|---|---|
| No token saved | Setup state, prompt to paste a token |
| HTTP 401 (Cursor) or 401/403 (Codex) | "Session expired" or "token expired", link to Settings |
| Other HTTP status or network error | Keep last snapshot, show error inline with age of data |
| Cost queries fail, usage succeeds | Show usage, mark costs as not loaded |
| Unrecognised Codex response | "Codex returned an unrecognized usage response." Cursor unaffected |
| Update check fails | Silent. The banner is simply not shown |

The rule for new code: a failure should always leave the user with one clear next step and never with an empty or misleading number.

## Persistence

Four small files and one `UserDefaults` domain (see `project.md` for paths). Writes are atomic for the Codex daily file. Permissions are set after every write. There is no database and no migration framework; the migration path is one-shot code that runs on launch and then records a flag (`didMigrateSessionTokenFromKeychain`).

## Testing

- `CodexUsageFetcherTests` covers response parsing for the Codex adapter.
- `CodexDailyUsageTracker.reduce` is a pure function and is a good candidate for more tests (day rollover, reset handling, backwards values).
- Cursor parsing (`parseSummary`) and cost classification (`isBillableEvent`, `isIncludedUsageEvent`) are private and untested. The first cost-related change should extract them into a testable type and add fixtures.
- The Python CLI has no tests. Its logic is thin and delegates to `cursor_api.py`.
- Manual checks: `scripts/test-update.sh` exercises the updater. For UI changes, check both light and dark appearance, the 320 pt popover, and a notched-Mac menu bar.

Fixtures must be sanitised. Do not commit real responses that contain email addresses, team names, or event IDs.

## Known tensions and open questions

- **Accuracy vs. simplicity of cost.** The app reports dashboard percentage as the headline and computes its own cost totals from events. If Cursor's own numbers ever diverge, the headline should win and the cost view should say it is a local estimate.
- **Codex is experimental.** Its UI is complete, but the endpoint is internal and the token is manual. Keep it visibly labelled until it has been stable across several releases.
- **Version bookkeeping.** The version lives in several files. A single source (for example, read `CFBundleShortVersionString` from the built bundle in the release script) would remove a class of release mistakes.
- **Notarisation.** Gatekeeper friction is a real cost for new users. Signing and notarising the DMG would remove the right-click workaround but needs an Apple Developer account.
- **Forecasting.** The even-pace marker is deliberately descriptive. A "projected to exhaust on" estimate would be useful but would depend on noisy short-term rates and was not built.

## Decision log (short)

- **Menu-bar text over icon.** Text is readable at a glance and survives crowded menu bars.
- **Popover over custom window for the compact panel.** `NSPopover` gives correct anchoring, dismissal, and Liquid Glass behaviour for free.
- **Two services in one app.** Codex was added to the same status item and panel rather than as a separate app, so one login item and one update path cover both.
- **Own cost aggregation.** Summing events locally gives a cycle and a "today" view that the dashboard does not offer directly.
- **Local JSON files over Keychain for tokens.** Keychain prompts were disruptive for a menu-bar app that refreshes in the background. Files with `600` permissions are the simpler trade-off, with the Keychain kept only for migration.
- **Python CLI kept alongside the app.** It is cheap to maintain, useful for scripting, and a reference for the API shape.
