# Wiggle Room — Build Spec

## 1. Overview

**Wiggle Room** tracks any allowance that depletes or accumulates over a fixed period against the pace needed to land exactly on target. Examples include a bank balance against a monthly budget, or a car's mileage against a lease's annual allowance. The core engine is a **Tracker** comparing an expected pace against an actual reading over a date range (§4). Trackers are deliberately generic, and the data that feeds a tracker comes from a **modular source provider** (§5), so new domains (a different bank, a different kind of reading entirely) can be added as self-contained units of code without touching the tracker/calculation engine itself.
Three source providers will ship initially: **Starling** (money), **Tesla** (car mileage, via its Fleet API), and **manual entry** (anything without an API). Three is a deliberate minimum, not two; building only Starling and manual entry risks the "provider interface" quietly becoming shaped around just those two cases without anyone noticing. Starling (personal access token, no OAuth), Tesla (OAuth2, a different auth shape entirely), and manual (no network access at all) are usefully different from each other, so if all three fit through the same interface cleanly, the abstraction is real rather than accidental. Additional providers beyond these three — another bank, another kind of connected data — are expected to require genuinely new code each time (this is not a no-code plugin system), but the architecture in §5 keeps that new code isolated behind one interface so it never touches tracker logic, calculations, or UI beyond a picker entry.
The name **Wiggle Room** captures the everyday idiom for having a bit of slack left before a limit — the two-ring visualization (like Apple Fitness's Activity rings) shows exactly how much of that slack remains, tracking pace vs. actual consumption against a target, detailed in §3.
The app is built for a single user's own use across their own devices. Two people (e.g. a couple) may each run their own independent installation against overlapping accounts (e.g. a shared joint account), but **the two installations never share or sync data with each other**. All sync is within one person's own Apple ID and devices only.
## 2. Platforms
In all cases, we target the latest generally available OS versions, including macOS and iOS 27 (watchOS remains on 26.0 deliberately, for real-device compatibility — see progress-notes.md).
- iOS (iPhone)
- iPadOS
- macOS
- watchOS (companion app + complication)
- **Deliberately not targeted**: visionOS and Mac Catalyst — explicitly removed from the project's supported platforms/device families (see progress-notes.md).
- Shared codebase via a single Xcode multiplatform SwiftUI project; platform-specific UI where noted below. 
## 3. Name & Visual Direction
This section gives the build agent a consistent design language, rather than defaulting to generic finance-app styling (heavy greens/reds, bar charts, alert-style banners). It's written with money as the example throughout for clarity, but every rule applies equally to a mileage tracker — swap "balance" for "reading" and "£" for "mi" as the tracker's `unit` dictates (§4.1).

### 3.1 Core metaphor
Everything in the UI should read as **holding (or drifting from) a steady pace toward a known endpoint**, not a countdown or a warning system. The emotional tone should be calm and steady, not alarming. Reaching a "full" ring at period end is an expected, neutral outcome (you were meant to use the whole allowance) — never framed as an achievement to celebrate the way Apple's own Activity rings frame closing a ring, since here "full" just means "period over," not "goal smashed."

### 3.2 Color language

- **Ahead of / on pace**: a calm, confident green — avoid neon/alert greens.
- **Slightly behind pace**: amber - just an indicator before it goes red
- **Behind pace**: an amber-leaning red rather than a harsh stop-sign red, to keep the tone corrective rather than alarming. Reserve pure red for genuinely urgent states (e.g. a money tracker's balance near zero, or a mileage tracker with the full allowance already used) — not just "behind pace" on its own. In practice this urgency distinction is what the amber early-warning band below is for, ahead of the harder red.
- **Neutral/refreshing**: cool grey-blue.
- **Error**: amber/warning tone, distinct from both the ahead-of-pace green and behind-pace red, so a stale-data state is never confused with a genuinely-behind-pace state (see §8.4).
- The **outer (pace) ring** stays a neutral gray/graphite in all states — it's a clock, not a status indicator. Only the **inner (actual) ring** carries the status color.
- **Implementation note**: the inner ring's status is a **three-state traffic light** (`PaceStatus`: good/warning/bad → green/amber/red), not a plain green/red binary. Green is exactly "on pace or ahead" (`difference >= 0`) — **there is no grace-zone tolerance before green turns amber**: any shortfall at all, however small a percentage of `totalAllowance`, is at least amber. (An earlier version of this rule let a shortfall under 1% of the total allowance still read as green/"under budget" — removed as a genuine bug, since it let the status color and word directly contradict the actual-vs-target figures shown right next to it.) Red is reserved for behind-pace by more than 5% of `totalAllowance` — a percentage rather than an absolute amount, since an absolute figure wouldn't mean the same thing for a £50 tracker as a £5,000 one. The 5% red threshold is a tuning decision, not a fixed requirement — adjust if real usage suggests otherwise.

### 3.3 Typography & iconography

- Numerals (current value, target value, difference) should be the visual anchor of every screen — large, tabular/monospaced figures so digits align as they change. **Implemented**: a custom typography system (`WiggleRoomFont`) uses Fraunces (a variable serif) for headlines/status words and SF Rounded with tabular figures for every numeric readout, kept as a separate font specifically so digit alignment is never put at risk by the display typeface.
- **App icon**: after exploring several concepts (including the two-ring motif originally proposed here), the shipped design is a single hand-drawn wiggle/sine-wave line in brand violet, with a lower-opacity second line descending behind it echoing the trend chart — not literal piggy-bank/coin imagery, and reads sensibly for non-money trackers. A matching watchOS app icon was added alongside it. The two-ring motif survives as the **in-app** data-visualization language (the dashboard rings, list-row indicators, empty-state ring stroke) even though the app icon itself moved away from it — avoid literal piggy-bank/coin imagery there too.

### 3.4 Ring encoding (primary visualization)

The primary visualization is two concentric rings, functionally accurate (not decorative) — numbers remain the source of truth throughout the app, but the rings should encode real values precisely:

- **Outer ring ("pace")** — fills according to elapsed time within the period: `fraction = hoursElapsed / periodHours`, clamped to `[0, 1]`. Colored neutral gray per §3.2.
- **Inner ring ("actual")** — fills according to how much of the total allowance has actually been consumed so far (§4.3 `consumedSoFar`): `fraction = clamp(consumedSoFar / totalAllowance, 0, 1)`. Colored per the three-state traffic light in §3.2 (green/amber/red).
- **Reading it**: if the inner ring is *less* filled than the outer ring, less of the allowance has been consumed than the elapsed time implies — ahead of pace. If the inner ring is *more* filled than the outer, behind pace.
- This is the primary at-a-glance visual on the main dashboard, Home Screen widgets, Lock Screen widgets, and watch complication. A trend-line chart (actual vs. pace over time) may still be included as a secondary/detail view, styled per §3.5, for users who want to see the historical shape rather than a single current snapshot.
- Numeric readouts (current value, target value, difference, in the tracker's own unit) must always be shown alongside the rings, never replaced by them.
- **Apple Fitness-style ring geometry**: the two rings sit close together with only a thin sliver of a gap between their painted bands (proportional to `lineWidth`, not a flat constant, so the same tight look holds from a ~36pt list-row indicator up to the ~260pt dashboard hero) — not a full ring-width of space apart. Each ring's rounded end cap also slightly overlaps its own starting point once that ring is essentially closed (≥98%), matching how Fitness's own rings visibly lap themselves shut, drawn as a short extra arc layered on top of the start rather than the two caps just meeting edge-to-edge.
- **No separate color-key legend** is drawn below the rings — the figure cards elsewhere on the same screen (Current Balance, Target Right Now) already use the exact same two colors, so a legend would only repeat that mapping.

### 3.5 Chart style

- The dashboard's trend chart (`TrendChartView`) plots three things at once: a solid, visually **dominant "Target" reference line** (the straight, fixed yardstick from the period's starting value to its end-of-period target — everything else is read against it); the **actual logged readings**, plotted as connected point-to-point segments colored green/red per-segment depending on whether that segment is ahead of or behind pace; and a **dotted trend line**, distinct in both style and color from the Target line, showing where the balance is headed if the current trend continues. The trend line is not a single straight best-fit — it uses an expanding-window regression, re-fit as each new reading arrives, so it traces gentle curves through history rather than one rigid line, and its final point projects to the tracker's actual end date (the "expected final balance"). Avoid cluttered gridlines or axis labels beyond what's needed to read "start" and "end" of the period; the shape of the lines is the point, not precise chart-reading.
- **Live feel**: alongside the real logged readings, two subtle carried-forward points keep the chart honest between readings — one at "now" (only while the tracker hasn't completed) and one at the window's end — both holding the latest logged value flat, so the actual-data series visually spans the full period even with sparse readings, distinct in color/opacity from the real data points.

### 3.6 Copy/tone

- Use calm, plain status language, adapted per tracker shape rather than one fixed phrase set:
  - A **decreasing, currency-denominated** tracker (the common money case) reads naturally as a budget, so it uses budget-specific wording: "Under Budget" / "Just Over Budget" / "Over Budget" (the warning-band wording was reworded more than once post-launch — see progress-notes.md — settling on "Just Over Budget" as the early-warning phrase), with the over/under amount phrased as "Over Budget by £8.00" (sign dropped — the color and word already say the direction, so a sign on top is redundant).
  - **Any increasing tracker** (mileage included, regardless of currency) *also* uses budget-style wording once behind pace — "Slightly Over Budget" / "Over Budget" — since a higher-than-planned number literally is going over whatever cap the allowance represents; only the good state stays "On Track" (there's no natural "under budget" framing for an increasing tracker's good case). Only a **decreasing, non-currency** tracker keeps the fully neutral wording: "On Track" / "Slightly Behind" / "Needs Attention".
  - The over/under **sign** on an increasing tracker's difference figure is oriented to match this wording, not the raw underlying arithmetic sign: a higher-than-target actual value (the bad, "over" case) shows **without** a minus sign, and a lower-than-target value (the good, "under" case) shows **with** one.
  - Avoid "danger" phrasing, and avoid "ahead of pace"/"behind pace" as literal UI copy — internally useful as calculation terms (§4.3), but it reads as a race and doesn't distinguish "good" from "bad" clearly enough for a user-facing label; the `PaceStatus` wording above is what ships.
- Widget/menu bar copy should stay terse and numeric (e.g. "+£42" or "+120 mi") with fuller pace framing reserved for slightly more spacious surfaces (main dashboard, notifications).
- UI labels adapt to the tracker's `unit` and `direction` (§4.1): a currency tracker shows "Current Balance" / "Target Right Now"; any other unit shows "Current" / "Target Right Now". The small caption under "Target Right Now" reads "Final target will be £X" (previously "Final balance will be" — "balance" doesn't fit a non-money tracker) on both the dashboard and the extra-large widget, at the same visual weight as Current Balance's "£X left in this budget" caption.
- **Updating a tracker's value**: on iOS/iPadOS, this is a **pull-to-refresh gesture** on the whole dashboard (`.refreshable`) rather than a dedicated button, with a small "Pull down to update"/"Pull down to refresh" hint (wording depends on whether the tracker is manual or a connected source) sitting next to the live-update countdown, above the rings — deliberately the same gesture for both today's manual "log a reading" action and a future connected source's refresh, so there's one gesture to learn regardless of where a tracker's data comes from. macOS has no pull gesture, so it keeps an explicit button, labeled "Update Current Balance". Keep "Update" as the consistent word wherever this action or its history is referenced (e.g. "Update History", "Edit Update"), rather than mixing in "Log"/"Reading" terminology for the same feature.
- A tracker's date range only shows a time of day when one was actually set (`Tracker.hasExplicitTimes`) — a tracker left at the plain-date default (both bounds at midnight) shows just the dates, not a meaningless "12:00 AM".
- A non-currency unit (mileage and the like) never shows decimal places — rounded to the nearest whole number, since a fraction of a mile isn't a meaningful reading. Currency units still show exactly 2 decimal places when the amount isn't whole.

## 4. Core Concept: Trackers

The fundamental unit of the app is a **Tracker**: any quantity that should move from a starting value toward an end-of-period target at a steady pace. A user can create multiple trackers, each independently configured.

### 4.1 Tracker fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `name` | String | User-facing label, e.g. "Joint account — September", "Car lease mileage" |
| `unit` | String | Display unit — drives number formatting and UI copy (§3.6). Picked from a fixed set of pills (£, $, €, mi, km, kg, L, hrs), not free text, so downstream currency/formatting checks (e.g. which units get budget language, §3.6) can rely on an exact string match rather than parsing arbitrary text |
| `direction` | Enum: `decreasing` \| `increasing` | `decreasing`: starts high and depletes (bank balance). `increasing`: starts at a baseline and accumulates upward toward a **cap/allowance** (odometer mileage against a lease limit) — implemented as "less than the pace target is good," the same good/bad sense as an under-spent budget. This does **not** support an open-ended "goal to exceed" framing (e.g. a savings goal, where going *over* the target is the good outcome) — that would need a distinct mode, not just `direction = increasing`, and isn't built |
| `connectedSourceId` | UUID | References a `ConnectedSource` (§5.2) — the account/connection this tracker reads from |
| `sourceTargetId` | String? | Which specific target within that source, e.g. a Starling `accountUid` or `spaceUid`. Nil for sources with only one implicit target (most manual trackers) |
| `startDate` | Date | Start of the period (inclusive) |
| `endDate` | Date | Start of the *next* period (exclusive) — i.e. the period runs `startDate` through 23:59:59 the day before `endDate` |
| `startingValue` | Decimal | The value at period start. Defaults to **0** for money trackers (user-editable); for mileage this is the odometer reading at period start |
| `totalAllowance` | Decimal | Total amount/distance available for the whole period |

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

### 4.4 Multiple trackers per source

Trackers and sources are many-to-one: several trackers can point at the same `ConnectedSource` (and even the same `sourceTargetId`) at once. For example, a Starling connected source's main balance could feed both a week-long tracker and a month-long tracker running concurrently, each with its own pace/allowance math, reading the same underlying live balance. When multiple trackers share a source/target, the app should fetch the underlying value once per refresh cycle and let all of them reuse it, rather than issuing duplicate API calls (relevant for Starling rate limits in particular).

### 4.5 Zoom levels — removed, needs a rethink

**Removed** (was briefly implemented on the main dashboard, then pulled back out — see progress-notes.md's "Zoom levels removed" entry for why and what broke). Not in the app in any form right now: no zoom picker, no sub-period scoping, no `ZoomLevel` type. A tracker's dashboard always shows its own full period.

The original idea, kept here for whenever this gets redesigned rather than deleted outright: a tracker spanning months or years (e.g. a 3-year/30,000-mile lease) has an outer pace ring that barely moves day to day — each day is a tiny fraction of the whole period — so the primary ring visual feels inert at that scale. The removed implementation exposed **zoom levels**: read-only computed views of the *same* tracker at a shorter, calendar-aligned grain (Overall / This Year / This Month / This Week), so the ahead/behind question could be asked at whatever scale seemed useful without redefining the tracker itself.

**Why it was pulled**: real-device testing (via the Starling integration) surfaced that a tracker's dashboard defaulted to "This Week" the moment it ran over 7 days — including trackers barely over that threshold, where the calendar-week-clamped sub-period could be a small fraction of the tracker's real length. Every headline figure (Target Right Now, Under/Over Budget, "X left in this budget") was then computed against that fractional sub-period's allowance, not the tracker's real total, with nothing on screen indicating the figures were scoped rather than whole-tracker. For a short tracker this produced numbers that looked flatly wrong relative to the real budget the user actually set. Rather than patch the default threshold or the caption wording as a stopgap, the whole feature was removed pending a genuine rethink of the concept (which sub-periods actually deserve a dedicated lens, whether scoping the *headline* dashboard figures — as opposed to just the ring/chart *visual* — was ever the right call, how to make a scoped view unambiguous at a glance).

If/when this comes back, the storage requirement it drove is worth keeping regardless: computing "the value at the start of this month" needs knowing what `actualValue` was at that point in time, not just its current value — which is exactly why every value obtained from a provider (§5.1) is stored as a **timestamped snapshot** history rather than a single overwritten "current value" field (see §6). That requirement stands on its own merits now (the trend chart, §3.5, already depends on it) independent of zoom levels ever returning.

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

A `ConnectedSource` is a configured instance of a provider — e.g. "My Starling account" — kept separate from individual trackers so multiple trackers can share one connection (§4.4):

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `providerId` | String | Matches a registered provider (§5.1) |
| `displayName` | String | User-given label shown in pickers, e.g. "My Starling" |
| `credentialToken` | String? | The provider's own auth token, stored directly — see §11 for why this isn't the Keychain |

- A **Settings → Connected Sources** screen lists all configured sources, independent of the Tracker list, with **add, reconnect, and remove** all implemented. Reconnect re-enters a token for an existing source in place (same record, same trackers keep working) rather than requiring delete-and-recreate. Remove is blocked while any tracker still uses that source (deleting it would otherwise leave those trackers silently pointed at nothing — no cascade-delete rule on the relationship), with a message naming the blocking trackers rather than allowing it and breaking them.
- Adding a new tracker involves: pick an existing Connected Source (or add a new one inline, via the same screen Settings uses), then pick a target within it (§5.1) — for a real source like Starling, this is a live-fetched account picker (`AddTrackerView`'s target-picker section).
- **Implementation note**: manual entry is *not* a `ConnectedSource` the user creates or multiplies — it's a single fixed, implicit source (auto-created once), kept out of the Settings → Connected Sources list entirely. That list only shows real external connections (`providerId != "manual"`) — Starling connections now populate it once added (§5.3); Tesla (§5.4) still doesn't exist. A manual tracker's `sourceTargetId` is simply its own tracker id — there's no "which manual log" picker, since each manual tracker owns its own dedicated reading history (§5.5) directly.

### 5.3 Provider: Starling

**Implemented** (see progress-notes.md's Starling-integration entry for the file-by-file rundown and verification caveats — this environment had no Swift toolchain at all, not even `swiftc`, so none of this has been built or run):

- Each user obtains their own **Starling personal access token** via developer.starlingbank.com (no OAuth flow required for this personal-use case) — notably simpler than most banks' developer offerings; do not assume a future bank provider will be this easy to build (see note below).
- One token per user is generally sufficient — it exposes every account the user's Starling login has access to (personal, joint, business), not just one.
- Required scopes: `account:read`, `balance:read`. `savings-goal:read`/Spaces support is **not implemented** — see the open item below.
- **Token storage (revised)**: stored directly as `ConnectedSource.credentialToken`, synced via CloudKit exactly like every other piece of the app's data — **not** the Keychain. The original design used the Keychain with `kSecAttrSynchronizable` for iCloud Keychain sync, but that's a separate sync system from CloudKit with its own per-device on/off toggle; real multi-device testing hit a `ConnectedSource` record arriving on a second device (via CloudKit, fast) well before — or without ever — its Keychain token arriving (iCloud Keychain sync is slower and depends on a setting most people don't think to check), producing a source that looked connected but wasn't. Moving the token onto the CloudKit-synced record itself means there's only one sync system to reason about, and it's the one already proven to work reliably in this app. Both storage locations already sat inside the boundary §11 always allowed ("stored outside Keychain/CloudKit" was the line, not "Keychain only") — §11 itself has been updated to match. Never stored in UserDefaults or a plain file either way.
- API calls: `GET /api/v2/accounts` (`StarlingAPIClient.fetchAccounts()`, used only when connecting a source and when picking a tracker's target — not on every refresh tick) and `GET /api/v2/accounts/{accountUid}/balance` (`fetchBalance(accountUid:)`, the actual per-tick call). The Spaces/savings-goals endpoint is **not implemented** — its shape was never verified against current Starling docs, so a tracker can only point at a top-level account, not a Space, for now.
- **Refresh cadence**: while a **tracker detail screen is on-screen** (`TrackerDetailView` on iOS/iPadOS/macOS's detail pane, `WatchTrackerDetailView`), polls every **30 seconds** for that tracker's data via the existing `AutoUpdateTicker`/`TrackerUpdateScheduling` mechanism (its `interval` property, added for this — 60s default elsewhere, e.g. `TrackerListView`'s own ticker, which still only recomputes the display, never fetches), applied to every tracker type uniformly (a no-op tick for manual trackers). Manual refresh reuses the existing pull-to-refresh gesture on iOS/iPadOS and the (now source-aware) "Update Current Balance"/"Refresh" button on macOS/watchOS — `TrackerDetailView.handleUpdateGesture()`/`updateBalanceButton`, `WatchTrackerDetailView`'s Refresh button. In the background, refreshes every **5 minutes** via `BGAppRefreshTask` (`BackgroundRefreshScheduler`, registered in `WiggleRoomApp.init()`, `BGTaskSchedulerPermittedIdentifiers` added to Info.plist) — iOS treats this as a minimum interval, not a guarantee. On failure, a distinct error line (§8.4, `WiggleRoomColors.error`) is shown on iOS/macOS; the watch app currently swallows a failed background/tick refresh silently (no on-screen error state built there yet — a known gap, watch screen space and time budget didn't stretch to it this pass).
  - **Rate limit research and mitigations**: a personal access token is limited to **5 requests/second and 1000 requests/day** (researched via the Home Assistant Starling integration's incident report and independent confirmation, since developer.starlingbank.com was unreachable directly from the research environment — **re-confirm at build time**); exceeding either returns HTTP 429 with `Retry-After`. Of the four mitigations this decision called for:
    1. **Done, and naturally so**: `fetchAccounts()` (3 fields worth of data) is only called from Add Source/target-picking, never from a refresh tick — every 30s/5min tick costs exactly one request (`fetchBalance`), not two or three.
    2. **Not done**: two trackers pointed at the same Starling account still each poll independently (no per-account request de-duplication/caching) — if this becomes a real problem, the fix is a small in-memory "last fetched at" cache keyed by `accountUid` inside `StarlingProvider`/`TrackerStore`, not built this pass.
    3. **Done**: `StarlingRequestBudget` (an actor) tracks a rolling 24h request count per app-run and refuses new requests approaching the 1000/day threshold, throwing `StarlingAPIError.budgetExceeded` before a call is even made. Shared app-wide via `StarlingProvider.sharedBudget` so the count reflects real usage across every tracker/screen — but it's in-memory only, so it resets on app relaunch rather than genuinely spanning 24h across restarts (an accepted v1 simplification).
    4. **Done**: a 429 response records a cool-down via `Retry-After` (or a 60s default if absent) on the shared budget, blocking further calls until it elapses.
  - **Low Power Mode backoff**: `AutoUpdateTicker`'s `effectiveInterval` triples the base interval (30s → 90s, within the originally-decided 60–120s range) whenever `ProcessInfo.processInfo.isLowPowerModeEnabled` is true — applies to every ticker, foreground-only (the background path needs no equivalent change, since iOS already deprioritizes `BGAppRefreshTask` scheduling itself under Low Power Mode). Sleep Focus and StandBy remain deliberately not used as signals, per the reasoning already on record.
- **"Starting value" auto-fills from the live balance, but only if still empty**: once the user picks an account in `AddTrackerView`'s target picker, `startingValueText` fills with that account's current Starling balance (`TrackerStore.fetchCurrentValue(for:from:)`) rather than left for the user to type blind — a "Fetching live balance…" indicator shows in place of the usual hint text while it's in flight. **Revised**: this must never overwrite a value the user has already typed — real-device testing surfaced a case (backdating a tracker's start time to 40 minutes ago, with the starting value manually set to what the balance genuinely was then) where the auto-fill silently replaced a deliberate historical figure with "whatever the balance is right now," producing a wrong `projectedFinalValue`/"Final target will be" figure with no indication anything had been overwritten. The prefill now checks `startingValueText.isEmpty` both before starting the fetch and again right before writing the result (guarding the async race where the user types while the fetch is in flight), and simply does nothing if the field already has content — matching how `totalAllowanceText` has always worked (no pre-filled default of its own). Only "Starting value," not "Total budget" — the two stay independent decisions. Silent failure (user can still type by hand).
- **No pre-filled "0" in numeric fields**: `startingValueText`'s `@State` default was the literal string `"0"`, not just a placeholder — meaning a user typing "639" into the field (without first clearing it) produced "6390," since the digits inserted ahead of the existing "0" rather than replacing it. Changed to an empty default (matching `totalAllowanceText`, which never had this default). `unitValueField`'s `TextField("0", …)` still shows a plain "0" as a grey placeholder hint when empty — that's the correct, standard pattern and was never the bug.
- **Known gaps, not built this pass**: Spaces/savings-goal targets; cross-tracker request de-duplication (mitigation 2 above); a watch-side error state for a failed refresh. (Reconnect/remove for a Connected Source are now built — see the table note above and §12.)
- **Findings from real-device testing, not Starling-specific** (see progress-notes.md's "Starling real-device testing" entry for the full diagnosis) — presented to the user as design questions rather than silently patched:
  1. `RingsView`'s inner-ring progress opacity fade (below a 3.5% fraction) is meant to mask a transient recycle-animation artifact but, per the code, also applies permanently to any small **settled** value — a genuinely fresh tracker's inner ring looks empty. Reproduces for any tracker (manual included), not Starling-specific.
  2. **Resolved by removing zoom levels entirely** (§4.5) rather than patching in place — see that section for the full story. The tracker's dashboard now always shows its real, whole-period figures; there's no scoped view to silently mismatch them anymore.
  3. **Confirmed not a bug, root cause pinned down**: a brand-new tracker can show a nonzero "Under/Over Budget" figure within minutes of creation, even with zero real spending. `hoursElapsed` is measured from the tracker's **period start** (`startDate`, normalized to midnight when `includesTime` is off — the default), not from when the tracker was actually created in the app — so creating a tracker at, say, 8pm with a start date of "today" already counts ~20 hours as elapsed for pace purposes. User confirmed via a follow-up tracker created with explicit start/end times (`includesTime` on) that the figures come out correct once creation time and period start genuinely match. No code change needed — this is `TrackerPace.computePace`'s intentional linear-pace model (`difference = expectedConsumedByNow - consumedSoFar`) working as designed.
- **Note for future bank providers**: Starling's simple personal-access-token model is not typical. Monzo, for example, requires full OAuth2 (client registration, redirect-based login, access/refresh token handling) even for personal use, and its plain developer API is explicitly restricted to the token owner's own account rather than general public use. Adding a second bank should be scoped as "a new, potentially significantly larger integration," not "copy Starling's connector." An aggregator (Plaid, TrueLayer, Yapily, GoCardless) is an alternative that speaks to many banks behind one API, at the cost of a third-party dependency and pricing/onboarding aimed more at companies than solo hobbyist apps — worth evaluating explicitly before committing, rather than assuming it's the default answer.

### 5.4 Provider: Tesla

Used for mileage trackers against a Tesla vehicle, as the "simplest available integration" rather than the most feature-rich:

- Auth is OAuth2 via Tesla's own login/consent screen — a genuinely different auth shape from Starling's personal access token, which is the point of including it (see §1). Requires registering a developer account and an OAuth application at developer.tesla.com, plus hosting a public key verification file at a domain you control (a one-off setup cost, not a per-use one).
- Data field: `Odometer`, read via the **cached** vehicle-data endpoint (up to ~20 minutes stale) rather than Fleet Telemetry streaming — deliberately the simplest, and for personal use typically free, option. Streaming is unnecessary here: mileage on a lease tracker only needs checking occasionally, not in real time.
- `direction = increasing` (mileage only goes up) — uses the same generic model as a Starling savings goal, no special-casing needed.
- Refresh cadence should default to infrequent (e.g. once a day, or purely on manual refresh) — there's no benefit to polling a slowly-changing odometer often, and doing so needlessly risks exceeding Tesla's free usage credit.
- OAuth access/refresh tokens stored directly on their `ConnectedSource` record with CloudKit sync, same pattern as Starling (§5.3) — not the Keychain, per that section's revised reasoning.
- Cost note for the user: Tesla's Fleet API gives each developer account a free monthly usage credit (£8 in the UK at time of writing) intended to cover exactly this kind of light personal use; a cached vehicle-data request is also free outright in Tesla's own pricing. The only likely real-world cost is a domain (if the user doesn't already have one) to host the required verification file — roughly £10–15/year, one-off ongoing cost rather than per-use.

### 5.5 Provider: Manual entry

- Used for anything without an API — mileage is the concrete v1 case, but this covers any quantity tracked by hand.
- The tracker's Add/Edit screen includes a "Log a reading" action: user enters a value and a timestamp (defaulting to now).
- `actualValue` is the most recent logged reading; no automatic refresh.
- **Implemented**: a lightweight local-notification reminder to log a new reading, on a per-tracker user-set cadence — None / Every Minute / Hourly / Daily / Weekly / Every 2 Weeks / Monthly (`reminderCadenceMinutes`, minute-granularity throughout, not just days) — see progress-notes.md. A reminder is automatically cancelled, not just left stale, once its tracker completes (`Tracker.isCompleted`).
- Manual readings are stored as part of the synced data (§6) — no separate storage mechanism needed.

## 6. Data Storage & Cross-Device Sync

- **Requirement: full sync of all trackers, connected sources, and reading history across the user's own iPhone, iPad, Mac, and Apple Watch.** This is a hard requirement, not optional.
- Every value obtained from a provider is stored as a **timestamped snapshot** rather than a single overwritten "current value" field — this history is required for the optional trend chart (§3.5, and originally for zoom levels too — see §4.5 for why those were since removed) and must sync in full, not just the latest reading.
- Implementation: **SwiftData with CloudKit sync** (`ModelContainer` configured with a CloudKit container, `cloudKitDatabase: .automatic`), confirmed working end-to-end (real cross-device sync verified between a physical device and the Simulator). A local-only `ModelConfiguration` is kept as a defensive fallback, used only if CloudKit container creation throws (e.g. no iCloud account signed in). Apple handles propagation and basic conflict resolution across devices signed into the same Apple ID.
  - This resolves the open question in §12 about SwiftData vs. Core Data — SwiftData proved sufficient; no need to fall back to `NSPersistentCloudKitContainer`.
  - **CloudKit requires every relationship on a `@Model` type to declare an inverse on both sides**, or the app crashes on launch (SwiftData does not enforce this locally, only once CloudKit is active) — a real requirement to design for, not just a debugging note, since it means every new relationship between model types needs its inverse added on both sides in the same change.
- Requires the app's iCloud capability (CloudKit) enabled in Xcode, and the Apple Developer Program membership (see §10) — **now active**; TestFlight and CloudKit sync are both usable.
- Widgets, the watch app, and Shortcuts intents each open their **own** `ModelContainer`, but all of them — plus the main app itself — point that container at a **shared App Group container** (`group.martinkearn.WiggleRoom`, see `AppGroup.swift`) rather than each target's own private sandbox. This is what makes same-device freshness actually work: the phone app and its widget extension read and write the literal same on-disk file, so a change is visible the instant it's asked for, with no CloudKit round-trip required for that. CloudKit sync is still what keeps *different devices* (the phone and the Mac, or the phone and the Watch) consistent with each other — it does not by itself explain same-device freshness, which is what the App Group is for. A freshly-created container's very first fetch can still race CloudKit's own initial history import and come back empty with no error (e.g. a genuinely first-ever launch, before any process has shared the group container yet); callers that need data immediately (e.g. a widget's configuration picker) should retry a few times rather than trusting the first empty result.
  - **Registering a new App Group capability needs a real signed-in Apple ID in Xcode's own GUI** — same requirement as CloudKit's capabilities before it (see progress-notes.md). The entitlements/`ModelConfiguration(groupContainer:)` code can be written and committed from anywhere, but the actual portal-side registration (Signing & Capabilities → + Capability → App Groups, on every target that touches the store) has to happen at least once through Xcode itself, by someone with real account access — a headless `xcodebuild`/CI environment without a signed-in account will fail with "doesn't include the App Groups capability" until that's done.
- **No sync between different users' data at any point** — each person's CloudKit container is scoped to their own private database under their own Apple ID.

## 7. Platform-Specific UI

### 7.1 iOS / iPadOS

- **Tracker list** — root screen listing all trackers (name, unit, quick ring-based status indicator per §3.4). A tracker whose period has ended shows a small "Completed" badge next to its name.
- **Tracker detail / dashboard** — the two-ring visual (§3.4) as the primary visual, plus current value, target value today, ahead/behind figure (in the tracker's own unit), a live-update countdown ("Refreshes in Xs") with the pull-to-refresh hint beside it (§3.6), date range/days-remaining, and optionally a secondary trend chart (styled per §3.5). Updating is the pull-to-refresh gesture described in §3.6, not a dedicated button. Always shows the tracker's own full period — no zoom/sub-period scoping (§4.5 was removed; every figure on this screen reflects the whole tracker). For a real, non-manual source, a small caption ("My Starling Account · Personal") above the update countdown names the connection and bound account — resolved once on appear (never re-fetched on the 30s tick), so it's always clear at a glance where this tracker's figures actually come from.
  - **Completed presentation**: once a tracker's period has genuinely ended (`Tracker.isCompleted`), the dashboard switches out of its live view — the live "Target Right Now" projection no longer applies, since there's nothing left to project. A "Completed" badge replaces the countdown/pull-hint area, and a single final-stats card (pinned to the tracker's own `endDate`, not "now") replaces the two live figure cards, showing the final value and its final over/under status. Balance updates are disabled (the pull-to-refresh gesture, the equivalent macOS button, and the `LogReadingIntent` Shortcut all refuse once completed), and any reminder is cancelled rather than left to keep firing.
- **Add/Edit tracker screen** — name, unit, direction, Connected Source picker (§5.2) then target picker within it, start date, end date, starting value (no pre-filled default — an empty field, not "0", so typing doesn't insert ahead of a stray existing digit), and total allowance. Shows computed hourly pace rate as a confirmation line. **Editing** an existing tracker shows its Source and (for a real, non-manual connection) bound Account as read-only rows — resolved live from the source's current account list, matched by the tracker's stored `sourceTargetId` — rather than an editable picker; neither can be changed after creation (§4.4's shared-fetch assumption depends on a tracker's target staying fixed).
- **Settings → Connected Sources** — add/reconnect/remove connected sources (Starling token entry, or name a new manual source).
- iPad: same views, laid out with more breathing room / split view where natural; no bespoke iPad-only screens required for v1.
- **Shortcuts/Siri**: implemented via `AppShortcutsProvider` — a "Log a reading" intent (manual trackers only) and a read-only "view tracker status" intent, each with their own App Intents entity so Shortcuts/Siri can invoke them without the app running.

### 7.2 macOS

- **Main window**: `NavigationSplitView` — sidebar lists trackers, detail pane shows the same dashboard content as iOS.
- **Settings**: native `Settings` scene (Cmd+,) for Connected Sources management and add/edit tracker.
- **Menu bar item** (`MenuBarExtra`): compact ahead/behind figure, color-coded per §3.2, with states for refreshing (spinner) and error (`--` with warning color) — see §8.4. Dropdown shows current value, target, difference, and a refresh/log-reading button. **Decision made**: shows a single tracker — the most-recently-started one — rather than a submenu; simpler of the two options the spec left open, revisit with a submenu if a single pinned tracker proves insufficient once there are enough concurrent trackers for it to matter.
- **Dock icon badge**: indicates when any tracker is behind pace. **Implemented** — `MacRootView` sets `NSApplication.shared.dockTile.badgeLabel` to `"!"` whenever any tracker's `PaceStatus` isn't `.good`, re-evaluated once a minute alongside the notification check below.
- **Notifications**: banner when a tracker crosses from ahead to behind pace (or vice versa), worded per §3.6. **Implemented** via `PaceCrossingNotifier` — tracks each tracker's last-known ahead/behind side in memory (not persisted; a timely heads-up, not an audit trail) and posts a local notification on any crossing, worded via the same `PaceStatus` labels as §3.6. macOS only for now, since iOS/watchOS already have an always-visible widget/complication covering this at a glance.

### 7.3 watchOS

- Companion app: simple list/detail view mirroring the dashboard (current value, target, ahead/behind) — read-only for auto-fetch sources; manual trackers support quick reading entry directly from the Watch (implemented as a real v1 feature, not left as a stretch goal, since manual entry is the only provider in scope so far). Talks to its own CloudKit-backed `ModelContainer` independently of the phone being nearby.
- Complication: shows the ahead/behind figure for a chosen/default tracker directly on the watch face. **Implemented** as a separate WidgetKit extension (`WiggleRoomComplication` target, embedded inside `WiggleRoomWatch`), covering `.accessoryCircular`/`.accessoryRectangular`/`.accessoryInline` families with its own tracker-picker configuration (App Intents entities aren't shared across extension targets), refreshed hourly with an immediate reload on data changes.

## 8. Widgets

### 8.1 iOS Home Screen widgets (WidgetKit)

- **Small**: mini two-ring visual (§3.4) with the ahead/behind figure below it.
- **Medium**: current value + target + the rings (compact) + ahead/behind line.
- **Large**: rings at a larger size, current/target figures as their own rows.
- **Extra large** (iOS/iPadOS/macOS 27+): mirrors the phone dashboard closely — full-size rings with center content, both figure cards with their captions, and the days-remaining line; switches to the same completed-tracker final-stats presentation as the dashboard (§7.1) once a tracker's period has ended.
- Every family shows a small "Completed" badge next to the tracker's name once its period has ended, and a subtle corner brand mark (a stand-in using the existing tinted app icon at reduced opacity, pending a proper transparent-background logo) on the medium/large/extra-large families.
- Each widget instance is configurable to a specific tracker (via an `AppIntentConfiguration` + `WidgetConfigurationIntent`, so two widgets can show two different trackers side by side). No zoom-level configuration — §4.5 was removed from the app entirely, so a widget always shows a tracker's real, whole-period pace.
- Reuses the same `RingsView` used by the main app dashboard rather than a bespoke widget-only visual.
- Each widget instance sets a `.widgetURL` (`wiggleroom://tracker/<uuid>`) so tapping it opens the app directly to that tracker's dashboard, rather than just to the tracker list.
- **Reload policy**: aligned to the tracker's own end date (`TrackerUpdateScheduling.nextWidgetReloadDate`) rather than a flat "always an hour away" ceiling — a budget-friendly ~15 minute cadence for most of a tracker's life, tightening to every minute in the final hour, so the last reload before a tracker completes lands on time. This is also the same scheduling utility the in-app dashboard/list use for their own live-update ticks, and is written generically enough to double as the polling logic for a future real connected-source refresh.
- **The widget's "choose a tracker" configuration picker** needs a generous CloudKit-sync wait before a just-created tracker reliably appears in it — see the `WidgetDataStore.fetchAllTrackersForConfiguration()`/`entities(for:)` notes in progress-notes.md if this ever seems broken again; a couple of real bugs here (the picker resolving an already-selected tracker's name too eagerly, and a single transient fetch error mid-poll discarding an otherwise-successful wait) were fixed once already and are worth checking first before assuming a new one.

### 8.2 iOS Lock Screen widgets

- **Circular**: the two-ring visual at Lock Screen scale — a natural fit, since Lock Screen circular widgets are already ring-shaped.
- **Rectangular**: ahead/behind figure + "Day X of Y".
- **Inline**: ahead/behind figure only, next to the clock.

### 8.3 macOS

- Same WidgetKit widgets reused as Desktop widgets (macOS Sonoma+) and Notification Center widgets — no separate implementation needed beyond the shared WidgetKit target.

### 8.4 Widget/menu bar states

All glanceable surfaces (widgets, menu bar item) should support four states, colored per §3.2: ahead of pace (green), behind pace (amber-red), refreshing (neutral grey-blue), and error (amber/warning — token invalid, no network, stale manual entry, etc., visually distinct from the behind-pace state). Never silently show a stale figure as if it were current.

- **Implementation note**: nothing tells WidgetKit a tracker's figures changed for free — an explicit reload trigger is required on every mutation path. In-app changes (any edit that goes through `TrackerStore`) call `WidgetCenter.shared.reloadAllTimelines()` directly; changes that arrive via CloudKit sync from another device while the app is simply open (never touching `TrackerStore`) need a separate observer on the store's remote-change notification to trigger the same reload. Both paths are needed — one alone leaves a real staleness gap. As of the App Group migration (§6), the reload itself is now fast to actually reflect once triggered — the widget's re-fetch reads the same on-disk file the app just wrote, rather than waiting on its own separate CloudKit sync — so the remaining staleness is bounded by the periodic reload policy (`TrackerUpdateScheduling.nextWidgetReloadDate`, §8.1) between explicit triggers, not by cross-process sync latency.

## 9. Out of Scope for v1 (possible future additions)

- Additional source providers beyond Starling, Tesla, and manual entry (another bank, an aggregator-backed provider, HealthKit, etc.) — the provider interface (§5.1) is designed to make these additive later without reworking the core app.
- Tesla Fleet Telemetry (real-time streaming) — v1 uses only the cached, free vehicle-data read (§5.4); streaming could be added later if a use case actually needs near-real-time mileage, which seems unlikely.
- Domains beyond money and mileage (e.g. weight/health tracking) — parked for now; would likely need extra consideration around data smoothing (raw readings are noisier than a bank balance or an odometer) if revisited later.
- Spotlight surfacing via App Intents.
- Handoff between the user's own devices.
- Live Activities / Dynamic Island — evaluated explicitly and skipped by design, not just left aside: the API is built for short, bounded events (a ride, a delivery) with a clear start/end held open on the Lock Screen for that duration, which doesn't fit a tracker running for weeks or months. A narrower version — surfacing one only in a tracker's final 24 hours — could be worth it later, but that's a distinct, smaller feature.
- Any cross-user sharing or syncing of tracker data.
- Transaction-level detail or spending categorization for money trackers.
- Payment initiation (Starling access is read-only; no `payment:create` or similar scopes needed).
- Zoom levels for long-running trackers (§4.5) — built, then removed after real-device testing showed it producing confusing, wrong-looking headline figures with no on-screen indication of scoping. Needs a genuine redesign before it's worth rebuilding, not a quick patch.

## 10. Deployment

- Built and signed under one Apple ID (the primary developer), enrolled in the **Apple Developer Program** ($99/year) — required for:
  - TestFlight distribution to a second person as an internal tester (no developer account needed on their end — just a free Apple ID and the TestFlight app).
  - The iCloud/CloudKit capability used for cross-device sync (§6).
- No App Store public listing required — internal TestFlight distribution is sufficient for personal/household use.

## 11. Security Notes

- **All provider credentials (e.g. the Starling access token) stored directly on their `ConnectedSource` record, synced via CloudKit** — revised from an original Keychain-based design (see §5.3 for why: real multi-device testing showed the Keychain's own sync mechanism, iCloud Keychain, lagging or never arriving independent of the app's CloudKit sync, producing a source that looked connected on one device and wasn't on another). Still scoped entirely to the user's own private CloudKit database under their own Apple ID, never transmitted anywhere but Starling itself and Apple's sync infrastructure — the same trust boundary as everything else this app stores, just one sync system instead of two. Not stored in UserDefaults or a plain file.
- No token, balance, mileage reading, or other tracker data should be logged, transmitted to any third-party service, or stored outside CloudKit.
- All Starling API calls made directly from the client to `api.starlingbank.com` — no intermediary backend server.

## 12. Assumptions / Open Items for the Build Agent to Confirm

Still open:

- **Nothing in this Starling implementation has been built or run against a real compiler** — this environment had no Swift toolchain at all (not even `swiftc`, let alone `xcodebuild`/a simulator), so every file described in §5.3 and progress-notes.md's Starling-integration entry is unverified beyond careful manual re-reading. Build in Xcode, resolve any compile errors, and run the test suite (including `StarlingAPIClientTests`/`StarlingProviderTests`/`StarlingRequestBudgetTests`) before trusting any of it further.
- Exact current Starling API endpoint(s) and scope name(s) for Spaces / savings goals — not implemented (§5.3); only top-level accounts are supported as tracker targets.
- Cross-tracker request de-duplication (§5.3's mitigation 2 — two trackers on the same Starling account still poll it independently) — not implemented.
- The daily request budget (`StarlingRequestBudget`) is in-memory only and resets on app relaunch rather than genuinely spanning 24h across restarts — an accepted v1 simplification, not a bug, but worth knowing if usage patterns ever seem to exceed Starling's real daily cap despite the budget.
- No on-screen error state for a failed refresh on watchOS (iOS/macOS have one, per §8.4) — a failed tick/background refresh there is currently silent.
- Rate limit *numbers* (§5.3: personal access tokens are 5 req/s, 1000 req/day per Starling's 2022 tightening) came from third-party sources — developer.starlingbank.com itself was unreachable to confirm directly in the research environment. Re-confirm against developer.starlingbank.com/faq at build time in case they've changed since.
- Exact Tesla Fleet API endpoint/scope names and current free-credit amount for the user's region (confirm against developer.tesla.com at build time, as pricing and endpoint names have changed before and may again) — no Tesla work has started yet.
- Zoom levels (§4.5) need a genuine redesign before they're worth rebuilding at all — see that section for what broke and why patching it in place wasn't the right call.

Resolved (kept here for the record):

- **SwiftData + CloudKit vs. Core Data**: SwiftData with CloudKit sync proved sufficient — see §6. No need to fall back to `NSPersistentCloudKitContainer`.
- **Menu bar behavior with multiple trackers**: a single pinned tracker (the most-recently-started one), not a submenu — see §7.2. Revisit if real usage shows it's insufficient.
- **Amber ring threshold**: not an exact "landed exactly on target" match — a percentage-of-total-allowance early-warning band, up to 5% behind pace (no lower grace zone — see the later "amber early-warning band's lower boundary" item below) — see §3.2.
- **Increasing-direction trackers model a cap/allowance, not an open-ended goal** — see §4.1. A savings-goal-style "exceeding is good" framing would need a distinct mode, not built.
- **App icon final design**: settled on a single hand-drawn wiggle/sine-wave line in brand violet, with a lower-opacity descending second line, rather than the two-ring motif originally proposed in §3.3 — see §3.3 and progress-notes.md for the decision history. A matching watchOS icon was added at the same time.
- **Whether manual-entry reminder notifications (§5.5) were worth building for v1**: built — a per-tracker `reminderCadenceMinutes` (None/Every Minute/Hourly/Daily/Weekly/Every 2 Weeks/Monthly), scheduled as a repeating local notification, minute-granularity throughout. See progress-notes.md's 2026-09-16 zoom-levels/reminders follow-up and the later reminder-cadence follow-up.
- **The amber early-warning band's lower boundary**: there is no grace zone — any shortfall behind pace, however small a percentage of the total allowance, is at least amber. An earlier version let anything under 1% behind still read as green; removed as a genuine bug once it was clear this could show a tracker's actual value below its own target figure while still saying "under budget." See §3.2 and progress-notes.md.
- **Whether an increasing tracker needed its own "over/under" wording and sign convention, distinct from a plain decreasing/non-currency tracker's neutral "On Track"/"Needs Attention"**: yes — see §3.6. A higher-than-target actual value is "over" for an increasing tracker exactly as it is for a decreasing budget tracker, so it now shares that wording (and the difference figure's sign is oriented to match), even for a non-currency unit like mileage.
- **Whether the manual "update" action needed its own dedicated on-screen button**: replaced on iOS/iPadOS with a pull-to-refresh gesture (`.refreshable`) plus a persistent hint, deliberately shaped to also serve as the future refresh action for a real connected source — see §3.6/§7.1. macOS, which has no pull gesture, keeps an explicit button.
- **Whether a tracker's period having ended needed an explicit, first-class "completed" state**, beyond the existing one-shot completion celebration: yes — `Tracker.isCompleted`, a "Completed" badge everywhere a tracker appears, and a completed-specific presentation on the dashboard/extra-large widget. See §7.1.
- **Starling refresh cadence**: 30s poll while a tracker detail screen is on-screen (reusing/retuning the existing `AutoUpdateTicker`/`TrackerUpdateScheduling` mechanism, applied to all tracker types, not just Starling — the list view's own ticker is unaffected), manual refresh via the existing pull-to-refresh gesture/macOS+watch buttons, 5-minute background refresh via `BGAppRefreshTask`. **Built** — see §5.3 and progress-notes.md's Starling-integration entry, and §12's still-open list above for what wasn't (Spaces, cross-tracker de-duplication, watch error UI) and the unverified-by-compiler caveat.
- **Low Power Mode backoff**: widen the foreground 30s poll (not the background path, which iOS already deprioritizes itself) whenever `ProcessInfo.isLowPowerModeEnabled` is true. Sleep Focus and StandBy were evaluated and explicitly rejected as separate backoff signals — no usable public API for the former, no distinct app-observable state for the latter. **Built** — see §5.3.
- **Whether widgets/complication needed to share an App Group with the app, rather than each syncing independently via CloudKit**: yes, added — see §6/§8.4 and progress-notes.md's 2026-09-17 App Group migration. Same-device freshness is no longer bounded by a CloudKit round-trip; only the periodic reload policy and genuine cross-device sync still depend on CloudKit.
- **Zoom levels (§4.5)**: implemented, then removed after real-device testing showed the default "This Week" scoping produced headline dashboard figures that looked flatly wrong for short trackers, with no on-screen indication they were scoped at all. See §4.5 and progress-notes.md's "Zoom levels removed" entry — the feature needs a genuine rethink, not a patch, before it's worth rebuilding.
- **Connected Source reconnect/remove**: built — Settings → Connected Sources rows navigate to a reconnect flow (`AddSourceView(existingSource:)`, re-enters a token for the same record without touching trackers using it) and support swipe-to-remove (blocked while any tracker still uses that source, since the relationship has no cascade-delete rule). See §5.2.
- **Starling token storage**: moved off the Keychain onto `ConnectedSource.credentialToken` directly, synced via CloudKit — see §5.3/§11 for the full reasoning (real multi-device testing showed iCloud Keychain sync lagging or never arriving independent of CloudKit, leaving a source that looked connected on one device and wasn't on another; one sync system beats two).

