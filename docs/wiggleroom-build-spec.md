# Wiggle Room — Build Spec

## 1. Overview

**Wiggle Room** tracks any allowance that depletes or accumulates over a fixed period against the pace needed to land exactly on target — a bank balance against a monthly budget, or a car's mileage against a lease's annual allowance are the two concrete domains for v1. The core engine — a **Tracker** comparing an expected pace against an actual reading over a date range (§4) — is deliberately generic, and the data that feeds a tracker comes from a **modular source provider** (§5), so new domains (a different bank, a different kind of reading entirely) can be added as self-contained units of code without touching the tracker/calculation engine itself.

Three source providers ship in v1: **Starling** (money), **Tesla** (car mileage, via its Fleet API), and **manual entry** (anything without an API). Three is a deliberate minimum, not two — building only Starling and manual entry risks the "provider interface" quietly becoming shaped around just those two cases without anyone noticing. Starling (personal access token, no OAuth), Tesla (OAuth2, a different auth shape entirely), and manual (no network access at all) are usefully different from each other, so if all three fit through the same interface cleanly, the abstraction is real rather than accidental. Additional providers beyond these three — another bank, another kind of connected data — are expected to require genuinely new code each time (this is not a no-code plugin system), but the architecture in §5 keeps that new code isolated behind one interface so it never touches tracker logic, calculations, or UI beyond a picker entry.

The name **Wiggle Room** captures the everyday idiom for having a bit of slack left before a limit — the two-ring visualization (like Apple Fitness's Activity rings) shows exactly how much of that slack remains, tracking pace vs. actual consumption against a target, detailed in §3.

The app is built for a single user's own use across their own devices. Two people (e.g. a couple) may each run their own independent installation against overlapping accounts (e.g. a shared joint account), but **the two installations never share or sync data with each other**. All sync is within one person's own Apple ID and devices only.

## 2. Platforms

- iOS (iPhone)
- iPadOS
- macOS
- watchOS (companion app + complication)
- Shared codebase via a single Xcode multiplatform SwiftUI project; platform-specific UI where noted below.

## 3. Name & Visual Direction

This section gives the build agent a consistent design language, rather than defaulting to generic finance-app styling (heavy greens/reds, bar charts, alert-style banners). It's written with money as the example throughout for clarity, but every rule applies equally to a mileage tracker — swap "balance" for "reading" and "£" for "mi" as the tracker's `unit` dictates (§4.1).

### 3.1 Core metaphor

Everything in the UI should read as **holding (or drifting from) a steady pace toward a known endpoint**, not a countdown or a warning system. The emotional tone should be calm and steady, not alarming. Reaching a "full" ring at period end is an expected, neutral outcome (you were meant to use the whole allowance) — never framed as an achievement to celebrate the way Apple's own Activity rings frame closing a ring, since here "full" just means "period over," not "goal smashed."

### 3.2 Color language

- **Ahead of pace**: a calm, confident green — avoid neon/alert greens.
- **Behind pace**: an amber-leaning red rather than a harsh stop-sign red, to keep the tone corrective rather than alarming. Reserve pure red for genuinely urgent states (e.g. a money tracker's balance near zero, or a mileage tracker with the full allowance already used) — not just "behind pace" on its own.
- **Neutral/refreshing**: cool grey-blue.
- **Error**: amber/warning tone, distinct from both the ahead-of-pace green and behind-pace red, so a stale-data state is never confused with a genuinely-behind-pace state (see §8.4).
- The **outer (pace) ring** stays a neutral gray/graphite in all states — it's a clock, not a status indicator. Only the **inner (actual) ring** carries the green/red status color.

### 3.3 Typography & iconography

- Numerals (current value, target value, difference) should be the visual anchor of every screen — large, tabular/monospaced figures so digits align as they change.
- App icon and in-app iconography center on two concentric rings. Avoid literal piggy-bank/coin imagery so the icon reads sensibly for non-money trackers too.
- SF Symbols candidates to consider: `circle.circle`, `smallcircle.circle`, or a custom two-ring glyph if none fit well enough.

### 3.4 Ring encoding (primary visualization)

The primary visualization is two concentric rings, functionally accurate (not decorative) — numbers remain the source of truth throughout the app, but the rings should encode real values precisely:

- **Outer ring ("pace")** — fills according to elapsed time within the period: `fraction = hoursElapsed / periodHours`, clamped to `[0, 1]`. Colored neutral gray per §3.2.
- **Inner ring ("actual")** — fills according to how much of the total allowance has actually been consumed so far (§4.3 `consumedSoFar`): `fraction = clamp(consumedSoFar / totalAllowance, 0, 1)`. Colored green if ahead of pace, amber-red if behind (§3.2).
- **Reading it**: if the inner ring is *less* filled than the outer ring, less of the allowance has been consumed than the elapsed time implies — ahead of pace. If the inner ring is *more* filled than the outer, behind pace.
- This is the primary at-a-glance visual on the main dashboard, Home Screen widgets, Lock Screen widgets, and watch complication. A trend-line chart (actual vs. pace over time) may still be included as a secondary/detail view, styled per §3.5, for users who want to see the historical shape rather than a single current snapshot.
- Numeric readouts (current value, target value, difference, in the tracker's own unit) must always be shown alongside the rings, never replaced by them.

### 3.5 Chart style

- Trend charts (large widget, macOS detail pane) should always show the pace as a clean straight (or gently curved) reference line, with the actual value plotted as a distinct line/color above or below it — not as two competing bar charts.
- Avoid cluttered gridlines or axis labels beyond what's needed to read "start" and "end" of the period; the shape of the line relative to the reference line is the point, not precise chart-reading.

### 3.6 Copy/tone

- Use calm, plain status language: "On pace", "Ahead of pace", "Behind pace" — avoid "danger", "warning", "over budget" phrasing except in genuinely urgent cases.
- Widget/menu bar copy should stay terse and numeric (e.g. "+£42" or "+120 mi") with fuller pace framing reserved for slightly more spacious surfaces (main dashboard, notifications).
- UI labels adapt to the tracker's `unit` and `direction` (§4.1): a money tracker shows "Current balance" / "Target balance today"; a mileage tracker shows "Current mileage" / "Target mileage today".

## 4. Core Concept: Trackers

The fundamental unit of the app is a **Tracker**: any quantity that should move from a starting value toward an end-of-period target at a steady pace. A user can create multiple trackers, each independently configured.

### 4.1 Tracker fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `name` | String | User-facing label, e.g. "Joint account — September", "Car lease mileage" |
| `unit` | String | Display unit, e.g. "£", "mi" — drives number formatting and UI copy (§3.6) |
| `direction` | Enum: `decreasing` \| `increasing` | `decreasing`: starts high and depletes (bank balance). `increasing`: starts at a baseline and accumulates upward (odometer mileage, or a savings goal) |
| `connectedSourceId` | UUID | References a `ConnectedSource` (§5.2) — the account/connection this tracker reads from |
| `sourceTargetId` | String? | Which specific target within that source, e.g. a Starling `accountUid` or `spaceUid`. Nil for sources with only one implicit target (most manual trackers) |
| `startDate` | Date | Start of the period (inclusive) |
| `endDate` | Date | Start of the *next* period (exclusive) — i.e. the period runs `startDate` through 23:59:59 the day before `endDate` |
| `startingValue` | Decimal | The value at period start. Defaults to **0** for money trackers (user-editable); for mileage this is the odometer reading at period start |
| `totalAllowance` | Decimal | Total amount/distance available for the whole period |
| `recurrence` | `RecurrenceRule`? | Optional — see §4.4. Nil for a genuine one-off tracker |

### 4.2 Resolving `actualValue`

Regardless of source, every tracker resolves to a single `actualValue` at any point in time, obtained by asking its `ConnectedSource` (via the source provider protocol, §5.1) for the current value at `sourceTargetId`. Auto-fetch sources (Starling) return a live value; manual sources return the most recently logged reading.

### 4.3 Derived values

- `periodHours` = total hours between `startDate` and `endDate`
- `hoursElapsed` = real elapsed hours from `startDate` to now (clamped to `[0, periodHours]`) — use actual elapsed wall-clock time, **not** calendar-hour components, so DST transitions don't distort the calculation
- `consumedSoFar` — direction-aware:
  - if `direction == decreasing`: `consumedSoFar = startingValue - actualValue`
  - if `direction == increasing`: `consumedSoFar = actualValue - startingValue`
- `expectedConsumedByNow` = `totalAllowance × (hoursElapsed / periodHours)`
- `difference` = `expectedConsumedByNow - consumedSoFar`
  - `difference >= 0` → **ahead of pace** (green, §3.2)
  - `difference < 0` → **behind pace** (amber-red, §3.2)
- For display, convert back into the tracker's own terms:
  - `decreasing`: "current balance" = `actualValue`; "target balance today" = `startingValue - expectedConsumedByNow`
  - `increasing`: "current value" = `actualValue`; "target value today" = `startingValue + expectedConsumedByNow`

### 4.4 Recurring trackers

Recurrence is implemented as **template-cloning**, not a live-resetting counter:

- A tracker may carry a `RecurrenceRule` (e.g. "monthly, anchored to the 25th", or "weekly, anchored to Monday").
- When a recurring tracker's `endDate` passes, the app automatically creates a **new** Tracker instance, cloning `name`, `unit`, `direction`, `connectedSourceId`, `sourceTargetId`, `totalAllowance`, and the same `recurrence` rule, with a freshly computed `startDate`/`endDate` for the next period.
- `startingValue` for the new instance:
  - For auto-fetch sources (Starling): capture the live `actualValue` at the rollover moment automatically, so periods chain together with no user input needed.
  - For manual sources: prompt the user to log a fresh starting reading, since there's no live value to capture.
- Completed tracker instances are kept (not deleted) so a history of past periods remains browsable (see the macOS sidebar in §7.2).
- A one-off tracker (e.g. a single mileage-tracking period tied to a specific lease year) simply has `recurrence = nil` and is never auto-cloned.

### 4.5 Multiple trackers per source

Trackers and sources are many-to-one: several trackers can point at the same `ConnectedSource` (and even the same `sourceTargetId`) at once. For example, a Starling connected source's main balance could feed both a week-long tracker and a month-long tracker running concurrently, each with its own pace/allowance math, reading the same underlying live balance. When multiple trackers share a source/target, the app should fetch the underlying value once per refresh cycle and let all of them reuse it, rather than issuing duplicate API calls (relevant for Starling rate limits in particular).

### 4.6 Zoom levels (for long-running trackers)

A tracker spanning months or years (e.g. a 3-year/30,000-mile lease) has an outer pace ring that barely moves day to day — each day is a tiny fraction of the whole period — so the primary ring visual would feel inert at that scale. Rather than solving this with a second Tracker record, a long-running tracker exposes **zoom levels**: read-only computed views of the *same* tracker at a shorter, calendar-aligned grain, so the ahead/behind question can be asked at whatever scale is actually useful ("how am I doing this month?") without redefining the tracker itself.

- Available zoom levels: **Overall**, **This year**, **This month**, **This week** — offered as tabs/segmented control on the dashboard. Which levels are offered depends on the tracker's own length (a week-long money tracker has no need for a "This year" tab).
- At a given zoom level, the sub-period's allowance and window are derived from the tracker's own totals, not independently configured:
  - `subAllowance = totalAllowance × (daysInSubPeriod / totalPeriodDays)`
  - `subPeriod` is **calendar-aligned** (the current calendar month, not a trailing 30-day window) so the zoomed ring visibly resets at a natural boundary and "time elapsed" means something intuitive within it.
  - `consumedSoFar`, `expectedConsumedByNow`, and `difference` (§4.3) are then computed exactly as before, just scoped to the sub-period's `subAllowance` and elapsed-time-within-`subPeriod`, using the value at the *start* of that sub-period as the local starting value (see below).
- This is a **separate concept from recurrence (§4.4)**: recurrence creates a genuinely new Tracker with a fresh, independently-set allowance each cycle; a zoom level is a read-only lens on one unchanging long-term tracker, purely for at-a-glance pacing, and never creates or modifies a Tracker record.
- **New storage requirement this introduces**: computing "the value at the start of this month" requires knowing what `actualValue` was at that point in time, not just its current value. Every value obtained from a provider (§5.1) — whether auto-fetched or manually logged — must be stored as a **timestamped snapshot**, appended to a history, rather than overwriting a single "current value" field. Auto-fetch providers (Starling, Tesla) append a snapshot on every refresh; manual entries are snapshots by nature already. This history is what both zoom levels and the existing optional trend chart (§3.5) read from.

## 5. Source Provider Architecture

### 5.1 The provider abstraction

Every data source (Starling, Tesla, manual entry, and any future source) implements a common interface, isolated from tracker/calculation logic:

- `providerId` / `displayName` — identifies the provider type, e.g. `"starling"`, `"manual"`.
- `requiresConnection` — whether this provider needs an auth/setup step before use (true for Starling, false for manual).
- `listAvailableTargets(for connection) -> [SourceTarget]` — e.g. Starling returns the accounts/Spaces visible to that token; manual returns a single implicit target (or a user-named log).
- `fetchCurrentValue(target) async throws -> Decimal` — Starling makes a live API call; manual returns the latest logged reading.
- `logManualReading(target, value, date)` — supported by manual-type providers (and usable as an override/correction path even for auto-fetch providers, if useful).

New sources are expected to require real engineering work (auth flows differ a lot between providers — see the Starling vs. a hypothetical OAuth-based bank below), but conforming to this one interface is the only requirement for a new source to slot into the existing Tracker/UI code with no changes elsewhere.

### 5.2 Connected Sources

A `ConnectedSource` is a configured instance of a provider — e.g. "My Starling account" — kept separate from individual trackers so multiple trackers can share one connection (§4.5):

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `providerId` | String | Matches a registered provider (§5.1) |
| `displayName` | String | User-given label shown in pickers, e.g. "My Starling" |
| `credentialKeychainKey` | String? | Reference to the auth token in Keychain, if any |

- A **Settings → Connected Sources** screen lists all configured sources, independent of the Tracker list, with add/remove actions.
- Adding a new tracker involves: pick an existing Connected Source (or add a new one inline), then pick a target within it (§5.1).

### 5.3 Provider: Starling

- Each user obtains their own **Starling personal access token** via developer.starlingbank.com (no OAuth flow required for this personal-use case) — notably simpler than most banks' developer offerings; do not assume a future bank provider will be this easy to build (see note below).
- One token per user is generally sufficient — it exposes every account the user's Starling login has access to (personal, joint, business), not just one.
- Required scopes: `account:read`, `balance:read`. Add `savings-goal:read` for trackers pointed at Spaces/savings goals (confirm exact scope name and endpoint shape against current Starling API docs at build time).
- Token stored in the iOS Keychain with `kSecAttrSynchronizable` set so it syncs via iCloud Keychain across the user's own devices — never stored in UserDefaults or plain files.
- API calls: `GET /api/v2/accounts` (list targets), `GET /api/v2/accounts/{accountUid}/balance` (main balance), and the Spaces/savings-goals endpoint(s) (verify current shape at build time).
- Refresh: manual refresh button in-app; background refresh for widgets every 15–30 minutes, not continuous polling. On failure, show a distinct error state (§8.4) rather than a stale/misleading figure.
- **Note for future bank providers**: Starling's simple personal-access-token model is not typical. Monzo, for example, requires full OAuth2 (client registration, redirect-based login, access/refresh token handling) even for personal use, and its plain developer API is explicitly restricted to the token owner's own account rather than general public use. Adding a second bank should be scoped as "a new, potentially significantly larger integration," not "copy Starling's connector." An aggregator (Plaid, TrueLayer, Yapily, GoCardless) is an alternative that speaks to many banks behind one API, at the cost of a third-party dependency and pricing/onboarding aimed more at companies than solo hobbyist apps — worth evaluating explicitly before committing, rather than assuming it's the default answer.

### 5.4 Provider: Tesla

Used for mileage trackers against a Tesla vehicle, as the "simplest available integration" rather than the most feature-rich:

- Auth is OAuth2 via Tesla's own login/consent screen — a genuinely different auth shape from Starling's personal access token, which is the point of including it (see §1). Requires registering a developer account and an OAuth application at developer.tesla.com, plus hosting a public key verification file at a domain you control (a one-off setup cost, not a per-use one).
- Data field: `Odometer`, read via the **cached** vehicle-data endpoint (up to ~20 minutes stale) rather than Fleet Telemetry streaming — deliberately the simplest, and for personal use typically free, option. Streaming is unnecessary here: mileage on a lease tracker only needs checking occasionally, not in real time.
- `direction = increasing` (mileage only goes up) — uses the same generic model as a Starling savings goal, no special-casing needed.
- Refresh cadence should default to infrequent (e.g. once a day, or purely on manual refresh) — there's no benefit to polling a slowly-changing odometer often, and doing so needlessly risks exceeding Tesla's free usage credit.
- OAuth access/refresh tokens stored in Keychain with iCloud sync, same pattern as Starling (§5.3).
- Cost note for the user: Tesla's Fleet API gives each developer account a free monthly usage credit (£8 in the UK at time of writing) intended to cover exactly this kind of light personal use; a cached vehicle-data request is also free outright in Tesla's own pricing. The only likely real-world cost is a domain (if the user doesn't already have one) to host the required verification file — roughly £10–15/year, one-off ongoing cost rather than per-use.

### 5.5 Provider: Manual entry

- Used for anything without an API — mileage is the concrete v1 case, but this covers any quantity tracked by hand.
- The tracker's Add/Edit screen includes a "Log a reading" action: user enters a value and a timestamp (defaulting to now).
- `actualValue` is the most recent logged reading; no automatic refresh.
- Consider a lightweight local-notification reminder to log a new reading on a user-set cadence (e.g. weekly) — a nice-to-have, not a hard requirement for v1.
- Manual readings are stored as part of the synced data (§6) — no separate storage mechanism needed.

## 6. Data Storage & Cross-Device Sync

- **Requirement: full sync of all trackers, connected sources, and reading history across the user's own iPhone, iPad, Mac, and Apple Watch.** This is a hard requirement, not optional.
- Every value obtained from a provider is stored as a **timestamped snapshot** (§4.6) rather than a single overwritten "current value" field — this history is required for zoom levels (§4.6) and the optional trend chart (§3.5), and must sync in full, not just the latest reading.
- Implementation: **SwiftData with CloudKit sync** (`ModelContainer` configured with a CloudKit container). Apple handles propagation and basic conflict resolution across devices signed into the same Apple ID.
  - Alternative if SwiftData proves unsuitable: Core Data + `NSPersistentCloudKitContainer`, same underlying mechanism.
- Requires the app's iCloud capability (CloudKit) enabled in Xcode, and the Apple Developer Program membership (see §10).
- **No sync between different users' data at any point** — each person's CloudKit container is scoped to their own private database under their own Apple ID.

## 7. Platform-Specific UI

### 7.1 iOS / iPadOS

- **Tracker list** — root screen listing all trackers (name, unit, quick ring-based status indicator per §3.4).
- **Tracker detail / dashboard** — the two-ring visual (§3.4) as the primary visual, plus current value, target value today, ahead/behind figure (in the tracker's own unit), days/hours remaining, refresh button (auto-fetch sources) or "Log a reading" button (manual sources), and optionally a secondary trend chart (styled per §3.5). For long-running trackers, a zoom-level selector (Overall / This year / This month / This week, per §4.6) sits above the rings, re-scoping the whole dashboard — rings, figures, and chart — to the selected sub-period.
- **Add/Edit tracker screen** — name, unit, direction, Connected Source picker (§5.2) then target picker within it, start date, end date, starting value (defaults to 0 for money), total allowance, and an optional recurrence rule (§4.4). Shows computed hourly pace rate as a confirmation line.
- **Settings → Connected Sources** — add/remove connected sources (Starling token entry, or name a new manual source).
- iPad: same views, laid out with more breathing room / split view where natural; no bespoke iPad-only screens required for v1.

### 7.2 macOS

- **Main window**: `NavigationSplitView` — sidebar lists trackers (including past, completed instances of recurring trackers as history), detail pane shows the same dashboard content as iOS.
- **Settings**: native `Settings` scene (Cmd+,) for Connected Sources management and add/edit tracker.
- **Menu bar item** (`MenuBarExtra`): compact ahead/behind figure, color-coded per §3.2, with states for refreshing (spinner) and error (`--` with warning color) — see §8.4. Dropdown shows current value, target, difference, and a refresh/log-reading button. Supports multiple trackers via a default/pinned tracker or a submenu (decide during build).
- **Dock icon badge**: indicates when any tracker is behind pace.
- **Notifications**: banner when a tracker crosses from ahead to behind pace (or vice versa), worded per §3.6.

### 7.3 watchOS

- Companion app: simple list/detail view mirroring the dashboard (current value, target, ahead/behind) — read-only for auto-fetch sources; manual trackers may support quick reading entry directly from the Watch as a stretch goal.
- Complication: shows the ahead/behind figure for a chosen/default tracker directly on the watch face.

## 8. Widgets

### 8.1 iOS Home Screen widgets (WidgetKit)

- **Small**: mini two-ring visual (§3.4) with the ahead/behind figure below it.
- **Medium**: current value + target + the rings (compact) + ahead/behind line.
- **Large**: rings at a larger size, optionally with a secondary trend chart (styled per §3.5).
- Each widget instance is configurable to a specific tracker and, for long-running trackers, a specific zoom level (§4.6) — e.g. a widget pinned to "3-year lease — This month" rather than always showing the full 3-year pace (WidgetKit configuration intent).

### 8.2 iOS Lock Screen widgets

- **Circular**: the two-ring visual at Lock Screen scale — a natural fit, since Lock Screen circular widgets are already ring-shaped.
- **Rectangular**: ahead/behind figure + "Day X of Y".
- **Inline**: ahead/behind figure only, next to the clock.

### 8.3 macOS

- Same WidgetKit widgets reused as Desktop widgets (macOS Sonoma+) and Notification Center widgets — no separate implementation needed beyond the shared WidgetKit target.

### 8.4 Widget/menu bar states

All glanceable surfaces (widgets, menu bar item) should support four states, colored per §3.2: ahead of pace (green), behind pace (amber-red), refreshing (neutral grey-blue), and error (amber/warning — token invalid, no network, stale manual entry, etc., visually distinct from the behind-pace state). Never silently show a stale figure as if it were current.

## 9. Out of Scope for v1 (possible future additions)

- Additional source providers beyond Starling, Tesla, and manual entry (another bank, an aggregator-backed provider, HealthKit, etc.) — the provider interface (§5.1) is designed to make these additive later without reworking the core app.
- Tesla Fleet Telemetry (real-time streaming) — v1 uses only the cached, free vehicle-data read (§5.4); streaming could be added later if a use case actually needs near-real-time mileage, which seems unlikely.
- Domains beyond money and mileage (e.g. weight/health tracking) — parked for now; would likely need extra consideration around data smoothing (raw readings are noisier than a bank balance or an odometer) if revisited later.
- Siri Shortcuts / voice status queries.
- Spotlight surfacing via App Intents.
- Handoff between the user's own devices.
- Live Activities / Dynamic Island.
- Any cross-user sharing or syncing of tracker data.
- Transaction-level detail or spending categorization for money trackers.
- Payment initiation (Starling access is read-only; no `payment:create` or similar scopes needed).

## 10. Deployment

- Built and signed under one Apple ID (the primary developer), enrolled in the **Apple Developer Program** ($99/year) — required for:
  - TestFlight distribution to a second person as an internal tester (no developer account needed on their end — just a free Apple ID and the TestFlight app).
  - The iCloud/CloudKit capability used for cross-device sync (§6).
- No App Store public listing required — internal TestFlight distribution is sufficient for personal/household use.

## 11. Security Notes

- All provider credentials (e.g. the Starling access token) stored in Keychain only, with iCloud sync enabled for the credential itself (so it doesn't need re-entering per device).
- No token, balance, mileage reading, or other tracker data should be logged, transmitted to any third-party service, or stored outside Keychain/CloudKit.
- All Starling API calls made directly from the client to `api.starlingbank.com` — no intermediary backend server.

## 12. Assumptions / Open Items for the Build Agent to Confirm

- Exact current Starling API endpoint(s) and scope name(s) for Spaces / savings goals (confirm against developer.starlingbank.com/docs, as this may have changed).
- Whether SwiftData + CloudKit or Core Data + NSPersistentCloudKitContainer is the better fit given current tooling maturity at build time.
- Menu bar behavior when multiple trackers exist (single pinned tracker vs. submenu) — pick a sensible default and note it as a decision made.
- Rate limit handling for Starling API calls (back off gracefully on 429s), especially given §4.5's shared-fetch requirement across trackers on the same source.
- Final app icon design exploring the two-ring motif from §3.3 — treat the direction given as a brief, not a locked-in final design.
- Exact `RecurrenceRule` representation (§4.4) — e.g. an RRULE-like structure vs. a simpler custom enum — left to the build agent's judgment, as long as it supports "monthly anchored to a day-of-month" and "weekly anchored to a weekday" at minimum.
- Whether manual-entry reminder notifications (§5.5) are worth including in v1 or deferred.
- Exact Tesla Fleet API endpoint/scope names and current free-credit amount for the user's region (confirm against developer.tesla.com at build time, as pricing and endpoint names have changed before and may again).

