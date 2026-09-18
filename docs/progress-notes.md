# Wiggle Room — Progress Notes

Status snapshot for picking this work back up. **Last updated 2026-09-18**,
after **2026-09-18 Update Current Value's macOS layout fixed — collapsed
value field, old-style date picker** — reported straight after the
Update History fix directly below, from a screenshot: the value entry
field showed a large "£0" but the actual focusable/highlighted box was a
narrow sliver next to it, and the Date field looked like an old-fashioned
stepper-and-text control ("like a '90s web browser"). Root cause for the
value field: `.fixedSize(horizontal: true, vertical: false)` sizes a
`TextField` to fit its *bound string's* content, not its placeholder —
with `valueText` starting as an empty string (by design, so typing
doesn't insert ahead of a stray placeholder digit, same reasoning as
§5.3's Starling starting-value fix), the field's real interactive width
collapsed to almost nothing while the "0" placeholder still painted at
full size outside that tiny box — exactly the look in the screenshot.
Fixed with an explicit `.frame(minWidth: 80, maxWidth: 160)` and
`.textFieldStyle(.plain)` instead of `fixedSize`. The date field had no
`.datePickerStyle` set at all, defaulting on macOS to the old
field-and-stepper look rather than a modern compact pill — added
`.datePickerStyle(.compact)` there and, for consistency, to
`AddTrackerView`'s Start/End date pickers too (same missing style, not
yet reported but the same underlying gap). `xcodebuild build` succeeded
on both `platform=macOS` and `generic/platform=iOS`. **Not yet visually
re-verified** — same caveat as the entry below, no macOS screen
automation available this session; worth a real look after rebuilding.
Before that, **2026-09-18 Update History rendering blank on macOS** — reported
right after the foreground auto-refresh removal below (real multi-device
testing): the Starling tracker's Update History sheet showed nothing on
macOS while iOS correctly listed its readings. Worked through by
elimination rather than guessing at a sync gap first: `TrackerDetailView`'s
"Update History" menu item is itself gated on `!tracker.sortedReadings
.isEmpty`, so the fact the user could open this screen at all already
proved macOS's local `tracker` had readings — ruling out "the readings
never synced" as the explanation and pointing at the screen's own
rendering instead. `ReadingHistoryView` had no explicit sizing anywhere,
and its empty-state fallback (`WiggleEmptyState`) is pure `Spacer()`-driven
with no intrinsic height of its own — a combination that, evidently, can
render a macOS sheet's content area with nothing visibly showing rather
than a clean empty state or a visible list. Fixed with an explicit
`.frame(minWidth: 360, minHeight: 320)` on the screen and `.listStyle(.plain)`
on the reading list (`TrackerListView`'s own list already used `.plain`
elsewhere; `ReadingHistoryView`'s never had a style set at all). `xcodebuild
build` succeeded on both `platform=macOS` and `generic/platform=iOS`.
**Not yet visually re-verified** — this session has no macOS screen
automation available (deliberately avoided after an earlier incident
this same project, see the 2026-09-18 Settings-redesign entries below,
where blind coordinate-based clicking mis-hit other apps), so this fix
is code-reasoned rather than screenshot-confirmed; worth a look on a
real rebuild to confirm the sheet now shows the readings.
Before that, **2026-09-18 Foreground auto-refresh removed entirely — fully
manual, always-refresh-on-open** — a direct, deliberate follow-up once
real multi-device testing (the same session that verified sync end-to-end
for manual trackers, Connected Sources, and a Starling tracker, all
working correctly) surfaced the actual insight: with the app open on more
than one device at once, each device's `TrackerDetailView`/
`WatchTrackerDetailView` ran its own independent flat-45s (30s on watch)
ticker, uncoordinated with any other device's — meaning the real number
of Starling requests being made for one tracker scaled with however many
devices happened to have its detail screen open, not just one. Removed
the ticker (`AutoUpdateTicker`) from both detail screens entirely — no
more periodic auto-fetch, no more live "Refreshes in Xs" countdown. The
screen still **always refreshes once when first opened** (on appear) and
whenever a manual pull-to-refresh (iOS)/Refresh or Update Current Balance
button (macOS/watchOS) is used — those were kept exactly as they already
worked — but nothing polls in between while the screen just sits open.
`now` (driving the ring, Target Right Now, days-remaining) is now a plain
`@State` set on appear and refreshed again after any successful
fetch/logged reading, rather than continuously advancing — figures are
exact as of the last open/refresh, not live-ticking. **Background
refresh is completely unaffected** — `BackgroundRefreshScheduler`'s
time-of-day-banded cadence and per-tracker burst detection (§5.3) keep
working exactly as before, independent of whether any foreground screen
is open anywhere. `xcodebuild build` succeeded on both `platform=macOS`
and `generic/platform=iOS` (covers the Watch target too). **Not yet
verified on real devices** — worth specifically confirming the
always-refresh-on-open behavior feels right in practice, and that
request counts (visible in Connected Sources per the same day's earlier
work) actually drop now that multiple open devices no longer each poll
independently. Before that, **2026-09-18 A real, verifiable "same code?" indicator in Settings**
— requested directly out of this session's own debugging pain: mid-way
through diagnosing why a Mac's Reset App Data wasn't reaching iOS, there
was no way to confirm both devices were actually running the fixes just
made, short of trusting "yes I rebuilt it." Landed on a git commit hash
(plus a `-dirty` suffix for uncommitted changes) rather than a build
date/timestamp — explicitly rejected once proposed, since two devices
built minutes apart from the *identical* commit would show different
"versions" and answer the wrong question (what matters is whether the
code matches, not when it was compiled).

**Getting the value into the app took three real attempts**, each hitting
a genuine Xcode build-system wall, all now documented directly in the
pbxproj build phase's own comment so the reasoning survives without
needing this log:
1. **Write directly into Info.plist via PlistBuddy**, in a script phase
   positioned after Xcode's own Info.plist generation. Failed silently at
   first — the write never took effect, no error surfaced — traced to
   **User Script Sandboxing** (`ENABLE_USER_SCRIPT_SANDBOXING = YES`,
   on by default in this Xcode version): a script phase can only write
   paths it explicitly declares as `outputPaths`. Declaring the Info.plist
   path as an output fixed the silent failure, but broke the build
   outright: `error: invalid task ... with mutable output but no other
   virtual output node` — a hard rule that two different build steps
   (here, this script and Xcode's own "ProcessInfoPlistFile") can never
   both be declared producers of the same file.
2. **Generate a Swift source file** (`GeneratedGitInfo.swift`) into
   `$(DERIVED_FILE_DIR)` instead, a brand-new file with exactly one
   producer — the classic, normally-reliable pattern for exactly this
   kind of build-time constant. Compiled fine as a file on disk (confirmed
   it was actually being written, correctly, every time), but the
   generated type was never visible to the rest of the target:
   `error: cannot find 'GeneratedGitInfo' in scope`. This project uses
   Xcode's newer **file-system-synchronized source groups** (folders
   auto-included as project membership, rather than explicit
   `PBXSourcesBuildPhase` file lists) — and, empirically, that mechanism
   doesn't pick up a script-generated derived `.swift` file as a compile
   input the way a classic explicit-file-list Sources phase would, even
   though the file inputs the underlying build tasks compile from is not
   different fundamentally.
3. **Write a plain text resource** (`git-commit.txt`) directly into the
   built app's Resources folder instead — sidesteps both problems at
   once: it's a brand-new file (satisfies the single-producer rule) that
   nothing needs to "discover" as a compile input (read at runtime via
   `Bundle.main.url(forResource:withExtension:)` instead). This is what
   shipped. `AppBuildInfo.swift` moved from `WiggleRoomShared` into the
   `WiggleRoom` app target specifically, since only that target's build
   has the generating script phase — the widget/watch/complication
   targets never needed this and would have failed to compile a reference
   to a type/resource that only exists for the main app's own build.

The script phase (`Write Git Commit Resource`, `WiggleRoom.xcodeproj/
project.pbxproj`, the `WiggleRoom` target's last build phase) declares
`.git/HEAD` and `.git/index` as its inputs, so Xcode's real dependency
analysis re-runs it whenever the checked-out commit or the working tree's
staged/unstaged state actually changes — no `alwaysOutOfDate` needed (and
that setting turned out to be flatly incompatible with declaring a real
output path anyway, per the Info.plist attempt above). Surfaced in
Settings on both platforms (macOS's `GeneralSettingsView`, iOS's
`SettingsView`) right under the existing Danger Zone section.

`xcodebuild build` succeeded on both `platform=macOS` and `generic/
platform=iOS` (confirmed the resource file lands correctly in both
built products, with matching content), and the existing
`StarlingRequestBudgetTests`/`StarlingAPIClientTests` suite still passes
unchanged. **Not yet verified end-to-end on a real device** — worth
confirming the "Build" row actually renders correctly once installed, and
that it reads identically on both the Mac and the iPhone once both are
rebuilt from the same commit. Before that, **2026-09-18 Fixed a real
crash: Reset App Data could crash the app
if a tracker's detail screen was open elsewhere** — the very first real
use of the Reset App Data feature (added the same day, entry below) hit
a genuine fatal crash on macOS: "This backing data was detached from a
context without resolving attributes," in `Tracker.direction.getter`,
called from `TrackerDetailView.body`. Root cause: `TrackerDetailView`
holds `tracker` as a direct object reference rather than re-resolving it
from a live query, so SwiftData's fine-grained Observation re-invokes its
`body` whenever that tracker changes *anywhere* — including a delete
happening in Settings (a separate window) while the main window's detail
view was still showing that same tracker. Reading a property on a
model whose backing data has been detached from its context is a hard,
unrecoverable crash, not something catchable. Fixed by checking
`tracker.modelContext == nil` (becomes `nil` once deleted) as the very
first thing `body` does, showing a plain "Tracker Deleted" placeholder
instead of touching any other property. Applied the identical guard to
`WatchTrackerDetailView`, which has the same structural risk. `xcodebuild
build` succeeded on both `platform=macOS` and `generic/platform=iOS`
(which also builds the Watch target). **Not yet re-verified against a
real Reset App Data run with a detail screen open** — the user hit the
original crash via a screenshot of Xcode's debugger, not yet confirmed
the fix resolves it in practice. Before that, **2026-09-18 Reset App Data
+ a proper iOS Settings screen** — a direct follow-up to the
schema-mismatch incident below, while cleaning up
its corrupted test data by hand surfaced two more real gaps: some
trackers couldn't even be *selected* in the macOS sidebar (right-click
"Delete Tracker" added, bypassing `selection` entirely — see `MacRootView`),
and there was no in-app way to wipe everything and start clean short of
deleting records one at a time. Added `TrackerStore.resetAllData()` (wipes
every tracker/reading, every real connected source, every Starling request
log entry — the fixed Manual Entry source is left alone) behind a
destructive confirmation, in Settings → General on macOS. Doing the iOS
equivalent raised a design question — iOS had no Settings screen at all,
just a gear icon opening Connected Sources directly — and the answer was
to build a real one: `SettingsView` (new, iOS-only), a List with
Connected Sources as its own row/section and a Danger Zone section below,
mirroring macOS's General/Connected Sources split instead of continuing
to bolt admin features onto whichever screen was nearest. `ConnectedSourcesView`'s
iOS body lost its own `NavigationStack` wrapper since it's now pushed
inside `SettingsView`'s stack rather than presented standalone. `xcodebuild
build` succeeded on both `platform=macOS` and `generic/platform=iOS`
(including a real gotcha: `TrackerListView.swift` compiles unconditionally
on macOS too even though never used there at runtime — `SettingsView`
being iOS-only needed an explicit `#if !os(macOS)`/`#else EmptyView()`
split at that one call site to keep the macOS build green). Before that,
**2026-09-18 Fixed a real, serious data-corruption bug: mismatched
SwiftData schemas across processes sharing the CloudKit store** — see the
full incident writeup at the bottom of this file before touching the data
model again. Short version: adding `StarlingRequestLogEntry` to the main
app's schema without adding it everywhere else that opens the same
CloudKit+App Group store (the widget extension, the Watch app, the
Shortcuts intent handler) left those processes running an older,
mismatched schema against the same on-disk/CloudKit store the main app
had already migrated — a real, documented way to trigger store
corruption, not just a theoretical risk. The user reported exactly the
matching symptoms in the field: a duplicate tracker appearing with no
user action, then **all trackers and all connected sources disappearing
entirely** roughly half an hour later, confirmed happening across
multiple synced devices. All data lost was test data, not anything
irreplaceable. **Fixed**: every `Schema([...])` in the codebase
(`WiggleRoomApp`, `WidgetDataStore`, `IntentDataStore`,
`WiggleRoomWatchApp`, plus the in-memory preview ones for consistency)
now lists the exact same model types, with a comment at each site naming
every other site that must stay in sync. **This is now a standing rule,
not a one-off fix**: any future new `@Model` type must be added to *all
six* `Schema([...])` call sites in the same change, or this can recur.
`xcodebuild build` succeeded for the `WiggleRoom` scheme (which embeds
the Watch app and widget extension, so this covers all of them) on both
`generic/platform=iOS` and `platform=macOS`. **Not yet verified against
a real device reinstall** — the user still needs to rebuild and install
this fix on every device, ideally close together in time (quit the app
everywhere first) to avoid a transition window where an old, still-
mismatched build and this fixed build are both touching the same synced
store at once. Before that, **2026-09-18 "Starling Requests Today" moved
again, onto the Connected Source screen; fixed a real actor-isolation
warning; guarded against duplicate trackers from a double-tap Save** —
three small
follow-ups in one pass. First: the "shown on every tracker" placement
from the entry directly below turned out not to be quite right either —
follow-up direction was that this admin/diagnostic figure belongs with
the *connection* it describes (Connected Sources → the specific Starling
source), not repeated identically on every tracker that happens to use
it, and that Settings is fine as long as it's the right (source-specific)
pane. Removed from `TrackerDetailView` again; restored on macOS's inline
`SourceEditorCard` (`ConnectedSourcesView`) and iOS's `AddSourceView`,
both gated to `source.providerId == "starling"`. Second: fixed a real
Xcode warning ("Converting function value of type '@MainActor @Sendable
(Date) -> ()' to '@Sendable (Date) -> Void'") that showed up across every
target (`WiggleRoom`, `WiggleRoomWatch`, `WiggleRoomComplication`,
`WiggleRoomWidgets`) — this project defaults every unannotated
declaration to `@MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION` build
setting), so `StarlingRequestLogger.record(at:)` was implicitly
`@MainActor`-isolated, mismatching `StarlingRequestBudget`'s plain
`@Sendable` `onRequestLogged` closure type. Fixed by typing the closure
as `@MainActor @Sendable (Date) -> Void` and making `consumeSlot()`
`async` so it can `await` into it, rather than fighting the project's
isolation default inside `StarlingRequestLogger`. Third: the user
reported a tracker appearing twice in the macOS sidebar — investigated
`AddTrackerView.save()` and found no debounce against a fast double
click/tap firing it twice (no async gap of its own for SwiftUI's normal
touch-debouncing to help with), a real, if narrow, path to a genuine
duplicate `Tracker` record. Added an `isSaving` guard, disabling the Save
button for the duration of a save. **Note**: this guards against a
*future* duplicate from this specific cause; it does not explain or
remove whichever existing duplicate the user saw, which — if caused by
this bug — would need finding and deleting by hand (or telling me its
name/dates so I can help identify it). `xcodebuild build` succeeded, with
no remaining warnings from any of these files, on `platform=macOS` and
`generic/platform=iOS`. Before that, **2026-09-18 "Starling Requests
Today" moved out of Settings, onto every Starling tracker's own detail
screen** — a same-day follow-up to
the cross-device-count fix directly below: the user pointed out this is
tracker-contextual information ("shown in the context of any and all
starling trackers, not on general settings... not applicable to manual
trackers or other sources"), not app configuration, so it had no business
living in Settings → General on macOS or the Connected Source detail
screen on iOS. Removed from both; added instead as a new card on
`TrackerDetailView`, shown only when that specific tracker's own source
is Starling (`isStarlingTracker`), on every platform uniformly — so a
manual tracker or (once built) a Tesla one never shows it. The figure
itself didn't change (still the same synced `StarlingRequestLogEntry`
query, still resets at local midnight) — only where it's surfaced. The
card's own caption makes clear the number is shared across every Starling
tracker (it's a per-token budget, not per-tracker), not implying each
tracker has its own separate quota. `xcodebuild build` succeeded on both
`platform=macOS` and `generic/platform=iOS`. **Unrelated pre-existing
flake noticed while re-running the test suite**: `ManualEntryProviderTests`
fails locally with "No eligible connection available" (a SwiftData
in-memory `ModelContainer` error) — confirmed present at the prior commit
too (before any of this session's changes), so it isn't something this
session introduced; not investigated further, worth a look in its own
right at some point. Before that, **2026-09-18
"Starling Requests Today" is now a real, synced, cross-device count** — the rate-limit insight added earlier the same day
only ever counted the current device's own in-memory requests since its
last relaunch; the user pointed out that since the Starling token is
CloudKit-synced (§5.3), the same PAT is typically active from more than
one device at once, so the count needs to be genuinely shared. Added a
new synced `StarlingRequestLogEntry` model (one record per real request,
inserted via `StarlingRequestBudget`'s new `onRequestLogged` hook →
`StarlingRequestLogger`), queried live via `@Query` and filtered to
`Calendar.current.isDateInToday(_:)` so it resets at local midnight. Also
surfaced this on iOS for the first time, on the Connected Source detail
screen (`AddSourceView`) — iOS has no Settings scene equivalent to
macOS's. Flagged explicitly and up front: Starling's API has no way to
report usage from other apps/scripts sharing the same token, so that part
of the ask isn't achievable — the caption text says so. Before that,
**2026-09-18 Estimated Final Balance: card and chart now share one
clamp, not two** — a same-day follow-up fix (below): the first fix for
this feature (a minimum-data-span guard, described further down) turned
out not to be the real problem, since the user still saw the card's
number wildly disagree with where the chart's own trend line visually
ended, even once that guard was passing. Root cause was structural, not
a threshold: the chart clamps its trend line's endpoint into its Y-axis
range before drawing (an existing workaround for a Swift Charts
rendering bug), while the card computed the same fit's raw, unclamped
value — same underlying regression, two different displayed numbers by
design. Fixed by extracting `Tracker.plausibleTrendRange` (starting
value, fixed target, every logged reading, padded 10%) as the one clamp
both `Tracker.estimatedFinalValue` and `TrendChartView.yDomain` now
derive from, so the card always states the exact number the trend line
visually ends at. `xcodebuild build` (iOS) succeeded; not yet re-verified
on a real device/simulator against the actual reported case.
Before that, **2026-09-18 Feature/bug backlog pass: Starling Spaces, refresh
cadence redesign, Estimated Final Balance (+ same-day fix), and a run of
smaller fixes** — see that entry (bottom of file) for the full rundown:
widget "by" wording, the widget resize/reconfigure blank fixed, Starling
Spaces as tracker targets, a cross-tracker balance cache, the Edit
Tracker Save-button bug fixed, the Estimated Final Balance feature (plus
a same-day fix for an over-extrapolated figure it could show), a Done
button on Update History, rate-limit insight in Settings + clearer
rate-limit error text, "Reconnect" renamed to "Save", and — the biggest
piece — a full redesign of Starling's refresh cadence (flat 45s
foreground, time-of-day-banded + per-tracker-burst background). Before
that, **2026-09-18 Settings redesign: sidebar + inline editing, not tabs
+ sheets** — replaced the icon-tab-bar Settings window with a fixed
sidebar (`SettingsRootView`) and moved Connected Sources to fully inline
editing on macOS (no pop-ups at all), added a "Connected"/"Not
Connected" status badge and an unhidden, growable token field (a
deliberate, user-confirmed choice — see that entry's security note), and
made the menu bar ring keep its number while dropping its status word.
Verified via real screenshots on both macOS and iOS this time. Before
that, **2026-09-18 Settings window padding, fixed and actually verified
on real screenshots** — this session gained real Accessibility/Screen
Recording permission mid-way through and used it to drive the actual
running app and screenshot it directly, rather than inferring layout
from code; found and fixed a real dead-space bug in the Reconnect sheet
(a forced `minHeight` fighting `Form`'s own fill-to-height behavior) and
gave the Settings window's `TabView` an explicit, deliberate size instead
of AppKit's implicit "largest tab" heuristic. Before that, **2026-09-18
Reconnect sheet had no Cancel; trimmed the PAT footer;
menu bar item now survives closing the main window** — a same-day
follow-up fixing a missing Cancel button on the new macOS Reconnect
sheet, shortening its token-field footer text, and adding an
`NSApplicationDelegate` so the menu bar item (and the app) survives
closing the main window rather than quitting with it. Before that,
**2026-09-18 macOS Starling requests were silently blocked by App
Sandbox (missing network entitlement)** — a real, previously-undiscovered
bug found and fixed this session (not the earlier Keychain→CloudKit
token-storage fix regressing), plus **2026-09-18 Settings screen looked
broken; consolidated all macOS config into Settings** just before it (the
macOS Settings window's Add/Reconnect Source flow switched from a broken
`NavigationLink` push to the app's usual sheet pattern, and which tracker
the menu bar shows moved from a submenu in the dropdown into a new
Settings → General pane). Before those, **2026-09-18 Fix macOS build:
`.listSectionSpacing` unavailable + `SourceProvider` not
class-constrained** — see that entry below for the first session in this
project's history with a real Xcode/simulator toolchain, so fixes from
that point on are actually build-verified, not just re-read. Before that,
**2026-09-18 Move Delete Tracker out of the crowded "…" menu** — on
the dashboard's "…" menu, Edit Tracker and Delete Tracker (destructive) sat
directly adjacent with no visual separation, a real mis-tap risk on iOS.
Delete now lives in its own section at the bottom of the Edit Tracker
screen instead, set apart from the fields above by a deliberately large
gap (`.listSectionSpacing`), with the same destructive confirmation dialog
as before. Before that, **2026-09-18 Menu bar tracker is now
user-configurable** — the macOS
menu bar item defaulted to whichever tracker started most recently with no
way to change it; added a "Show in Menu Bar" submenu (shown once there's
more than one tracker) that pins a specific tracker via `@AppStorage`,
falling back to the old most-recently-started default when nothing's
pinned or the pinned tracker gets deleted. Before that, **2026-09-17
Surface the bound account read-only, in two places** —
confirmed a tracker's connected source/account is already fully locked
after creation (only the initializer ever sets those fields), then made
the binding visible rather than editable: a read-only "Account" row in
Edit Tracker, and a small source/account caption on the Tracker Detail
dashboard, both resolved once and never on the 30s refresh tick. Before
that, **2026-09-17 Fix Starting-value auto-fill clobbering manual entry**
— a Starling tracker backdated to reflect an earlier balance (£639) had
its starting value silently overwritten with the balance *at save time*
(£615) once the user picked the Starling account, because the auto-fill
feature from two sessions ago overwrote unconditionally rather than only
filling a blank field; fixed to never touch a field the user has already
typed into, and `startingValueText`'s pre-filled `"0"` default (which
turned typing "639" into "6390") is now an empty string like every other
numeric field. Before that, **2026-09-17 Connected Source management +
token storage moved off Keychain** — real multi-device testing surfaced a
Starling source that
synced (via CloudKit) but showed "Not connected" on a second device,
because its token lived in the Keychain, a separate sync system (iCloud
Keychain) with its own per-device toggle and its own lag. Per the user's
explicit direction ("everything should use the same sync system"), the
token now lives directly on `ConnectedSource.credentialToken`, synced by
the same CloudKit path as everything else — no more Keychain dependency
anywhere in the app. Settings → Connected Sources also gained real
reconnect (re-enter a token in place) and remove (blocked while any
tracker still uses that source) actions, which is also the practical fix
for "there's no way to edit sources." Before that, **2026-09-17 Fix Swift
type-checker crash in ReadingHistoryView** — the first real build attempt
on this branch failed outright ("Failed to produce diagnostic for
expression") from a ternary mixing a function reference and `nil` at an
`.onDelete(perform:)` call site, a known Swift compiler crash trigger;
fixed by extracting it into an explicitly-typed computed property. Before
that, **2026-09-17 Starling reading dedup +
Update History for real sources** — `TrackerStore.refreshFromSource` now
skips logging a reading when the fetched value hasn't changed (was
flooding the trend chart with overlapping same-value points every 30s
tick, reading as "no dots" — they were there, just too dense to tell
apart), and "Update History" is
now visible (read-only) for any tracker with readings, not just manual
ones. Before that, **2026-09-17 Zoom levels removed** — §4.5's whole feature (the
`ZoomLevel` type, the picker, sub-period scoping everywhere it touched:
`Tracker`, `TrackerPace`, `RingsView`, `TrendChartView`,
`TrackerDetailView`) was pulled out of the app entirely, cleanly rather
than hidden/disabled, after real-device testing showed its default "This
Week" scoping producing wrong-looking headline dashboard figures with no
on-screen indication they were scoped. Every tracker's dashboard/chart/
widget always shows its real, whole-period figures now — build-spec.md
§4.5 is rewritten to record the original idea for a future redesign rather
than deleted outright. Before that, **2026-09-17 Starling real-device
testing: findings and a fix** — the user connected a real Starling account
and tested end to end, surfacing three real findings (an inner-ring
opacity-fade bug for small settled values, the zoom-scoping issue just
described, and the app's intentional linear-pace model producing a nonzero
under/over-budget figure from minute one even with zero spending — the
last one isn't a bug) plus a shipped fix (Starting value now auto-fills
from the picked account's live balance). Before that, **2026-09-17 Starling
implementation: first real Xcode feedback** — the user's own Xcode caught a
deprecated `BGTaskScheduler.submit` call and two default-main-actor-isolation
errors in the Starling code below, both fixed (see that entry) — merged
alongside the separately-developed **2026-09-17 App Group migration**
landed on this same branch in the
meantime, which moved the app/widgets/watch/complication/Shortcuts onto a
shared App Group container as the real fix for widget staleness (the
scheduling-interval tightening from earlier that day turned out to be only
a partial mitigation). Before the Xcode-feedback fixes, **2026-09-17
Starling connected-source implementation** — Starling is now a real,
code-level `SourceProvider` (Keychain-backed token storage,
`StarlingAPIClient`, the 30s-foreground/5-minute-background refresh
cadence with a Low Power Mode backoff and a client-side daily rate-limit
budget, a real Add Source token-entry flow, and a live account-target
picker in Add Tracker) — but **still not fully verified by a compiler**,
since neither environment that touched it has had a Swift toolchain at
all; read that entry's "Verifying this session's changes" before trusting
any of it. That session followed three same-day docs-only planning
sessions further below (**2026-09-17 Low Power Mode backoff decision**,
**Starling rate-limit research follow-up**, and **Starling refresh-cadence
planning**) that made the decisions the implementation followed — no code
changed in any of those three. Before all of that, a long same-day session
(see **2026-09-17
chart/scheduling/completed-state overhaul**) redesigned the trend chart and
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

## 2026-09-17 App Group migration

A same-day follow-up specifically to fix widget/complication staleness for
real, after the scheduling-interval tightening earlier that day turned out
to be a smaller mitigation, not a fix — the user asked for the App Group
architecture change previously declined earlier in the day.

- [`AppGroup.swift`](../src/WiggleRoomShared/AppGroup.swift) (new) — a
  single shared constant, `AppGroup.identifier = "group.martinkearn.WiggleRoom"`,
  used everywhere a `ModelConfiguration` is built so the literal string only
  exists in one place.
- Every `ModelConfiguration(schema:cloudKitDatabase:)` call site now also
  passes `groupContainer: .identifier(AppGroup.identifier)` — the four
  places a container gets built:
  [`WiggleRoomApp.swift`](../src/WiggleRoom/WiggleRoomApp.swift) (both the
  CloudKit config and its local-only fallback),
  [`WiggleRoomWatchApp.swift`](../src/WiggleRoomWatch/WiggleRoomWatchApp.swift)
  (same, both configs),
  [`WidgetDataStore.makeContainer()`](../src/WiggleRoomShared/WidgetDataStore.swift)
  (shared by `WiggleRoomWidgets` and `WiggleRoomComplication`), and
  [`IntentDataStore.makeContainer()`](../src/WiggleRoom/Intents/IntentDataStore.swift)
  (Shortcuts/Siri). CloudKit sync (`cloudKitDatabase: .automatic`) is
  unchanged everywhere — the App Group only affects *where the local file
  lives*, not cross-device sync, which is still CloudKit's job.
- `com.apple.security.application-groups` (`group.martinkearn.WiggleRoom`)
  added to all four targets' entitlements files:
  `WiggleRoom.entitlements`, `WiggleRoomWidgets.entitlements`,
  `WiggleRoomWatch.entitlements`, `WiggleRoomComplication.entitlements`.
- **This environment now has working `xcodebuild` access** (a change from
  earlier the same day — `xcode-select` now points at the full `Xcode.app`
  rather than the command-line-tools-only path it did before), which let an
  iOS Simulator build be confirmed directly. It does **not**, however, have
  access to the signed-in Apple ID/account context Xcode.app's own GUI
  process has (confirmed: `~/Library/MobileDevice/Provisioning Profiles/`
  is root-owned and unwritable from this session, and `xcodebuild
  -allowProvisioningUpdates` fails with "No Accounts: Add a new account in
  Accounts settings" even after the user added the App Groups capability
  through Xcode's own Signing & Capabilities UI and confirmed clean builds
  there for both iOS and macOS). **Registering a brand-new capability like
  this always needs a real pass through Xcode's GUI with a signed-in
  account** — same lesson as CloudKit's own capabilities earlier in this
  project's history (see the "CloudKit — enabled and confirmed working"
  section above) — command-line `-allowProvisioningUpdates` alone is not
  sufficient for a capability that has never been registered before, at
  least not from a session without real account access.
- **Verification**: `swiftc -parse` clean on every changed file, entitlements
  plists validated for well-formed XML. The iOS Simulator build succeeded
  via `xcodebuild` from this session directly. The macOS build (which
  actually signs and would have caught a broken App Group setup) could not
  be verified from this session due to the account-access gap above — **the
  user confirmed a clean build for both iOS and macOS themselves, in Xcode,
  after adding the App Groups capability to all four targets** — that's the
  verification this change actually rests on, not anything run from this
  session.

## 2026-09-17 Starling refresh-cadence planning (no code changed)

Docs-only session, prompted by the user asking to confirm build-readiness for
the Starling integration and to set a specific refresh cadence, before any
implementation. No Swift files were touched.

**What was checked**: an audit of the repo confirmed there is still no
Starling code at all — no HTTP client, no auth flow, no models for
Starling accounts/balances (`AddSourceView.swift` remains an explicit
"Coming Soon" stub, matching every prior session's scope note). It also
confirmed what "the existing refresh mechanism" actually is:
`AutoUpdateTicker` (`src/WiggleRoomShared/State/AutoUpdateTicker.swift`) plus
`TrackerUpdateScheduling` (`src/WiggleRoomShared/Models/TrackerUpdateScheduling.swift`)
is a **display-recompute** scheduler (currently a 60s in-app tick,
900s/60s widget reload), not a network poller — there is no periodic data
fetch anywhere in the app yet. Pull-to-refresh (`TrackerDetailView.swift`'s
`.refreshable`, wired to `handleUpdateGesture()`) exists and works for
manual-entry trackers, but its auto-fetch-source branch is a documented
no-op pending a real provider. No `BGTaskScheduler`/`BGAppRefreshTask`
usage exists anywhere, and the background-fetch `Info.plist`/entitlement
config hasn't been confirmed either way.

**Decision recorded** (see build-spec.md §5.3, §12): when built, Starling
(and, per the user's request, every source generally) should poll every
**30 seconds while the app is open**, by retuning and extending the
existing `AutoUpdateTicker`/`TrackerUpdateScheduling` mechanism to actually
trigger a fetch on tick rather than only a display recompute — not a new,
separate polling mechanism. Manual refresh should reuse the existing
pull-to-refresh gesture rather than adding a new button. Background refresh
should run every **5 minutes**, which needs `BGTaskScheduler` set up from
scratch (nothing currently configured). This replaces the build spec's
previous "15–30 minute widget background refresh, not continuous polling"
line — that line is now out of date and has been rewritten.

**Known gap called out explicitly, not resolved**: Starling's actual API
rate limits are still unresearched (build-spec.md §12 flagged this before
today too). A 30-second foreground poll is a meaningfully more aggressive
cadence than the old spec language, so this needs confirming against
current Starling developer docs before implementation starts, especially
given §4.4's requirement to share one fetch across multiple trackers
pointed at the same connected source. Also still missing and now spelled
out in §12: a Keychain read/write wrapper (only the schema field exists),
any HTTP client/retry scaffolding, and confirmation of the background-fetch
entitlement/`Info.plist` state.

### Verifying this session's changes

No code changed — this was a docs-only planning session. Nothing to build
or run; the build-spec.md and this file are the only diffs.

## 2026-09-17 Starling rate-limit research follow-up (no code changed)

Same-day follow-up to the session above, answering the open rate-limit
question it deliberately left unresolved. Still no code changed.

**Research**: `developer.starlingbank.com` was unreachable directly (egress
blocked in this environment), so the numbers below are cross-verified via
the Home Assistant Starling integration's own incident report
([home-assistant/core#73225](https://github.com/home-assistant/core/issues/73225))
plus independent web search confirmation, not fetched from Starling's own
docs — **re-confirm at build time**. Personal access tokens are limited to
**5 requests/second and 1000 requests/day** (Starling tightened this in
2022 specifically because third-party integrations, including Home
Assistant's, were over-polling); a breach returns HTTP 429 with a
`Retry-After` header. 5 req/s is trivial to stay under at a 30s cadence;
**1000/day is the real constraint** a naive implementation could hit in a
few hours if each 30s tick makes more than one API call (accounts list +
balance + spaces, per §5.3, is three).

**Decision refined** (see build-spec.md §5.3 for the full mitigations
list): the 30s cadence stands, but scoped to **whichever tracker detail
screen is actually on-screen** (`TrackerDetailView` /
`WatchTrackerDetailView` / macOS's detail pane), not the whole app —
confirmed against the existing code, `AutoUpdateTicker` is already
`@State`-owned per-view (`TrackerDetailView.swift:56`,
`WatchTrackerDetailView.swift:18`, `MacRootView.swift:24`,
`TrackerListView.swift:35` each hold their own instance), so this is a
natural fit rather than a new mechanism — the list view's own ticker
should stay display-only and not gain a fetch. Required mitigations before
this cadence is safe to ship, not optional cleanup: cache the accounts
list instead of re-fetching it every tick (one request per tick, not
three), share one fetch across multiple trackers on the same connected
source (already required by §4.4), track a rolling 24h request count
client-side and back off before hitting the cap, and always honor
`Retry-After` on 429. None of this is built yet — still no Starling
provider code exists at all (see the session above).

### Verifying this session's changes

No code changed — research and a spec refinement only.

## 2026-09-17 Low Power Mode backoff decision (no code changed)

Same-day follow-up, closing out a question the user raised about whether
the refresh cadence should back off under Low Power Mode, Sleep Focus, or
StandBy. No code changed.

**Decision** (see build-spec.md §5.3): back off the foreground 30s
detail-screen poll (widen to roughly 60–120s, exact figure left to tune at
build time) whenever `ProcessInfo.processInfo.isLowPowerModeEnabled` is
true, observed live via `NSProcessInfoPowerStateDidChange`. Foreground-only
— the 5-minute `BGAppRefreshTask` background path needs no app-side change,
since iOS already deprioritizes background task scheduling itself under
Low Power Mode/low battery.

Sleep Focus and StandBy were both considered and explicitly **not**
adopted as backoff signals: Sleep Focus has no public API to detect
specifically (`INFocusStatusCenter`'s `focusStatus.isFocused` only reports
that *some* Focus is active — Sleep, Work, and Do Not Disturb are
indistinguishable — and needs a user authorization prompt to use at all,
which isn't worth it for what it buys); StandBy isn't a distinct
app-observable state at all — it's a display mode while locked/charging,
and is already covered by the existing foreground-vs-background split (the
30s poll only runs while a detail screen is genuinely on-screen).

### Verifying this session's changes

No code changed — a scoped decision recorded in the spec only.

## 2026-09-17 Starling connected-source implementation

Implements the Starling integration itself, following the four planning
sessions immediately above this one. **Critical caveat up front**: this
environment had no Swift toolchain at all — not even `swiftc`, which prior
sessions at least had for a syntax-only check. Every file below was
verified only by careful manual re-reading (checking actor isolation,
Decimal literal precision, Swift pattern-matching over `Error`, and a
second pass specifically hunting for the kind of mistake a compiler would
catch), never compiled, never run, never tested in a simulator or on
device. Treat this as a strong first draft, not confirmed-working code —
build in Xcode and run the test suite before trusting it further.

**New files** (all under `src/WiggleRoomShared/` unless noted):

- `Security/SecureTokenStore.swift` — `SecureTokenStore` protocol,
  `KeychainTokenStore` (real Keychain, `kSecAttrSynchronizable` set per
  §11), `InMemoryTokenStore` (previews/tests — `KeychainTokenStore` itself
  isn't unit-tested here, since a plain XCTest run doesn't reliably have
  real Keychain access without a signed, entitled test bundle).
- `Providers/StarlingRequestBudget.swift` — an `actor` tracking a rolling
  24h request count against the researched 5/req/s, 1000/req/day limits
  (§5.3/§12), refusing new requests as the daily count approaches the
  limit and recording a cool-down on a real 429's `Retry-After`. Shared
  app-wide via `StarlingProvider.sharedBudget` (in-memory, resets on
  relaunch — a known simplification, see build-spec.md §12).
- `Providers/StarlingAPIClient.swift` — direct `URLSession`-based client
  for `GET /api/v2/accounts` and `GET /api/v2/accounts/{uid}/balance` only
  — the Spaces/savings-goal endpoint was never implemented, since its
  shape was never confirmed against current Starling docs (still an open
  item). Maps 401/403 → invalid token, 429 → rate-limited (+ records the
  budget cool-down), other non-2xx → a generic HTTP error, decode failures
  → a decoding error.
- `Providers/StarlingProvider.swift` — the actual `SourceProvider`
  conformance. Each instance is bound to one `ConnectedSource` at init
  (resolves its token from Keychain via `credentialKeychainKey`);
  `listAvailableTargets(for:)` takes its own connection argument instead
  so it also works against a draft, not-yet-persisted connection during
  Add Source setup. Starling has no write scopes, so
  `logManualReading(target:value:date:)` always throws
  `manualLoggingNotSupported`.
- `src/WiggleRoom/Background/BackgroundRefreshScheduler.swift` (iOS-only,
  deliberately placed in the app's own folder rather than the shared one
  compiled into every extension target, since `BGTaskScheduler` is
  app-only) — registers a `BGAppRefreshTask` handler
  (`martinkearn.WiggleRoom.starlingRefresh`), requests the next run on
  launch and on every backgrounding, and on fire loops every non-manual,
  non-completed tracker through `TrackerStore.refreshFromSource`.

**Changed files**:

- `TrackerStore.swift` — now `@MainActor`-isolated (needed since
  `refreshFromSource(_:)` is a genuine async network call, and every other
  method here already touches `ModelContext` directly). Every existing
  call site was already effectively on the main actor (App `init`s,
  `@MainActor`-marked Intent code, `#Preview` blocks), so this shouldn't
  change behavior, only make the isolation explicit. Added
  `provider(for:)` (resolves the right `SourceProvider` for a tracker's
  connected source — manual, Starling, or `nil` for anything else),
  `listAvailableTargets(for:)` (same resolution, but from a bare
  `ConnectedSource` before any tracker exists — used by the new target
  picker), and `refreshFromSource(_:)` (fetches + logs a reading the same
  shape as a manual one, so history/zoom levels don't care where a reading
  came from).
- `AutoUpdateTicker.swift` — added a settable `interval` (default 60,
  unchanged for existing callers like `TrackerListView`; `TrackerDetailView`
  and `WatchTrackerDetailView` now set 30 on appear) and an
  `effectiveInterval` that triples it under
  `ProcessInfo.isLowPowerModeEnabled` (the Low Power Mode backoff decided
  two sessions ago).
- `TrackerDetailView.swift` — the ticker now actually triggers
  `store.refreshFromSource` on tick for a non-manual, non-completed
  tracker (previously display-recompute only); `handleUpdateGesture()`
  (the pull-to-refresh action) now really refreshes instead of no-op'ing
  for an auto-fetch source; a new `refreshErrorMessage` state surfaces a
  distinct error line (§8.4, `WiggleRoomColors.error`) on failure; the
  macOS button (previously manual-only) now shows for every tracker type,
  wording/icon switching between "Update Current Balance" and "Refresh".
- `WatchTrackerDetailView.swift` — same 30s-tick-triggers-a-fetch wiring,
  plus a new Refresh button alongside the existing manual-only Log button
  (no error-state UI here yet — see the known gaps below).
- `AddSourceView.swift` — was a "Coming Soon" stub; now a real form
  (name + personal access token), validated by actually calling
  `listAvailableTargets` before persisting anything — a rejected/expired
  token is never silently stored as a working connection, and its
  Keychain entry is deleted again if validation fails.
- `AddTrackerView.swift` — previously hard-blocked saving with a real
  (non-manual) source selected ("This source isn't supported yet"). Now
  has a live target-picker section (`targetPickerSection`,
  `loadAvailableTargetsIfNeeded()`) that fetches the selected source's
  accounts via `store.listAvailableTargets(for:)` whenever the source
  selection changes, skipped entirely when editing an existing tracker
  (its source can't change) so as not to spend a Starling request on
  nothing.
- `WiggleRoomApp.swift` — registers/schedules `BackgroundRefreshScheduler`
  in `init()` (iOS only), and reschedules on every `scenePhase` transition
  to `.background`.
- `Info.plist` — added `BGTaskSchedulerPermittedIdentifiers` with the
  background task's identifier (`UIBackgroundModes`'s `fetch`/`processing`
  entries already existed from an earlier session, confirmed still
  present).

**New tests** (`src/WiggleRoomTests/`): `StarlingRequestBudgetTests`
(threshold/cool-down/24h-aging behavior, using a settable `TestClock`
reference type rather than capturing a mutable `var` in the actor's
`now` closure — the latter wouldn't satisfy `@Sendable` under strict
concurrency), `StarlingAPIClientTests` (a `StubURLProtocol`-backed
`URLSession` — no real network — covering account/balance decoding,
401→invalidToken, 429→rateLimited-with-cooldown, and the daily budget
refusing a call before it's even made), `StarlingProviderTests` (the
`notConnected`/`manualLoggingNotSupported` paths, using
`InMemoryTokenStore` — never real Keychain), `SecureTokenStoreTests`
(`InMemoryTokenStore` roundtrip only), and additions to
`TrackerStoreTests` (`provider(for:)` resolution across manual/Starling/
unknown provider ids, `refreshFromSource` no-op for manual and
`notConnected` for an unconnected Starling tracker).

**Known gaps, called out rather than silently left** (also in
build-spec.md §5.3/§12): Spaces/savings-goal targets aren't supported
(only top-level accounts); two trackers on the same Starling account still
poll it independently rather than sharing one fetch (§5.3's mitigation 2
from two sessions ago); the request budget is in-memory only and resets on
relaunch; there's no way to remove/disconnect a Starling source from
Settings once added; the watch app has no on-screen error state for a
failed refresh (iOS/macOS do).

### Verifying this session's changes

**Not verified in any real sense.** No Swift toolchain of any kind was
available — no `swiftc`, no `xcodebuild`, no simulator. Every file was
written carefully and re-read for common mistakes (actor-isolation
mismatches, a `Decimal` literal that would round-trip through `Double` and
silently fail an equality test, `switch`-over-`Error` pattern syntax,
whether every new file's target membership would actually resolve via the
project's synchronized-folder groups), but none of that is a substitute
for an actual build. The next session with real Xcode access should, in
order: build every target (`WiggleRoom` iOS/macOS/watchOS, widgets,
complication), run the full test suite including the five new/extended
test files above, then manually connect a real Starling personal access
token and confirm the account picker, balance fetch, pull-to-refresh, and
30s live-updating tick all actually work end to end before trusting any
of this as done.

## 2026-09-17 Starling implementation: first real Xcode feedback

The user opened the branch in actual Xcode after the implementation above
and reported real compiler warnings — the first genuine build-tool signal
this whole Starling effort has had, since every prior session in this
chain had no Swift toolchain at all. Two real issues, both fixed here:

- **`BGTaskScheduler.shared.submit(_:)` is deprecated as of iOS 27** in
  favor of `submitTaskRequest(_:completionHandler:)` (or an async
  `submitTask` variant). `BackgroundRefreshScheduler.scheduleNext()`
  (`src/WiggleRoom/Background/BackgroundRefreshScheduler.swift`) now calls
  the completion-handler form, still discarding any error the same way the
  old `try?`-style call did — a submission failure (Simulator, capability
  not granted) is expected and non-fatal either way. Confirms this
  project targets a genuinely new-enough SDK (iOS 27) that `submit` had
  already been deprecated by the time this was written from a toolchain-less
  environment with no way to know that.
- **Default main-actor isolation broke `StarlingProvider.init`'s default
  argument values.** This project apparently has Swift's "default actor
  isolation = MainActor" setting enabled (a real, current Xcode feature —
  every declaration in the module is MainActor-isolated unless marked
  `nonisolated`). Under that setting, a function's *default argument
  expressions* are evaluated in the caller's (non-isolated) context, not
  the callee's — so `tokenStore: SecureTokenStore = KeychainTokenStore()`
  and `budget: StarlingRequestBudget = StarlingProvider.sharedBudget` as
  default *argument* values were both invalid, even though the
  initializer they belonged to is itself `@MainActor`. Fixed by defaulting
  both to `nil` and resolving them inside the initializer's body instead
  (which *is* MainActor-isolated, since that's where `self` gets built) —
  see `StarlingProvider.init` in `StarlingProvider.swift`. Also marked
  `KeychainTokenStore` and `InMemoryTokenStore`
  (`Security/SecureTokenStore.swift`) explicitly `nonisolated`, since
  neither has any real reason to be main-actor-confined (plain synchronous
  Keychain/in-memory calls) and leaving them to the module's implicit
  default risked the same class of issue resurfacing elsewhere, or worse,
  breaking their conformance to `SecureTokenStore`'s synchronous
  (non-`async`) protocol requirements if the compiler ever treated them as
  actor-isolated.

**Not independently re-verified** — still no Swift toolchain in this
environment. These fixes address exactly the diagnostics reported (a
screenshot of Xcode's issue navigator showing the deprecation warning and
two isolation errors, repeated identically across the WiggleRoom,
WiggleRoomWatch, WiggleRoomComplication, and WiggleRoomWidgets targets
since `StarlingProvider.swift` is shared), reasoned through carefully, but
the next real Xcode build is what actually confirms them clean. If
`StarlingProvider.swift` still shows isolation warnings after this, the
module's default-isolation setting may work differently than assumed here
(e.g. it could be per-target rather than whole-module, or `nonisolated` on
a class might need to additionally propagate to individual members) —
worth checking the target's Swift Language Version / "Default Actor
Isolation" build setting directly rather than guessing further blind.

### Verifying this session's changes

Not verified by a compiler — see above. Reasoned fixes only, based on the
exact diagnostic text reported from a real Xcode session.

## 2026-09-17 Starling real-device testing: findings and a fix

The user connected a real Starling account and tested end to end, catching
three distinct issues worth separating clearly:

1. **The inner ring looked empty on a freshly-added tracker.** Traced to
   real numbers (self-reported: starting value and total budget both
   £639, nothing spent since creation): with essentially nothing consumed
   yet, the inner ring's fraction is genuinely tiny, and
   `RingsView.progressOpacity` fades any fraction below its
   `dotFadeThreshold` (3.5%) proportionally — a fade meant only to mask a
   transient animation artifact during the drain/refill "recycle"
   animation, but which (per its own doc comment's stated intent) ends up
   applying permanently to any small **settled** value too, not just
   mid-transition ones. Not fixed this pass — flagged as a real, pre-existing
   defect (not Starling-specific; would reproduce identically for any
   fresh manual tracker) since fixing it means touching carefully-tuned
   animation code without being asked to.
2. **"X left in this budget" showed a fraction of the real total.**
   Confirmed via `Tracker.availableZoomLevels`/`subPeriod(for:asOf:)`: any
   tracker over 7 days defaults its dashboard to the "This Week" zoom
   (`TrackerDetailView.init`'s `defaultZoom` logic), which scopes
   `Target Right Now`/`Under Budget`/`remainingInAllowanceCaption` to a
   **calendar-week-clamped sub-period's fractional allowance**
   (`Tracker.pace(...zoomLevel:)`'s `subAllowance`), not the tracker's real
   total. For an 8-day tracker, "This Week" clamps to just a few days,
   producing a materially smaller number than the real budget with no
   on-screen indication the figures are scoped rather than whole-tracker.
   Also not Starling-specific — same math for a manual tracker of the same
   length. Not fixed this pass either — it's a deliberate prior design
   (zoom re-scopes "the whole dashboard," per `TrackerDetailView`'s own
   doc comment) with real tradeoffs (short-tracker default threshold vs.
   caption wording vs. leaving as-is), presented to the user as options
   rather than picked unilaterally.
3. **"Under Budget by £67.20" with zero actual spending — confirmed not a
   bug, and now fully explained.** `TrackerPace.computePace`'s
   `difference = expectedConsumedByNow - consumedSoFar` means the moment
   *any* time elapses since the tracker's **period start**, a nonzero
   figure appears even with zero real spending (§3.1's intentional linear
   pace model) — that part was already understood. What wasn't yet pinned
   down: the user's own math (£3.33/hour expected at their tracker's
   size) didn't match a ~£68 swing within under an hour of *creating* the
   tracker. Root cause: `hoursElapsed` is measured from `startDate`,
   normalized to **midnight** when `includesTime` is off (the default) —
   not from when the tracker was actually saved. Creating a tracker in
   the evening with a start date of "today" already counts most of that
   day as elapsed pace-wise. The user confirmed this directly: a follow-up
   tracker created with explicit start/end times (`includesTime` on, so
   `startDate` matches actual creation time) produced correct-looking
   figures. **No code change needed or made** — working as designed once
   the period-start-vs-creation-time distinction is understood.

**Fixed this pass**: "Starting value" now auto-fills from the picked
account's live Starling balance in Add Tracker, rather than requiring the
user to type in today's real number blind. `TrackerStore` gained
`fetchCurrentValue(for:from:)` (refactored alongside `provider(for:)` and
`listAvailableTargets(for:)` to share one `resolvedProvider(for:)` helper
rather than three copies of the same provider-id switch) and
`AddTrackerView` now has a `.task(id: selectedTargetId)` that fetches and
overwrites `startingValueText` whenever the user picks/changes an account,
with a small "Fetching live balance…" indicator in place of the usual
hint text while it's in flight. Deliberately overwrites rather than only
filling when empty — picking an account is the user asking this field to
reflect that account's real number — and only "Starting value," not
"Total budget," per what was actually asked; the two remain independent
decisions. Fails silently (the user can still type a value by hand) since
a failed prefetch shouldn't block tracker creation.

### Verifying this session's changes

Not verified by a compiler, same caveat as every Starling-related entry
above. The three findings above, though, **were** verified against a real
device/Starling account by the user — those are confirmed real, not
speculative.

## 2026-09-17 Zoom levels removed

Following finding #2 from the real-device testing session above (the
default "This Week" zoom silently scoping headline dashboard figures to a
calendar-week-clamped fraction of a tracker's real budget, with no visual
indication), the user asked to remove zoom levels from the app entirely
rather than patch the default threshold or caption wording as a stopgap —
"not working well so need a re-think... not important just yet anyway."
Removed cleanly, not disabled/hidden: no `ZoomLevel` type, no zoom picker,
no sub-period scoping anywhere in the app. A tracker's dashboard, trend
chart, and every widget/complication family now always show the tracker's
real, whole-period figures — exactly the pre-zoom-levels behavior.

**Files deleted**: `src/WiggleRoomShared/Models/ZoomLevel.swift`,
`src/WiggleRoomTests/ZoomLevelTests.swift`.

**Files changed**:
- `Tracker.swift` — removed `actualValue(atOrBefore:)` (only had one
  caller, the now-removed zoomed pace calculation), `availableZoomLevels`,
  and `subPeriod(for:asOf:)`. `periodRemainingText(asOf:until:)` lost its
  `until` parameter (every other caller already used the default) and
  reverted to always measuring against the tracker's own `endDate`.
- `TrackerPace.swift` — removed the zoomed `pace(actualValue:asOf:zoomLevel:)`
  overload entirely. The previously-separate `computePace` static function
  (kept apart specifically so the zoomed overload could reuse it against a
  sub-period) had only one caller left once that overload was gone, so it's
  now inlined directly into the plain `pace(actualValue:asOf:)` — one
  function, not two, doing the exact same math as before for every
  existing caller.
- `RingsView.swift` — removed the `zoomLevel: ZoomLevel = .overall`
  parameter; `pace` always computes against the tracker's real period now.
- `TrendChartView.swift` — removed the `zoomLevel` parameter along with
  the whole "window" abstraction it existed to support
  (`windowStartingValue`, `windowAllowance`, `windowedReadings` are gone);
  every call site now reads `tracker.startingValue`/`tracker.totalAllowance`/
  `tracker.sortedReadings` directly, since the chart always covers the
  tracker's real full period again.
- `TrackerDetailView.swift` — removed the `@State private var zoomLevel`
  property, the custom `init` that used to pick its default (the type now
  relies on Swift's synthesized memberwise `init(tracker:)`, since `let
  tracker: Tracker` is the only stored property left without a default
  value), `availableZoomLevels`, `zoomWindowEnd`, `windowedReadingCount`
  (now just `tracker.sortedReadings.count` inlined at its one call site),
  the zoom picker section in `body`, and the `zoomLevelPicker` view itself.
  `RingsView`/`TrendChartView` are called with no zoom argument;
  `periodRemainingText` dropped its `until:` argument to match `Tracker`'s
  simplified signature.
- `ValueSnapshot.swift`, `TrackerPace.swift` (`finalPaceStatus` doc
  comment), `TrackerStore.swift` (`refreshFromSource` doc comment) — doc
  comments that referenced zoom levels as a reason for the timestamped-
  snapshot history requirement or as a caveat, reworded to stand on their
  own (the trend chart alone already justifies keeping reading history;
  `finalPaceStatus`/`refreshFromSource` no longer need to disclaim
  anything zoom-related).
- `docs/wiggleroom-build-spec.md` — §4.5 rewritten from a feature
  description into a "removed, needs a rethink" section explaining what
  broke and why it was pulled rather than patched in place, keeping the
  original design idea on record for whenever it's revisited; every other
  cross-reference to zoom levels (§6, §7.1, §8.1, §9, §12) updated to
  match current (zoom-free) behavior rather than left stale.
- `README.md` — status checklist line for §4.5 changed from done to "built,
  then removed pending a redesign."

**Widgets/complication were never touched** — they never adopted zoom
levels in the first place (confirmed by grep before starting this removal:
zero references anywhere in `WiggleRoomWidgets`/`WiggleRoomComplication`),
so §8.1's build-spec line about "zoom-level configuration not yet built
for widgets" is now moot rather than resolved — there's no base feature
left for a widget to configure a zoom level against.

**No regressions intended**: every simplified function computes exactly
the same result it did before for the `.overall` case (which was already
the only case most trackers — anything a week or shorter — ever used),
since removing the zoom branch just means that code path is gone, not that
the surviving path's math changed. `TrackerPaceTests`/`TrackerTests`
already only exercised the plain `pace(actualValue:asOf:)` overload and
`periodRemainingText(asOf:)` with no `until:` argument, so neither needed
updating — only `ZoomLevelTests.swift` (entirely zoom-specific) was
deleted outright.

### Verifying this session's changes

Not verified by a compiler — same standing caveat as every Starling/
real-device-testing entry above (no Swift toolchain in this environment).
Manually re-checked every changed file for leftover references (a repo-wide
grep for `zoomLevel`/`ZoomLevel`/`subPeriod`/`availableZoomLevels`/
`windowedReadings`/`windowStartingValue`/`windowAllowance`/
`actualValue(atOrBefore` returns nothing after this change) and for
structural correctness (brace matching, the synthesized memberwise init
replacing the deleted custom one). Build in Xcode and run the test suite
before trusting this further, same as everything else in this file's
Starling-adjacent entries.

## 2026-09-17 Starling reading dedup + Update History for real sources

Two more findings from continued real-device testing on the Starling
branch, both fixed:

1. **`refreshFromSource` logged a new reading on every successful poll,
   even when the value hadn't changed.** With the detail screen's 30s tick
   (§5.3), this meant a Starling tracker accumulated a near-duplicate,
   same-value reading every 30 seconds it was left open — flooding
   `TrendChartView`'s point marks so densely that individual readings
   became visually indistinguishable from the line connecting them (the
   user's "why am I not seeing green dots" — the dots were being drawn,
   just so densely overlapped they read as a solid line), and needlessly
   bloating the synced reading history for no informational gain. Fixed in
   `TrackerStore.refreshFromSource` (`src/WiggleRoomShared/State/TrackerStore.swift`):
   a fetched value equal to `tracker.latestReading?.value` is treated as a
   successful, no-op check rather than a new row — a poll that finds
   nothing changed doesn't need its own reading. Not independently unit
   tested (the guard's own logic is a one-line comparison, and testing it
   end-to-end through `TrackerStore.refreshFromSource` would need
   `provider(for:)` to accept an injectable fake provider, which it
   currently doesn't — a bigger seam than this fix warranted); needs
   manual verification against a real Starling account.
2. **"Update History" was hidden entirely for a Starling tracker.**
   Pre-existing, deliberate design (predates the Starling work) —
   `ReadingHistoryView` was built to let a user edit/delete their own
   manually-logged readings, gated behind `Tracker.isManualEntry` in
   `TrackerDetailView`'s toolbar menu, on the reasoning that "a real
   provider's history should reflect what it actually reported." That
   reasoning still holds for *editing*, but with Starling readings now
   genuinely accumulating, hiding the list entirely means there's no way
   to just *see* a Starling tracker's history at all. Changed the toolbar
   gate to `!tracker.sortedReadings.isEmpty` (any tracker with readings
   gets the menu item, not just manual ones), and reworked
   `ReadingHistoryView` (`src/WiggleRoom/Views/ReadingHistoryView.swift`)
   so a manual tracker's rows stay tap-to-edit/swipe-or-context-menu-to-
   delete exactly as before, while a real source's rows render as plain,
   non-interactive text — same list, view-only. `EditButton`/`onDelete`
   are now also gated on `tracker.isManualEntry`.

### Verifying this session's changes

Not verified by a compiler — same standing caveat as every entry in this
Starling-adjacent stretch (no Swift toolchain in this environment). Manually
re-checked both changed files for consistent `isManualEntry` gating and
correct `@ViewBuilder`/optional-closure syntax (`onDelete(perform:
tracker.isManualEntry ? deleteReadings : nil)`). Needs a real build, the
test suite, and ideally a real Starling account left open for a few
minutes to confirm the dedup actually stops the reading flood and that
Update History renders sensibly (read-only) for a Starling tracker.

## 2026-09-17 Fix Swift type-checker crash in ReadingHistoryView

First actual build attempt against a real device on this branch, and it
failed outright: Xcode reported "Failed to produce diagnostic for
expression; please submit a bug report" in `ReadingHistoryView.swift` —
the Swift compiler giving up on type-checking an expression rather than
producing a normal error, a known failure mode for certain expression
shapes rather than a real semantic mistake.

Prime suspect: `.onDelete(perform: tracker.isManualEntry ? deleteReadings
: nil)`, added in the previous session — a ternary whose branches are a
bare function reference and `nil` is a recognized trigger for this exact
crash (the type checker has to simultaneously infer the ternary's result
type, the optional-closure conversion, and the function-reference-to-
closure conversion, and sometimes just fails to produce a diagnostic
rather than resolving it or reporting a real error). Fixed by extracting
it into its own explicitly-typed computed property (`private var
deleteAction: ((IndexSet) -> Void)?`), so `.onDelete(perform:
deleteAction)` at the call site is now trivial for the checker.

While in there, also simplified `row(for:)`, which had a similar shape (a
shared, untyped `let content = HStack { ... }` reused inside both branches
of an `if tracker.isManualEntry { Button { ... } label: { content } } else
{ content }`) — not confirmed as a second contributor to the crash, but
the same general pattern, so split into two straightforward functions
(`row(for:)` branching between a `Button` and plain content, `rowContent(for:)`
building the actual `HStack` once with an explicit `some View` return
type) as a precaution rather than leaving a second instance of a pattern
already known to cause this class of failure.

### Verifying this session's changes

Not verified by a compiler in this environment (same standing caveat as
every entry in this stretch) — this fix is a response to a real compiler
failure the user reported from their own Xcode, targeting the specific,
well-known trigger pattern, but hasn't been confirmed clean by a
follow-up build. If Xcode still reports the same crash (or a new one) in
this file after this change, the `row(for:)`/`rowContent(for:)` split
wasn't the (or the only) cause, and the actual offending expression needs
pinpointing directly from Xcode's own (admittedly unhelpful) diagnostic —
worth trying to isolate by temporarily commenting out sections of the
file to binary-search for the exact line, since Xcode's crash message
doesn't reliably point at the real culprit's line number.

## 2026-09-17 Connected Source management + token storage moved off Keychain

Two related fixes from continued real-device, multi-device testing: the
user ran the app on a second device and got "Not connected — reconnect
this source in Settings" for their Starling tracker, then pointed out (1)
there was no way to actually reconnect/manage a source from Settings at
all, and (2) the token should travel between devices on the same Apple ID
the same way everything else in the app does — "everything should use the
same sync system, including sources."

**Root cause of the cross-device failure**: `kSecAttrSynchronizable`
Keychain items sync via **iCloud Keychain**, a genuinely separate sync
system from the CloudKit private-database sync that carries every other
piece of this app's data. It has its own per-device on/off toggle
(Settings → [name] → iCloud → Passwords and Keychain) that most people
never think to check, and even when on, it can lag CloudKit's near-real-time
sync by a noticeable margin. So a `ConnectedSource` record could (and, per
the user's report, did) arrive on a second device via CloudKit well before
— or without ever — its Keychain-held token arriving via the separate
iCloud Keychain path, leaving a source that looked connected but wasn't.

**Fix, per the user's explicit direction**: moved the token off the
Keychain entirely and onto `ConnectedSource.credentialToken` — a plain
`String?` field on the same `@Model` record, synced via the exact same
CloudKit mechanism as trackers, readings, and everything else. One sync
system, not two. This is still within the security boundary build-spec.md
§11 always allowed ("stored outside Keychain/CloudKit" was the actual
line, not "Keychain only" — that stricter wording has been corrected)
since it's still the user's own private CloudKit database under their own
Apple ID, never transmitted anywhere but Starling and Apple's own sync
infrastructure.

**Files deleted**: `src/WiggleRoomShared/Security/SecureTokenStore.swift`
(the `SecureTokenStore` protocol, `KeychainTokenStore`, `InMemoryTokenStore`
— no longer needed once nothing reads/writes the Keychain) and
`src/WiggleRoomTests/SecureTokenStoreTests.swift`.

**Files changed**:
- `ConnectedSource.swift` — `credentialKeychainKey: String?` renamed/
  repurposed to `credentialToken: String?`, now holding the actual token
  value directly rather than a Keychain lookup key.
- `StarlingProvider.swift` — dropped the `tokenStore: SecureTokenStore`
  dependency entirely; `makeClient(for:)` now reads
  `connection.credentialToken` straight off the record. `init` simplified
  to just `connection`/`budget` params.
- `AddSourceView.swift` — dropped all Keychain calls; `connect()` now sets
  `credentialToken` directly on the (draft, then real) `ConnectedSource`.
  Also gained an **existing-source mode**: `AddSourceView(existingSource:)`
  reconnects a source in place (same record, same `credentialToken` field,
  so every tracker already pointed at it keeps working) instead of only
  ever creating a new one — this is the practical fix for "no option to
  edit sources," not just the sync-system change.
- `ConnectedSourcesView.swift` — rows are now `NavigationLink`s into the
  reconnect flow, plus swipe-to-remove. Removal is blocked while any
  tracker still uses that source — `ConnectedSource`'s relationship to
  `Tracker` has no cascade-delete rule (defaults to `.nullify`), so
  deleting a source out from under active trackers would silently leave
  them with a `nil` connection rather than cleanly failing; the blocked-
  removal alert names the trackers still using it instead.
- Test files (`StarlingProviderTests.swift`, `TrackerStoreTests.swift`) —
  updated to construct `ConnectedSource` with `credentialToken` instead of
  `credentialKeychainKey`, and `StarlingProvider`/`InMemoryTokenStore`
  call sites simplified to match the new, Keychain-free constructor.

**Docs**: build-spec.md §5.2 (table + prose), §5.3, §5.4, §11, and §12
all rewritten to describe CloudKit-synced token storage and the
reconnect/remove UI as the current, built behavior rather than a Keychain
design with known gaps; README's status line updated to match.

**Trade-off understood, not treated as free**: a Keychain entry gets
OS-level encryption-at-rest and biometric/passcode-gated access by
default; a plain SwiftData field synced through CloudKit relies on
CloudKit's own private-database encryption and the device's standard
Data Protection instead — a different, not strictly lesser, protection
model, and a reasonable one for a personal single-user app already
trusting CloudKit with every other piece of financial data it stores
(balances, budgets). Not treated as a decision to revisit without being
asked.

### Verifying this session's changes

Not verified by a compiler — same standing caveat as every entry in this
Starling-adjacent stretch (no Swift toolchain in this environment).
Manually re-checked every changed file and ran a repo-wide grep for
`credentialKeychainKey`/`SecureTokenStore`/`KeychainTokenStore`/
`InMemoryTokenStore`/`tokenStore:`/`Keychain` to confirm nothing stale was
left behind (three intentional doc-comment mentions remain, explaining
*why* the design moved away from Keychain — not leftover references to
code that no longer exists). Needs a real build, the test suite, and
ideally the exact scenario that surfaced this — connecting Starling on one
device, then opening the app on a second device signed into the same
Apple ID — to confirm the source now shows connected there without any
iCloud Keychain dependency.

## 2026-09-17 Fix Starting-value auto-fill clobbering manual entry

Real-device report: the user created a Starling tracker with its start
time set to 40 minutes in the past, and manually typed the starting
balance as what it genuinely was then (£639). After saving, the tracker's
starting balance had become £615 — the account's balance *at save time*,
not what was typed — and "Final target will be" showed a nonsensical
-£23 (`projectedFinalValue = startingValue - totalAllowance`, now computed
against the wrong starting value). Also reported: the "Starting value"
field already contained "0" before typing, so entering "639" produced
"6390" (the digits landed ahead of the existing "0" rather than replacing
it).

**Root cause of the first bug**: `AddTrackerView`'s "Starting value
auto-fills from the live balance" feature (built two sessions ago, per
explicit request) fetched the picked account's *current* balance and
unconditionally overwrote `startingValueText` — including a value the
user had already deliberately typed. The Budget section sits above the
Source section in the form, so the realistic flow is: type a (possibly
backdated) starting value first, then scroll down and pick the Starling
account — at which point the prefill fired and silently replaced what was
just typed. This directly explains 639 → 615: the live balance at the
moment the account was picked (or shortly after, whenever the fetch
resolved) simply overwrote the historical figure, with nothing on screen
indicating the field had changed out from under the user.

**Fixes**, both in `src/WiggleRoom/Views/AddTrackerView.swift`:
1. `prefillStartingValueIfNeeded()` now checks `startingValueText.isEmpty`
   before *and* after the async fetch (the second check guards the race
   where the user types while the fetch is still in flight) and does
   nothing if the field already has content — it only ever fills a truly
   blank field, never overwrites. Doc comment rewritten to state this as
   the actual contract, not "overwrites, since picking an account is what
   the user asked for" (the previous, now-recognized-as-wrong reasoning).
2. `startingValueText`'s `@State` default changed from the literal string
   `"0"` to `""`. A `"0"` default isn't a placeholder — it's real content
   already in the field — so typing "639" without first clearing it
   produced "6390". `totalAllowanceText` never had this default and never
   had this problem; `startingValueText` now matches it. The `TextField`'s
   own `"0"` argument (a genuine grey placeholder, shown only when the
   bound text is empty) was correct already and needed no change.

Trade-off accepted for fix 1: after one successful auto-fill, switching to
a *different* Starling account in the same form won't re-fill the field
even though the user didn't type anything themselves (it's no longer
empty). Deliberate — silently overwriting is the actively wrong behavior
this fix exists to prevent, and it applies uniformly rather than trying to
distinguish "auto-filled, safe to replace" from "user-typed, don't touch."

### Verifying this session's changes

Not verified by a compiler — same standing caveat as every entry in this
stretch (no Swift toolchain in this environment). The bug's mechanism was
traced through the actual code (`prefillStartingValueIfNeeded`'s
unconditional overwrite, `startingValueText`'s `"0"` default) rather than
guessed at, and the fix directly addresses the traced mechanism, but
hasn't been confirmed against a real build or the exact reported scenario
(backdated start time + manual starting value + picking a Starling
account) on a device.

## 2026-09-17 Surface the bound account read-only, in two places

Confirmed with the user that a tracker's connected source and account are
already fully locked after creation — the only code that ever sets
`Tracker.connectedSource`/`sourceTargetId` is the initializer itself, and
`AddTrackerView`'s edit mode has never rendered an editable picker for
either. Two follow-up asks from that conversation, both about *showing*
that binding rather than changing it:

1. **Edit Tracker** showed the source's display name as a read-only row
   already, but never which specific account within it. Added an
   "Account" row alongside it (`AddTrackerView.swift`) — resolved live via
   `store.listAvailableTargets(for:)`, matched against the tracker's
   stored `sourceTargetId`, with a loading spinner while in flight and a
   fallback to the raw id if the fetch fails or the account's no longer
   listed. New state: `resolvedAccountName`/`isResolvingAccountName`, a
   `resolveAccountNameIfNeeded(for:)` async function, called once from the
   existing `.task { }` that populates the edit form. Footer text updated
   from "source can't be changed" to "source and account can't be
   changed."
2. **Tracker Detail dashboard** had no indication anywhere of which
   source/account a tracker's live figures come from. Added a small
   tertiary-style caption ("My Starling Account · Personal") above the
   "Refreshes in Xs" countdown, shown only for a real (non-manual) source
   (`TrackerDetailView.swift`). Same resolution approach as Edit Tracker
   (`resolveAccountNameIfNeeded()`, `sourceCaption`), but deliberately
   **not** tied to the 30s refresh tick — it resolves once per appearance
   (guarded by `resolvedAccountName == nil`) since a tracker's bound
   account never changes, and re-fetching the full account list every 30
   seconds alongside the balance poll would burn extra Starling requests
   for information that's already static.

Neither change touches `Tracker.connectedSource`/`sourceTargetId` at all —
both are pure display, confirming (not just preserving) the existing
lock.

### Verifying this session's changes

Not verified by a compiler — same standing caveat as every entry in this
stretch. Both new resolution functions follow the exact pattern already
used (and manually re-checked) by `AddTrackerView`'s target-picker
prefill from earlier sessions, so the risk profile is similar; still
needs a real build and a look at an actual Starling tracker's Edit screen
and dashboard to confirm the caption/row render sensibly and don't
crowd already-tight layouts (the watch app and small widget families
were deliberately left untouched — no room for this there).

## 2026-09-18 Menu bar tracker is now user-configurable

**Bug reported by the user**: with more than one tracker, the macOS menu
bar item always showed the most-recently-started tracker, and there was no
way to pick a different one — `MenuBarStatusView`/`MenuBarStatusLabel`
both hard-coded `trackers.first` off a `startDate`-descending `@Query`,
matching the spec's original "simpler of the two options" decision (§7.2)
but with no escape hatch once that default wasn't the tracker the user
actually wanted glanceable.

**Fix** (`MenuBarStatusView.swift`):

- Added a module-private `menuBarTrackerIDKey` (`"menuBarTrackerID"`) and a
  `resolveMenuBarTracker(pinnedID:in:)` helper shared by both views: looks
  up a tracker by the stored id string, falling back to `trackers.first`
  (the old default) if nothing's pinned yet or the pinned tracker was
  since deleted — so a stale id can never produce a blank menu bar.
- Both `MenuBarStatusView` and `MenuBarStatusLabel` now read the pin via
  `@AppStorage(menuBarTrackerIDKey)` — a plain per-Mac UI preference in
  `UserDefaults.standard`, deliberately **not** routed through
  SwiftData/CloudKit, since which tracker shows in *this* Mac's menu bar
  isn't data that should follow the user to their other devices.
- `MenuBarStatusView`'s dropdown gained a "Show in Menu Bar" submenu
  (`Menu` with a `Button` per tracker, checkmark on the currently-shown
  one), shown only once there are 2+ trackers — with a single tracker
  there's nothing to choose between, matching how the old default already
  behaved correctly for that case.

No changes to `TrackerPace`, `Tracker`, or any other target — this is
scoped entirely to the macOS menu bar's own two views.

### Verifying this session's changes

**Not verified by a compiler or the Simulator** — this environment has no
Xcode/Swift toolchain at all (`xcodebuild`/`swiftc`/`xcode-select` all
unavailable), consistent with every prior entry in this stretch. The
change follows an established, already-working pattern in this codebase
(`@AppStorage` + a plain string key, a `Menu`/`Button` list mirroring the
one already used elsewhere for pickers) rather than anything novel, but
build in Xcode and manually confirm before trusting it: create 2+
trackers, open the menu bar item, pick a non-default tracker from "Show in
Menu Bar", confirm both the label and dropdown update immediately and
persist across a relaunch, then delete that tracker and confirm the menu
bar falls back to the most-recently-started one without crashing.

## 2026-09-18 Move Delete Tracker out of the crowded "…" menu

**Bug reported by the user**: on iOS, the dashboard's "…" menu
(`TrackerDetailView`) put **Edit Tracker** and the destructive **Delete
Tracker** right next to each other with no visual gap between them — an
easy mis-tap, especially one-handed.

**Fix**:

- `TrackerDetailView.swift` — removed the "Delete Tracker" button (and its
  `confirmationDialog`) from the "…" menu entirely. The menu now only has
  Edit Tracker and (when the tracker has readings) Update History.
- `AddTrackerView.swift` (the Edit Tracker screen) — added a new `Section`
  at the very bottom of the form, shown only in edit mode
  (`existingTracker != nil`), containing a single centered destructive
  "Delete Tracker" button and the same confirmation dialog/wording the
  dashboard used to show. `.listSectionSpacing(.custom(48))` gives this
  section a deliberately larger gap above it than the default
  inter-section spacing, so it reads as a clearly separate, "point of no
  return" zone rather than just the next field in the form.
- Deleting now happens from inside the Edit Tracker sheet, which meant the
  dashboard behind it (`TrackerDetailView`) needed to know to close too,
  since it would otherwise be left showing a tracker that no longer
  exists. Added `AddTrackerView.onDelete: (() -> Void)?`, called right
  before the sheet dismisses itself; `TrackerDetailView` passes `{
  dismiss() }` when presenting the edit sheet, so confirming delete closes
  both the sheet and the dashboard in one action, same end result as
  before. `onDelete` is `nil`/unused everywhere `AddTrackerView` is opened
  for a *new* tracker (`TrackerListView`, `MacRootView`) — nothing changed
  there.
- This is a shared view used by both iOS/iPadOS and macOS
  (`TrackerDetailView`/`AddTrackerView` have no platform-specific code
  here), so the fix applies on both, even though the bug was reported
  specifically on iOS — keeping one behavior rather than forking Delete's
  placement per platform.

### Verifying this session's changes

**Not verified by a compiler or the Simulator** — same standing caveat as
every entry in this stretch (no Xcode/Swift toolchain in this
environment). `.listSectionSpacing(_:)` is available well within this
project's iOS 27/macOS deployment target (introduced iOS 17/macOS 14), so
it isn't a new-API risk, but build in Xcode and manually confirm: open
Edit Tracker on an existing tracker, confirm Delete Tracker sits clearly
separated at the bottom with its own visual gap, confirm the destructive
confirmation dialog still reads correctly, and confirm deleting closes
both the Edit sheet and the dashboard behind it (landing back on the
tracker list). Also confirm the New Tracker flow (`TrackerListView`'s "+"
and `MacRootView`'s toolbar button) shows no Delete section at all.

## 2026-09-18 Fix macOS build: `.listSectionSpacing` unavailable + `SourceProvider` not class-constrained

User reported an Xcode build error direct from their own machine:
`'listSectionSpacing' is unavailable in macOS` in `AddTrackerView.swift`
(the `.listSectionSpacing(.custom(48))` call added in the previous
session's "Move Delete Tracker out of the crowded '…' menu" entry, to give
the new Delete Tracker section visual separation). The modifier is
iOS/iPadOS/tvOS/watchOS-only and simply doesn't exist on macOS, and
`AddTrackerView` is shared, unconditional code across every platform —
this always would have failed a macOS build, just never one until now,
since prior sessions had no Swift toolchain at all to catch it (see the
long run of "not verified by a compiler" caveats through this file).

**This is the first session in this project with a real Xcode
installation and simulators available** (Xcode 27.0, confirmed via
`xcodebuild -version` and `xcrun simctl list devices`), so unlike every
prior entry here, these fixes are genuinely build-verified rather than
just carefully re-read.

**Fix 1** (`src/WiggleRoom/Views/AddTrackerView.swift`): wrapped the
`.listSectionSpacing(.custom(48))` call in `#if os(iOS) … #endif`. macOS
already has no equivalent list-section-spacing API and didn't need one —
the Delete section still renders in its own `Section`, just without the
extra gap on macOS specifically (its list rendering has more inherent
breathing room between sections than iOS's grouped-list style already).

**Fix 2, found while verifying the first fix** (`xcodebuild build`
succeeded, but a follow-up `xcodebuild test` run surfaced a second,
unrelated pre-existing compile error): `TrackerStoreTests.swift`'s
`testProvider_forManualTracker_returnsManualProvider` does
`XCTAssertTrue(provider === store.manualProvider)` to confirm
`TrackerStore.provider(for:)` returned the shared `manualProvider`
instance rather than a fresh one — but `SourceProvider` (the protocol
`provider(for:)` returns, §5.1) was declared as a plain, non-class
protocol, so `===` identity comparison on `(any SourceProvider)?` doesn't
type-check ("expected to be an instance of a class or class-constrained
type"). This test must never have compiled successfully before either —
another casualty of no compiler ever having checked this codebase until
now. Fixed by declaring `protocol SourceProvider: AnyObject` in
`src/WiggleRoomShared/Providers/SourceProvider.swift`: both real
conformers (`ManualEntryProvider`, `StarlingProvider`) are already `final
class`, so this doesn't constrain anything that wasn't already true in
practice — it just makes the compiler enforce it, which is exactly what
the identity-comparison test needs.

**Verification**: `xcodebuild -scheme WiggleRoom build` succeeded for
both `-destination 'platform=macOS'` and `-destination 'generic/platform=iOS
Simulator'` after both fixes — a real build, not a syntax check, the first
of its kind for this project. `xcodebuild test -destination
'platform=macOS'` then compiled and ran the full suite (fixing fix 2 was
required to get the test target to build at all), but a large batch of
`TrackerStoreTests`/`ManualEntryProviderTests` cases failed at runtime
with CoreData's `NSInternalInconsistencyException: No eligible connection
available` — traced to this specific machine/session having **no iCloud
account signed into System Settings** (`defaults read MobileMeAccounts`
returns empty) while every target's entitlements require
`com.apple.developer.icloud-services`/CloudKit; SwiftData's in-memory test
`ModelContainer` (`TestSupport.swift`'s `makeInMemoryModelContainer()`)
still appears to attempt CloudKit-related setup tied to those entitlements
even for a local-only store, and fails without a signed-in account. This
reproduced identically with the command sandbox disabled, ruling out a
sandboxing artifact. **Not a code bug** — it's an environment gap specific
to this machine having no Apple ID configured in Xcode/System Settings,
distinct from (and narrower than) the "no toolchain at all" gap every
prior entry in this file describes. `WiggleRoomUITests` (which don't touch
SwiftData) passed cleanly in the same run. Whoever picks this up on a
machine with a signed-in Apple ID should re-run the full test suite to
confirm — this session couldn't get further than isolating the cause.

## 2026-09-18 Menu bar dropdown was greyed out; added the rings

User asked why the macOS menu bar item's dropdown looked entirely greyed
out, and whether the same two-ring visual from the iOS dashboard could be
shown there too.

**Root cause of the greyed-out look**: `WiggleRoomApp.swift`'s
`MenuBarExtra` used `.menuBarExtraStyle(.menu)`, which renders the
dropdown as a genuine AppKit `NSMenu`. AppKit forces any menu content that
isn't a `Button`/`Toggle`/`Menu` control into its own dimmed
"informational item" text style — `MenuBarStatusView`'s tracker
name/current-value/target/difference rows are all plain `Text`/`HStack`,
so every one of them rendered dimmed even though nothing was actually
disabled. `.menu` style also can't host an arbitrary custom SwiftUI view
at all, which was the second half of the ask — there was no way to drop
`RingsView` into an `NSMenu`.

**Fix**: switched to `.menuBarExtraStyle(.window)` in
`src/WiggleRoom/WiggleRoomApp.swift`. `.window` presents the dropdown as
genuine SwiftUI content in a floating panel rather than a real menu, which
fixes both problems at once — plain text renders normally, and the panel
can hold any view. Rewrote `MenuBarStatusView`
(`src/WiggleRoom/Views/MenuBarStatusView.swift`) to add `RingsView` (the
same view `TrackerDetailView` uses, §3.4/§7.1) above the existing
current/target/difference rows, at a 132×132pt size with a 14pt line
width scaled down from the dashboard's larger hero size. The "Show in Menu
Bar" tracker-picker `Menu` and the "Open Wiggle Room"/"Quit Wiggle Room"
buttons are unchanged in behavior — in `.window` style they now act as
ordinary SwiftUI buttons/menus rather than NSMenu items, which if
anything reads more consistently than before.

**Not built, scope kept to the actual ask**: build-spec.md's §7.2 already
called for "a refresh/log-reading button" in this dropdown, but that was
never actually implemented even before this session (confirmed by
re-reading the pre-existing `MenuBarStatusView` — it only ever had the
tracker picker and Open/Quit) — that's a pre-existing spec/implementation
gap, not something introduced or fixed here. Left as-is rather than
building it opportunistically while already in this file; §7.2 now notes
it explicitly as a known gap instead of silently implying it exists.

### Verifying this session's changes

`xcodebuild -scheme WiggleRoom -destination 'platform=macOS' build`
succeeded — a real build, not a syntax check. Could not visually confirm
the fix in the actual running menu bar: the app was launched
(`open .../WiggleRoom.app`), but driving/screenshotting the live menu bar
item needs Accessibility/Screen Recording permission this sandboxed
session doesn't have (`osascript` failed with "not allowed assistive
access", `screencapture` failed with "could not create image from
display"). The `.window`-style fix itself is a well-documented, common
pattern for exactly this AppKit dimming behavior, and the view code
compiles and type-checks against real `RingsView`/`TrackerPace` APIs, but
this still needs an actual look in a running menu bar (click the menu bar
icon, confirm the rings render and no text looks dimmed) before treating
it as fully confirmed — flagging this explicitly rather than claiming
verification that didn't happen.

## 2026-09-18 Menu bar dropdown: drop the duplicate status row

Immediate same-day follow-up, this time with the user's own screenshot of
the real, running menu bar dropdown (the `.window`-style fix above did
work — no more dimmed text) confirming the fix and flagging one thing to
tidy: below the rings, a "Just Over Budget · -£26.48" row sat directly
underneath a ring whose own center content already reads "JUST OVER
BUDGET" / "-£26…" — the exact same status label and figure, repeated a
few pixels apart.

**Fix**: removed that third `HStack` (status label + `displayDifference`)
from `MenuBarStatusView`'s body (`src/WiggleRoom/Views/MenuBarStatusView.swift`)
— the "Current Balance"/"Target Right Now" rows above it stay, since
those two numbers aren't shown anywhere else in the dropdown and remain
genuinely useful alongside the ring.

### Verifying this session's changes

`xcodebuild -scheme WiggleRoom -destination 'platform=macOS' build`
succeeded. Not re-confirmed visually in a live menu bar — same
Accessibility/Screen Recording permission gap as the previous entry — but
this change only deletes a `View` builder block with no new API surface,
a much lower-risk change than the `.window`-style switch was.

## 2026-09-18 Menu bar dropdown: left-align the bottom action rows

Another same-day follow-up from the same screenshot: "Show in Menu Bar",
"Open Wiggle Room", and "Quit Wiggle Room" all rendered centered rather
than flush-left like a native menu's items would.

**Root cause**: the containing `VStack(alignment: .leading, ...)` only
controls how its children are positioned *relative to each other* — each
`Button`/`Menu` still sizes to fit its own label and centers its text
within that tight-fitting frame, so `alignment: .leading` on the parent
had nothing to actually push left. This is a `.window`-style-specific gap
in `MenuBarStatusView`
(`src/WiggleRoom/Views/MenuBarStatusView.swift`) — the old `.menu`-style
dropdown didn't have this problem, since real `NSMenuItem`s are always
flush-left automatically.

**Fix**: added `.frame(maxWidth: .infinity, alignment: .leading)` to the
`Menu` and each `Button`, stretching each row to the panel's full width
before left-aligning the label within it.

### Verifying this session's changes

`xcodebuild -scheme WiggleRoom -destination 'platform=macOS' build`
succeeded. Not re-confirmed visually in a live menu bar — same
Accessibility/Screen Recording permission gap as the previous two
entries.

## 2026-09-18 Settings screen looked broken; consolidated all macOS config into Settings

User flagged a screenshot of Settings → Connected Sources → Reconnect
looking broken: a cramped back-chevron-plus-"Reconnect" bar squeezed above
the form, and the "Personal Access Token" label nearly touching the
window's left edge. Separately asked for a broader macOS design/HIG pass,
and mid-session added: every configurable thing in the macOS app should
live in Settings — including which tracker the menu bar item shows,
currently a "Show in Menu Bar" submenu buried inside the menu bar
dropdown itself.

**Root cause of the broken Reconnect screen**: `ConnectedSourcesView`
(the Settings window's content) pushed `AddSourceView` via `NavigationLink`
inside its own `NavigationStack` — the only place in the app still using
push/back navigation for an add/edit flow. Everywhere else on macOS
(`AddTrackerView` from `MacRootView`, `ReadingHistoryView` from
`TrackerDetailView`) presents this kind of screen as a **sheet** wrapping
a fresh `NavigationStack`, which is what gives those screens a clean
title bar with Cancel/Save at the corners and no back button. A pushed
destination inside the Settings scene's own stack instead rendered
AppKit's real back/forward chrome crammed above the content, and (since
`AddSourceView` doesn't self-wrap in a `NavigationStack`, relying on
whatever presented it) inherited the Settings window's own narrow,
List-driven natural width rather than getting a sensibly-sized sheet of
its own — hence the squeezed label.

**Fix 1 — Reconnect/Add Source layout**
(`src/WiggleRoom/Views/ConnectedSourcesView.swift`): on macOS only, rows
are now `Button`s that set `sourceToReconnect`/`isPresentingAddSource`,
presented via `.sheet(item:)`/`.sheet(isPresented:)` wrapping
`AddSourceView` in its own `NavigationStack` — exactly the established
sheet pattern. iOS keeps the original `NavigationLink` push (normal,
expected iOS Settings-style navigation — this was never broken there).
Added `.frame(minWidth: 420, minHeight: ...)` to the Settings window and
both sheets so the label column always has reasonable room regardless of
content.

**Fix 2 — configuration consolidated into Settings**: the macOS `Settings`
scene (`WiggleRoomApp.swift`) is now a two-tab `TabView` — **General**
(new `src/WiggleRoom/Views/GeneralSettingsView.swift`, a `Picker` for
which tracker the menu bar shows, reusing the exact `@AppStorage`
key/fallback logic `MenuBarStatusView` already had) and **Connected
Sources** (the existing view, unchanged in content). The "Show in Menu
Bar" `Menu` was removed from `MenuBarStatusView`'s dropdown entirely; a
`SettingsLink` row ("Settings…") replaces it as the way to reach that
picker now that it isn't in the dropdown itself — without it, closing the
main window would leave no way back into Settings at all. `menuBarTrackerIDKey`
(previously `private` in `MenuBarStatusView.swift`) is now internal so
`GeneralSettingsView` can read/write the same `UserDefaults` key.

**Not changed**: Add/Edit Tracker stays a sheet from the main window, not
a Settings pane — it's per-tracker action, not app configuration, so it
doesn't belong alongside General/Connected Sources.

### Verifying this session's changes

`xcodebuild -scheme WiggleRoom -destination 'platform=macOS' build` and
`-destination 'generic/platform=iOS Simulator' build` both succeeded — a
real build on both platforms, not a syntax check. Not visually confirmed
in a live Settings window or menu bar dropdown — same Accessibility/
Screen Recording permission gap as every entry in this stretch. Worth a
real look at: Settings → General's picker, Settings → Connected Sources'
Add/Reconnect sheets (both empty-state and populated), and the menu bar
dropdown's new "Settings…" row actually opening the Settings window.

## 2026-09-18 macOS Starling requests were silently blocked by App Sandbox (missing network entitlement)

User reported "Couldn't reach Starling — check your connection" on a real
Mac and asked specifically whether the earlier Keychain→CloudKit token-
storage fix (§5.3/§11, 2026-09-17) had regressed on macOS. It hadn't —
this is a distinct, previously-undiscovered bug: **macOS App Sandbox was
blocking all outbound network connections from the app**, unrelated to
the token itself.

**Diagnosis**: the `WiggleRoom` Xcode target's build settings set
`ENABLE_APP_SANDBOX = YES` (`src/WiggleRoom.xcodeproj/project.pbxproj`),
which puts the macOS build under App Sandbox — Xcode auto-injects
`com.apple.security.app-sandbox = true` into the compiled binary's
entitlements at sign time from that build setting alone, even though the
checked-in `WiggleRoom/WiggleRoom.entitlements` file never literally
listed it. Confirmed directly against the actually compiled/signed app
(`codesign -d --entitlements :- .../WiggleRoom.app`): `com.apple.security
.app-sandbox` was present, but `com.apple.security.network.client` was
not. Under App Sandbox, **outbound network connections are blocked
entirely** without that entitlement — every Starling API call
(`StarlingAPIClient`'s `URLSession.data(for:)`) would fail at the
networking layer regardless of whether the stored token was valid,
producing exactly `StarlingAPIError.network` → "Couldn't reach Starling
— check your connection." This was confirmed reproducible in this
session's own sandboxed environment too, independently, before the real
cause was traced: launching the built app and letting it attempt a
Starling call showed `dnssd_clientstub ConnectToServer... Operation not
permitted` / DNS resolution failure in the system log — the same failure
signature App Sandbox produces for any process lacking
`network.client`, while a plain `curl` from a Bash shell (a separate,
unsandboxed process) reached `api.starlingbank.com` from the exact same
machine without issue at the same time.

This gap had no way to surface before now — every prior session working
on the Starling integration had no Swift toolchain at all (see the long
run of "not verified by a compiler" entries through this file), so
nobody had ever actually run a signed, sandboxed macOS build of this code
until this session.

**Fix** (`src/WiggleRoom/WiggleRoom.entitlements`): added
`com.apple.security.network.client = true` directly to the entitlements
plist. Re-verified against the actually compiled/signed binary after
rebuilding — `codesign -d --entitlements :-` now shows the key present.
iOS has no App Sandbox concept at all, so this entitlement is inert
there — no risk of a cross-platform regression from adding it.

**Not a token/CloudKit-sync issue**: worth stating plainly since that was
the user's explicit question — `ConnectedSource.credentialToken` was
being stored and synced correctly the whole time. CloudKit sync itself
goes through a privileged system XPC path that isn't blocked by the
missing `network.client` entitlement (that's specifically why CloudKit
sync appeared to work fine while direct Starling HTTPS calls failed
outright) — this made the symptom look confusingly selective ("sync
works, but Starling itself doesn't") rather than a blanket "no network at
all" failure, which is what actually made it easy to initially suspect
the token/sync layer instead of entitlements.

### Verifying this session's changes

`xcodebuild -scheme WiggleRoom -destination 'platform=macOS' build`
succeeded, and `codesign -d --entitlements :-` on the rebuilt,
freshly-signed `.app` confirms `com.apple.security.network.client` is
now present — this is a deterministic, well-documented OS-level
restriction (App Sandbox either grants outbound networking or it
doesn't), not a "might still fail" fix. **Not verified end-to-end**: this
machine has no iCloud account signed in and no real Starling token
available, so an actual successful Starling fetch from the running app
wasn't observed directly in this session — re-confirming against a real
Starling account on a real Mac (the exact scenario the user reported)
would close this out completely.

## 2026-09-18 Reconnect sheet had no Cancel; trimmed the PAT footer; menu bar item now survives closing the main window

Same-day follow-up from a fresh screenshot of the new macOS Reconnect
sheet: the "back-chevron/squeezed-label" problem from the earlier entry
was gone, but the sheet had no way to dismiss it besides Esc — a lone
"Reconnect" button sat bottom-trailing with nothing next to it. Also
flagged: the token field's footer text was too long, and a question
about whether the menu bar item can stay up even when the app's main
window isn't open.

**Fix 1 — missing Cancel button**
(`src/WiggleRoom/Views/AddSourceView.swift`): `AddSourceView` never had a
`.cancellationAction` toolbar item at all — on iOS this didn't matter
because it's still pushed via `NavigationLink` there, which gets a free
back button; but now that macOS presents it as a sheet (previous entry),
there was genuinely no dismiss affordance besides Esc. Added
`ToolbarItem(placement: .cancellationAction) { Button("Cancel") {
dismiss() } }`, gated `#if os(macOS)` since iOS's back button already
covers it and doesn't need a second, redundant Cancel.

**Fix 2 — footer text trimmed**: `tokenFieldFooter` dropped from three
sentences (where to get a token + scopes, an iCloud-sync explanation, and
— for reconnect — a "this replaces the current token" note) down to one:
"Generate a personal access token at developer.starlingbank.com with
account:read and balance:read scopes." Per explicit request — just where
to get the token and the scopes needed, nothing else. The reconnect-only
branch (`existingSource != nil`) is gone too, so the footer is now
identical for Add and Reconnect.

**Fix 3 — menu bar item didn't survive closing the main window**: SwiftUI
terminates a macOS app once its last window closes by default, which
would take the `MenuBarExtra` down with it — defeating the entire point
of a menu bar item (glanceable status with no window open). Added
`src/WiggleRoom/AppDelegate.swift`, a minimal `NSApplicationDelegate`
overriding `applicationShouldTerminateAfterLastWindowClosed` to return
`false`, wired in via `@NSApplicationDelegateAdaptor(AppDelegate.self)`
in `WiggleRoomApp` (macOS only). Closing the main window now just closes
the window — the app keeps running, the menu bar item stays up, and
"Open Wiggle Room" in its dropdown brings the main window back.

### Verifying this session's changes

`xcodebuild -scheme WiggleRoom -destination 'platform=macOS' build` and
`-destination 'generic/platform=iOS Simulator' build` both succeeded.
Not visually/behaviorally confirmed — same Accessibility/Screen Recording
gap as this whole stretch of entries. Fix 3 in particular is worth a real
check: close the main window (red button, not Cmd+Q) and confirm the
menu bar item is still there and "Open Wiggle Room" brings the window
back, and separately confirm Cmd+Q from the menu bar's "Quit Wiggle
Room" still fully quits (this change only touches the last-window-closed
path, not an explicit quit).

## 2026-09-18 Settings window padding, fixed and actually verified on real screenshots

User pushed back that the Settings padding "still" didn't look right, and
asked to actually look at the screen being designed rather than keep
guessing — a fair complaint, since every prior entry in this stretch
could only reason from code and the user's own screenshots. This session
gained real Accessibility/Screen Recording permission partway through
(confirmed by retrying `screencapture`, which had failed identically
earlier), and from that point on every claim below was checked against a
real, running instance of the app — `open` the built `.app`,
`osascript`/System Events to drive it (`tell application "System Events"
to keystroke ","` for ⌘,, and clicking accessibility elements resolved
via `get entire contents` rather than guessed screen coordinates), and
`screencapture -x` plus reading the resulting PNG to actually see the
result. This is a meaningfully different verification bar than anything
else in this file — genuinely seeing the screen, not inferring it.

**Bug found by screenshot**: the Reconnect sheet (`AddSourceView`,
previous entries) had a large dead-space gap between the token field's
footer text and the Cancel/Reconnect button bar at the bottom — visually
confirmed, not assumed. Root cause: `ConnectedSourcesView.swift`'s two
`.sheet` presentations had `.frame(minWidth: 420, minHeight: 260)`, and
macOS `Form` stretches to fill whatever height it's given rather than
hugging its own content — the forced `minHeight` was itself the bug.
**Fix**: dropped `minHeight` entirely from both sheets and the main
Settings window's own frame, keeping only `minWidth: 420` for label
comfort. Re-screenshotted after rebuilding: the sheet now hugs its
content tightly, gap gone.

**Second thing found only by comparing tabs directly**: even after that
fix, the main Settings window (not a sheet) still showed a lot of empty
space below Connected Sources' one row. Screenshotting the General tab
back-to-back at the same window size (a single Picker row + caption)
confirmed this wasn't a per-view bug — both tabs render at exactly the
same size, because a `TabView`-based `Settings` scene keeps one
consistent window size across every tab (the same convention System
Settings itself uses, so switching tabs doesn't visibly resize the
window) rather than auto-sizing per tab. That's correct, native macOS
behavior, not something to "fix" by fighting the shared-size convention
— but the specific size AppKit was landing on by its own implicit
heuristic was bigger than either tab actually needed. **Fix**: added an
explicit `.frame(width: 480, height: 340)` directly on the `TabView` in
`WiggleRoomApp.swift`, a deliberate size choice (not a min/max) verified
against real screenshots of both tabs at that exact size — General's row
+ caption and Connected Sources' row + toolbar both sit comfortably
without either looking sparse or needing to scroll for a few sources.

**Also fixed, prompted by the same screenshot pass**: `tokenFieldFooter`
was trimmed (previous entry, before this one) but hadn't been re-verified
visually until now — confirmed correct at "Generate a personal access
token at developer.starlingbank.com with account:read and balance:read
scopes." with no leftover extra sentence.

### Verifying this session's changes

Unlike every other entry in this file, this one **is** visually verified
— real screenshots of the Reconnect sheet (before and after) and both
Settings tabs (before and after the fixed frame), all against the
actual, running, freshly-rebuilt app, not inferred from code or
described secondhand. `xcodebuild build` succeeded for both
`platform=macOS` and `generic/platform=iOS Simulator` after each change.
One thing not re-verified: a macOS password-autofill popover appeared
over the Personal Access Token field during one automated click pass
(a system feature reacting to the field gaining focus, unrelated to any
code here) — worth being aware it can appear over that field in normal
use, though it's standard macOS behavior for any secure text field, not
something this app controls or should suppress.

## 2026-09-18 Settings redesign: sidebar + inline editing, not tabs + sheets

User pushed back hard on the just-built Settings window: "the basic
layout is not how settings pages work in macOS apps... navigation
[should be] on the side... I don't expect the 'add source' button to be
part of the main navigation, that should be within sources... source
details [shouldn't be] their own pop-up... they should just be editable
inside source screen, model this on Claude's own settings page." A fair,
specific critique — the previous session had built an icon-tab-bar
`TabView` with a sheet-based Add/Reconnect flow, which is the *older*
macOS Settings convention (pre-Ventura System Preferences), not the
sidebar-plus-inline-content style modern macOS System Settings (and
Claude's own desktop app) actually use.

**Replaced entirely.** New `src/WiggleRoom/Views/SettingsRootView.swift`:
a fixed, non-collapsing sidebar (`List(selection:)`, deliberately a plain
`HStack` rather than `NavigationSplitView` — the latter brings a
draggable/collapsible divider neither System Settings' own sidebar nor
this one has) alongside a `ScrollView` showing whichever pane is
selected. `GeneralSettingsView` lost its own `Form`/frame chrome (that
scene structure moved up to `SettingsRootView`) and is now plain content
laid directly into the pane.

**Connected Sources changes most**, on macOS only (iOS keeps its
original List + NavigationLink + full-screen `AddSourceView` push —
normal, correct iOS Settings navigation, never the thing that was
broken): no more sheet at all. `SourceEditorCard` edits a source
directly inline — the name is a live `@Bindable` binding to
`source.displayName` (saved on every change, no explicit save step,
since renaming needs no validation), while the token has its own local
draft and an explicit "Update" button (network validation against
Starling genuinely needs a deliberate action, unlike the name). Adding a
new source appends an inline `NewSourceCard` to the bottom of the list
instead of presenting anything modal, and its "Add Source" trigger lives
inside the Connected Sources pane's own content — not the window's
shared toolbar, which is what "part of the main navigation" was
correctly objecting to.

**Also fixed in the same pass, flagged by the same review**: it was
impossible to tell whether an existing source actually had a working
token stored — the token field always started blank ("enter a new token
to reconnect"), giving no signal either way. Since a Starling PAT is
user-entered, not a system secret, the user explicitly said hiding it
added friction without real protection ("given that the pa is user
entered, we do not need to hide it... given it is a very long string we
can have a bigger input box"). Fixed three ways: (1) the token field now
pre-fills from `source.credentialToken` instead of starting empty, so
what's actually stored is directly visible/reviewable/copyable; (2)
switched from `SecureField` to a plain, monospaced `TextField(axis:
.vertical)` that grows to fit a token's real length instead of scrolling
sideways in a single-line box; (3) added an explicit "Connected"/"Not
Connected" badge (green checkmark / amber) next to each source's name,
independent of reading the token itself. Per a follow-up message, this
was extended to `AddSourceView.swift` too (iOS's Reconnect screen, and
macOS's own separate inline "Add New Source" shortcut from
`AddTrackerView`, both of which still use it) — same pre-fill, same
field style, same status row.

**Security note, surfaced live**: while verifying this on a real
iOS Simulator (the user signed into their own iCloud account there so
real synced data — including the real Starling connection — would be
visible), the Reconnect screen's now-unhidden field displayed the
user's actual, real, full Starling personal access token, which ended up
captured in a screenshot inside this AI coding session's conversation
history. Flagged directly to the user rather than silently proceeding:
recommended rotating that specific token as a precaution now that it's
been exposed outside the device, and offered a masked-with-tap-to-reveal
alternative design instead of always-visible-at-rest. **User's explicit
decision**: keep it as built (always visible, no masking) — this is a
deliberate, informed choice, not an oversight. Recorded here so the
tradeoff is on record: opening this screen for an already-connected
source shows its real credential in full, to anything that can see the
screen (screenshot, screen share, recording, shoulder-surfing) — the
same class of exposure that happened during this session's own
verification.

Also removed the "Show in Menu Bar" tracker-picker's earlier home (none
— that was already moved to `GeneralSettingsView` in the previous
session; this entry is just re-confirming it survived the sidebar
rewrite intact, which it did without changes needed).

**A separate, smaller fix landed in the same session**: the menu bar
dropdown's ring showed both its status word ("JUST OVER BUDGET") and its
number — a follow-up request asked to keep the number (not shown
anywhere else in that compact dropdown) but drop the word (already
repeated in the rows below the ring). `RingsView` gained
`showsStatusLabel` (independent of the existing `showsCenterContent`),
set `false` only in `MenuBarStatusView`.

### Verifying this session's changes

`xcodebuild build` succeeded for both `platform=macOS` and
`generic/platform=iOS Simulator` after every change in this entry.
**Real visual verification this time, on both platforms**: the macOS
sidebar (General and Connected Sources panes) was screenshotted directly
via `osascript`/`screencapture` against the actual running, freshly
built app — confirmed rendering correctly. The iOS Reconnect screen
(pre-filled token, monospaced growing field, "Connected" status badge)
was confirmed via a real iOS Simulator screenshot, with the user signed
into their own iCloud account so genuine synced data was visible rather
than an empty store. **Not independently re-verified**: the macOS
Connected Sources inline cards specifically (`SourceEditorCard`/
`NewSourceCard`) — automated clicking in this session repeatedly
mis-hit and activated unrelated frontmost apps (Microsoft Teams, once
landing in a live chat's compose box with no message sent; ChatGPT's own
Settings window once), so further blind macOS UI automation was
deliberately stopped rather than risking another mis-click near a real
app with live content. High confidence from code review and from the
iOS screenshot (same underlying view code, `#if os(macOS)`-gated but
structurally identical patterns), but worth a real look on macOS
specifically before treating it as fully confirmed.

## 2026-09-18 Feature/bug backlog pass: Starling Spaces, refresh cadence redesign, Estimated Final Balance (+ same-day fix)

A single consolidated list of bugs/features across Widgets, Starling,
Edit Tracker, Tracker chart, Tracker history, Tracker details, and
Connected Sources, worked through in one session after the macOS
Settings redesign above. Ordered roughly by size.

**Widgets**: added "by" after "Under Budget"/"Over Budget" wherever the
status word sits next to a figure (`TrackerPace.statusLine(for:)`,
already shared by widgets/complication/Shortcuts dialog — the wording
was already centralized, so this was a one-line change plus updating the
three call sites in `TrackerWidgetEntryView`/`TrackerComplicationEntryView`/
`ViewTrackerStatusIntent` that had been calling the plainer
`PaceStatus.label(for:)` instead). Also fixed the ~20s blank a widget
shows on resize/reconfigure: `TrackerTimelineProvider.snapshot(for:in:)`
was sharing `timeline(for:in:)`'s fetch path, which includes a
deliberate CloudKit-wait for freshly-created trackers — correct for a
real timeline reload, wrong for `snapshot`, which WidgetKit expects back
near-instantly. Switched `snapshot` to
`WidgetDataStore.fetchAllTrackersImmediately()`, a plain local fetch.

**Starling Spaces**: a tracker can now target a savings goal or spending
space, not just the top-level account — `StarlingAPIClient.fetchSpaces
(accountUid:)` (`GET /api/v2/account/{accountUid}/spaces`, note singular
"account" unlike the other endpoints), new `StarlingSpacesResponse`/
`StarlingSavingsGoal`/`StarlingSpendingSpace` structs. Schema was
verified live against Starling's own API reference before writing any
code, not guessed. `StarlingProvider.listAvailableTargets(for:)` now
flattens each account with its active spaces underneath; a private
`StarlingSpaceTargetID` enum encodes which kind a given target id is
(account vs. space, and which account it belongs to) so
`fetchCurrentValue(target:)` knows which endpoint to call.

**Edit Tracker Save button greyed out**: a real bug, not a missing
feature. `AddTrackerView.isValid` required `selectedTargetId != nil`
unconditionally, but that's never populated in edit mode (the target
picker isn't shown when editing) — so Save stayed disabled regardless of
what the user actually changed. Fields themselves (name, unit,
direction, dates, starting value, allowance, reminder) were always
editable; `save()` never touches source/target either way. Fixed by
exempting `existingTracker != nil` from that one validity check.

**Estimated Final Balance**: a new detail-screen-only card
(`TrackerDetailView.estimatedFinalBalanceCard`) showing where a
tracker's trend line projects it to land by `endDate`, and how far that
is above/below the fixed target — `Tracker.estimatedFinalValue`/
`estimatedFinalDifference` in a new `WiggleRoomShared/Models/
LinearFit.swift`, which also became the one shared regression
implementation (`linearFit(through:)`) — `TrendChartView`'s own trend
line now calls it too instead of keeping a private duplicate.

**Same-day fix — the estimate could be wildly wrong**: reported by the
user as "-£1458 whihc is crazy and doe snot align with where the trend
line is heading." Root cause: `TrendChartView`'s dotted trend line and
the new card compute the *exact same* fit and endpoint value, but the
chart line is deliberately clamped into the visible Y range before
drawing (an existing, commented workaround for a real Swift Charts
rendering bug when handed far-out-of-frame values) — so on-screen the
trend line always looks like a plausible, bounded slope, while the
card's raw unclamped number can be anything the fit implies. With only
two or three readings logged close together in time (e.g. from the 45s
foreground poll), the fit's slope is only meaningful over that short
span; extrapolating it linearly across the weeks remaining in the
tracker amplifies any small wobble into a huge, untrustworthy figure —
mathematically correct for that fit, not a credible prediction. Fixed by
withholding the estimate (`nil`) until the logged readings span at least
10% of the tracker's total period, with a 6-hour floor for short
trackers (`Tracker.hasSufficientSpanForTrend`, `LinearFit.swift`) — the
chart's trend line is untouched (it still shows *something* even with
sparse data, which is fine for a visual "steepness" cue that's already
being clamped), only the numeric card became more conservative about
when it states a specific number.

**Tracker history duplicate-recording — investigated, not resolved**:
reported as readings seeming to log even when the balance hasn't
changed. Re-read `TrackerStore.refreshFromSource`'s dedup guard (`guard
value != tracker.latestReading?.value else { return false }`) and every
call site (`BackgroundRefreshScheduler`, `TrackerDetailView`) — the logic
already looks correct: a new `ValueSnapshot` is only inserted when the
fetched value differs from the last one on record, for both background
and foreground paths. No bug was found via static review. Possible
explanation floated back to the user rather than assumed: Starling's
`effectiveBalance` includes pending-transaction holds that can genuinely
shift by pennies between polls even when nothing "really" changed from
the user's point of view — meaning what looks like a duplicate-despite-
no-change might be a real (tiny) change. Needs either a real-device repro
with the exact values involved, or confirmation the "duplicates" really
do carry the exact same value, before this can be investigated further.

**Reading History dismissal**: `ReadingHistoryView` was swipe-down-only
to dismiss, not an obvious affordance per Apple HIG for a
sheet/pushed history view. Added a trailing "Done" `ToolbarItem`
alongside the existing gesture.

**Rate-limit insight + smarter refresh cadence** — the largest single
piece of this pass, and the one that went through the most design
back-and-forth before landing (see the "Design process" subsection
below for the actual back-and-forth, since the final design differs
non-trivially from the first few proposals):
- `TrackerDetailView`'s rate-limit error message now names the actual
  retry/reset time instead of a generic "try again shortly"
  (`errorMessage(for:)`, new `retryTimeFormatter`).
- **Settings → General** gained a "Starling Requests Today" section —
  current count vs. the 1000/day limit, an active cooldown message, and
  a manual refresh — via a new `StarlingRequestBudget.status` (`Status`:
  `requestsInLast24Hours`, `dailyLimit`, `cooldownUntil`).
- **Cross-tracker balance cache**: `StarlingBalanceCache` (new actor,
  25s TTL) — two trackers on the same account/Space now share one
  fetched value within that window rather than each polling
  independently, closing a gap the spec had flagged as not built.
- **Refresh cadence redesigned**: foreground is now a flat **45s** poll
  on load + every tick, no adaptive logic at all
  (`TrackerDetailView.basePollInterval`). Background
  (`BackgroundRefreshScheduler`) now uses three local time-of-day bands
  (`TrackerUpdateScheduling.RefreshBand`: peak 08:00–17:00 → 5 min,
  standard → 15 min, off-peak 00:00–06:00 → 60 min) plus **per-tracker**
  burst detection (`isBursting`: more than one reading in a trailing
  30-minute window bumps *that tracker only* to peak cadence, regardless
  of clock time). This needed a real schema change — `Tracker
  .lastAutoFetchAttempt: Date?`, set on every background attempt
  regardless of outcome — since `BGAppRefreshTask` only supports one
  earliest-begin-date for the whole app/process; per-tracker cadence
  instead comes from computing each tracker's own next-due time from
  this field and skipping any tracker that isn't due yet on a given
  wake-up.
- **Compatibility checked before building, not after**: re-confirmed via
  developer.starlingbank.com that a personal access token is still 5
  req/s / 1000 req/day. Worst case under the new bands (one tracker
  sustained at peak cadence around the clock) is ~288 requests/day —
  well inside budget even with several trackers running; the
  `StarlingRequestBudget` hard cap/cooldown already covers the
  pathological continuous-foreground-viewing case regardless of cadence
  design.

**Design process for the refresh cadence** (kept for the record, since
the shipped design differs from the first few ideas floated): started
from "freshest data possible while minimizing/eliminating rate limits."
First proposal (adaptive backoff based on how recently a value had
changed) was rejected — "just because something moves, it doe snot meant
it will move again quickly," and time-of-day matters (unlikely to see
transactions overnight). Added time-of-day bands plus a "look at trends,
ramp up on concurrent changes" idea; the exact burst threshold was
refined twice (first "more than 1 transaction in 20 minutes," revised to
"more than 1 change in a 30 minute window"). Was asked to stop mid-
implementation and design in prose first rather than keep iterating in
code — the design that resulted from that conversation (flat 45s
foreground / three-band + per-tracker-burst background) is what
actually shipped; several rounds of adaptive-foreground logic built
during the earlier iteration were fully reverted, confirmed via a clean
build with no dangling references. The per-tracker-only burst scoping
was an explicit choice over a simpler app-wide-burst approximation, made
knowingly as a real schema change ("we're still building so its ok to
change the schema") rather than deferred.

**Connected Sources wording**: "Reconnect" renamed to "Save" — the old
label read wrong for the common case of just renaming a source, and
"save" better describes what the button does either way (re-validates
the PAT, reports connection status, whether or not the token itself
changed). `AddSourceView`'s title changed from "Reconnect" to "Edit
Source" to match.

### Verifying this session's changes

`xcodebuild build` (iOS, `generic/platform=iOS`) succeeded after every
change in this entry, including the same-day Estimated Final Balance
fix. **Not verified in a simulator/on a real device this session** —
no simulator/device pass was run against the actual UI for any of these
changes (Spaces picker, Edit Tracker Save button, Estimated Final
Balance card, rate-limit Settings panel, background refresh timing).
Background refresh cadence in particular is inherently hard to verify
quickly even on-device, since `BGAppRefreshTask` firing is
system-scheduled and not something a short manual test session can
force reliably — worth specifically watching real background-refresh
behavior over the following few days of normal use rather than treating
this as fully verified from a build pass alone.

## 2026-09-18 Estimated Final Balance: card and chart now share one clamp, not two

Follow-up to the same-day fix in the entry above. That fix added a
minimum-data-span guard (`hasSufficientSpanForTrend`) to withhold the
estimate when readings were too closely clustered in time to trust — a
real safeguard, but not actually what was making the reported number
(`-£1,458.39`) look wrong, since the tracker in question had enough
span to clear that guard and still showed a figure nowhere near where
its own trend line visually ended (screenshotted: the dotted trend line
ran to just under £0, the card said -£1,458).

**Real root cause**: `TrendChartView`'s trend line and
`Tracker.estimatedFinalValue` fit the exact same regression through the
exact same readings and evaluate it at the exact same `endDate` — but
the chart clamps that endpoint into its Y-axis range before drawing
(`yDomain`, an existing workaround for a real Swift Charts bug where an
out-of-frame value's stroke bleeds off the plot area), while the card
was stating the raw, unclamped value. Structurally, the two were always
going to be able to disagree — the span guard reduced how *often* they'd
disagree by a large margin, but never made them structurally incapable
of it.

**Fix**: extracted the clamp itself into one shared property,
`Tracker.plausibleTrendRange` (`WiggleRoomShared/Models/LinearFit.swift`)
— starting value, the fixed target (`projectedFinalValue`), and every
logged reading, padded 10%, exactly what `TrendChartView.yDomain` used
to compute privately. `estimatedFinalValue` now clamps the raw fit value
into this range before returning it; `TrendChartView.yDomain` now just
converts the same range to `Double` instead of recomputing it. The two
can no longer structurally diverge — the card will always show the
literal number the trend line visually ends at, since they're now the
same clamp applied once. The minimum-span guard from the earlier fix was
removed — the clamp alone is what keeps the number sane, and it no
longer needs a separate "don't even try yet" threshold on top.

Chosen over the alternative of switching to a different projection
formula (e.g. averaging the overall observed rate since `startDate`
rather than least-squares through logged readings) — that would still
be capable of producing a large number whenever little time has elapsed
relative to what's left (the ratio-amplification problem is inherent to
*any* linear extrapolation run that early in a tracker's life, not
specific to least-squares), and wouldn't address the actual complaint,
which was inconsistency between the two displayed numbers rather than
the projection method itself being wrong.

### Verifying this change

`xcodebuild build` (iOS, `generic/platform=iOS`) succeeded. **Not
verified on a real device/simulator against the actual tracker the user
reported this against** — worth specifically re-checking that tracker's
detail screen once rebuilt, to confirm the card's number now matches
where its trend line visually ends.

## 2026-09-18 "Starling Requests Today" is now a real, synced, cross-device count

Follow-up to the rate-limit insight added earlier in the same day's
backlog-pass entry. The user's ask, verbatim: it should be "a real count
of all requests across all apps which share that PAT," resetting at
00:00 — and, once told that "across all apps" (meaning any app/script,
not just this one) isn't achievable, clarified the real requirement:
this app's own count, but shared correctly across this user's own
devices, "since it is now sync'd" (the Starling PAT lives on
`ConnectedSource.credentialToken`, CloudKit-synced like everything else,
§5.3 — so the same real token is genuinely active from more than one
device at once, and a per-device-only count was quietly wrong for
exactly that reason).

**What's achievable vs. not, told to the user up front before building
anything**: Starling's public API has no endpoint and no response header
that reports how many requests have been made against a token, to any
client, ever. There is no way — from this app, or any app — to see usage
by some *other* app or script sharing the same PAT. That part of the
original ask is a hard technical limit, not a design tradeoff. What
genuinely is achievable: a true count of every request *this app* makes,
merged correctly across every device the user runs it on.

**Design**: added `StarlingRequestLogEntry` (`WiggleRoomShared/Models/
StarlingRequestLogEntry.swift`) — a minimal `@Model` with just a `date`,
inserted into the same CloudKit-synced schema every other model already
uses (added to `WiggleRoomApp.swift`'s `Schema([...])` list). One record
per real Starling HTTP request, never a shared mutable counter —
CloudKit resolves a genuine write conflict on a single record by picking
one side, which would silently drop whichever device's increment lost;
independent inserts instead merge additively with no conflict possible,
identical reasoning to why `ValueSnapshot` already stores reading history
as discrete records rather than one overwritten "current value" (§6).
`StarlingRequestBudget` gained an `onRequestLogged: (@Sendable (Date) ->
Void)?` hook, fired once per successfully-consumed request slot;
`StarlingProvider.sharedBudget` wires it to a new `StarlingRequestLogger
.record(at:)`, which opens its own short-lived `ModelContext` (not
`container.mainContext`, which is main-actor-bound — this can be called
from `StarlingRequestBudget`'s own, non-main, actor executor) and
inserts/saves. `StarlingRequestLogger.configure(container:)` is called
from `WiggleRoomApp.init()` alongside the existing `BackgroundRefreshScheduler
.register(container:)`, and also prunes entries older than 3 days at
launch — generous enough to always cover "today" in any timezone,
without keeping every request ever made as a permanent synced record.

Both display surfaces (`GeneralSettingsView.starlingRateLimitSection` on
macOS, a new section in `AddSourceView` on iOS — the latter added because
iOS has no Settings scene at all equivalent to macOS's, so the Connected
Source detail screen is the only place to put this there) now read a
live `@Query(sort: \StarlingRequestLogEntry.date, ...)` directly, filtered
in-view to `Calendar.current.isDateInToday($0.date)` — genuinely resets
at local midnight rather than a rolling window, and updates automatically
as CloudKit sync delivers another device's requests, with no polling or
actor round-trip needed for the number itself. The shared caption text
explaining what is and isn't counted (`StarlingRequestBudget.requestCaption`)
lives on the plain, non-platform-gated `StarlingRequestBudget` type so
both the macOS-only `GeneralSettingsView` and the cross-platform
`AddSourceView` can reference the same string without either depending
on the other.

**What deliberately did not change**: `StarlingRequestBudget.consumeSlot()`
— the actual pre-flight check that refuses to make a request once near
the daily cap — still uses its original local, in-memory, rolling-24h
window, unaware of other devices. This is a deliberate choice, not an
oversight: it's a same-device safety margin, and Starling doesn't
document whether its own real daily window is rolling or resets at a
fixed clock boundary, so weakening this check to match the new
midnight-reset *display* semantics would have traded a conservative,
safe local guard for one that could theoretically let a device exceed
the real cap depending on how Starling's own window actually works. The
existing 429-triggered cooldown (`recordRateLimited`) remains the
authoritative backstop regardless of how any client-side estimate is
computed.

### Verifying this change

`xcodebuild build` succeeded for both `platform=macOS` and
`generic/platform=iOS`. `xcodebuild test` (macOS) — `StarlingRequestBudgetTests`
and `StarlingAPIClientTests` (9 tests total) — passed unchanged (the
`onRequestLogged` parameter defaults to `nil`, so no existing test needed
updating). **Not verified on a real device against genuine multi-device
sync** — worth specifically checking, once this reaches an actual iPhone
and Mac signed into the same iCloud account with the same Starling
source connected, that a request made on one device does show up in the
other device's "Starling Requests Today" figure within a reasonable
CloudKit sync delay.

## 2026-09-18 Incident: mismatched SwiftData schemas across processes caused duplicate then vanished data

**Symptom, reported by the user in this exact order**: a Starling tracker
appeared duplicated (an exact clone — same name, dates, values) with no
user action taken on any device; roughly an hour later, still without
touching the app; about 30 minutes after that, **both the duplicate and
the original tracker were gone, and separately, every Connected Source
had also disappeared**. Confirmed the user runs the app on more than one
device (iPhone + Mac) signed into the same iCloud account, and that the
duplicate was an exact clone, not two separately-entered trackers.

**Investigation**: first ruled out an obvious application-level cause —
grepped the whole codebase for anywhere a `Tracker` gets created and
found exactly one call site, `AddTrackerView.save()` → `TrackerStore
.addTracker(_:)`, already guarded against a same-device double-tap by an
earlier fix in this same session (an `isSaving` flag disabling the Save
button for the duration of the call — see the entry above). That
ruled out the most obvious "why would this be duplicated" theory.

With a code-level double-insert ruled out and the user confirming
multi-device use, the investigation turned to how the shared store itself
is configured. This app has **six separate places** that construct a
`ModelContainer`/`Schema` against the same on-disk store (the App
Group-shared, CloudKit-synced SQLite file) or an in-memory preview
equivalent:

- `WiggleRoomApp.swift` (the main app — every platform)
- `WiggleRoomShared/WidgetDataStore.swift` (Home/Lock Screen widgets, the
  watch complication — a separate process per extension)
- `WiggleRoom/Intents/IntentDataStore.swift` (Shortcuts/Siri, runs even
  when the app isn't open)
- `WiggleRoomWatch/WiggleRoomWatchApp.swift` (the watch companion app)
- `WiggleRoom/PreviewSupport.swift` / `WiggleRoomShared/SharedPreviewData.swift`
  (in-memory only, `#Preview` blocks — no real corruption risk, but
  worth keeping consistent so a preview referencing a newer model
  doesn't crash the canvas)

Earlier the same session, `StarlingRequestLogEntry` (§5.3's cross-device
Starling request log) was added to **only the first of these** —
`WiggleRoomApp.swift`'s `Schema([...])` — because that was the only file
actually read/edited while wiring up that feature. The other five were
never touched, and so kept declaring the old, three-entity schema
(`Tracker`, `ConnectedSource`, `ValueSnapshot`) — while pointed at the
exact same physical store the main app had already migrated to include a
fourth entity type.

**Why this is a real corruption mechanism, not just an inconsistency**:
SwiftData is built on Core Data's `NSPersistentCloudKitContainer`. Every
process that opens a given persistent store (here, the same SQLite file
via the shared App Group container, additionally CloudKit-mirrored)
needs a `Schema` that matches what's actually on disk — Core Data
performs its own migration/compatibility check on every open, and a
process opening a store with a model missing an entity type the store
already has is exactly the kind of "incompatible persistent store"
situation Core Data's automatic lightweight migration handling is not
guaranteed to resolve safely, especially layered under CloudKit's own
independent per-process mirroring/import-export engine. Each of the five
mismatched processes (widget extension, watch app, watch complication,
Shortcuts intent handler) could open the shared store at any time —
a widget re-rendering, a complication updating, a Shortcut running in the
background — with no user interaction required, which lines up exactly
with the user's report of changes happening with the app not open on any
device. The mechanism most consistent with the observed symptoms (a
spurious duplicate, then a wholesale wipe of multiple entity types) is a
destructive local migration/reset triggered by one of these mismatched
processes, which then propagated via CloudKit sync to every device.

**Fix**: every one of the six `Schema([...])` declarations now lists the
exact same model types (`Tracker.self, ConnectedSource.self,
ValueSnapshot.self, StarlingRequestLogEntry.self`), with a comment at
each site explicitly naming every other site that must be kept in sync
with it. This is a **standing rule for all future work on this project,
not a one-off fix for this incident**: any new `@Model` type added to
the schema from now on must be added to all six call sites in the same
change — `WiggleRoomApp.swift`, `WidgetDataStore.swift`,
`IntentDataStore.swift`, `WiggleRoomWatchApp.swift`,
`PreviewSupport.swift`, `SharedPreviewData.swift` — or this exact failure
mode can recur, this time potentially with real (not test) data.

**Data lost**: the user confirmed everything lost was test data created
during this session's own feature testing, not anything irreplaceable —
so no recovery attempt was needed or made. Had this been real data, the
realistic recovery options would have been limited: Apple does not
expose end-user-facing CloudKit record history/undelete for a private
database outside the CloudKit Dashboard (a developer tool, not something
built into this app), so the practical options would have been checking
whether any single device's own local App Group store still held a
pre-wipe copy before it next opened with a (then-still-mismatched) build
and got wiped/reconciled itself — a race against further app/widget/
Shortcut launches on any device, which is exactly why the user was asked
to stop launching the app anywhere while this was being diagnosed.

### Verifying this fix

`xcodebuild build` succeeded for the `WiggleRoom` scheme (which builds
and embeds the Watch app and widget extension targets as part of the
same scheme) on both `generic/platform=iOS` and `platform=macOS` —
confirms every one of the six sites compiles with the now-consistent
schema. **Not verified against a real multi-device reinstall** — this
needs the user to rebuild and install the fixed version on every device
they use, and ideally do so close together in time (quitting the app
everywhere first) rather than leaving an old mismatched build running on
one device while a fixed build runs on another, which would recreate the
exact same mismatch condition during the transition.

## 2026-09-18 macOS: right-click delete on tracker rows, bypassing selection

Follow-up to the schema-mismatch incident above. While cleaning up the
corrupted test data left behind by it, the user found two remaining
trackers in the macOS sidebar that **could not be selected at all** —
clicking did nothing, so there was no way to open them and use the
normal Edit Tracker → Delete flow. Consistent with the underlying store
having been left with ambiguous/duplicate row identity by the earlier
incident: `MacRootView`'s sidebar `List(trackers, selection: $selection)`
matches taps to rows via `tracker.id` (`.tag(tracker.id)`), and if two
rows' `Tracker` objects don't have cleanly distinct identity at the
SwiftUI diffing level, tap-to-select can silently fail to register for
either.

Added a `.contextMenu` (right-click) "Delete Tracker" action directly on
each sidebar row, calling `store.deleteTracker(tracker)` against that
row's own `Tracker` reference from the `trackers` array — entirely
independent of `selection`, so it works even for a row selection itself
can't reach. `xcodebuild build` succeeded on `platform=macOS`.

**Not a fix for the underlying identity ambiguity itself** — just a
practical way to delete an affected row when it happens. If a tracker
ever again can't be selected/opened normally, this context menu is the
way to remove it.
