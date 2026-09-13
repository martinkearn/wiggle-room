# Ringet — Progress Notes

Status snapshot for picking this work back up. Written 2026-09-13, after the
first four build phases. Read alongside [ringet-build-spec.md](ringet-build-spec.md) —
this file tracks *what's actually been built*, not the spec itself.

## What's implemented

### §4.1 / §4.3 — Tracker model & pace calculations
- [`Tracker.swift`](../src/Ringet/Models/Tracker.swift) — the `Tracker` struct and `TrackerDirection` enum. `recurrence: RecurrenceRule?` exists only as a placeholder type (§4.4 isn't designed yet).
- [`TrackerPace.swift`](../src/Ringet/Models/TrackerPace.swift) — `Tracker.pace(actualValue:asOf:)` computing periodHours/hoursElapsed/consumedSoFar/expectedConsumedByNow/difference/target-today in one call, so a single snapshot of "now" stays consistent. `hoursElapsed` uses `timeIntervalSince` (wall-clock seconds), which is DST-safe by construction.
- Tests: [`TrackerPaceTests.swift`](../src/RingetTests/TrackerPaceTests.swift) — both directions, ahead/behind pace, period-start/end edges, one DST-transition regression test (derives the expected day length from `TimeZone.nextDaylightSavingTimeTransition`, so it's not tied to a hardcoded date).

### §5.1 / §5.2 / §5.5 — Source provider abstraction & manual entry
- [`SourceProvider.swift`](../src/Ringet/Providers/SourceProvider.swift) — the protocol (`providerId`, `displayName`, `requiresConnection`, `listAvailableTargets`, `fetchCurrentValue`, `logManualReading`).
- [`SourceTarget.swift`](../src/Ringet/Models/SourceTarget.swift), [`ConnectedSource.swift`](../src/Ringet/Models/ConnectedSource.swift), [`ValueSnapshot.swift`](../src/Ringet/Models/ValueSnapshot.swift) — supporting models.
- [`ManualEntryProvider.swift`](../src/Ringet/Providers/ManualEntryProvider.swift) — a Swift `actor` backing manual entry with an in-memory store (not persisted yet — see §6 below). Each target's implicit id embeds its owning connection's id, since `fetchCurrentValue`/`logManualReading` only take a target, not a connection.
- No Starling or Tesla provider exists yet.

### §7.1 / §5.2 — Screens
- [`TrackerListView.swift`](../src/Ringet/Views/TrackerListView.swift) — root list, empty state, "+" as the primary toolbar action (front and center, per explicit feedback), a gear icon as a secondary action opening Connected Sources.
- [`AddTrackerView.swift`](../src/Ringet/Views/AddTrackerView.swift) — name/unit/direction (segmented control)/period/budget/source. See **Key decisions** below for the Source-picker design — this file has had the most back-and-forth and its doc comment explains the current model in detail.
- [`ConnectedSourcesView.swift`](../src/Ringet/Views/ConnectedSourcesView.swift) + [`AddSourceView.swift`](../src/Ringet/Views/AddSourceView.swift) — Settings → Connected Sources (§5.2). `AddSourceView` is a deliberate stub ("Coming Soon") — no Starling/Tesla setup UI exists yet.
- [`TrackerStore.swift`](../src/Ringet/State/TrackerStore.swift) — in-memory `@Observable` app state (trackers, the fixed manual-entry source, added real sources). This is a placeholder for SwiftData (§6) — see **Next up**.

## Key decisions worth knowing before you touch this again

1. **Manual Entry is not a "source" the user can multiply.** It's a single fixed choice (`TrackerStore.manualEntrySource`), separate from `TrackerStore.addedSources` (real external connections — Starling, Tesla, etc., currently always empty). Settings → Connected Sources only ever lists `addedSources`. This came from explicit user correction mid-build — the first draft modeled manual entry as an ordinary, user-creatable `ConnectedSource`, which was wrong.
2. **A manual tracker gets its own dedicated reading log automatically.** There's no user-facing "which log" picker for manual entry — `AddTrackerView.save()` calls `ManualEntryProvider.addTarget(displayName: trackerName, ...)` behind the scenes. This replaced an earlier design with a visible "New Log…" picker, simplified away once it became clear each manual tracker naturally wants its own independent log.
3. **"Add New Source…" lives inside the tracker's Source picker**, pushing the same `AddSourceView` Settings uses — a shortcut so a user mid-way through creating a tracker doesn't have to back out to Settings first. ⚠️ **Not fully click-verified** — see Known gaps below.
4. **Budget field wording**: "Allowance" → "Budget", "Total allowance" → "Total budget", with direction-aware inline hints and a footer worked example. This was a direct fix for real confusion: `startingValue` is the *budget's own* starting point (e.g. 3000 for a £3000 budget), not literally whatever a real bank account happens to read — that distinction wasn't clear before.
5. **Cross-platform build gotchas**: this project builds for iOS *and* macOS (the test suite runs against `platform=macOS` for speed). `.keyboardType` and `.navigationBarTitleDisplayMode` are UIKit-only — both are wrapped in small `#if os(iOS)` helper extensions (`decimalKeyboardIfAvailable()`, `inlineNavigationBarIfAvailable()`). Watch for this with any new UIKit-only modifier.
6. **Xcode 16 file-system-synchronized groups**: this project doesn't use manually-maintained `.pbxproj` file lists — any `.swift` file dropped into `src/Ringet/` or `src/RingetTests/` is picked up automatically. No project-file surgery needed when adding files.
7. **Running `xcodebuild` in this environment**: the active `xcode-select` developer directory is Command Line Tools, not Xcode. Prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (don't run `xcode-select -s` globally — that's a system-wide change). Simulator builds went through the `mcp__Claude_Code_iOS_Simulator__build` tool rather than raw `xcodebuild` for the app itself.

## Known gaps / things to verify by hand

- **"Add New Source…" tap-through is unverified.** The Source picker in `AddTrackerView` correctly *displays* both "Manual Entry" and "Add New Source…" (confirmed visually), and the code follows the same `onChange` + `.navigationDestination(isPresented:)` pattern already confirmed working for `ConnectedSourcesView → AddSourceView`. But repeated attempts to tap that specific menu item in the iOS Simulator (via the automation tool, without an accessibility inspector available) landed on the wrong row or missed the popup entirely. Worth 30 seconds on a real device or in Xcode's own simulator to confirm the tap actually pushes `AddSourceView` and correctly reverts the picker selection afterward.
- No SwiftUI view has unit/UI tests — verification so far has been manual (simulator screenshots) plus unit tests on the non-UI layers (`TrackerPace`, `ManualEntryProvider`, `TrackerStore`). Consider adding `ViewInspector`-style tests or UI tests if this grows much further.

## Explicitly out of scope so far (per spec, deferred on purpose)

- §4.4 Recurrence, §4.5 multi-tracker source sharing/dedup, §4.6 zoom levels
- §5.3 Starling, §5.4 Tesla providers (only the manual provider exists)
- §6 SwiftData/CloudKit persistence — everything today lives in an in-memory `TrackerStore`, wiped on relaunch
- §3 ring visualization, §7.2 macOS-specific UI, §7.3 watchOS, §8 widgets
- Editing/deleting trackers (only create + list exist)

## Suggested next steps (not a commitment, just a sane order)

1. Persistence (§6, SwiftData) — everything currently resets on relaunch, which will get old fast for continued manual testing.
2. Tracker detail/dashboard screen showing the derived pace (`Tracker.pace(...)`) against a live/logged reading — right now `TrackerPace` is fully implemented and tested but nothing in the UI displays it yet.
3. A "Log a reading" flow for manual trackers (referenced by §5.5 but not built — there's currently no way to actually add a reading to a manual tracker's target from the UI).
4. Edit/delete tracker.

## Verifying the app still builds

```bash
cd src
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Ringet.xcodeproj -scheme Ringet -destination 'platform=macOS' \
  -only-testing:RingetTests test
```

25 tests should pass (`TrackerPaceTests`, `ManualEntryProviderTests`, `TrackerStoreTests`, plus the two scaffold tests in `RingetTests`).
