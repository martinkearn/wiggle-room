# Ringet — Progress Notes

Status snapshot for picking this work back up. Last updated 2026-09-13, after
the SwiftData persistence + full-screen dashboard phase. Read alongside
[ringet-build-spec.md](ringet-build-spec.md) — this file tracks *what's
actually been built*, not the spec itself.

## What's implemented

### §4.1 / §4.3 — Tracker model & pace calculations
- [`Tracker.swift`](../src/Ringet/Models/Tracker.swift) — `Tracker`, now a SwiftData `@Model` class (see **Persistence** below), and the `TrackerDirection` enum. The `recurrence` field (§4.4 placeholder) was removed — see decision #7.
- [`TrackerPace.swift`](../src/Ringet/Models/TrackerPace.swift) — `Tracker.pace(actualValue:asOf:)` computing periodHours/hoursElapsed/consumedSoFar/expectedConsumedByNow/difference/target-today in one call, so a single snapshot of "now" stays consistent. `hoursElapsed` uses `timeIntervalSince` (wall-clock seconds), which is DST-safe by construction. Unchanged this phase — still pure computation, works the same on a class as it did on a struct.
- Tests: [`TrackerPaceTests.swift`](../src/RingetTests/TrackerPaceTests.swift) — both directions, ahead/behind pace, period-start/end edges, one DST-transition regression test.

### §5.1 / §5.2 / §5.5 — Source provider abstraction & manual entry
- [`SourceProvider.swift`](../src/Ringet/Providers/SourceProvider.swift) — the protocol, unchanged.
- [`SourceTarget.swift`](../src/Ringet/Models/SourceTarget.swift) — still a plain (non-persisted) struct; a lightweight DTO for the provider protocol's API shape.
- [`ConnectedSource.swift`](../src/Ringet/Models/ConnectedSource.swift), [`ValueSnapshot.swift`](../src/Ringet/Models/ValueSnapshot.swift) — now SwiftData `@Model` classes.
- [`ManualEntryProvider.swift`](../src/Ringet/Providers/ManualEntryProvider.swift) — rewritten this phase: no longer an `actor` with an in-memory dictionary. It's now a `@MainActor` class holding a `ModelContext`; `fetchCurrentValue`/`logManualReading` resolve a target's id back to a `Tracker` (`sourceTargetId == tracker.id.uuidString`) and read/write `tracker.readings` directly. In practice, app code that already holds the `Tracker` (the dashboard, the log-reading sheet) bypasses this indirection and uses `TrackerStore.logReading`/`tracker.latestReading` directly — this provider mainly exists so the abstraction has a real implementation ahead of Starling/Tesla.
- No Starling or Tesla provider exists yet.

### §6 — Persistence (local; CloudKit not yet enabled — see below)
- [`RingetApp.swift`](../src/Ringet/RingetApp.swift) — builds a `ModelContainer` for `[Tracker, ConnectedSource, ValueSnapshot]`. Currently **local-only** (`ModelConfiguration(schema:)`, no CloudKit). The CloudKit-configured path is written but commented out — see **CloudKit** section below for exactly what's needed to turn it on.
- [`TrackerStore.swift`](../src/Ringet/State/TrackerStore.swift) — now a thin `@Observable` wrapper around a `ModelContext`: owns `manualEntrySource` (fetched-or-created once) and the `manualProvider`, and exposes `addTracker`/`deleteTracker`/`logReading` actions. Tracker/source **lists** are no longer held here — views read them via `@Query` directly (idiomatic SwiftData/SwiftUI, auto-updating).
- **Confirmed working on-device (simulator)**: created a tracker, force-quit the app (`xcrun simctl terminate`), relaunched — the tracker and its logged reading were both still there.

### §7.1 — Screens (full-screen only; no widgets/Lock Screen/menu bar yet, per instruction)
- [`TrackerListView.swift`](../src/Ringet/Views/TrackerListView.swift) — `@Query`-backed list, empty state, swipe-to-delete, "+" as the primary toolbar action, gear icon (secondary) opening Connected Sources. Each row shows a small `RingsView` pace indicator (§7.1's "quick ring-based status indicator").
- [`AddTrackerView.swift`](../src/Ringet/Views/AddTrackerView.swift) — name/unit/direction (segmented control)/period/budget/source, unchanged in substance from before, just now persists via `store.addTracker` (SwiftData insert) instead of an in-memory array. See **Key decisions** for the Source-picker design.
- [`TrackerDetailView.swift`](../src/Ringet/Views/TrackerDetailView.swift) — **new**: the tracker dashboard (§7.1). Two-ring visual, "Ahead of pace"/"Behind pace"/"No data yet" status, Current/Target-today/Difference figures (signed, tabular digits per §3.3), days-remaining text, a trend chart once ≥2 readings exist, "Log a Reading" button, and a "…" menu with Delete (confirmation dialog first). A 60-second timer keeps the pace figures and days-remaining live while the screen is open.
- [`RingsView.swift`](../src/Ringet/Views/RingsView.swift) — **new**: the two-ring visual itself (§3.4) — outer neutral-gray pace ring (elapsed-time fraction), inner green/amber-red actual ring (consumed fraction), colored per `RingetColors` (§3.2's calm palette, not alert colors). Reusable at any size (list row uses a small `lineWidth`).
- [`TrendChartView.swift`](../src/Ringet/Views/TrendChartView.swift) — **new**: Swift Charts line (§3.5) — a straight gray pace-reference line from start to end, actual logged readings plotted in blue on top.
- [`LogReadingView.swift`](../src/Ringet/Views/LogReadingView.swift) — **new**: the §5.5 "log a reading" sheet — value + date, direction-aware hint text, calls `store.logReading`.
- [`ConnectedSourcesView.swift`](../src/Ringet/Views/ConnectedSourcesView.swift) + [`AddSourceView.swift`](../src/Ringet/Views/AddSourceView.swift) — Settings → Connected Sources (§5.2), now `@Query`-backed. `AddSourceView` is still a deliberate stub ("Coming Soon") — no Starling/Tesla setup UI exists yet.
- [`View+PlatformHelpers.swift`](../src/Ringet/Views/View+PlatformHelpers.swift) — shared `#if os(iOS)` wrappers for UIKit-only modifiers (see decision #5).
- [`PreviewSupport.swift`](../src/Ringet/PreviewSupport.swift) — shared in-memory SwiftData stack + sample-tracker factory, used by every view's `#Preview`.

## CloudKit — what happened and what's needed (READ BEFORE TRYING AGAIN)

**The user does not currently have a paid Apple Developer Program
membership** — Xcode is signed in with a free "Personal Team". This session
tried to enable CloudKit sync and hit Apple's own hard restriction:

> "Cannot create a Mac App Development provisioning profile for
> 'martinkearn.Ringet'. Personal development teams, including 'Martin
> Kearn', do not support the iCloud capability."

This matches the spec's own §10 ("Apple Developer Program ($99/year) —
required for... The iCloud/CloudKit capability"). **There is no workaround
— a personal team cannot use CloudKit at all, full stop.** Don't spend time
trying alternate entitlement configurations; the block is at the account
level, not the project level.

**Decision (confirmed with the user):** ship local-only persistence now.
Each device (the user's iPhone, iPad, Mac) will store its own trackers
independently with no sync between them, until the account is upgraded.
This is acceptable for testing the app's value on a single device with real
data before paying for the Program.

**What's already in place, ready to flip on:**
- [`Ringet.entitlements`](../src/Ringet/Ringet.entitlements) exists in the repo, declaring `iCloud.martinkearn.Ringet` + the CloudKit service — but it is **not** referenced by the Xcode project right now (no `CODE_SIGN_ENTITLEMENTS` build setting points to it), so it has zero effect on the current build.
- [`RingetApp.swift`](../src/Ringet/RingetApp.swift) has the CloudKit `ModelConfiguration(schema:cloudKitDatabase:.automatic)` path written out in a comment, directly above the local-only path that's actually active.

**To enable sync once the account is upgraded to the paid Program:**
1. Open the project in Xcode (not needed for anything else right now, but is needed for this).
2. Select the `Ringet` target → **Signing & Capabilities** → confirm the (now-paid) team is selected → **+ Capability** → add **iCloud** → check **CloudKit**. Let Xcode create/select the `iCloud.martinkearn.Ringet` container — this is the step that actually registers the capability with Apple's developer portal, and it has to happen through Xcode's own UI with the account signed in.
3. In `RingetApp.swift`, uncomment the `cloudConfiguration` block and delete/comment out the local-only fallback path (or leave the fallback in place as a defensive measure — it's harmless either way, since it only activates if the CloudKit container creation throws).
4. If Xcode didn't already add `CODE_SIGN_ENTITLEMENTS` for you in step 2, point it at `Ringet/Ringet.entitlements` (the file already has the right content).
5. Build and run on two of the user's own signed-in devices to confirm sync.

Don't attempt any of this without the user confirming the Program enrollment is done — re-adding the entitlement without it reproduces the exact build failure above.

## Key decisions worth knowing before you touch this again

1. **Manual Entry is not a "source" the user can multiply.** It's a single fixed choice (`TrackerStore.manualEntrySource`), separate from real external connections (`ConnectedSource` rows with `providerId != "manual"`, queried directly by views — currently always empty since no such provider exists). Settings → Connected Sources only ever lists those. This came from explicit user correction mid-build — the first draft modeled manual entry as an ordinary, user-creatable `ConnectedSource`, which was wrong.
2. **A manual tracker gets its own dedicated reading log automatically** — its `sourceTargetId` is just its own `id.uuidString`, and its readings live on `Tracker.readings` directly. There's no user-facing "which log" picker for manual entry.
3. **"Add New Source…" lives inside the tracker's Source picker**, pushing the same `AddSourceView` Settings uses — a shortcut so a user mid-way through creating a tracker doesn't have to back out to Settings first. This was click-verified as a menu item that renders correctly; the exact tap-through in the automated simulator tooling wasn't fully confirmed in an earlier pass, but the underlying `onChange` + `.navigationDestination(isPresented:)` pattern is standard and shared with the already-verified `ConnectedSourcesView → AddSourceView` path.
4. **Budget field wording**: "Allowance" → "Budget", "Total allowance" → "Total budget", with direction-aware inline hints and a footer worked example (e.g. a simple £3000 budget: starting value and total budget both 3000, then log your remaining balance over time). Fixed real confusion: `startingValue` is the *budget's own* starting point, not literally whatever a real bank account happens to read.
5. **Cross-platform build gotchas**: this project builds for iOS *and* macOS. `.keyboardType` and `.navigationBarTitleDisplayMode` are UIKit-only — wrapped in `View+PlatformHelpers.swift`'s `decimalKeyboardIfAvailable()`/`inlineNavigationBarIfAvailable()`. Watch for this with any new UIKit-only modifier.
6. **Xcode 16 file-system-synchronized groups**: no manually-maintained `.pbxproj` file lists — any `.swift` file dropped into `src/Ringet/` or `src/RingetTests/` is picked up automatically.
7. **`recurrence` field was removed from `Tracker`** (it was an unused `RecurrenceRule?` placeholder for §4.4). This happened mid-debugging a SwiftData crash (see #9) and was kept removed afterward rather than restored, since an unused field serves no purpose until §4.4 is actually designed. Re-add it properly (with real semantics) when that phase starts.
8. **Running `xcodebuild` in this environment**: the active `xcode-select` developer directory is Command Line Tools, not Xcode. Prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Simulator builds went through the `mcp__Claude_Code_iOS_Simulator__build` tool.
9. **A nasty SwiftData footgun, now fixed but worth remembering**: an in-memory `ModelContainer`'s backing store is tied to the container object's own lifetime — if you create a container, grab only its `.mainContext`, and let the container itself go out of scope, the context silently becomes unusable and **crashes on first `insert()`** (not on creation, not on fetch — specifically on insert). This cost significant debugging time because the crash reports were completely opaque ("Crash: Ringet at TestName()", no assertion message, no stack trace in the captured logs). The fix: always hold onto the `ModelContainer` itself for as long as you use its context — see [`TestSupport.swift`](../src/RingetTests/TestSupport.swift)'s `makeInMemoryModelContainer()`, which returns the container (not just `.mainContext`) for exactly this reason. If you ever see a bizarre, zero-detail "Crash" from a SwiftData-touching test again, check this first.

## Known gaps / things to verify by hand

- CloudKit sync — see dedicated section above. Not possible until the Apple Developer Program is paid for.
- §4.6 zoom levels (This year/This month/This week sub-period views) are not implemented — the dashboard always shows the tracker's full period.
- No SwiftUI view has automated UI tests — verification has been manual (simulator screenshots + interaction) plus unit tests on the non-UI layers (`TrackerPace`, `ManualEntryProvider`, `TrackerStore` — 23 tests, all passing). Consider `ViewInspector`-style tests or UI tests if this grows much further.
- Editing an existing tracker isn't built (only create, view, delete).

## Explicitly out of scope so far (per spec, deferred on purpose)

- §4.4 Recurrence, §4.5 multi-tracker source-sharing/dedup (only matters once a second provider exists), §4.6 zoom levels
- §5.3 Starling, §5.4 Tesla providers (only the manual provider exists)
- §7.2 macOS-specific UI (sidebar/menu bar), §7.3 watchOS, §8 widgets/Lock Screen — explicitly excluded by the user for this phase ("just focus on what happens when app is full screen")
- Editing an existing tracker

## Suggested next steps (not a commitment, just a sane order)

1. Get real usage on the user's own phone with real trackers/data (the reason this phase happened) — see **Verifying on a real device** below.
2. Once that's proven valuable: enroll in the Apple Developer Program and enable CloudKit sync (see dedicated section above).
3. Edit tracker (currently only create/view/delete exist).
4. §4.6 zoom levels, once a long-running tracker makes the full-period ring feel too static to be useful day-to-day.
5. A real source provider (Starling is the simplest per spec's own note in §5.3) — this is what actually exercises the multi-source parts of the Settings screen and the "Add New Source" flow for real.

## Verifying the app still builds and passes tests

```bash
cd src
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Ringet.xcodeproj -scheme Ringet -destination 'platform=macOS' \
  -only-testing:RingetTests test
```

23 tests should pass (`TrackerPaceTests`, `ManualEntryProviderTests`,
`TrackerStoreTests`, plus the two scaffold tests in `RingetTests`).

## Verifying on a real device

1. Plug in the iPhone/iPad/Mac, select it as the run destination in Xcode (or via `xcodebuild -destination`), and run. Automatic signing with the existing personal team should just work for on-device testing — that restriction is CloudKit-specific, not a general "personal teams can't run on real devices" limit.
2. Create a tracker, log a few readings over a couple of days, confirm the dashboard/rings/chart look right and data survives relaunch.
3. Repeat independently on a second device (e.g. the Mac) if desired — remember, no sync between them yet, so it's two separate data sets until CloudKit is enabled.
