# Ringet — Progress Notes

Status snapshot for picking this work back up. Last updated 2026-09-14, after
enabling CloudKit sync and a round of dashboard/UX refinements. Read
alongside [ringet-build-spec.md](ringet-build-spec.md) — this file tracks
*what's actually been built*, not the spec itself.

## What's implemented

### §4.1 / §4.3 — Tracker model & pace calculations
- [`Tracker.swift`](../src/Ringet/Models/Tracker.swift) — `Tracker`, a SwiftData `@Model` class (see **Persistence** below), and the `TrackerDirection` enum. Also holds `isCurrencyUnit` and `formattedValue(_:signed:)` — a currency symbol (£, $, €, …) is prefixed with no space ("£1,234.56"); any other unit is suffixed with a space ("1,234 miles"). The `recurrence` field (§4.4 placeholder) was removed — see decision #7.
- [`TrackerPace.swift`](../src/Ringet/Models/TrackerPace.swift) — `Tracker.pace(actualValue:asOf:)` computing periodHours/hoursElapsed/consumedSoFar/expectedConsumedByNow/difference/target-right-now in one call, so a single snapshot of "now" stays consistent. `hoursElapsed` uses `timeIntervalSince` (wall-clock seconds), which is DST-safe by construction. Also defines `PaceStatus` (`.good`/`.warning`/`.bad`) — the traffic-light read of a tracker's pace within a 5%-of-total-allowance tolerance band — with `.color` (green/amber/red) and `.label(for tracker:)`, which switches to budget language ("Under Budget"/"Near Budget"/"Over Budget") specifically for decreasing trackers denominated in currency, and stays neutral ("On Track"/"Near Target"/"Needs Attention") otherwise.
- Tests: [`TrackerPaceTests.swift`](../src/RingetTests/TrackerPaceTests.swift) — both directions, ahead/behind pace, period-start/end edges, one DST-transition regression test.

### §5.1 / §5.2 / §5.5 — Source provider abstraction & manual entry
- [`SourceProvider.swift`](../src/Ringet/Providers/SourceProvider.swift) — the protocol, unchanged.
- [`SourceTarget.swift`](../src/Ringet/Models/SourceTarget.swift) — still a plain (non-persisted) struct; a lightweight DTO for the provider protocol's API shape.
- [`ConnectedSource.swift`](../src/Ringet/Models/ConnectedSource.swift), [`ValueSnapshot.swift`](../src/Ringet/Models/ValueSnapshot.swift) — SwiftData `@Model` classes. `ConnectedSource.trackers` is the CloudKit-required inverse of `Tracker.connectedSource` — see decision #10, this one cost real debugging time.
- [`ManualEntryProvider.swift`](../src/Ringet/Providers/ManualEntryProvider.swift) — a `@MainActor` class holding a `ModelContext`; `fetchCurrentValue`/`logManualReading` resolve a target's id back to a `Tracker` (`sourceTargetId == tracker.id.uuidString`) and read/write `tracker.readings` directly. In practice, app code that already holds the `Tracker` (the dashboard, the log-reading sheet) bypasses this indirection and uses `TrackerStore.logReading`/`tracker.latestReading` directly — this provider mainly exists so the abstraction has a real implementation ahead of Starling/Tesla.
- No Starling or Tesla provider exists yet.

### §6 — Persistence, now with CloudKit sync enabled
- [`RingetApp.swift`](../src/Ringet/RingetApp.swift) — builds a `ModelContainer` for `[Tracker, ConnectedSource, ValueSnapshot]` using `ModelConfiguration(schema:cloudKitDatabase:.automatic)`, with a local-only `ModelConfiguration` as a defensive fallback (only kicks in if CloudKit container creation throws — e.g. no iCloud account signed in). **This is live now**: the user's Apple Developer Program enrollment went from "Pending" to active partway through this session, and re-enabling CloudKit surfaced (and fixed) a real schema bug — see decision #10.
- [`Ringet.entitlements`](../src/Ringet/Ringet.entitlements) declares `iCloud.martinkearn.Ringet` + the CloudKit service, and is wired in as the `Ringet` target's `CODE_SIGN_ENTITLEMENTS` build setting (Debug and Release, main app target only — not the test targets).
- [`TrackerStore.swift`](../src/Ringet/State/TrackerStore.swift) — a thin `@Observable` wrapper around a `ModelContext`: owns `manualEntrySource` (fetched-or-created once) and the `manualProvider`, and exposes `addTracker`/`deleteTracker`/`logReading`/`saveChanges` actions (`saveChanges` flushes in-place edits from `AddTrackerView`'s edit mode). Tracker/source **lists** are not held here — views read them via `@Query` directly (idiomatic SwiftData/SwiftUI, auto-updating).
- **Confirmed working this session**: created a tracker with CloudKit enabled, force-quit the app, relaunched — the tracker was still there (local disk persistence works regardless of sync). Cross-device sync itself (two real devices, or a device + the Simulator, seeing the same data) has **not** been verified yet — see **Verifying CloudKit sync** below for how to do that next.

### §7.1 — Screens (full-screen only; no widgets/Lock Screen/menu bar yet, per instruction)
- [`TrackerListView.swift`](../src/Ringet/Views/TrackerListView.swift) — `@Query`-backed list, empty state, swipe-to-delete, "+" as the primary toolbar action, gear icon (secondary) opening Connected Sources. Each row shows a small `RingsView` pace indicator plus the **difference from target** (colored per `PaceStatus`) as the subtitle — not the unit/direction text that used to be there, per explicit user feedback that the difference is the number that matters at a glance.
- [`AddTrackerView.swift`](../src/Ringet/Views/AddTrackerView.swift) — now doubles as the **edit** screen: pass `existingTracker:` and it prefills every field (including detecting whether the tracker already has a specific time-of-day set) and mutates in place via `store.saveChanges()` on save, rather than creating a new `Tracker`. A tracker's source can't be changed after creation — the edit form shows it read-only. Also has:
  - **Unit quick-pick chips** (£, $, €, mi, km, kg) under the Unit field, so setting a currency symbol doesn't depend on the keyboard layout having easy access to it.
  - **"Set specific times" toggle** for the period's Start/End — off by default (midnight-to-midnight), on to reveal `.hourAndMinute` pickers. Whichever mode is used, `startDate`/`endDate` are normalized to midnight on save if the toggle is off, so a tracker never silently inherits whatever time-of-day the form happened to be opened at.
  - Robust decimal parsing (`parseDecimal`, locale-aware via `NumberFormatter` before falling back to `Decimal(string:)`) for the Starting value/Total budget fields — see decision #11, a real data-corruption bug this fixes.
- [`TrackerDetailView.swift`](../src/Ringet/Views/TrackerDetailView.swift) — the tracker dashboard. Two-ring visual with the **difference-from-target as its centerpiece** (large, bold, colored, inside the rings — not a separate small figure), a `PaceStatus`-driven status word above it, Current/Target-Right-Now figures below, days-remaining text, a trend chart once ≥2 readings exist, an "Update Current Value" button (renamed from "Log a Reading" — see decision #4 below), and a "…" menu with **Edit Tracker** and Delete (confirmation dialog first). Pace figures refresh once a minute (`minuteTimer`) — the period is fixed, so each minute has exactly one correct target value — and a `secondTimer`-driven "Updates in Xs" caption counts down to that refresh so someone watching the screen sees it's still live.
- [`RingsView.swift`](../src/Ringet/Views/RingsView.swift) — the two-ring visual itself (§3.4) — outer neutral-gray pace ring (elapsed-time fraction), inner ring colored per `PaceStatus` (green/amber/red — true traffic-light semantics, not just a green/red binary). Bigger by default (used at 260pt in the dashboard) with the difference figure and a legend ("Time elapsed"/"Progress") as center content; `showsCenterContent: false` gives the bare rings for small uses like the list-row indicator. Uses a `GeometryReader` to constrain the center text's width so long values shrink to fit rather than overflowing past the ring — this was a real layout bug, fixed mid-session.
- [`TrendChartView.swift`](../src/Ringet/Views/TrendChartView.swift) — Swift Charts line (§3.5) — a straight gray pace-reference line from start to end, actual logged readings plotted in blue on top.
- [`LogReadingView.swift`](../src/Ringet/Views/LogReadingView.swift) — the §5.5 value-entry sheet, titled "Update Current Value" — value + date, direction-aware hint text, calls `store.logReading`. Also uses the same robust decimal parsing as `AddTrackerView`.
- [`ConnectedSourcesView.swift`](../src/Ringet/Views/ConnectedSourcesView.swift) + [`AddSourceView.swift`](../src/Ringet/Views/AddSourceView.swift) — Settings → Connected Sources (§5.2), `@Query`-backed. `AddSourceView` is still a deliberate stub ("Coming Soon") — no Starling/Tesla setup UI exists yet.
- [`View+PlatformHelpers.swift`](../src/Ringet/Views/View+PlatformHelpers.swift) — shared `#if os(iOS)` wrappers for UIKit-only modifiers (see decision #5).
- [`PreviewSupport.swift`](../src/Ringet/PreviewSupport.swift) — shared in-memory SwiftData stack + sample-tracker factory, used by every view's `#Preview`.

## CloudKit — now enabled (read this before touching it again)

The user's Apple Developer Program enrollment went from "Pending" to fully
active during this session. Re-enabling CloudKit was **not** just a matter
of flipping the config back on — it surfaced a real, previously-latent
schema bug (decision #10 below). If CloudKit sync ever seems broken again,
read that decision first before assuming it's an account/entitlement issue.

**Current setup:**
- `RingetApp.swift` uses `cloudKitDatabase: .automatic`, with a local-only fallback that only activates if the CloudKit `ModelContainer` fails to initialize.
- `Ringet.entitlements` + the `CODE_SIGN_ENTITLEMENTS` build setting are both in place on the main app target.
- The container id is `iCloud.martinkearn.Ringet`.

**What's confirmed:**
- The app builds, signs, and launches successfully with the CloudKit configuration active (both for a real device build and the iOS Simulator).
- A tracker persists across a full terminate/relaunch cycle with CloudKit enabled (local disk persistence).

**What's NOT yet confirmed — do this next:**
- Actual cross-device sync (two real devices, or a device + Simulator, both signed into the same iCloud account, seeing the same tracker appear on both). See **Verifying CloudKit sync** below.

**A one-time snag on this Mac**: running tests with `-destination
'platform=macOS'` now fails with *"Device ... isn't registered in your
developer account"* — the CloudKit entitlement means the macOS build needs a
Mac App Development provisioning profile, which needs this specific Mac
registered as a device on the paid account. `xcodebuild -allowProvisioningUpdates`
could **not** do this registration itself from the command line — it needs
Xcode's own GUI (open the project, select "My Mac" as the run destination,
build once; Xcode handles the device registration handshake automatically).
Until that's done once, **run tests against the iOS Simulator destination
instead** (see the command below) — simulators don't need per-device
registration and this now covers all 23 tests fine.

## Verifying CloudKit sync

Not yet done — next real verification step. Roughly:

1. **On the Simulator**: open the Settings app inside the Simulator and sign in with the same Apple ID used on the real device (Settings → sign in banner at the top). CloudKit sync in the Simulator can be flaky; if it doesn't seem to work, that's a known Simulator limitation, not necessarily an app bug — try two real devices instead.
2. **On both the Simulator and the real device**, make sure that Apple ID's iCloud Drive (or at minimum, this app's iCloud access) is enabled, and that both are online.
3. Create a tracker on one, and check whether it appears on the other after a short wait (CloudKit sync isn't instant — allow up to a minute or two, especially the first time a device syncs a new container).
4. Both debug builds use CloudKit's **Development** environment by default, so as long as both are signed into the same Apple ID and pointed at the same container id, they should share data.

## Key decisions worth knowing before you touch this again

1. **Manual Entry is not a "source" the user can multiply.** It's a single fixed choice (`TrackerStore.manualEntrySource`), separate from real external connections (`ConnectedSource` rows with `providerId != "manual"`, queried directly by views — currently always empty since no such provider exists). Settings → Connected Sources only ever lists those. This came from explicit user correction mid-build — the first draft modeled manual entry as an ordinary, user-creatable `ConnectedSource`, which was wrong.
2. **A manual tracker gets its own dedicated reading log automatically** — its `sourceTargetId` is just its own `id.uuidString`, and its readings live on `Tracker.readings` directly. There's no user-facing "which log" picker for manual entry.
3. **"Add New Source…" lives inside the tracker's Source picker**, pushing the same `AddSourceView` Settings uses — a shortcut so a user mid-way through creating a tracker doesn't have to back out to Settings first.
4. **Wording is deliberately non-judgmental and traffic-light-coded.** "Ahead of pace"/"Behind pace" read as a race, and didn't distinguish "good" from "bad" clearly enough — replaced with `PaceStatus` (good/warning/amber/bad → green/amber/red), with budget-specific wording ("Under/Near/Over Budget") for decreasing currency trackers specifically, since that's the case where the good/bad framing is clearest. "Log a Reading" became "Update Current Value" — the old wording didn't read naturally for a manual-entry balance update. "Target today" became "Target Right Now" since the figure is live to the minute, not daily.
5. **Cross-platform build gotchas**: this project builds for iOS *and* macOS. `.keyboardType` and `.navigationBarTitleDisplayMode` are UIKit-only — wrapped in `View+PlatformHelpers.swift`'s `decimalKeyboardIfAvailable()`/`inlineNavigationBarIfAvailable()`. Watch for this with any new UIKit-only modifier. Also avoid UIKit-only `Color` initializers like `Color(.secondarySystemFill)` — use cross-platform equivalents (e.g. `Color.secondary.opacity(...)`).
6. **Xcode 16 file-system-synchronized groups**: no manually-maintained `.pbxproj` file lists — any `.swift` file dropped into `src/Ringet/` or `src/RingetTests/` is picked up automatically.
7. **`recurrence` field was removed from `Tracker`** (it was an unused `RecurrenceRule?` placeholder for §4.4). Re-add it properly (with real semantics) when that phase starts.
8. **Running `xcodebuild` in this environment**: the active `xcode-select` developer directory is Command Line Tools, not Xcode. Prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
9. **A nasty SwiftData footgun**: an in-memory `ModelContainer`'s backing store is tied to the container object's own lifetime — if you create a container, grab only its `.mainContext`, and let the container itself go out of scope, the context silently becomes unusable and **crashes on first `insert()`**. Always hold onto the `ModelContainer` itself for as long as you use its context — see [`TestSupport.swift`](../src/RingetTests/TestSupport.swift)'s `makeInMemoryModelContainer()`.
10. **CloudKit requires every relationship to declare an inverse, on both sides of the model, or the app crashes on launch with an opaque Core Data error** ("CloudKit integration requires that all relationships have an inverse, the following do not: Tracker: connectedSource"). `Tracker.connectedSource` had no inverse declared on `ConnectedSource` — it worked fine locally (SwiftData doesn't enforce this for local-only stores) but broke the instant CloudKit was turned back on. Fixed by adding `@Relationship(inverse: \Tracker.connectedSource) var trackers: [Tracker]? = []` to `ConnectedSource`. **If you add any new relationship to a `@Model` type, check this immediately** — it won't show up in local testing, only once CloudKit is active, and the crash message doesn't point at the fix very clearly.
11. **`Decimal(string:)` silently truncates at a grouping separator instead of failing.** `Decimal(string: "3,000")` does **not** return `nil` — it parses `"3"` and stops at the comma, corrupting the value by 1000x. This bit us for real: prefilling the edit form with `.formatted(.number...)` (which adds thousands separators, e.g. "3,000") round-tripped through this on save and silently turned a £3,000 budget into £3. Fixed two ways: (a) prefill text fields with `.formatted(.number.grouping(.never)...)` so there's no separator to round-trip in the first place, and (b) added a `parseDecimal` helper (locale-aware `NumberFormatter` first, falling back to `Decimal(string:)`) used everywhere a user-typed or pasted decimal is parsed, as defense in depth. **Never use bare `Decimal(string:)` on text that might contain a thousands separator** — check `isValid`/`save()` in `AddTrackerView.swift` and `LogReadingView.swift` for the pattern to copy.

## Known gaps / things to verify by hand

- **CloudKit cross-device sync itself** — the config is live and the app doesn't crash, but actual two-device sync hasn't been observed yet. See **Verifying CloudKit sync** above.
- §4.6 zoom levels (This year/This month/This week sub-period views) are not implemented — the dashboard always shows the tracker's full period.
- No SwiftUI view has automated UI tests — verification has been manual (simulator screenshots + interaction) plus unit tests on the non-UI layers (`TrackerPace`, `ManualEntryProvider`, `TrackerStore` — 23 tests, all passing). Consider `ViewInspector`-style tests or UI tests if this grows much further.
- This Mac isn't yet registered as a device on the paid developer account (needed only for running/testing the macOS target locally with the CloudKit entitlement — see the CloudKit section above for the one-time Xcode GUI step that fixes this).

## Explicitly out of scope so far (per spec, deferred on purpose)

- §4.4 Recurrence, §4.5 multi-tracker source-sharing/dedup (only matters once a second provider exists), §4.6 zoom levels
- §5.3 Starling, §5.4 Tesla providers (only the manual provider exists)
- §7.2 macOS-specific UI (sidebar/menu bar), §7.3 watchOS, §8 widgets/Lock Screen — explicitly excluded by the user for this phase ("just focus on what happens when app is full screen")

## Suggested next steps (not a commitment, just a sane order)

1. Verify actual CloudKit sync across two real devices (or device + Simulator) — see **Verifying CloudKit sync** above.
2. Register this Mac on the developer account via Xcode's GUI, so macOS-destination tests work again locally.
3. §4.6 zoom levels, once a long-running tracker makes the full-period ring feel too static to be useful day-to-day.
4. A real source provider (Starling is the simplest per spec's own note in §5.3) — this is what actually exercises the multi-source parts of the Settings screen and the "Add New Source" flow for real.

## Verifying the app still builds and passes tests

Use the iOS Simulator destination — the macOS destination currently needs a
one-time device registration step in Xcode's GUI first (see the CloudKit
section above):

```bash
cd src
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Ringet.xcodeproj -scheme Ringet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:RingetTests test
```

23 tests should pass (`TrackerPaceTests`, `ManualEntryProviderTests`,
`TrackerStoreTests`, plus the two scaffold tests in `RingetTests`).

## Verifying on a real device

1. Plug in the iPhone/iPad/Mac, select it as the run destination in Xcode (or via `xcodebuild -destination`), and run.
2. Create a tracker, log a few readings over a couple of days, confirm the dashboard/rings/chart look right and data survives relaunch.
3. If testing sync, repeat on a second device signed into the same Apple ID — see **Verifying CloudKit sync** above.
4. **A free/personal Apple ID team install expires after ~7 days** and needs re-signing from Xcode; this doesn't apply anymore now the account is on the paid Program, but is worth knowing if a personal team is ever used again for a quick test.
