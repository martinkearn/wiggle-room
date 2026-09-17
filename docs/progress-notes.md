# Wiggle Room — Progress Notes

Status snapshot for picking this work back up. **Last updated 2026-09-17**,
after a long same-day session (see **2026-09-17 chart/scheduling/
completed-state overhaul** near the end) that redesigned the trend chart and
ring visuals, replaced three separately-coded ~60s refresh timers with one
shared end-aligned scheduler, added a first-class completed-tracker state,
moved to pull-to-refresh on iOS, and fixed several real bugs (a pace-status
grace zone that could show a tracker as "under budget" while its actual
value sat below its own target, an inverted sign/wording convention for
increasing trackers, mileage trackers showing decimals, and the widget
"choose a tracker" picker resolving an already-selected tracker too eagerly).
Two small changes landed the same day outside that session, directly in the
project file — removing visionOS/Mac Catalyst from the supported platforms,
and adding Xcode Cloud configuration — noted where relevant below but not
otherwise elaborated on here. Before that: a same-day pass (see **2026-09-16
zoom levels & reminders follow-up**) implemented §4.5 zoom levels on the main
dashboard, §5.5 manual-entry reminder notifications, and two small known-gap
fixes (macOS Update History delete, the budget-footer copy). Before that: an
earlier follow-up the same day (see **2026-09-16 follow-up**) added the watch
complication, widget-to-tracker deep linking, macOS Dock badge +
pace-crossing notifications, a custom app font system, an app icon redesign,
and various widget/countdown bug fixes. Before that: an overnight session on
2026-09-14 added the widget extension, watch app, macOS parity, and
Shortcuts/Siri integration — see **Overnight platform expansion** below for
that work; everything above it predates that session. Read alongside
[wiggleroom-build-spec.md](wiggleroom-build-spec.md) — this file tracks *what's
actually been built*, not the spec itself.

**Keeping this file and the build spec in sync**: see
[`CLAUDE.md`](../CLAUDE.md) at the repo root for the standing instruction —
every session that changes app behavior updates both docs (and this file's
intro paragraph) before finishing, not just when explicitly asked to.

**Scope note**: the overnight session was explicitly told to stay manual-entry
only — no Starling/Tesla work was done or attempted, despite the new
platform surfaces (widgets, watch, Shortcuts) being exactly the kind of thing
that would eventually want live provider data. Every new surface reads
`Tracker`/`ValueSnapshot` generically, so a future provider needs no changes
to widgets/watch/Shortcuts — they already work for whatever `actualValue`
resolves to.

## What's implemented

### §4.1 / §4.3 — Tracker model & pace calculations
- [`Tracker.swift`](../src/WiggleRoomShared/Models/Tracker.swift) — `Tracker`, a SwiftData `@Model` class (see **Persistence** below), and the `TrackerDirection` enum. Also holds `isCurrencyUnit` and `formattedValue(_:signed:)` — a currency symbol (£, $, €, …) is prefixed with no space ("£1,234.56"); any other unit is suffixed with a space ("1,234 miles"). The `recurrence` field (an unused placeholder) was removed — see decision #7; recurring trackers were later cut from the spec entirely.
- [`TrackerPace.swift`](../src/WiggleRoomShared/Models/TrackerPace.swift) — `Tracker.pace(actualValue:asOf:)` computing periodHours/hoursElapsed/consumedSoFar/expectedConsumedByNow/difference/target-right-now in one call, so a single snapshot of "now" stays consistent. `hoursElapsed` uses `timeIntervalSince` (wall-clock seconds), which is DST-safe by construction. Also defines `PaceStatus` (`.good`/`.warning`/`.bad`) — the traffic-light read of a tracker's pace — with `.color` (green/amber/red) and `.label(for tracker:)`, which switches to budget language ("Under Budget"/"At Budget"/"Over Budget") specifically for decreasing trackers denominated in currency, and stays neutral ("On Track"/"At Target"/"Needs Attention") otherwise. `.status`'s amber band is a percentage-of-total-allowance early warning (1–5% behind pace, see decision #26), not an exact match. `.label(for tracker:)` switches to budget language ("Under Budget"/"Slightly Over Budget"/"Over Budget") specifically for decreasing trackers denominated in currency, and stays neutral ("On Track"/"Slightly Behind"/"Needs Attention") otherwise — the warning-band wording was reworded from an earlier "At Budget" to "Slightly Over Budget" per follow-up feedback, to read as an early warning rather than a neutral midpoint. `TrackerPace.displayDifference(for:)` is the one place that decides whether to show a signed value or drop the sign — see decision #4.
- Tests: [`TrackerPaceTests.swift`](../src/WiggleRoomTests/TrackerPaceTests.swift) — both directions, ahead/behind pace, period-start/end edges, one DST-transition regression test.

### §5.1 / §5.2 / §5.5 — Source provider abstraction & manual entry
- [`SourceProvider.swift`](../src/WiggleRoomShared/Providers/SourceProvider.swift) — the protocol, unchanged.
- [`SourceTarget.swift`](../src/WiggleRoomShared/Models/SourceTarget.swift) — still a plain (non-persisted) struct; a lightweight DTO for the provider protocol's API shape.
- [`ConnectedSource.swift`](../src/WiggleRoomShared/Models/ConnectedSource.swift), [`ValueSnapshot.swift`](../src/WiggleRoomShared/Models/ValueSnapshot.swift) — SwiftData `@Model` classes. `ConnectedSource.trackers` is the CloudKit-required inverse of `Tracker.connectedSource` — see decision #10, this one cost real debugging time.
- [`ManualEntryProvider.swift`](../src/WiggleRoomShared/Providers/ManualEntryProvider.swift) — a `@MainActor` class holding a `ModelContext`; `fetchCurrentValue`/`logManualReading` resolve a target's id back to a `Tracker` (`sourceTargetId == tracker.id.uuidString`) and read/write `tracker.readings` directly. In practice, app code that already holds the `Tracker` (the dashboard, the log-reading sheet) bypasses this indirection and uses `TrackerStore.logReading`/`tracker.latestReading` directly — this provider mainly exists so the abstraction has a real implementation ahead of Starling/Tesla.
- No Starling or Tesla provider exists yet.

### §6 — Persistence, now with CloudKit sync enabled
- [`WiggleRoomApp.swift`](../src/WiggleRoom/WiggleRoomApp.swift) — builds a `ModelContainer` for `[Tracker, ConnectedSource, ValueSnapshot]` using `ModelConfiguration(schema:cloudKitDatabase:.automatic)`, with a local-only `ModelConfiguration` as a defensive fallback (only kicks in if CloudKit container creation throws — e.g. no iCloud account signed in). **This is live now**: the user's Apple Developer Program enrollment went from "Pending" to active partway through this session, and re-enabling CloudKit surfaced (and fixed) a real schema bug — see decision #10.
- [`WiggleRoom.entitlements`](../src/WiggleRoom/WiggleRoom.entitlements) declares `iCloud.martinkearn.WiggleRoom` + the CloudKit service + `aps-environment` (needed for CloudKit's push-based sync — see **CloudKit** below), and is wired in as the `WiggleRoom` target's `CODE_SIGN_ENTITLEMENTS` build setting (Debug and Release, main app target only — not the test targets).
- [`TrackerStore.swift`](../src/WiggleRoomShared/State/TrackerStore.swift) — a thin `@Observable` wrapper around a `ModelContext`: owns `manualEntrySource` (fetched-or-created once) and the `manualProvider`, and exposes `addTracker`/`deleteTracker`/`logReading`/`saveChanges` actions (`saveChanges` flushes in-place edits from `AddTrackerView`'s edit mode). Tracker/source **lists** are not held here — views read them via `@Query` directly (idiomatic SwiftData/SwiftUI, auto-updating).
- **Confirmed working this session, including real cross-device sync**: created a tracker with CloudKit enabled, force-quit the app, relaunched — still there. Then signed the Simulator into the user's real iCloud account and saw their actual real-device tracker ("Dublin Pocket Money") appear in the Simulator via CloudKit sync — this is real end-to-end confirmation, not just local-disk persistence. See **CloudKit** below for the capabilities that had to be added to get here.

### §7.1 — Screens (iOS full-screen; see **Overnight platform expansion** below for widgets/Lock Screen/watch/macOS)
- [`TrackerListView.swift`](../src/WiggleRoom/Views/TrackerListView.swift) — `@Query`-backed list, empty state, swipe-to-delete, "+" as the primary toolbar action, gear icon (secondary) opening Connected Sources. Each row shows a small `RingsView` pace indicator plus the **difference from target** (via `TrackerPace.displayDifference(for:)`, colored per `PaceStatus`) as the subtitle — not the unit/direction text that used to be there, per explicit user feedback that the difference is the number that matters at a glance.
- [`AddTrackerView.swift`](../src/WiggleRoom/Views/AddTrackerView.swift) — now doubles as the **edit** screen: pass `existingTracker:` and it prefills every field (including detecting whether the tracker already has a specific time-of-day set) and mutates in place via `store.saveChanges()` on save, rather than creating a new `Tracker`. A tracker's source can't be changed after creation — the edit form shows it read-only. Also has:
  - **Unit is picked from a fixed set of pills only** (£, $, €, mi, km, kg) — no free-text entry. This was quick-pick chips alongside a text field earlier; per feedback it's now the *only* way to set the unit, so every currency/formatting check downstream can rely on an exact string match.
  - **"Set specific times" toggle** for the period's Start/End — off by default (midnight-to-midnight), on to reveal `.hourAndMinute` pickers. Whichever mode is used, `startDate`/`endDate` are normalized to midnight on save if the toggle is off, so a tracker never silently inherits whatever time-of-day the form happened to be opened at.
  - Robust decimal parsing (`parseDecimal`, locale-aware via `NumberFormatter` before falling back to `Decimal(string:)`) for the Starting value/Total budget fields — see decision #11, a real data-corruption bug this fixes.
  - An hourly pace estimate, joined by a **daily** one once the period runs longer than 24 hours (`dailyPaceDescription`).
  - A **remaining-at-end** projection (`Tracker.projectedRemainder`) shown whenever starting value and total budget differ — e.g. "£600 will remain at the end of the tracker" for a decreasing tracker, or a warning if the budget exceeds the starting value. Decreasing trackers only — see decision #14 on why increasing trackers don't have an equivalent "remaining" concept.
  - Verified a 1-minute-long tracker (Start/End 1 minute apart via the times toggle) doesn't crash — the hourly-rate math degrades to a very large but finite number, and the daily line correctly stays hidden.
- [`TrackerDetailView.swift`](../src/WiggleRoom/Views/TrackerDetailView.swift) — the tracker dashboard. Two-ring visual with the **difference-from-target as its centerpiece** (large, bold, colored, inside the rings), a `PaceStatus`-driven status word above it (e.g. "OVER BUDGET BY £8.00" for budget trackers — no sign, see decision #4), a trend chart once ≥2 readings exist, and a "…" menu with **Edit Tracker**, **Update History** (manual trackers only — see `ReadingHistoryView` below), and Delete (confirmation first). Below the rings, **Current Balance/Current and Target Right Now are two visually separate cards**, not a shared row — they're different things updated in different ways, and the "Update" button (a capsule, `.controlSize(.large)`, plus-icon — reads as a proper button per Apple HIG, not the cramped two-line label it was before) lives inside the Current Balance card specifically, since that's the only figure it changes. The "Current Balance" vs. "Current" title comes from `Tracker.currentValueLabel` (currency vs. not). Pace figures refresh once a minute; a `secondTimer`-driven "Updates in Xs" caption sits at the **top of the screen**, under the nav title — it reflects the whole screen's live figures (the ring, the difference, Target Right Now), not just one card, so it doesn't belong tucked under a single figure. That countdown's baseline is set in `.onAppear`, not a default `@State` value — see decision #12. The minute rollover itself was originally a separately `let`-stored `Timer.publish(every: 60...)`, which turned out to never fire in practice (see decision #28) — it's now folded into the same 1-second timer that drives the visible countdown. The remaining-at-end caption sits under the **Target Right Now** figure card specifically (moved from under the days-remaining text — it's a projection about the tracker's target, not about time remaining), and that card does a full 360° flip animation whenever a new reading lands.
- [`ReadingHistoryView.swift`](../src/WiggleRoom/Views/ReadingHistoryView.swift) — **new**: lists every logged update for a manual tracker, newest first, tap to edit (via `LogReadingView`'s edit mode) or swipe/Edit-mode to delete. Reachable only for `tracker.isManualEntry` trackers — a real provider's history should reflect what it actually reported, not something hand-edited.
- [`RingsView.swift`](../src/WiggleRoomShared/RingsView.swift) — the two-ring visual itself (§3.4) — outer neutral-gray pace ring (elapsed-time fraction), inner ring colored per `PaceStatus` (green/amber/red — true traffic-light semantics, not just a green/red binary). Bigger by default (used at 260pt in the dashboard) with the difference figure and a legend as center content; `showsCenterContent: false` gives the bare rings for small uses like the list-row indicator. The legend uses the exact same wording as the figure cards below it ("Current Balance"/"Target Right Now"), in the same left-to-right order — not a separately-worded "Progress"/"Time elapsed" pair the reader had to map onto the figures themselves. Uses a `GeometryReader` to constrain the center text's width so long values shrink to fit rather than overflowing past the ring.
- [`TrendChartView.swift`](../src/WiggleRoom/Views/TrendChartView.swift) — Swift Charts line (§3.5) — a straight gray pace-reference line from start to end, actual logged readings plotted in blue on top.
- [`LogReadingView.swift`](../src/WiggleRoom/Views/LogReadingView.swift) — the §5.5 value-entry sheet ("Update Current Value" when creating, "Edit Update" when editing an existing one via `existingReading:`, with a Delete action alongside Save). A large, centered numeric input with the unit as a prefix/suffix label replaces the old small trailing-aligned field — bigger, easier to tap, and the whole row focuses it. Uses the same robust decimal parsing as `AddTrackerView`.
- [`ConnectedSourcesView.swift`](../src/WiggleRoom/Views/ConnectedSourcesView.swift) + [`AddSourceView.swift`](../src/WiggleRoom/Views/AddSourceView.swift) — Settings → Connected Sources (§5.2), `@Query`-backed. `AddSourceView` is still a deliberate stub ("Coming Soon") — no Starling/Tesla setup UI exists yet.
- [`View+PlatformHelpers.swift`](../src/WiggleRoom/Views/View+PlatformHelpers.swift) — shared `#if os(iOS)` wrappers for UIKit-only modifiers (see decision #5).
- [`PreviewSupport.swift`](../src/WiggleRoom/PreviewSupport.swift) — shared in-memory SwiftData stack + sample-tracker factory, used by every view's `#Preview`.

## CloudKit — enabled and confirmed working (read this before touching it again)

The user's Apple Developer Program enrollment went from "Pending" to fully
active during this session. Getting sync fully working took three separate
fixes, in order — if CloudKit ever seems broken again, check these before
assuming it's a new problem:

1. **A latent schema bug**: `Tracker.connectedSource` had no declared inverse relationship. Worked fine locally, crashed on launch the instant CloudKit was turned on. See decision #10.
2. **Capabilities beyond just "iCloud"**: Apple's provisioning validation also required **Push Notifications** (+ `aps-environment` entitlement) and **Background Modes → Remote notifications** (which needed a real `Info.plist` with `UIBackgroundModes`, since CloudKit relies on silent push to detect remote changes). All three capabilities had to be added through Xcode's own Signing & Capabilities UI — that's what actually registers them against the App ID on Apple's developer portal; hand-editing the entitlements file and `project.pbxproj` directly (which is as far as this session's tooling could go on its own) is not enough on its own for a **new** capability, though it did work for re-adding one already registered.
3. Even after both of those, the App ID's capabilities took a short while to propagate — the exact error was *"The capability associated with 'ICLOUD' could not be determined"* alongside *"Provisioning profile ... doesn't include the iCloud capability"*. Re-adding Push Notifications + Background Modes and clicking "Try Again" in Xcode cleared it.

**Current setup:**
- `WiggleRoomApp.swift` uses `cloudKitDatabase: .automatic`, with a local-only fallback that only activates if the CloudKit `ModelContainer` fails to initialize.
- `WiggleRoom.entitlements` declares the iCloud container, CloudKit service, and `aps-environment`; `Info.plist` declares `UIBackgroundModes: [remote-notification, processing, fetch]`. Both are wired into the main app target's build settings (Debug and Release).
- The container id is `iCloud.martinkearn.WiggleRoom`.

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
6. **Xcode 16 file-system-synchronized groups**: no manually-maintained `.pbxproj` file lists — any `.swift` file dropped into `src/WiggleRoom/` or `src/WiggleRoomTests/` is picked up automatically.
7. **`recurrence` field was removed from `Tracker`** (it was an unused `RecurrenceRule?` placeholder). The recurring-trackers feature it was for was later cut from the spec entirely — see the scope-cut decision below — so this field is not coming back.
8. **Running `xcodebuild` in this environment**: the active `xcode-select` developer directory is Command Line Tools, not Xcode. Prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
9. **A nasty SwiftData footgun**: an in-memory `ModelContainer`'s backing store is tied to the container object's own lifetime — if you create a container, grab only its `.mainContext`, and let the container itself go out of scope, the context silently becomes unusable and **crashes on first `insert()`**. Always hold onto the `ModelContainer` itself for as long as you use its context — see [`TestSupport.swift`](../src/WiggleRoomTests/TestSupport.swift)'s `makeInMemoryModelContainer()`.
10. **CloudKit requires every relationship to declare an inverse, on both sides of the model, or the app crashes on launch with an opaque Core Data error** ("CloudKit integration requires that all relationships have an inverse, the following do not: Tracker: connectedSource"). `Tracker.connectedSource` had no inverse declared on `ConnectedSource` — it worked fine locally (SwiftData doesn't enforce this for local-only stores) but broke the instant CloudKit was turned back on. Fixed by adding `@Relationship(inverse: \Tracker.connectedSource) var trackers: [Tracker]? = []` to `ConnectedSource`. **If you add any new relationship to a `@Model` type, check this immediately** — it won't show up in local testing, only once CloudKit is active, and the crash message doesn't point at the fix very clearly.
11. **`Decimal(string:)` silently truncates at a grouping separator instead of failing.** `Decimal(string: "3,000")` does **not** return `nil` — it parses `"3"` and stops at the comma, corrupting the value by 1000x. This bit us for real: prefilling the edit form with `.formatted(.number...)` (which adds thousands separators, e.g. "3,000") round-tripped through this on save and silently turned a £3,000 budget into £3. Fixed two ways: (a) prefill text fields with `.formatted(.number.grouping(.never)...)` so there's no separator to round-trip in the first place, and (b) added a `parseDecimal` helper (locale-aware `NumberFormatter` first, falling back to `Decimal(string:)`) used everywhere a user-typed or pasted decimal is parsed, as defense in depth. **Never use bare `Decimal(string:)` on text that might contain a thousands separator** — check `isValid`/`save()` in `AddTrackerView.swift` and `LogReadingView.swift` for the pattern to copy.
12. **A `@State` default value can initialize before a screen is actually visible.** The dashboard's countdown baseline (`nextUpdateAt = Date.now.addingTimeInterval(60)`) was originally a default `@State` value — but SwiftUI can construct a view struct (and its `@State` defaults) before the screen is actually shown, e.g. `NavigationLink` destinations are sometimes built ahead of the tap. This made the countdown sometimes start already at "0s". Fixed by setting the real baseline in `.onAppear` instead of a property default. **Any "starts a timer relative to now" state needs to be set in `.onAppear`/`.task`, never a property default**, or it can silently measure from the wrong "now".
13. **An installed Simulator app can be stale in a way that's easy to misdiagnose as a logic bug.** `xcrun simctl boot`/`launch` do not reinstall — if an `install` step fails silently (e.g. the Simulator had shut down) and you don't check its exit code, a later `launch` will happily relaunch the **old** binary with no error. This looked exactly like a code bug (one screen showed a fix, another screen — same tracker, same running process — didn't) until re-installing fixed it. **After any `simctl install`, check its actual exit code before trusting what you see on screen**; a `boot`+`launch`-only sequence with no accompanying `install` is a red flag if you've rebuilt since the app was last installed.
14. **"Increasing" trackers model a cap/allowance, not an open-ended goal.** Tested this explicitly: for an increasing tracker (e.g. mileage lease), "good"/green means the current value is *at or under* the pace target — using less of the allowance than expected is the good outcome, same direction as a decreasing budget tracker being under-spent. This means an increasing tracker is a poor fit for something like a "savings goal" where *exceeding* the target would intuitively be the good outcome — the app doesn't support that framing today. Worth knowing before suggesting increasing trackers for goal-type use cases; a distinct "goal" mode would be needed for that, not just direction=increasing — not built, and not currently planned.
15. **Simulator tap coordinates must be in device points (e.g. 402×874 for this iPhone 17 Pro), not screenshot pixels.** A screenshot comes back at the device's native pixel resolution (3x the point size), and it's easy to eyeball a coordinate straight off the image and pass it through unscaled — anything over ~400 in x or ~874 in y is out of bounds and the tap silently lands nowhere (no error). When a tap has no visible effect, check the coordinate is within the reported point bounds before assuming a UI bug.
16. **Terminology must match exactly between the action and the record of it.** The button is "Update" (not "Log a Reading"), so every place its results are described needs the same word — "Update History" not "Reading History", "Edit Update"/"Delete Update" not "Edit/Delete Reading". Caught via direct user feedback after shipping "Reading History" first; a naming pass should check *all* user-facing strings tied to a renamed action, not just the button itself.
17. **Recurring trackers (spec §4.4, as originally numbered) cut from scope entirely, by direct user instruction.** Reasoning given: creating/deleting a tracker is now easy enough (the whole Add Tracker flow, seeded initial reading, etc.) that automatic template-cloning on period rollover isn't worth the complexity — a user can just make the next period's tracker themselves. The spec's §4.4 section, the `recurrence`/`RecurrenceRule` field, and every cross-reference to it were removed from `wiggleroom-build-spec.md`; sections after it were renumbered (old §4.5/§4.6 → §4.4/§4.5) rather than left with a numbering gap. No code ever implemented this (the field was already just an unused placeholder — decision #7), so this was a pure spec/docs edit.

## Known gaps / things to verify by hand

- §4.5 zoom levels are implemented on the main dashboard (see **2026-09-16 zoom levels & reminders follow-up**) but **not** for widgets/the watch complication — a widget instance always shows a tracker's `.overall` pace. See that section for why (a tooling constraint, not a design decision).
- A `WiggleRoomUITests` target exists (`WiggleRoomUITests.swift`, `WiggleRoomUITestsLaunchTests.swift`), added in the 2026-09-16 follow-up, but hasn't grown beyond Xcode's generated scaffold yet — no view has real automated UI-interaction coverage. Verification is still mostly manual (simulator screenshots + interaction) plus unit tests on the non-UI layers (`TrackerPace`, `Tracker`, `ManualEntryProvider`, `TrackerStore`, `ZoomLevel`/zoom-scoped `Tracker`/`TrackerPace` behavior — see **2026-09-16 zoom levels & reminders follow-up** for the current count). Consider `ViewInspector`-style tests or fleshing out the UI test target if this grows much further.
- ~~This Mac isn't yet registered as a device on the paid developer account~~ — resolved during the overnight session: `-allowProvisioningUpdates` now generates a working Mac profile from the command line with no Xcode GUI step needed (see **Overnight platform expansion**).
- An increasing tracker can't model an open-ended "goal to exceed" (e.g. a savings goal) — see decision #14. Only tested as a cap/allowance (mileage-lease-style), which is what the current pace math supports.

## Explicitly out of scope so far (per spec, deferred on purpose)

- §4.4 multi-tracker source-sharing/dedup (only matters once a second provider exists)
- Widget/watch-complication zoom-level configuration (§8.1) — §4.5 zoom levels themselves are now implemented on the main dashboard; see **2026-09-16 zoom levels & reminders follow-up**
- §5.3 Starling, §5.4 Tesla providers (only the manual provider exists) — explicitly kept out of scope for the overnight session too, by direct instruction
- Live Activities / Dynamic Island — considered during the overnight session and deliberately skipped; see **Overnight platform expansion** for why

## Suggested next steps (not a commitment, just a sane order)

1. Widget/watch-complication zoom-level configuration, once the two-extension-target plumbing can safely be done (needs Xcode's GUI or a scripted `.pbxproj` change in this environment — see **2026-09-16 zoom levels & reminders follow-up**).
2. A real source provider (Starling is the simplest per spec's own note in §5.3) — this is what actually exercises the multi-source parts of the Settings screen and the "Add New Source" flow for real, and is also what would make the widget/watch/Shortcuts refresh cadence choices (hourly, once-a-day, on-demand) actually matter.
3. If a goal-type tracker (exceed-the-target framing, e.g. savings) turns out to matter, it needs new semantics distinct from "increasing" — see decision #14.
4. See **Overnight platform expansion**'s own "Suggested next steps" for widget/watch/macOS-specific follow-ups.

## Verifying the app still builds and passes tests

Use the iOS Simulator destination. **Note**: since the deployment target was
raised to 27.0, the destination needs an actual iOS 27.0 simulator — a
generic `name=iPhone 17 Pro` destination may resolve to an older-OS instance
of that device model and fail with a deployment-target mismatch error; if
so, create one (`xcrun simctl create "iPhone 17 Pro (iOS 27)"
com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
com.apple.CoreSimulator.SimRuntime.iOS-27-0`, if the iOS 27.0 runtime is
installed) and pass `-destination 'platform=iOS Simulator,id=<its udid>'`
instead:

```bash
cd src
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WiggleRoom.xcodeproj -scheme WiggleRoom \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WiggleRoomTests test
```

75 tests should pass (`TrackerPaceTests`, `TrackerTests`, `ZoomLevelTests`,
`ManualEntryProviderTests`, `TrackerStoreTests`, plus the two scaffold tests
in `WiggleRoomTests`) — up from 23 as of the 2026-09-16 follow-up, which
added `TrackerTests.swift`. **As of this session, `ManualEntryProviderTests`
and `TrackerStoreTests` cannot actually be confirmed passing** on at least
one iOS 27.0 Simulator — see gotcha #28 above before assuming a failure
there is a real regression.

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

- **WiggleRoomWidgets** (`src/WiggleRoomWidgets/`) — a WidgetKit extension, embedded
  in the iOS app's `PlugIns/`. One `AppIntentConfiguration`-based `Widget`
  covers Home Screen small/medium/large/extra-large and Lock Screen
  circular/rectangular/inline (iOS only — WidgetKit's accessory families
  don't exist on macOS, see below). Each widget instance is independently
  configurable to a tracker via a `WidgetConfigurationIntent` +
  `TrackerEntity`/`TrackerEntityQuery` (App Intents), so two widgets can show
  two different trackers side by side. `WidgetDataStore` opens its own
  `ModelContainer` against the same CloudKit container on every timeline
  refresh (no App Group needed — see **Architecture** below) and refreshes
  hourly. Reuses `RingsView` directly rather than a bespoke widget visual.
  Each widget instance also sets a `.widgetURL` (`wiggleroom://tracker/<uuid>`)
  so tapping it deep-links straight to that tracker's dashboard (see
  **2026-09-16 follow-up** below for `DeepLinkRouter`). The extra-large
  family, widget typography, and a tracker-name truncation fix were also
  added in that later pass.
- **WiggleRoomWatch** (`src/WiggleRoomWatch/`) — a single-target watchOS companion
  app, embedded in the iOS app via the classic "Embed Watch Content" phase.
  A tracker list, a detail screen (`RingsView` again, at watch size), and a
  "Log" action for manual trackers — promoted from the spec's §7.3 "stretch
  goal" to a real feature, since manual entry is the only provider in scope.
  Talks to its own `ModelContainer`/CloudKit container independently of the
  phone being nearby.
- At the time of this overnight session, no separate widget/complication
  target for the watch had been attempted — watchOS complications are
  WidgetKit widgets too (since watchOS 9), but need their own extension
  embedded *inside* `WiggleRoomWatch`. **This was built in the 2026-09-16
  follow-up** — see below (`WiggleRoomComplication`) — this bullet is kept
  for history.

### Architecture: WiggleRoomShared

The model/pace layer and a few view/store pieces were moved into a new
`src/WiggleRoomShared/` folder, compiled directly into the app, widget
extension, and watch app targets (via a `PBXFileSystemSynchronizedRootGroup`
listed under all three targets — see **Tooling gotchas** below for what that
actually means and why it needed scripting rather than Xcode's GUI):

- `Models/` — `Tracker`, `ConnectedSource`, `ValueSnapshot`, `TrackerPace`, `SourceTarget` (moved from `src/WiggleRoom/Models/`)
- `Providers/` — `SourceProvider`, `ManualEntryProvider` (moved from `src/WiggleRoom/Providers/`)
- `State/TrackerStore.swift` (moved from `src/WiggleRoom/State/`)
- `RingsView.swift` (moved from `src/WiggleRoom/Views/`) — the two-ring visual, reused verbatim by the widget and watch app
- `WiggleRoomColors.swift` — extracted out of `RingsView.swift` (it used to be a private-ish enum at the bottom of that file) since widgets/watch need it independently; also gained `Color.widgetBackground`, a cross-platform stand-in for `UIColor.systemBackground` (no macOS/watchOS equivalent)
- `SharedPreviewData.swift` — a `TrackerStore`-free preview fixture for shared views, since the app's own `PreviewData` (in `src/WiggleRoom/PreviewSupport.swift`) pulls in `TrackerStore`, which shared views shouldn't need just to render a preview

**No App Group was needed anywhere.** Widgets and the watch app don't share
a local store with the phone app — each opens its own `ModelContainer`
against the same `iCloud.martinkearn.WiggleRoom` CloudKit container (Apple's
recommended pattern for widgets reading SwiftData+CloudKit data), and
CloudKit sync is what keeps them consistent, not a shared on-disk file. This
was flagged as a possible blocking need in the pre-flight check and turned
out not to be one.

**Shortcuts/Siri** (`src/WiggleRoom/Intents/`) lives in the main app target, not
`WiggleRoomShared` — `LogReadingIntent` (manual trackers only) and
`ViewTrackerStatusIntent` (read-only), registered via `WiggleRoomShortcuts:
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
- A `MenuBarExtra` in `WiggleRoomApp.swift` (macOS only) — `MenuBarStatusView`/
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
- Not attempted at the time: a macOS Dock icon badge for "any tracker behind
  pace", and a cross-app-crossing-pace notification (§7.2's last two
  bullets). **Both were built in the 2026-09-16 follow-up** — see below.

### Live Activities — deliberately not built

Explicitly requested for exploration tonight, and explicitly out of scope
in the build spec (§9) before that. Judgment call: skipped. Live Activities
are designed for short, bounded events (a ride, a delivery, a sports game)
with a clear start/end shown continuously on the Lock Screen/Dynamic Island
for that duration — a Wiggle Room tracker runs for days, weeks, or months, so
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
18. **A `PBXFileSystemSynchronizedRootGroup` can be listed under more than one target's `fileSystemSynchronizedGroups`** — that's how `WiggleRoomShared` ends up compiled into three different targets/modules without three copies of the files on disk, and without a separate framework target. Each target gets its own independently-compiled copy of the same source (not a shared binary) — fine for a folder this small.
19. **`xcodebuild -destination` could not discover *any* watchOS simulator destination** for `WiggleRoomWatch`, even a booted, paired one, and even after adding a real shared `.xcscheme` (autocreated schemes aren't enough for `xcodebuild` to resolve watchOS destinations reliably when the project has never been opened in Xcode.app itself). Building the target directly bypasses this: `xcodebuild -target WiggleRoomWatch -sdk watchsimulator build`. **Caveat**: `-sdk <sdk>` on the command line force-overrides `SDKROOT` for *every* target in the build graph, including dependencies with their own different `SDKROOT` — this silently corrupted `WiggleRoomWatch`'s generated `Info.plist` (wrong `UIDeviceFamily`) when building `-target WiggleRoom -sdk iphonesimulator` (which also builds the embedded `WiggleRoomWatch` dependency). The scheme+`-destination` route doesn't have this problem, once the matching simulator runtime is installed — see #20.
20. **A scheme containing an embedded watch app refuses to `build` (not just run) unless a simulator runtime matching the *SDK* version is installed** — not the app's `WATCHOS_DEPLOYMENT_TARGET`. This machine had watchOS SDK 26.5 but only runtimes up to 26.4 installed, so `xcodebuild -scheme WiggleRoom -destination 'platform=iOS Simulator,...' build` failed with *"This scheme builds an embedded Apple Watch app. watchOS 26.5 must be installed"* even though the watch target's own deployment target was set to 26.4. Fixed by running `xcodebuild -downloadPlatform watchOS` (network access confirmed available; ran in the background for the rest of the session). Building for **macOS** never hit this at all, since WiggleRoomWatch is correctly excluded there — see #21.
21. **A macOS build fails outright if it embeds a watchOS binary** — "This target is built for macOS but contains embedded content (WiggleRoomWatch.app) built for watchOS, which is not allowed." Fixed with Xcode's **platform filter** mechanism (`platform_filters = ['ios']` via the `xcodeproj` gem) on *both* the `PBXTargetDependency` and the `PBXBuildFile` inside the "Embed Watch Content" copy-files phase — this is exactly what Xcode's own multiplatform-target wizard sets up, just applied by script instead.
22. **A single-target watchOS app's generated `Info.plist` needs `UIDeviceFamily: [4]` explicitly** — `GENERATE_INFOPLIST_FILE = YES` did not reliably infer it from `TARGETED_DEVICE_FAMILY = 4` in this setup, and the Simulator's install step fails with a clear ("WatchKit 2.0 app's UIDeviceFamily key does not specify...") but easy-to-miss error if it's wrong. Set directly in `WiggleRoomWatch/Info.plist` rather than relying on the generated-plist inference. **This was also a false alarm once**: building via `-target WiggleRoom -sdk iphonesimulator` (rather than `-scheme`+`-destination`) forces `SDKROOT` onto every target in the graph including `WiggleRoomWatch`, which regenerates its `Info.plist` as if it were an iOS target (`UIDeviceFamily: [1,2]`) even though the key is correctly set in source — the proper `-scheme`/`-destination` build produces `[4]` correctly. Don't diagnose an `Info.plist` problem from a `-target`/`-sdk` build; use the scheme.
23. **`xcodebuild -downloadPlatform watchOS` can report success while installing a runtime that's already present**, failing with *"Duplicate of \<uuid\>"* right at the end — harmless (the already-installed copy, found via `xcrun simctl runtime list`, is what matters; `simctl list runtimes` can lag behind `simctl runtime list` immediately after an install, don't trust the former alone). Clean up the failed duplicate with `xcrun simctl runtime delete <uuid>`. Also: simulator **pairing is one-to-one** (a watch already paired to one phone must be `simctl unpair`'d before pairing it to another), and a paired phone+watch must be **within the same OS cycle** the app's deployment targets require — installing a 26.5-deployment-target app onto a paired-but-26.4 iPhone Simulator fails outright ("Requires a Newer Version of iOS"), so the phone and watch simulators in a pair need OS versions that satisfy the app's actual deployment targets, not just any pairing that happens to exist already.
24. **Adding an explicit shared `.xcscheme` for even one target disables Xcode's scheme autocreation for the *whole* project** (it only runs when a project has zero explicit schemes) — adding `WiggleRoomWidgets.xcscheme`/`WiggleRoomWatch.xcscheme` silently made the `WiggleRoom` app scheme vanish from both `xcodebuild -list` and Xcode's own scheme picker. Fixed by explicitly writing a `WiggleRoom.xcscheme` too (`scripts/add_wiggleroom_scheme.rb`). **Anyone adding a new target's scheme by hand to this project should add/verify all schemes at the same time**, not just the new one.
25. **A widget's App Intents entity query (the "choose a tracker" configuration picker) can flash "Loading" and silently revert to empty with zero error UI**, and the cause is *not necessarily* a permissions/capability problem even though it looks exactly like one. Confirmed via `xcrun simctl spawn <udid> log stream --predicate 'process == "WiggleRoomWidgets"'` (essential technique — this is the only way to see what a widget extension is actually doing, since there's no on-screen error surface): the widget's `ModelContainer` opened successfully with no thrown error, but its first-ever CloudKit history import into that fresh sandboxed container (a `CKModifyRecordZonesOperation`/`CKModifySubscriptionsOperation` pair, visible in the log under the `CloudKit` subsystem) hadn't completed yet when the fetch ran — so it legitimately saw zero rows even though the data already existed in iCloud. Fixed with a bounded retry (`WidgetDataStore.fetchAllTrackers()`, up to 8 attempts / 0.5s apart) rather than accepting the first empty result — a one-time cost per extension process since the container itself is cached. **Don't assume "empty result, no visible error" in a widget/extension means a missing capability — check the actual log stream before guessing**, and know that a fresh CloudKit-backed `ModelContainer`'s first fetch can race its own initial import.

### What was verified tonight (and how)

- **iOS**: `xcodebuild -scheme WiggleRoom -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` and `test` both succeed (23/23 tests). The built `WiggleRoom.app` — with `WiggleRoomWidgets.appex` in `PlugIns/` and `WiggleRoomWatch.app` in `Watch/`, both correctly signed — was installed and launched on that simulator, showing the real CloudKit-synced "Dublin Pocket Money" tracker untouched. `WiggleRoomWatch.app` extracted from that same build and installed standalone onto a paired Apple Watch Series 11 (46mm) simulator (watchOS 26.5) launches correctly and shows the expected "No Trackers" empty state (that simulator isn't signed into the same iCloud account). The widget was confirmed registered with the system (found via the Home Screen's "Add Widget" search).
- **macOS**: `xcodebuild -scheme WiggleRoom -destination 'platform=macOS' -allowProvisioningUpdates build` succeeds, with `WiggleRoomWidgets` embedded and `WiggleRoomWatch` correctly excluded.
- **Not verified live**: actually placing a widget on the Home Screen and screenshotting its rendered output (the on-simulator widget-gallery flow is fiddly to drive via coordinate taps and was only partially completed — the widget's presence in the system was confirmed, its final rendered appearance wasn't screenshotted); the macOS app's actual window/menu bar item on screen (no macOS GUI-automation tool is available in this environment — `osascript`/`screencapture` both require a permission prompt only a human can grant, so this is a real environment limitation, not a skipped step); the real phone→watch companion auto-install via Simulator pairing (Simulator's `simctl pair` doesn't replicate the full WatchConnectivity install-push a real device or an Xcode-driven combined run destination does — installing the extracted watch app directly, as done above, is the workaround and is what's actually been verified).

### Suggested next steps (widget/watch/macOS-specific)

1. ~~A real watch complication~~ — **done**, see **2026-09-16 follow-up** below (`WiggleRoomComplication` target).
2. ~~A macOS Dock badge + cross-pace notification~~ — **done**, see **2026-09-16 follow-up** below (`MacRootView`'s dock badge, `PaceCrossingNotifier`).
3. A first real design pass — this was explicitly functionality-first tonight, and the "not verified live" gaps above (actual widget rendering on a Home Screen, the macOS window) are exactly where a design pass would want to start looking. Partially addressed since (app icon, typography, wiggle-line trend accent — see **2026-09-16 follow-up**), but a full pass hasn't happened.
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

## 2026-09-16 follow-up

A further pass building out the gaps the previous two sessions had flagged
as deferred, plus a first real design pass and a batch of small bug fixes.

### Watch complication (§7.3, resolves a known gap)

- **`WiggleRoomComplication`** (`src/WiggleRoomComplication/`) — a second
  WidgetKit extension, embedded inside `WiggleRoomWatch` (not the phone app),
  showing a chosen/default tracker's ahead/behind figure across
  `.accessoryCircular`/`.accessoryRectangular`/`.accessoryInline` families —
  the same families already proven out on the iOS Lock Screen, styled to
  match. `TrackerComplicationProvider` (`AppIntentTimelineProvider`) refreshes
  hourly; `SelectTrackerIntent` has its own `TrackerEntity`/`TrackerEntityQuery`
  rather than reusing the phone widget extension's — App Intents entities
  aren't shared across extension/module boundaries, each target needs its own
  (same lesson as the Shortcuts intents in the overnight session).
- `WidgetDataStore` (the CloudKit cold-start/import-wait retry logic, see
  decision #25) moved into `WiggleRoomShared` so the phone widgets, macOS
  widgets, and this new watch complication share one implementation instead
  of a third copy.
- Target/scheme creation scripted via the `xcodeproj` gem
  (`scripts/add_complication_target.rb`, `scripts/add_complication_scheme.rb`),
  same approach as the existing `scripts/add_*_target.rb` files — this
  project's file-system-synchronized group format still needs that instead of
  Xcode's "New Target" wizard (see decision #17). A new shared scheme was
  required too, per decision #24 (adding one explicit scheme disables
  autocreation project-wide).
- One SDK quirk: this watchOS SDK's `AppIntentTimelineProvider` has no
  default `recommendations()` implementation the way the iOS one does, so
  the complication needed an explicit empty stub to conform.

### macOS Dock badge + pace-crossing notifications (§7.2, resolves a known gap)

- **Dock badge**: `MacRootView` sets `NSApplication.shared.dockTile.badgeLabel`
  to `"!"` whenever any tracker's `PaceStatus` isn't `.good`, `nil` otherwise —
  re-evaluated once a minute via `paceRefreshTimer`, the same cadence
  `TrackerDetailView` recomputes its own figures at.
- **`PaceCrossingNotifier.swift`** — posts a local notification when a
  tracker crosses from ahead-of/on-pace to behind, or back again. Tracks each
  tracker's last-known side of the ahead/behind line purely in memory (not
  persisted across relaunches) — the point is a timely heads-up while the app
  happens to be running, not an audit trail; readings themselves remain the
  durable record. macOS only for now, since iOS/watchOS already have an
  always-visible widget/complication covering this at a glance.

### Widget-to-tracker deep linking

- **`DeepLinkRouter.swift`** (main app) + **`WiggleRoomDeepLink.swift`**
  (shared) — each widget instance sets a `.widgetURL`
  (`wiggleroom://tracker/<uuid>`), parsed via `.onOpenURL` and picked up by
  `TrackerListView` to push straight to that tracker's dashboard, rather than
  just opening the app to the tracker list.

### Widget fixes and additions

- **Tracker names truncating despite unused space**: in the medium/large
  layouts, a trailing `Spacer(minLength: 0)` was soaking up the row's
  leftover width instead of the name `Text`, leaving visible whitespace after
  the ellipsis (e.g. "Dublin Trip" showing as "Dublin T..."). Every
  tracker-name `Text` (small/medium/large/extra-large + the rectangular Lock
  Screen widget) now gets `.frame(maxWidth: .infinity, ...)` plus
  `.minimumScaleFactor()`; the now-redundant trailing Spacers were removed.
- **Extra-large widget family**: added `.systemExtraLarge` (iOS/iPadOS/macOS
  27+ only — this is why the deployment target was raised, see below). Its
  layout mirrors `TrackerDetailView` closely (full rings, both figure cards
  with captions, days-remaining line) rather than the more compact `large`
  layout.
- Widgets now adopt `WiggleRoomFont` (see design pass below) instead of
  system fonts, matching the main app's typography.

### Dashboard fixes

- **Countdown stalling at 0s**: `TrackerDetailView`'s minute rollover was a
  `let`-stored `Timer.publish(every: 60...)` on the view struct. Since the
  view's body re-evaluates every second (driven by the visible 1-second
  countdown), that 60-second timer got torn down and recreated roughly once a
  second — never surviving long enough to actually fire, so the countdown
  never rolled forward once it reached 0. Fixed by folding the minute
  rollover into the existing 1-second timer's own handler instead (compares
  the current date against `nextUpdateAt`), which only ever needs to survive
  ~1s between recreations — something it already did reliably, since the
  visible countdown itself was ticking fine. A related but distinct bug from
  decision #12's `.onAppear` baseline fix, same view.
- **Remaining-at-end caption moved**: now sits under the **Target Right Now**
  figure card specifically (was under the days-remaining text) — it's a
  projection about the tracker's target, not about time remaining. That card
  also gained a full 360° flip animation whenever a new reading lands (a full
  turn rather than a toggle, so back-to-back updates never fight over
  direction).
- **"Slightly Over Budget" wording**: the warning-band budget label was
  reworded from an earlier "At Budget" to "Slightly Over Budget", to read as
  an early warning rather than a neutral midpoint — matches the neutral
  side's existing "Slightly Behind". The amber *threshold* itself
  (decision #26, 1-5%) is unchanged; only the label text moved.
- **Add/Edit Tracker number fields**: a follow-up beyond the earlier
  full-row-tappable fix (see the 2026-09-15 section above) wasn't needed here
  — noted only because it's easy to confuse with this session's other small
  interaction fixes.

### A first real design pass

iOS-focused; macOS/watchOS/widgets picked up the new fonts but not a full
bespoke pass.

- **App icon redesigned twice**: first replaced the original two-ring motif
  with a bold single sine-wave line in the brand violet/coral/green palette
  (`21afa89`), then further refined to a violet background with the wiggle
  line plus a lower-opacity descending second line echoing the trend chart
  (`baceacd`). A matching watchOS app icon was added at the same time. The
  two-ring motif remains the in-app data-visualization language (dashboard
  rings, list-row indicators, `WiggleEmptyState`'s ring stroke) even though
  the app icon itself moved away from it.
- **`WiggleRoomFonts.swift`** (`WiggleRoomShared`) — Fraunces (a variable
  serif, WONK axis) for headlines/status words via
  `WiggleRoomFont.headline`/`.statusWord`/`.aside`, registered per-process via
  Core Text (`registerIfNeeded()` — safe to call from every target since
  app/widget/watch/complication don't share a process); SF Rounded with
  tabular figures (`Font.wiggleNumber`) for every numeric readout, kept
  deliberately separate from Fraunces so digit alignment (§3.3) is never put
  at risk. An iOS-only `installNavigationBarAppearance()` applies Fraunces to
  `UINavigationBar` titles, since SwiftUI's `.navigationTitle` has no native
  font hook.
- **`WiggleEmptyState.swift`** — a shared empty-state view (ring stroke + SF
  Symbol tinted brand violet, title/message/optional action button) used
  across every empty list, so even a blank screen reads as Wiggle Room.
- **Ring recycle animation fix**: dropped a desyncing "cap dot" that drifted
  out of sync with the ring fill during recycled (0%→100%→0%) animations, and
  synced the list-row ring's motion to match.
- **`WiggleRoomColors.swift`** gained the brand violet/warm palette backing
  the new icon and fonts (`.brand`, `.brandWarm`).

### Other additions

- **`AppCommands.swift`** — backs macOS's File > New Tracker (⌘N) menu
  command. Uses an ever-incrementing counter (same pattern as
  `TrackerDetailView`'s flip-animation counter above) rather than a plain
  `Bool`, so a second ⌘N pressed before the first sheet finishes dismissing
  still registers instead of silently no-oping on an already-true flag.
  Observed by `MacRootView`.
- **`TrackerTests.swift`** — 22 new tests covering `Tracker` model behavior
  directly (`isCurrencyUnit`, `usesBudgetLanguage`, `currentValueLabel`,
  `formattedValue`, `projectedRemainder`, `remainingAtEndCaption`,
  `periodRemainingText`), distinct from `TrackerPaceTests`. A
  `WiggleRoomUITests` target was also added but is still Xcode's generated
  scaffold — no real UI-interaction coverage yet.
- **Deployment targets raised to 27.0** (iOS/macOS) to support the
  extra-large widget family; watchOS/`WiggleRoomWatch`/`WiggleRoomComplication`
  deliberately left at 26.0 for real-device compatibility. Test target
  deployment settings were also cleaned up (recommended iOS/visionOS
  targets, macOS test target to 27.0, redundant Xcode project exceptions
  removed).
- Recurring trackers (spec's old §4.4) were removed from the spec entirely —
  see decision #17, unchanged by this session, listed here only because the
  commit landed in the same run.

### Known gaps, updated

- The macOS `ReadingHistoryView` swipe-to-delete gap (Suggested next steps
  item #4 above) is still open — not addressed this session.
- No Starling/Tesla provider work was done this session either — still just
  manual entry, per every prior session's scope note.

## 2026-09-16 zoom levels & reminders follow-up

A second pass the same day, asked to implement everything remaining in the
spec except Starling/Tesla. Reviewed both this file and
`wiggleroom-build-spec.md` end to end first — the only substantial gap left
was §4.5 zoom levels; everything else was either already built, explicitly
out of scope (Starling/Tesla, per every prior session), or a small
known-gap item already flagged above.

### §4.5 Zoom levels — the main gap, now closed on the dashboard

- **`ZoomLevel.swift`** (`WiggleRoomShared/Models/`) — a small
  `.overall`/`.thisYear`/`.thisMonth`/`.thisWeek` enum with a display label.
- **`Tracker.swift`** gained three pieces: `actualValue(atOrBefore:)` (the
  latest reading at or before a date, or `startingValue` if there isn't
  one — this is what makes "the value at the start of this month" answerable
  without a separate snapshot mechanism, exactly as §4.5 anticipated);
  `availableZoomLevels` (which levels are worth offering, based on the
  tracker's own length — `> 366/31/7` days respectively); and
  `subPeriod(for:asOf:)`, which returns the calendar-aligned `DateInterval`
  for a level via `Calendar.current.dateInterval(of:for:)`, clamped to the
  tracker's own `startDate`/`endDate` so a zoomed window never extends past
  the tracker's real period even when the calendar month/year/week does.
- **`TrackerPace.swift`**: the existing `pace(actualValue:asOf:)` body was
  extracted into a private `Tracker.computePace(startDate:endDate:
  startingValue:totalAllowance:direction:actualValue:asOf:)` so a new
  `pace(actualValue:asOf:zoomLevel:)` overload could reuse the exact same
  math against a sub-period's bounds/allowance/local-starting-value instead
  of duplicating it. `.overall` (or a level with no valid sub-period for the
  given `asOf`) falls back to the plain full-period `pace`. The original
  `pace(actualValue:asOf:)` signature/behavior is untouched, so every
  existing caller (widgets, watch, Shortcuts, `PaceCrossingNotifier`,
  `MenuBarStatusView`, etc.) needed no changes.
- **`RingsView`** gained a `zoomLevel: ZoomLevel = .overall` parameter,
  threaded into its internal `pace` computation — the default keeps every
  pre-existing caller (list rows, widgets) unaffected.
- **`TrendChartView`** gained `zoomLevel`/`now` parameters and a `window`
  computed property; every place it used to read `tracker.startDate`/
  `endDate`/`startingValue`/`sortedReadings` directly now reads the
  zoom-scoped equivalents (`window.start`/`.end`, `windowStartingValue`,
  `windowedReadings`) instead — the reference line, trend line, and plotted
  points are all scoped to the sub-period when zoomed, not just the ring.
- **`TrackerDetailView`** gained a segmented zoom-level picker (`Picker` +
  `.pickerStyle(.segmented)`) above the rings, shown only when
  `tracker.availableZoomLevels.count > 1` (per §7.1: "a week-long money
  tracker has no need for a 'This year' tab"). Selecting a level re-scopes
  the rings, both figure cards (via the zoomed `pace`), the days-remaining
  caption (now takes an `until:` parameter, defaulting to the tracker's own
  `endDate` but passed the zoomed sub-period's end when zoomed), and the
  trend chart together — exactly the "whole dashboard" re-scoping §7.1 asks
  for, not just the ring.
- **Tests**: `ZoomLevelTests.swift` (13 tests) covers `availableZoomLevels`,
  `subPeriod` (calendar alignment and clamping at both ends of the
  tracker's period), `actualValue(atOrBefore:)`, and the zoomed `pace`
  overload (allowance scaling, local starting value from history, period
  bounds, and the `.overall`/not-offered-level fallback paths).

**Not built**: per-widget/complication zoom-level configuration (§8.1's own
note that this "isn't built yet"). Threading a zoom-level `AppEnum`
parameter through `SelectTrackerIntent` would need changes to two separate
extension targets' (`WiggleRoomWidgets`, `WiggleRoomComplication`) own build
settings — this environment has no Xcode GUI and past sessions only touch
`.pbxproj` targets/schemes via the scripted `xcodeproj`-gem route (decision
#17), which is a heavier, riskier change than justified for this pass. A
widget/complication instance always shows a tracker's `.overall` pace for
now — see **Suggested next steps**.

### §5.5 Manual-entry reminder notifications — built

- **`Tracker.reminderCadenceDays: Int?`** — `nil` means no reminder;
  otherwise the number of days between reminders. Only meaningful for a
  manual-entry tracker.
- **`ReminderScheduler.swift`** (new, `WiggleRoomShared/`) — `sync(_:)`
  schedules (after requesting notification authorization) or cancels a
  single repeating `UNNotificationRequest` per tracker, keyed by
  `"reminder-<tracker.id>"` so re-syncing replaces rather than duplicates a
  prior request. Uses `UNTimeIntervalNotificationTrigger(timeInterval:
  repeats: true)` rather than a calendar trigger — a calendar trigger can
  only repeat on regular calendar components (daily, weekly, ...), not an
  arbitrary "every N days" cadence, but a time-interval trigger can.
- **`TrackerStore`** calls `ReminderScheduler.sync`/`.cancel` from
  `addTracker`/`deleteTracker`, and `saveChanges(reminderTracker:)` gained
  an optional parameter so an edit can re-sync the reminder only when a
  tracker (as opposed to, say, a reading edit via `LogReadingView`) was
  what changed.
- **`AddTrackerView`** gained a "Reminder" section (None/Daily/Weekly/Every
  2 Weeks/Monthly picker), shown only when the tracker being created/edited
  is manual-entry (`isManualEntrySelected`).

### Two known-gap fixes

- **macOS `ReadingHistoryView` had no delete affordance** (flagged as an
  open gap in two prior sessions) — macOS `List` has no swipe gesture and
  this view has no `selection:` binding to drive `EditButton`'s usual
  Delete-key path, so a per-row `.contextMenu` with a destructive "Delete
  Update" button was added, macOS-only (`#if os(macOS)`).
- **`AddTrackerView`'s budget footer text** always described a mileage-lease
  example for increasing trackers regardless of the unit actually chosen
  (flagged as a cosmetic gap previously). Now branches on
  `Tracker.isCurrencyUnit(unit)` for both directions and interpolates the
  chosen unit into the non-currency wording, instead of a hardcoded "mile".

### A real environment issue hit while testing this session (unresolved)

28. **Every test that calls `ModelContext.fetch(_:)` against an in-memory
    `ModelContainer` reliably crashes on this machine's new "iPhone 17 Pro
    (iOS 27)" Simulator** (created fresh this session via `xcrun simctl
    create`, since no iOS 27.0 device existed yet — the deployment target
    was raised to 27.0 in the previous session, but no matching simulator had
    been made). The crash is `NSInternalInconsistencyException: "No eligible
    connection available"`, thrown from inside CoreData's
    `-[NSSQLCore executeRequest:withContext:error:]`, every time, directly
    preceded by a `[CloudKit] ... CKAccountStatusNoAccount` recovery-attempt
    log line even though the container involved is a plain local
    `isStoredInMemoryOnly: true` one with no CloudKit configuration at all —
    this looks like the *app's own* real CloudKit-backed container (built at
    launch by `WiggleRoomApp.swift`, since the test host launches the real
    app) failing its account-status check and somehow leaving the process's
    shared CoreData/SQLite connection pool in a bad state for *every*
    context, not just its own. **This hits every test that constructs a
    `TrackerStore` or `ManualEntryProvider` and calls `context.fetch`**
    (`TrackerStoreTests`, `ManualEntryProviderTests` — both go through
    `TrackerStore.init` → `fetchOrCreateManualEntrySource` →
    `context.fetch(FetchDescriptor<ConnectedSource>())`), reproducing
    consistently across three separate full test-suite runs this session.
    **It does not hit any test that only constructs model objects directly
    without going through a `ModelContext` fetch** — `TrackerPaceTests`,
    `TrackerTests`, and the new `ZoomLevelTests` all build `Tracker`/
    `ConnectedSource`/`ValueSnapshot` as plain unmanaged objects and never
    call `.fetch`, and all passed cleanly, every run. This strongly points
    at a genuine SwiftData/CoreData bug or mis-signed-in-iCloud interaction
    specific to this early iOS 27.0 Simulator runtime, **not** a regression
    in any of this session's code changes (none of the affected tests
    exercise anything touched this session — zoom levels or reminders). Not
    root-caused or fixed this session; flagging for whoever picks this back
    up rather than guessing further. Worth trying: a different/non-fresh
    simulator, an older iOS 27.0 runtime point release if one becomes
    available, or running with no iCloud account signed into the Simulator's
    Settings app at all (vs. whatever ambient state this one has).

### Verifying this session's changes

`xcodebuild ... -only-testing:WiggleRoomTests test` on the "iPhone 17 Pro
(iOS 27)" simulator described above, run three times this session. Every
run: `TrackerPaceTests` (25), `TrackerTests` (22), `WiggleRoomTests` (2), and
the new `ZoomLevelTests` (13) passed with 0 failures — the zoom-level model
logic (`ZoomLevel`, `Tracker.availableZoomLevels`/`subPeriod`/
`actualValue(atOrBefore:)`, the zoomed `TrackerPace` overload) is confirmed
correct by these. `ManualEntryProviderTests` and `TrackerStoreTests` could
not be verified in this environment at all, blocked by the environment issue
in gotcha #28 above — this predates and is unrelated to this session's
changes (neither suite touches zoom levels or reminders), but it does mean
`TrackerStore.addTracker`/`.deleteTracker`'s new `ReminderScheduler.sync`/
`.cancel` calls specifically were not exercised by an automated test this
session; they were verified by code review only (the calls mirror the
existing `WidgetCenter.shared.reloadAllTimelines()` pattern in the same
methods). Not verified live in a simulator UI either: the zoom-level
picker's actual on-screen appearance/interaction, or a reminder notification
actually arriving — this environment has no interactive way to watch a
notification fire or tap through a running app's UI.

**Full builds confirmed clean** (0 errors) for both platforms with this
session's changes, including the embedded extensions that compile
`WiggleRoomShared` (where most of the zoom-level/reminder code lives):
`xcodebuild -scheme WiggleRoom -destination 'platform=iOS Simulator,...'
build` (`WiggleRoomWidgets`, `WiggleRoomWatch`, `WiggleRoomComplication` all
embedded and signed) and `xcodebuild -scheme WiggleRoom -destination
'platform=macOS' -allowProvisioningUpdates build`.

## 2026-09-17 chart/scheduling/completed-state overhaul

A long same-day session covering six areas requested together: chart
visualization, scheduling/reminders, the tracker-details "Current Balance"
UI, a first-class completed-tracker state, cross-platform data freshness,
and widget/ring visual polish — followed by several rounds of bug fixes and
refinements against real usage/screenshots. Unlike prior sessions recorded
in this file, **this environment had no Xcode/simulator/`xcodebuild` access
at all** — every change was verified with `swiftc -parse` (syntax only, no
type-checking or SDK-availability checking) plus careful reading, not a real
build. Treat everything below as reviewed-but-not-built-and-run until
confirmed in Xcode; a few specific verification gaps are called out inline.

### Chart & ring redesign

- [`TrendChartView.swift`](../src/WiggleRoom/Views/TrendChartView.swift) —
  the "Pace" reference line is renamed **"Target"** everywhere (legend,
  Swift Charts series/value labels) to match the rest of the app's own
  "Target Right Now" language, and is now the visually dominant line (solid,
  `lineWidth: 3.5`) while the trend line is now **dotted** and distinct.
  `trendPoints` no longer fits one straight line across the whole window —
  it's an **expanding-window regression**, re-fit at each historical
  reading and evaluated at that reading's own date, so the line traces
  gentle curves as the trend shifts rather than being rigid; the final
  point projects the full-data fit to the window's end (the "expected final
  balance"), rendered with `interpolationMethod: .catmullRom`. Two new
  subtle "carried-forward" points (`liveNowPoint`/`liveEndPoint`) hold the
  latest reading's value flat out to "now" and to the window's end, so the
  actual-data series visually spans the whole period even with sparse
  readings — both skipped once the tracker has completed.
- [`RingsView.swift`](../src/WiggleRoomShared/RingsView.swift) — went
  through **two** passes this session. The first attempt shrank the
  outer/inner ring gap to `lineWidth * 0.15` and added a self-closure
  overlap arc, but the gap change was wrong: it didn't account for each
  ring's stroke extending `lineWidth / 2` to either side of its own
  center-line radius, so the two rings' *painted bands* actually overlapped
  each other rather than just sitting close together. Fixed by separating
  `ringGap` (the radius inset, which must exceed a full `lineWidth` to keep
  the bands apart at all) from a new `bandGap` (`lineWidth * 0.12`, the
  actual visible gap once that's accounted for) — see the type's own doc
  comment for the exact geometry. The self-closure overlap (a short extra
  arc drawn on top of a ring's own start once it's ≥98% closed, matching
  Apple Fitness) is unrelated to that bug and was correct as designed; only
  its threshold moved slightly (0.999 → 0.98) to fire a touch before an
  exact 100% match. The below-the-rings color-key **legend was removed
  entirely** (`legend`/`legendItem` deleted) — the figure cards elsewhere on
  the same screen already use the identical two colors, so it was pure
  repetition.

### One shared, end-aligned scheduler replacing three separate timers

- [`TrackerUpdateScheduling.swift`](../src/WiggleRoomShared/Models/TrackerUpdateScheduling.swift)
  (new) — a pure, dependency-free function,
  `nextUpdateDate(after:until:interval:)`, that walks backward from a
  tracker's `endDate` in fixed steps rather than forward from "now", so the
  *last* computed tick always lands exactly on `endDate` instead of
  possibly overshooting by up to a full interval. `nextWidgetReloadDate`
  wraps it with a budget-friendly ~15 minute cadence that tightens to 1
  minute in the final hour. Deliberately has no `Timer`/`WidgetKit`/SwiftUI
  dependency so it can be reused later by a real background fetch for a
  connected source (Starling/Tesla) — "when should we next poll?" is the
  same question either way.
- [`AutoUpdateTicker.swift`](../src/WiggleRoomShared/State/AutoUpdateTicker.swift)
  (new) — an `@Observable` class wrapping a 1-second poll (same trick the
  old dashboard timer used — a `let`-stored `Timer.publish` gets recreated
  every SwiftUI body re-evaluation, so anything relying on it surviving
  longer than that interval silently never fires) that reschedules itself
  via the function above against the nearest relevant tracker end date.
  Replaced the three independently-coded ~60s-ish timers that used to live
  separately in `TrackerDetailView` (1s + manual 60s rollover),
  `TrackerListView`/`WatchTrackerDetailView` (bare 60s), and `MacRootView`
  (a separate 60s timer for the Dock badge).
- Widget/complication timeline reload policy
  ([`TrackerTimelineProvider.swift`](../src/WiggleRoomWidgets/TrackerTimelineProvider.swift),
  [`TrackerComplicationProvider.swift`](../src/WiggleRoomComplication/TrackerComplicationProvider.swift))
  now uses `nextWidgetReloadDate` instead of a flat `now + 1h` — the direct
  fix for widgets lagging the main app by several minutes.
- Reminder cadence (§5.5) is now minute-granularity: `Tracker.reminderCadenceDays`
  became **`reminderCadenceMinutes`** (a straight in-place rename — a
  one-time reset of anyone's existing reminder selection, judged acceptable
  for a solo-dev app under active iteration), with new **Every Minute** and
  **Hourly** options in [`AddTrackerView.swift`](../src/WiggleRoom/Views/AddTrackerView.swift)'s
  picker alongside Daily/Weekly/Every 2 Weeks/Monthly.
  [`ReminderScheduler.swift`](../src/WiggleRoomShared/ReminderScheduler.swift)'s
  trigger interval math changed accordingly (floored at 60s — `UNTimeIntervalNotificationTrigger`'s
  own OS-enforced minimum for a repeating trigger), and it now also refuses
  to (re-)schedule a reminder for a completed tracker, cancelling any
  existing one instead.

### Completed-tracker state (new)

- [`Tracker.swift`](../src/WiggleRoomShared/Models/Tracker.swift) gained
  `isCompleted(asOf:)` — the single source of truth for "this tracker's
  period has ended," replacing ad hoc `now >= endDate` checks scattered
  around the codebase. Used to: disable the update button/pull-to-refresh
  action and the `LogReadingIntent` Shortcut, cancel reminders, hide the
  zoom picker, and switch the dashboard into a completed presentation.
- [`CompletedBadge.swift`](../src/WiggleRoomShared/CompletedBadge.swift)
  (new) — a small shared "Completed" pill, shown on the tracker list, the
  dashboard, the watch list, and every widget/complication family.
- [`TrackerDetailView.swift`](../src/WiggleRoom/Views/TrackerDetailView.swift)'s
  completed presentation replaces the live figure cards with a single
  final-stats card (`completedSummary`) pinned to the tracker's own
  `endDate` via a new `finalPace` computed property, rather than whatever
  "now" happens to be well after closing — so re-opening a long-finished
  tracker always shows the same final numbers.
- The extra-large widget mirrors the same completed swap (final stats
  instead of the live "Target Right Now" figure).

### Tracker-details UI restructure

Went through several rounds of layout changes based on live feedback, so
the *current* end state is what matters, not the intermediate ones:

- The date range and days-remaining line moved around a few times —
  **current layout**: the date range lives in `.navigationSubtitle` (pinned
  under the nav title, stays visible while scrolling), and
  days-remaining sits as its own line beneath the Current
  Balance/Target Right Now cards (or the completed summary). The date
  range only includes a time of day when the tracker actually has one set
  — new `Tracker.hasExplicitTimes` (mirrors `AddTrackerView`'s own "Set
  specific times" toggle logic) — rather than always printing a
  meaningless "12:00 AM" for the plain-date default.
- The "Update" button moved out from inside the Current Balance card (both
  figure cards now share identical visual weight) and, on iOS/iPadOS, was
  **replaced entirely by a pull-to-refresh gesture** (`.refreshable` on the
  dashboard's `ScrollView`) — deliberately the same gesture that's meant to
  double as a future connected source's refresh action, not just today's
  manual log-reading sheet. A small hint ("Pull down to update"/"Pull down
  to refresh", wording depends on `tracker.isManualEntry`) sits on the same
  line as the live-update countdown, above the rings — `.refreshable`'s own
  system control only appears mid-pull, so without a persistent hint
  there'd be no on-screen indication the gesture exists. macOS, which has
  no pull gesture, keeps the explicit button (still labeled "Update Current
  Balance").
- The top-of-screen countdown is now worded **"Refreshes in Xs"** (was
  "Updates in Xs"), matching the pull-to-refresh gesture it announces.
- The Target Right Now card's caption changed twice this session: first
  from the static "£X should remain at the end" to a new, universal "Final
  target will be £X" (`Tracker.projectedFinalValue`, at the same visual
  weight as Current Balance's "£X left in this budget"), driven by explicit
  feedback that "balance" doesn't fit every tracker type.
- The dashboard's default zoom level (§4.5) is now **This Week**, not
  Overall, whenever a tracker is long enough to offer zoom levels at all —
  set in a custom `init` so the very first render is already correct.

### Real bugs fixed this session (not just polish)

- **Pace-status grace zone hid small overages as "under budget"/green** —
  [`TrackerPace.swift`](../src/WiggleRoomShared/Models/TrackerPace.swift)'s
  `status` used to let a shortfall under 1% of `totalAllowance` still read
  as `.good`, so a tracker whose actual value sat visibly *below* its own
  target figure could still say "Under Budget" in green. Reported against a
  real screenshot (balance £840, target £846.53, shown green/"under
  budget"). Fixed: any `difference < 0` is now at least `.warning`; the
  1–5%/>5% split (unchanged) only decides warning vs. bad from there. See
  the updated §3.2 in the build spec — this reverses part of decision #26
  below and is the new source of truth for that threshold.
- **Increasing trackers showed the wrong sign and wording for "over"** —
  a higher-than-target actual value (the bad/over case for an increasing
  tracker, e.g. mileage) was displayed with a **minus sign** (via
  `displayDifference`'s raw, unoriented `difference`) and labeled "Needs
  Attention" instead of reading as "over budget." Fixed: `displayDifference`
  negates `difference` first for an increasing tracker, so "over" (bad, a
  higher number) shows without a minus and "under" (good, a lower number)
  shows with one; `PaceStatus.label(for:)` now gives an increasing tracker
  "Slightly Over Budget"/"Over Budget" wording (matching the decreasing
  budget case) regardless of currency, keeping only a decreasing
  non-currency tracker on the fully neutral "On Track"/"Needs Attention".
- **Mileage (and other non-currency) trackers showed decimal places** —
  `Tracker.formattedValue` now only shows the 2-decimal-when-fractional
  rule for currency units; a non-currency unit always rounds to a whole
  number.
- **Widget/complication "choose a tracker" picker showed "Tracker: Tracker"
  instead of the real selection, and could get stuck on "Loading" then
  revert with nothing selectable** —
  [`SelectTrackerIntent.swift`](../src/WiggleRoomWidgets/SelectTrackerIntent.swift)
  (and the [`WiggleRoomComplication` copy](../src/WiggleRoomComplication/SelectTrackerIntent.swift))'s
  `entities(for:)` — the call that resolves an *already-selected* tracker's
  real name — was using `WidgetDataStore.fetchAllTrackers()`'s short ~2-4s
  wait, meant to protect WidgetKit's own timeline-render budget, not the
  interactive configuration UI's own much longer budget. Now shares
  `fetchAllTrackersForConfiguration()` with `suggestedEntities()`.
  Separately, [`WidgetDataStore.swift`](../src/WiggleRoomShared/WidgetDataStore.swift)'s
  `fetchAllTrackersForConfiguration()` used to let a single transient fetch
  error partway through its 25s polling window abort the whole call and
  discard whatever had already been found — now only the very first fetch
  is fatal; a mid-poll failure is treated as "nothing new this round." Also
  widened the "a tracker is already visible" case from a 10s wait to the
  same generous 25s as the cold-start case, since a genuinely *new*
  tracker's first CloudKit sync doesn't know or care whether other
  trackers already existed. **Not independently confirmed against a real
  device this session** (no simulator access) — if a just-created tracker
  still doesn't appear promptly after these fixes, it may be a real
  CloudKit propagation delay outside the app's control rather than a
  remaining code bug; worth checking device logs (see decision #25's
  `log stream` technique) before assuming otherwise.

### Not touched this session (known gaps)

- [`MenuBarStatusView.swift`](../src/WiggleRoom/Views/MenuBarStatusView.swift)
  (macOS menu bar item) still reads `PaceStatus.label(for:)` directly, so
  it picks up the increasing-tracker wording change above for free, but
  wasn't separately reviewed/laid out against it.
- Per-widget/complication zoom-level configuration (§4.5/§8.1's long-open
  item) — still not built; unrelated to this session's scheduling changes.
- No Starling/Tesla provider work — still just manual entry, per every
  prior session's scope note.
- Two changes landed the same day **outside** this session, directly in
  `project.pbxproj`/`Info.plist`/a new `xcshareddata/xcodecloud/` folder —
  removing visionOS/Mac Catalyst from the project's supported platforms and
  device families, and adding Xcode Cloud configuration. Neither is
  elaborated on in this file beyond this note, since neither came from an
  agent session with context to record.

### Verifying this session's changes

No `xcodebuild`/simulator access in this environment at all (a change from
every prior session recorded above) — verification was `swiftc -parse`
(syntax only) on every changed file, plus careful reading and cross-checking
of call sites. New/updated unit tests were **written** for the new logic —
`TrackerUpdateSchedulingTests` (new), and additions to `TrackerPaceTests`
(the grace-zone fix, the increasing-tracker sign/wording flip) and
`TrackerTests` (`isCompleted`, the periodRemainingText minutes branch, the
non-currency decimal fix) — but **not run**; there is no way to invoke
`xcodebuild test` from here. Nothing in this session was verified live in a
simulator or on device either — the chart's curve rendering, the ring
overlap/gap visuals, the pull-to-refresh gesture, the completed-state UI,
and the widget picker fixes all need a real build to confirm. Build in
Xcode and run the test suite before trusting any of this further; if
anything doesn't compile or behave as described, that's expected until
someone with real Xcode access does that pass.
