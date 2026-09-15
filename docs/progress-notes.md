# Ringet — Progress Notes

Status snapshot for picking this work back up. Last updated 2026-09-14
(overnight session), after an autonomous pass that added the widget
extension, watch app, macOS parity, and Shortcuts/Siri integration — see
**Overnight platform expansion** below for that work; everything above it
predates that session. Read alongside
[ringet-build-spec.md](ringet-build-spec.md) — this file tracks *what's
actually been built*, not the spec itself.

**Scope note**: the overnight session was explicitly told to stay manual-entry
only — no Starling/Tesla work was done or attempted, despite the new
platform surfaces (widgets, watch, Shortcuts) being exactly the kind of thing
that would eventually want live provider data. Every new surface reads
`Tracker`/`ValueSnapshot` generically, so a future provider needs no changes
to widgets/watch/Shortcuts — they already work for whatever `actualValue`
resolves to.

## What's implemented

### §4.1 / §4.3 — Tracker model & pace calculations
- [`Tracker.swift`](../src/RingetShared/Models/Tracker.swift) — `Tracker`, a SwiftData `@Model` class (see **Persistence** below), and the `TrackerDirection` enum. Also holds `isCurrencyUnit` and `formattedValue(_:signed:)` — a currency symbol (£, $, €, …) is prefixed with no space ("£1,234.56"); any other unit is suffixed with a space ("1,234 miles"). The `recurrence` field (§4.4 placeholder) was removed — see decision #7.
- [`TrackerPace.swift`](../src/RingetShared/Models/TrackerPace.swift) — `Tracker.pace(actualValue:asOf:)` computing periodHours/hoursElapsed/consumedSoFar/expectedConsumedByNow/difference/target-right-now in one call, so a single snapshot of "now" stays consistent. `hoursElapsed` uses `timeIntervalSince` (wall-clock seconds), which is DST-safe by construction. Also defines `PaceStatus` (`.good`/`.warning`/`.bad`) — the traffic-light read of a tracker's pace — with `.color` (green/amber/red) and `.label(for tracker:)`, which switches to budget language ("Under Budget"/"At Budget"/"Over Budget") specifically for decreasing trackers denominated in currency, and stays neutral ("On Track"/"At Target"/"Needs Attention") otherwise. `.status` is `.warning` ("at") only on an **exact whole-number match** between current and target (pennies/cents don't count) — not a percentage tolerance band, per explicit feedback that a fuzzy "near" reading was confusing. `TrackerPace.displayDifference(for:)` is the one place that decides whether to show a signed value or drop the sign — see decision #4.
- Tests: [`TrackerPaceTests.swift`](../src/RingetTests/TrackerPaceTests.swift) — both directions, ahead/behind pace, period-start/end edges, one DST-transition regression test.

### §5.1 / §5.2 / §5.5 — Source provider abstraction & manual entry
- [`SourceProvider.swift`](../src/RingetShared/Providers/SourceProvider.swift) — the protocol, unchanged.
- [`SourceTarget.swift`](../src/RingetShared/Models/SourceTarget.swift) — still a plain (non-persisted) struct; a lightweight DTO for the provider protocol's API shape.
- [`ConnectedSource.swift`](../src/RingetShared/Models/ConnectedSource.swift), [`ValueSnapshot.swift`](../src/RingetShared/Models/ValueSnapshot.swift) — SwiftData `@Model` classes. `ConnectedSource.trackers` is the CloudKit-required inverse of `Tracker.connectedSource` — see decision #10, this one cost real debugging time.
- [`ManualEntryProvider.swift`](../src/RingetShared/Providers/ManualEntryProvider.swift) — a `@MainActor` class holding a `ModelContext`; `fetchCurrentValue`/`logManualReading` resolve a target's id back to a `Tracker` (`sourceTargetId == tracker.id.uuidString`) and read/write `tracker.readings` directly. In practice, app code that already holds the `Tracker` (the dashboard, the log-reading sheet) bypasses this indirection and uses `TrackerStore.logReading`/`tracker.latestReading` directly — this provider mainly exists so the abstraction has a real implementation ahead of Starling/Tesla.
- No Starling or Tesla provider exists yet.

### §6 — Persistence, now with CloudKit sync enabled
- [`RingetApp.swift`](../src/Ringet/RingetApp.swift) — builds a `ModelContainer` for `[Tracker, ConnectedSource, ValueSnapshot]` using `ModelConfiguration(schema:cloudKitDatabase:.automatic)`, with a local-only `ModelConfiguration` as a defensive fallback (only kicks in if CloudKit container creation throws — e.g. no iCloud account signed in). **This is live now**: the user's Apple Developer Program enrollment went from "Pending" to active partway through this session, and re-enabling CloudKit surfaced (and fixed) a real schema bug — see decision #10.
- [`Ringet.entitlements`](../src/Ringet/Ringet.entitlements) declares `iCloud.martinkearn.Ringet` + the CloudKit service + `aps-environment` (needed for CloudKit's push-based sync — see **CloudKit** below), and is wired in as the `Ringet` target's `CODE_SIGN_ENTITLEMENTS` build setting (Debug and Release, main app target only — not the test targets).
- [`TrackerStore.swift`](../src/RingetShared/State/TrackerStore.swift) — a thin `@Observable` wrapper around a `ModelContext`: owns `manualEntrySource` (fetched-or-created once) and the `manualProvider`, and exposes `addTracker`/`deleteTracker`/`logReading`/`saveChanges` actions (`saveChanges` flushes in-place edits from `AddTrackerView`'s edit mode). Tracker/source **lists** are not held here — views read them via `@Query` directly (idiomatic SwiftData/SwiftUI, auto-updating).
- **Confirmed working this session, including real cross-device sync**: created a tracker with CloudKit enabled, force-quit the app, relaunched — still there. Then signed the Simulator into the user's real iCloud account and saw their actual real-device tracker ("Dublin Pocket Money") appear in the Simulator via CloudKit sync — this is real end-to-end confirmation, not just local-disk persistence. See **CloudKit** below for the capabilities that had to be added to get here.

### §7.1 — Screens (iOS full-screen; see **Overnight platform expansion** below for widgets/Lock Screen/watch/macOS)
- [`TrackerListView.swift`](../src/Ringet/Views/TrackerListView.swift) — `@Query`-backed list, empty state, swipe-to-delete, "+" as the primary toolbar action, gear icon (secondary) opening Connected Sources. Each row shows a small `RingsView` pace indicator plus the **difference from target** (via `TrackerPace.displayDifference(for:)`, colored per `PaceStatus`) as the subtitle — not the unit/direction text that used to be there, per explicit user feedback that the difference is the number that matters at a glance.
- [`AddTrackerView.swift`](../src/Ringet/Views/AddTrackerView.swift) — now doubles as the **edit** screen: pass `existingTracker:` and it prefills every field (including detecting whether the tracker already has a specific time-of-day set) and mutates in place via `store.saveChanges()` on save, rather than creating a new `Tracker`. A tracker's source can't be changed after creation — the edit form shows it read-only. Also has:
  - **Unit is picked from a fixed set of pills only** (£, $, €, mi, km, kg) — no free-text entry. This was quick-pick chips alongside a text field earlier; per feedback it's now the *only* way to set the unit, so every currency/formatting check downstream can rely on an exact string match.
  - **"Set specific times" toggle** for the period's Start/End — off by default (midnight-to-midnight), on to reveal `.hourAndMinute` pickers. Whichever mode is used, `startDate`/`endDate` are normalized to midnight on save if the toggle is off, so a tracker never silently inherits whatever time-of-day the form happened to be opened at.
  - Robust decimal parsing (`parseDecimal`, locale-aware via `NumberFormatter` before falling back to `Decimal(string:)`) for the Starting value/Total budget fields — see decision #11, a real data-corruption bug this fixes.
  - An hourly pace estimate, joined by a **daily** one once the period runs longer than 24 hours (`dailyPaceDescription`).
  - A **remaining-at-end** projection (`Tracker.projectedRemainder`) shown whenever starting value and total budget differ — e.g. "£600 will remain at the end of the tracker" for a decreasing tracker, or a warning if the budget exceeds the starting value. Decreasing trackers only — see decision #14 on why increasing trackers don't have an equivalent "remaining" concept.
  - Verified a 1-minute-long tracker (Start/End 1 minute apart via the times toggle) doesn't crash — the hourly-rate math degrades to a very large but finite number, and the daily line correctly stays hidden.
- [`TrackerDetailView.swift`](../src/Ringet/Views/TrackerDetailView.swift) — the tracker dashboard. Two-ring visual with the **difference-from-target as its centerpiece** (large, bold, colored, inside the rings), a `PaceStatus`-driven status word above it (e.g. "OVER BUDGET BY £8.00" for budget trackers — no sign, see decision #4), a trend chart once ≥2 readings exist, and a "…" menu with **Edit Tracker**, **Update History** (manual trackers only — see `ReadingHistoryView` below), and Delete (confirmation first). Below the rings, **Current Balance/Current and Target Right Now are two visually separate cards**, not a shared row — they're different things updated in different ways, and the "Update" button (a capsule, `.controlSize(.large)`, plus-icon — reads as a proper button per Apple HIG, not the cramped two-line label it was before) lives inside the Current Balance card specifically, since that's the only figure it changes. The "Current Balance" vs. "Current" title comes from `Tracker.currentValueLabel` (currency vs. not). Pace figures refresh once a minute (`minuteTimer`); a `secondTimer`-driven "Updates in Xs" caption sits at the **top of the screen**, under the nav title — it reflects the whole screen's live figures (the ring, the difference, Target Right Now), not just one card, so it doesn't belong tucked under a single figure. That countdown's baseline is set in `.onAppear`, not a default `@State` value — see decision #12. A subtle remaining-at-end caption sits under the days-remaining text (same projection as the add/edit form, see above).
- [`ReadingHistoryView.swift`](../src/Ringet/Views/ReadingHistoryView.swift) — **new**: lists every logged update for a manual tracker, newest first, tap to edit (via `LogReadingView`'s edit mode) or swipe/Edit-mode to delete. Reachable only for `tracker.isManualEntry` trackers — a real provider's history should reflect what it actually reported, not something hand-edited.
- [`RingsView.swift`](../src/RingetShared/RingsView.swift) — the two-ring visual itself (§3.4) — outer neutral-gray pace ring (elapsed-time fraction), inner ring colored per `PaceStatus` (green/amber/red — true traffic-light semantics, not just a green/red binary). Bigger by default (used at 260pt in the dashboard) with the difference figure and a legend as center content; `showsCenterContent: false` gives the bare rings for small uses like the list-row indicator. The legend uses the exact same wording as the figure cards below it ("Current Balance"/"Target Right Now"), in the same left-to-right order — not a separately-worded "Progress"/"Time elapsed" pair the reader had to map onto the figures themselves. Uses a `GeometryReader` to constrain the center text's width so long values shrink to fit rather than overflowing past the ring.
- [`TrendChartView.swift`](../src/Ringet/Views/TrendChartView.swift) — Swift Charts line (§3.5) — a straight gray pace-reference line from start to end, actual logged readings plotted in blue on top.
- [`LogReadingView.swift`](../src/Ringet/Views/LogReadingView.swift) — the §5.5 value-entry sheet ("Update Current Value" when creating, "Edit Update" when editing an existing one via `existingReading:`, with a Delete action alongside Save). A large, centered numeric input with the unit as a prefix/suffix label replaces the old small trailing-aligned field — bigger, easier to tap, and the whole row focuses it. Uses the same robust decimal parsing as `AddTrackerView`.
- [`ConnectedSourcesView.swift`](../src/Ringet/Views/ConnectedSourcesView.swift) + [`AddSourceView.swift`](../src/Ringet/Views/AddSourceView.swift) — Settings → Connected Sources (§5.2), `@Query`-backed. `AddSourceView` is still a deliberate stub ("Coming Soon") — no Starling/Tesla setup UI exists yet.
- [`View+PlatformHelpers.swift`](../src/Ringet/Views/View+PlatformHelpers.swift) — shared `#if os(iOS)` wrappers for UIKit-only modifiers (see decision #5).
- [`PreviewSupport.swift`](../src/Ringet/PreviewSupport.swift) — shared in-memory SwiftData stack + sample-tracker factory, used by every view's `#Preview`.

## CloudKit — enabled and confirmed working (read this before touching it again)

The user's Apple Developer Program enrollment went from "Pending" to fully
active during this session. Getting sync fully working took three separate
fixes, in order — if CloudKit ever seems broken again, check these before
assuming it's a new problem:

1. **A latent schema bug**: `Tracker.connectedSource` had no declared inverse relationship. Worked fine locally, crashed on launch the instant CloudKit was turned on. See decision #10.
2. **Capabilities beyond just "iCloud"**: Apple's provisioning validation also required **Push Notifications** (+ `aps-environment` entitlement) and **Background Modes → Remote notifications** (which needed a real `Info.plist` with `UIBackgroundModes`, since CloudKit relies on silent push to detect remote changes). All three capabilities had to be added through Xcode's own Signing & Capabilities UI — that's what actually registers them against the App ID on Apple's developer portal; hand-editing the entitlements file and `project.pbxproj` directly (which is as far as this session's tooling could go on its own) is not enough on its own for a **new** capability, though it did work for re-adding one already registered.
3. Even after both of those, the App ID's capabilities took a short while to propagate — the exact error was *"The capability associated with 'ICLOUD' could not be determined"* alongside *"Provisioning profile ... doesn't include the iCloud capability"*. Re-adding Push Notifications + Background Modes and clicking "Try Again" in Xcode cleared it.

**Current setup:**
- `RingetApp.swift` uses `cloudKitDatabase: .automatic`, with a local-only fallback that only activates if the CloudKit `ModelContainer` fails to initialize.
- `Ringet.entitlements` declares the iCloud container, CloudKit service, and `aps-environment`; `Info.plist` declares `UIBackgroundModes: [remote-notification, processing, fetch]`. Both are wired into the main app target's build settings (Debug and Release).
- The container id is `iCloud.martinkearn.Ringet`.

**Confirmed working, end to end**: with the Simulator signed into the user's real iCloud account (Settings app inside the Simulator, same Apple ID as their real device), the user's actual real-device tracker synced down and appeared in the Simulator. This is real cross-device sync, not just local persistence — the main open question from earlier in this session is resolved.

**Update from the overnight session**: the note below about macOS needing a
one-time Xcode GUI device-registration step no longer applies — building for
`platform=macOS` with `-allowProvisioningUpdates` now succeeds directly from
the command line (this Mac must have gotten registered at some point between
sessions). Still, prefer the iOS Simulator destination for routine test runs
(faster, no signing involved at all).

## Key decisions worth knowing before you touch this again

1. **Manual Entry is not a "source" the user can multiply.** It's a single fixed choice (`TrackerStore.manualEntrySource`), separate from real external connections (`ConnectedSource` rows with `providerId != "manual"`, queried directly by views — currently always empty since no such provider exists). Settings → Connected Sources only ever lists those. This came from explicit user correction mid-build — the first draft modeled manual entry as an ordinary, user-creatable `ConnectedSource`, which was wrong.
2. **A manual tracker gets its own dedicated reading log automatically** — its `sourceTargetId` is just its own `id.uuidString`, and its readings live on `Tracker.readings` directly. There's no user-facing "which log" picker for manual entry.
3. **"Add New Source…" lives inside the tracker's Source picker**, pushing the same `AddSourceView` Settings uses — a shortcut so a user mid-way through creating a tracker doesn't have to back out to Settings first.
4. **Wording is deliberately non-judgmental and traffic-light-coded.** "Ahead of pace"/"Behind pace" read as a race, and didn't distinguish "good" from "bad" clearly enough — replaced with `PaceStatus` (good/warning/bad → green/amber/red), with budget-specific wording ("Under Budget"/"At Budget"/"Over Budget") for decreasing currency trackers specifically, since that's the case where the good/bad framing is clearest. Over/under amounts drop their +/- sign and read as "Over Budget by £8.00" instead — the color and word already say the direction, so a sign on top is redundant, not clarifying (generic non-budget wording keeps its sign, since there's no natural "by" phrasing without reintroducing race language). "Log a Reading" became "Update Current Value" — the old wording didn't read naturally for a manual-entry balance update. "Target today" became "Target Right Now" since the figure is live to the minute, not daily.
5. **Cross-platform build gotchas**: this project builds for iOS *and* macOS. `.keyboardType` and `.navigationBarTitleDisplayMode` are UIKit-only — wrapped in `View+PlatformHelpers.swift`'s `decimalKeyboardIfAvailable()`/`inlineNavigationBarIfAvailable()`. Watch for this with any new UIKit-only modifier. Also avoid UIKit-only `Color` initializers like `Color(.secondarySystemFill)` — use cross-platform equivalents (e.g. `Color.secondary.opacity(...)`).
6. **Xcode 16 file-system-synchronized groups**: no manually-maintained `.pbxproj` file lists — any `.swift` file dropped into `src/Ringet/` or `src/RingetTests/` is picked up automatically.
7. **`recurrence` field was removed from `Tracker`** (it was an unused `RecurrenceRule?` placeholder for §4.4). Re-add it properly (with real semantics) when that phase starts.
8. **Running `xcodebuild` in this environment**: the active `xcode-select` developer directory is Command Line Tools, not Xcode. Prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
9. **A nasty SwiftData footgun**: an in-memory `ModelContainer`'s backing store is tied to the container object's own lifetime — if you create a container, grab only its `.mainContext`, and let the container itself go out of scope, the context silently becomes unusable and **crashes on first `insert()`**. Always hold onto the `ModelContainer` itself for as long as you use its context — see [`TestSupport.swift`](../src/RingetTests/TestSupport.swift)'s `makeInMemoryModelContainer()`.
10. **CloudKit requires every relationship to declare an inverse, on both sides of the model, or the app crashes on launch with an opaque Core Data error** ("CloudKit integration requires that all relationships have an inverse, the following do not: Tracker: connectedSource"). `Tracker.connectedSource` had no inverse declared on `ConnectedSource` — it worked fine locally (SwiftData doesn't enforce this for local-only stores) but broke the instant CloudKit was turned back on. Fixed by adding `@Relationship(inverse: \Tracker.connectedSource) var trackers: [Tracker]? = []` to `ConnectedSource`. **If you add any new relationship to a `@Model` type, check this immediately** — it won't show up in local testing, only once CloudKit is active, and the crash message doesn't point at the fix very clearly.
11. **`Decimal(string:)` silently truncates at a grouping separator instead of failing.** `Decimal(string: "3,000")` does **not** return `nil` — it parses `"3"` and stops at the comma, corrupting the value by 1000x. This bit us for real: prefilling the edit form with `.formatted(.number...)` (which adds thousands separators, e.g. "3,000") round-tripped through this on save and silently turned a £3,000 budget into £3. Fixed two ways: (a) prefill text fields with `.formatted(.number.grouping(.never)...)` so there's no separator to round-trip in the first place, and (b) added a `parseDecimal` helper (locale-aware `NumberFormatter` first, falling back to `Decimal(string:)`) used everywhere a user-typed or pasted decimal is parsed, as defense in depth. **Never use bare `Decimal(string:)` on text that might contain a thousands separator** — check `isValid`/`save()` in `AddTrackerView.swift` and `LogReadingView.swift` for the pattern to copy.
12. **A `@State` default value can initialize before a screen is actually visible.** The dashboard's countdown baseline (`nextUpdateAt = Date.now.addingTimeInterval(60)`) was originally a default `@State` value — but SwiftUI can construct a view struct (and its `@State` defaults) before the screen is actually shown, e.g. `NavigationLink` destinations are sometimes built ahead of the tap. This made the countdown sometimes start already at "0s". Fixed by setting the real baseline in `.onAppear` instead of a property default. **Any "starts a timer relative to now" state needs to be set in `.onAppear`/`.task`, never a property default**, or it can silently measure from the wrong "now".
13. **An installed Simulator app can be stale in a way that's easy to misdiagnose as a logic bug.** `xcrun simctl boot`/`launch` do not reinstall — if an `install` step fails silently (e.g. the Simulator had shut down) and you don't check its exit code, a later `launch` will happily relaunch the **old** binary with no error. This looked exactly like a code bug (one screen showed a fix, another screen — same tracker, same running process — didn't) until re-installing fixed it. **After any `simctl install`, check its actual exit code before trusting what you see on screen**; a `boot`+`launch`-only sequence with no accompanying `install` is a red flag if you've rebuilt since the app was last installed.
14. **"Increasing" trackers model a cap/allowance, not an open-ended goal.** Tested this explicitly: for an increasing tracker (e.g. mileage lease), "good"/green means the current value is *at or under* the pace target — using less of the allowance than expected is the good outcome, same direction as a decreasing budget tracker being under-spent. This means an increasing tracker is a poor fit for something like a "savings goal" where *exceeding* the target would intuitively be the good outcome — the app doesn't support that framing today. Worth knowing before suggesting increasing trackers for goal-type use cases; §4.4/future work would need a distinct "goal" mode for that, not just direction=increasing.
15. **Simulator tap coordinates must be in device points (e.g. 402×874 for this iPhone 17 Pro), not screenshot pixels.** A screenshot comes back at the device's native pixel resolution (3x the point size), and it's easy to eyeball a coordinate straight off the image and pass it through unscaled — anything over ~400 in x or ~874 in y is out of bounds and the tap silently lands nowhere (no error). When a tap has no visible effect, check the coordinate is within the reported point bounds before assuming a UI bug.
16. **Terminology must match exactly between the action and the record of it.** The button is "Update" (not "Log a Reading"), so every place its results are described needs the same word — "Update History" not "Reading History", "Edit Update"/"Delete Update" not "Edit/Delete Reading". Caught via direct user feedback after shipping "Reading History" first; a naming pass should check *all* user-facing strings tied to a renamed action, not just the button itself.

## Known gaps / things to verify by hand

- §4.6 zoom levels (This year/This month/This week sub-period views) are not implemented — the dashboard always shows the tracker's full period.
- No SwiftUI view has automated UI tests — verification has been manual (simulator screenshots + interaction) plus unit tests on the non-UI layers (`TrackerPace`, `ManualEntryProvider`, `TrackerStore` — 23 tests, all passing). Consider `ViewInspector`-style tests or UI tests if this grows much further.
- ~~This Mac isn't yet registered as a device on the paid developer account~~ — resolved during the overnight session: `-allowProvisioningUpdates` now generates a working Mac profile from the command line with no Xcode GUI step needed (see **Overnight platform expansion**).
- An increasing tracker can't model an open-ended "goal to exceed" (e.g. a savings goal) — see decision #14. Only tested as a cap/allowance (mileage-lease-style), which is what the current pace math supports.
- The Budget section's example/footer text in `AddTrackerView` is written for the mileage-lease example on increasing trackers regardless of the unit actually chosen (it doesn't adapt to a currency unit) — minor, cosmetic, not fixed this session.

## Explicitly out of scope so far (per spec, deferred on purpose)

- §4.4 Recurrence, §4.5 multi-tracker source-sharing/dedup (only matters once a second provider exists), §4.6 zoom levels
- §5.3 Starling, §5.4 Tesla providers (only the manual provider exists) — explicitly kept out of scope for the overnight session too, by direct instruction
- Live Activities / Dynamic Island — considered during the overnight session and deliberately skipped; see **Overnight platform expansion** for why

## Suggested next steps (not a commitment, just a sane order)

1. §4.6 zoom levels, once a long-running tracker makes the full-period ring feel too static to be useful day-to-day.
2. A real source provider (Starling is the simplest per spec's own note in §5.3) — this is what actually exercises the multi-source parts of the Settings screen and the "Add New Source" flow for real, and is also what would make the widget/watch/Shortcuts refresh cadence choices (hourly, once-a-day, on-demand) actually matter.
3. If a goal-type tracker (exceed-the-target framing, e.g. savings) turns out to matter, it needs new semantics distinct from "increasing" — see decision #14.
4. See **Overnight platform expansion**'s own "Suggested next steps" for widget/watch/macOS-specific follow-ups.

## Verifying the app still builds and passes tests

Use the iOS Simulator destination:

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
3. If testing sync, repeat on a second device signed into the same Apple ID — confirmed working this session between a real device and the Simulator, see the **CloudKit** section above.
4. **A free/personal Apple ID team install expires after ~7 days** and needs re-signing from Xcode; this doesn't apply anymore now the account is on the paid Program, but is worth knowing if a personal team is ever used again for a quick test.

## Overnight platform expansion (2026-09-14)

An autonomous overnight session took the app from "iPhone app, full-screen
only" to widgets, a watch app, and macOS parity — all still manual-entry
only, per explicit instruction (no Starling/Tesla work). Functionality over
visual polish throughout, per the session's own brief; none of this has had
a design pass.

### New targets

- **RingetWidgets** (`src/RingetWidgets/`) — a WidgetKit extension, embedded
  in the iOS app's `PlugIns/`. One `AppIntentConfiguration`-based `Widget`
  covers Home Screen small/medium/large and Lock Screen
  circular/rectangular/inline (iOS only — WidgetKit's accessory families
  don't exist on macOS, see below). Each widget instance is independently
  configurable to a tracker via a `WidgetConfigurationIntent` +
  `TrackerEntity`/`TrackerEntityQuery` (App Intents), so two widgets can show
  two different trackers side by side. `WidgetDataStore` opens its own
  `ModelContainer` against the same CloudKit container on every timeline
  refresh (no App Group needed — see **Architecture** below) and refreshes
  hourly. Reuses `RingsView` directly rather than a bespoke widget visual.
- **RingetWatch** (`src/RingetWatch/`) — a single-target watchOS companion
  app, embedded in the iOS app via the classic "Embed Watch Content" phase.
  A tracker list, a detail screen (`RingsView` again, at watch size), and a
  "Log" action for manual trackers — promoted from the spec's §7.3 "stretch
  goal" to a real feature, since manual entry is the only provider in scope.
  Talks to its own `ModelContainer`/CloudKit container independently of the
  phone being nearby.
- No separate widget/complication target for the watch was attempted —
  watchOS complications are WidgetKit widgets too (since watchOS 9), but
  they'd need their own extension embedded *inside* `RingetWatch`, which is
  a second round of the same target-surgery done for `RingetWidgets` above.
  Deferred — see "Suggested next steps" below.

### Architecture: RingetShared

The model/pace layer and a few view/store pieces were moved into a new
`src/RingetShared/` folder, compiled directly into the app, widget
extension, and watch app targets (via a `PBXFileSystemSynchronizedRootGroup`
listed under all three targets — see **Tooling gotchas** below for what that
actually means and why it needed scripting rather than Xcode's GUI):

- `Models/` — `Tracker`, `ConnectedSource`, `ValueSnapshot`, `TrackerPace`, `SourceTarget` (moved from `src/Ringet/Models/`)
- `Providers/` — `SourceProvider`, `ManualEntryProvider` (moved from `src/Ringet/Providers/`)
- `State/TrackerStore.swift` (moved from `src/Ringet/State/`)
- `RingsView.swift` (moved from `src/Ringet/Views/`) — the two-ring visual, reused verbatim by the widget and watch app
- `RingetColors.swift` — extracted out of `RingsView.swift` (it used to be a private-ish enum at the bottom of that file) since widgets/watch need it independently; also gained `Color.widgetBackground`, a cross-platform stand-in for `UIColor.systemBackground` (no macOS/watchOS equivalent)
- `SharedPreviewData.swift` — a `TrackerStore`-free preview fixture for shared views, since the app's own `PreviewData` (in `src/Ringet/PreviewSupport.swift`) pulls in `TrackerStore`, which shared views shouldn't need just to render a preview

**No App Group was needed anywhere.** Widgets and the watch app don't share
a local store with the phone app — each opens its own `ModelContainer`
against the same `iCloud.martinkearn.Ringet` CloudKit container (Apple's
recommended pattern for widgets reading SwiftData+CloudKit data), and
CloudKit sync is what keeps them consistent, not a shared on-disk file. This
was flagged as a possible blocking need in the pre-flight check and turned
out not to be one.

**Shortcuts/Siri** (`src/Ringet/Intents/`) lives in the main app target, not
`RingetShared` — `LogReadingIntent` (manual trackers only) and
`ViewTrackerStatusIntent` (read-only), registered via `RingetShortcuts:
AppShortcutsProvider`. Each opens its own `ModelContainer`
(`IntentDataStore`) for the same reason widgets do: Shortcuts/Siri can
invoke an intent while the app isn't running. Has its own
`TrackerEntity`/`TrackerEntityQuery` rather than reusing the widget
extension's — App Intents entities aren't shared across extension/module
boundaries, each target needs its own.

### macOS parity pass

- `MacRootView.swift` — `NavigationSplitView` sidebar + detail (§7.2),
  reusing `TrackerDetailView` verbatim in the detail pane. `ContentView`
  branches on `#if os(macOS)` between this and the iOS `TrackerListView`.
- A `MenuBarExtra` in `RingetApp.swift` (macOS only) — `MenuBarStatusView`/
  `MenuBarStatusLabel` show one tracker's ahead/behind figure and a small
  dropdown of its key numbers. Shows the most-recently-started tracker
  (simplest of the two options §7.2 leaves to the build's judgment — a
  submenu for multiple trackers is easy to add later if a single pinned
  tracker turns out not to be enough).
- Two real, pre-existing macOS build breaks fixed along the way (not new
  code from tonight, just never previously exercised since macOS hadn't
  been built with these targets before): `EditButton()` in
  `ReadingHistoryView` is iOS-only, guarded with `#if !os(macOS)`; and
  WidgetKit's accessory widget families (`.accessoryCircular/Rectangular/
  Inline` — Lock Screen only) don't exist on macOS at all, so both the
  widget's `.supportedFamilies` list and its entry view's family switch are
  platform-gated.
- **`-allowProvisioningUpdates` now succeeds for macOS from the command
  line** — see the updated CloudKit section above; this had previously
  looked like an Xcode-GUI-only fix.
- Not attempted: a macOS Dock icon badge for "any tracker behind pace", and
  a cross-app-crossing-pace notification (§7.2's last two bullets) — both
  small, but neither is load-bearing and both can be added later without
  touching anything else.

### Live Activities — deliberately not built

Explicitly requested for exploration tonight, and explicitly out of scope
in the build spec (§9) before that. Judgment call: skipped. Live Activities
are designed for short, bounded events (a ride, a delivery, a sports game)
with a clear start/end shown continuously on the Lock Screen/Dynamic Island
for that duration — a Ringet tracker runs for days, weeks, or months, so
"start a Live Activity when the tracker starts" would mean asking the Lock
Screen to hold a Live Activity open for the entire period, which isn't what
the API is for and would likely get the activity silently ended early by
the system. A *narrow* version — surfacing one only in the tracker's final
24 hours, similar to the existing "Updates in Xs" countdown but system-level
— could be worth it later, but that's a distinct, smaller feature, not
"add Live Activities" as asked; flagging the reasoning rather than either
silently skipping it or building something that doesn't fit the API.

### Tooling gotchas hit tonight (read before touching the `.xcodeproj` again)

17. **This project has no Xcode-GUI access in this environment**, and its `.xcodeproj` uses the newer `PBXFileSystemSynchronizedRootGroup` format (see decision #6) that most third-party Xcode-project tooling doesn't understand. The `xcodeproj` Ruby gem (v1.28.1, installed via `gem install --user-install xcodeproj` — also needed `CFPropertyList -v 3.0.9` pinned for this machine's Ruby 2.6) turned out to round-trip this format losslessly (verified by opening-and-resaving with zero changes before trusting it with anything real) and was used for every target/scheme change tonight. The scripts are kept in `scripts/*.rb` for reference, not because they need running again.
18. **A `PBXFileSystemSynchronizedRootGroup` can be listed under more than one target's `fileSystemSynchronizedGroups`** — that's how `RingetShared` ends up compiled into three different targets/modules without three copies of the files on disk, and without a separate framework target. Each target gets its own independently-compiled copy of the same source (not a shared binary) — fine for a folder this small.
19. **`xcodebuild -destination` could not discover *any* watchOS simulator destination** for `RingetWatch`, even a booted, paired one, and even after adding a real shared `.xcscheme` (autocreated schemes aren't enough for `xcodebuild` to resolve watchOS destinations reliably when the project has never been opened in Xcode.app itself). Building the target directly bypasses this: `xcodebuild -target RingetWatch -sdk watchsimulator build`. **Caveat**: `-sdk <sdk>` on the command line force-overrides `SDKROOT` for *every* target in the build graph, including dependencies with their own different `SDKROOT` — this silently corrupted `RingetWatch`'s generated `Info.plist` (wrong `UIDeviceFamily`) when building `-target Ringet -sdk iphonesimulator` (which also builds the embedded `RingetWatch` dependency). The scheme+`-destination` route doesn't have this problem, once the matching simulator runtime is installed — see #20.
20. **A scheme containing an embedded watch app refuses to `build` (not just run) unless a simulator runtime matching the *SDK* version is installed** — not the app's `WATCHOS_DEPLOYMENT_TARGET`. This machine had watchOS SDK 26.5 but only runtimes up to 26.4 installed, so `xcodebuild -scheme Ringet -destination 'platform=iOS Simulator,...' build` failed with *"This scheme builds an embedded Apple Watch app. watchOS 26.5 must be installed"* even though the watch target's own deployment target was set to 26.4. Fixed by running `xcodebuild -downloadPlatform watchOS` (network access confirmed available; ran in the background for the rest of the session). Building for **macOS** never hit this at all, since RingetWatch is correctly excluded there — see #21.
21. **A macOS build fails outright if it embeds a watchOS binary** — "This target is built for macOS but contains embedded content (RingetWatch.app) built for watchOS, which is not allowed." Fixed with Xcode's **platform filter** mechanism (`platform_filters = ['ios']` via the `xcodeproj` gem) on *both* the `PBXTargetDependency` and the `PBXBuildFile` inside the "Embed Watch Content" copy-files phase — this is exactly what Xcode's own multiplatform-target wizard sets up, just applied by script instead.
22. **A single-target watchOS app's generated `Info.plist` needs `UIDeviceFamily: [4]` explicitly** — `GENERATE_INFOPLIST_FILE = YES` did not reliably infer it from `TARGETED_DEVICE_FAMILY = 4` in this setup, and the Simulator's install step fails with a clear ("WatchKit 2.0 app's UIDeviceFamily key does not specify...") but easy-to-miss error if it's wrong. Set directly in `RingetWatch/Info.plist` rather than relying on the generated-plist inference. **This was also a false alarm once**: building via `-target Ringet -sdk iphonesimulator` (rather than `-scheme`+`-destination`) forces `SDKROOT` onto every target in the graph including `RingetWatch`, which regenerates its `Info.plist` as if it were an iOS target (`UIDeviceFamily: [1,2]`) even though the key is correctly set in source — the proper `-scheme`/`-destination` build produces `[4]` correctly. Don't diagnose an `Info.plist` problem from a `-target`/`-sdk` build; use the scheme.
23. **`xcodebuild -downloadPlatform watchOS` can report success while installing a runtime that's already present**, failing with *"Duplicate of \<uuid\>"* right at the end — harmless (the already-installed copy, found via `xcrun simctl runtime list`, is what matters; `simctl list runtimes` can lag behind `simctl runtime list` immediately after an install, don't trust the former alone). Clean up the failed duplicate with `xcrun simctl runtime delete <uuid>`. Also: simulator **pairing is one-to-one** (a watch already paired to one phone must be `simctl unpair`'d before pairing it to another), and a paired phone+watch must be **within the same OS cycle** the app's deployment targets require — installing a 26.5-deployment-target app onto a paired-but-26.4 iPhone Simulator fails outright ("Requires a Newer Version of iOS"), so the phone and watch simulators in a pair need OS versions that satisfy the app's actual deployment targets, not just any pairing that happens to exist already.
24. **Adding an explicit shared `.xcscheme` for even one target disables Xcode's scheme autocreation for the *whole* project** (it only runs when a project has zero explicit schemes) — adding `RingetWidgets.xcscheme`/`RingetWatch.xcscheme` silently made the `Ringet` app scheme vanish from both `xcodebuild -list` and Xcode's own scheme picker. Fixed by explicitly writing a `Ringet.xcscheme` too (`scripts/add_ringet_scheme.rb`). **Anyone adding a new target's scheme by hand to this project should add/verify all schemes at the same time**, not just the new one.
25. **A widget's App Intents entity query (the "choose a tracker" configuration picker) can flash "Loading" and silently revert to empty with zero error UI**, and the cause is *not necessarily* a permissions/capability problem even though it looks exactly like one. Confirmed via `xcrun simctl spawn <udid> log stream --predicate 'process == "RingetWidgets"'` (essential technique — this is the only way to see what a widget extension is actually doing, since there's no on-screen error surface): the widget's `ModelContainer` opened successfully with no thrown error, but its first-ever CloudKit history import into that fresh sandboxed container (a `CKModifyRecordZonesOperation`/`CKModifySubscriptionsOperation` pair, visible in the log under the `CloudKit` subsystem) hadn't completed yet when the fetch ran — so it legitimately saw zero rows even though the data already existed in iCloud. Fixed with a bounded retry (`WidgetDataStore.fetchAllTrackers()`, up to 8 attempts / 0.5s apart) rather than accepting the first empty result — a one-time cost per extension process since the container itself is cached. **Don't assume "empty result, no visible error" in a widget/extension means a missing capability — check the actual log stream before guessing**, and know that a fresh CloudKit-backed `ModelContainer`'s first fetch can race its own initial import.

### What was verified tonight (and how)

- **iOS**: `xcodebuild -scheme Ringet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` and `test` both succeed (23/23 tests). The built `Ringet.app` — with `RingetWidgets.appex` in `PlugIns/` and `RingetWatch.app` in `Watch/`, both correctly signed — was installed and launched on that simulator, showing the real CloudKit-synced "Dublin Pocket Money" tracker untouched. `RingetWatch.app` extracted from that same build and installed standalone onto a paired Apple Watch Series 11 (46mm) simulator (watchOS 26.5) launches correctly and shows the expected "No Trackers" empty state (that simulator isn't signed into the same iCloud account). The widget was confirmed registered with the system (found via the Home Screen's "Add Widget" search).
- **macOS**: `xcodebuild -scheme Ringet -destination 'platform=macOS' -allowProvisioningUpdates build` succeeds, with `RingetWidgets` embedded and `RingetWatch` correctly excluded.
- **Not verified live**: actually placing a widget on the Home Screen and screenshotting its rendered output (the on-simulator widget-gallery flow is fiddly to drive via coordinate taps and was only partially completed — the widget's presence in the system was confirmed, its final rendered appearance wasn't screenshotted); the macOS app's actual window/menu bar item on screen (no macOS GUI-automation tool is available in this environment — `osascript`/`screencapture` both require a permission prompt only a human can grant, so this is a real environment limitation, not a skipped step); the real phone→watch companion auto-install via Simulator pairing (Simulator's `simctl pair` doesn't replicate the full WatchConnectivity install-push a real device or an Xcode-driven combined run destination does — installing the extracted watch app directly, as done above, is the workaround and is what's actually been verified).

### Suggested next steps (widget/watch/macOS-specific)

1. A real watch complication (a second WidgetKit extension embedded inside `RingetWatch`, using the same accessory families as the Lock Screen widgets) — the natural next step now the plumbing for #17–21 above is understood.
2. A macOS Dock badge + cross-pace notification (§7.2's last two bullets) — small, deferred, not started.
3. A first real design pass — this was explicitly functionality-first tonight, and the "not verified live" gaps above (actual widget rendering on a Home Screen, the macOS window) are exactly where a design pass would want to start looking.
4. `EditButton()`-equivalent delete-by-swipe on macOS's `ReadingHistoryView` list currently has no visible affordance (macOS `List` supports `.onDelete` via a selected row + Delete key, but the list has no `selection:` binding yet) — small follow-up.

## Follow-up feedback round (2026-09-15)

A batch of feedback after trying the widget/watch/macOS work above:

- **Widgets/complications were reading stale data.** Nothing ever told
  WidgetKit a tracker's figures had changed. Fixed two ways:
  `TrackerStore`'s mutation methods now call
  `WidgetCenter.shared.reloadAllTimelines()` (covers the app and
  Shortcuts, both of which always go through `TrackerStore`); and a new
  `CloudSyncWidgetRefresher` observes `NSPersistentStoreRemoteChange` and
  reloads widgets when CloudKit syncs a change down from another device
  while the app is simply open — a case that never touches
  `TrackerStore` at all.
- **Amber ring threshold changed** from an exact "landed exactly on
  target" match to a percentage-of-allowance band (1-5% behind pace) —
  see decision below and `TrackerPace.status`.
- **Fixed a real visual bug**: the inner ring at small sizes (list rows,
  widgets) was reduced to an unreadable "blob" by a flat
  `lineWidth + 10` gap between the rings, sized fine at the 260pt
  dashboard but consuming most of a 36pt row. Made proportional
  (`lineWidth` alone).
- **Trend chart now colors the actual-value line green/red** per
  segment (ahead/behind pace at that point), reusing
  `TrackerPace.isAheadOfPace` rather than a flat blue line.
- **Add/Edit Tracker's number fields** (Starting value, Total budget)
  only had the tiny digits themselves as a tap target, with a `Spacer`
  next to them absorbing taps that did nothing. Made the whole row
  tappable, same pattern already used by `LogReadingView`.
- **Unit pills**: expanded then immediately trimmed back per follow-up
  feedback — settled on £/$/€ plus mi/km/kg/L/hrs, not an exhaustive
  currency/unit list.

### Key decisions

26. **Amber is now a percentage-of-total-allowance band (1-5% behind pace), not an exact match** — reverses part of an earlier explicit decision (§ decision #4/#16's "below, at, or above — only true if the pounds match") based on new feedback that a genuine early-warning zone is more useful than a zero-tolerance snap. `TrackerPace` gained a `totalAllowance` field so `status` can express "behind" relative to the whole rather than an absolute amount (meaningless to compare a £50 tracker's absolute pounds-behind to a £5,000 one's). If this needs tuning again, the two boundary numbers (currently 1 and 5) are the only things to change, in one place (`TrackerPace.status`).
27. **A ring's inner/outer gap must scale with the size it's drawn at, not a flat constant** — `RingsView` is reused from a 36pt list-row indicator up to a 260pt dashboard hero and everything in between (widgets, watch); any spacing constant in it needs to be proportional (here, tied to `lineWidth`, which callers already scale per context) or it silently breaks at whichever end of that size range wasn't visually checked.
