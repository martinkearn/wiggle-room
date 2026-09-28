# Wiggle Room — Build Specification

## 1. Product

Wiggle Room tracks a quantity against the pace required to reach a defined budget at the end of a fixed period. Example trackers include:

- **Holiday spending** — a decreasing currency balance.
- **Family car mileage** — an increasing distance allowance.
- **Coffee subscription** — a decreasing count entered manually.

The product is designed for one person's use across their own Apple devices. It does not provide cross-account sharing or collaborative editing.

## 2. Platforms and technology

- iOS and iPadOS
- macOS
- watchOS companion app and complication
- WidgetKit widgets and Live Activities
- SwiftUI user interface
- SwiftData persistence with CloudKit private-database sync
- App Groups for same-device access by apps and extensions
- HealthKit on iOS and iPadOS only, via a per-SDK entitlements file (a macOS App ID cannot carry the HealthKit capability)

The minimum systems are iOS and iPadOS 26.5, macOS 26.5 and watchOS 26.0. The app is built with Xcode 27 or later (the iOS 27 and macOS 27 SDKs), locally and in CI.

visionOS and Mac Catalyst are not currently supported.

## 3. Tracker model

A `Tracker` represents one allowance over a date range.

| Field | Purpose |
|---|---|
| `id` | Stable UUID |
| `name` | User-facing name |
| `typeRawValue` | Tracker type, stored as a plain string |
| `unit` | Measurement unit, constrained to those the type permits |
| `startDate`, `endDate` | Tracking period |
| `startingValue` | Value at the beginning of the period |
| `totalAllowance` | Planned movement over the period |
| `connectedSource` | Manual or external data source |
| `sourceTargetId` | Provider-specific account or target identifier |
| `sortOrder` | Synced custom ordering |
| `colorIndex`, `glyph` | Visual identity |
| `isZoomed` | Whether the rings and chart are zoomed to five days (see Zoom) |
| `reminderCadenceMinutes` | Optional manual-entry reminder |

### Tracker types

Every tracker is one of seven types, chosen at creation and locked thereafter. The type sets the permitted units, the direction, the polarity, all user-facing wording, the default glyph and reminder, and which sources may back it.

Direction and polarity are independent axes. Direction is which way the value travels; polarity is which side of the pace line is the good side. Those two axes carry all the behavior, so a new type is a matter of wording and units rather than new pace maths.

| Type | Direction | Good side | Orientation | Units |
|---|---|---|---|---|
| Spending Money | Decreasing | Higher | Allowance | £, $, € |
| Spending Credit | Increasing | Lower | Allowance | £, $, € |
| Saving Money | Increasing | Higher | Goal | £, $, € |
| Mileage | Increasing | Lower | Allowance | mi, km |
| Weight loss | Decreasing | Lower | Goal | kg, lb |
| Rising Number | Increasing | Higher | Goal | none |
| Falling Number | Decreasing | Lower | Goal | none |

Spending Credit is the mirror of Spending Money: the same spending, counted upward on a card toward a limit rather than downward out of a balance, so a lower figure is the good news. The two plain-number types are the catch-all for anything the named types don't cover, and share one neutral set of wording (Value, Target) because a plain number has no domain noun to borrow.

Orientation decides how the whole-period figure is entered. An allowance type is entered as a movement ("a £500 budget"); a goal type is entered as an end value ("£5,000", "85 kg"). Storage is uniform: a goal type's `totalAllowance` is the distance from `startingValue` to the stated goal, recomputed if the starting value is later edited so the goal itself cannot drift.

`TrackerType` owns a terminology table covering every type-dependent phrase — the current figure, the current pace figure ("Budget now", "Target now"), the whole-period figure, the final figure, the three status labels, the remaining-amount caption, and the completion celebration. Each type needs a whole-period noun and a current-pace noun, because the dashboard shows both figures side by side.

`typeRawValue` is a plain `String` with a default rather than an enum attribute, and is read through an accessor that falls back to a known type. A newer build writing an unrecognised value must not fault an older device that syncs the record.

### Units

Precision and the amber floor belong to the unit, not the type: kg and lb differ within Weight loss, while the currencies are shared by all three money types.

| Unit | Placement | Precision | Amber floor |
|---|---|---|---|
| £ $ € | Prefix, no space | 2 dp | 0.02 |
| mi | Suffix, space | 0 dp | 2 |
| km | Suffix, space | 0 dp | 2 |
| kg | Suffix, space | 1 dp | 1.0 |
| lb | Suffix, space | 0 dp | 2 |
| none | No symbol | 0 dp | 2 |

The plain-number types use a unit with no symbol at all, so their figures render bare (`8,400`). It is still a real unit rather than a special case, so precision, rounding and the amber floor keep working the same way everywhere. Because a unit's raw value is its symbol for every unit that has one, `Tracker.unit` stores the raw value — the unitless one stores the word `number`.

A whole value drops its decimals entirely, so values read as `£684`, `£692.40`, `8,400 mi`, `85 kg`, `84.6 kg`, `8,400`. A zero-precision unit rounds typed input up to a whole number, with the rounding stated inline on the log screen. Rounding is a property of the unit, so both plain-number types round the same way even though they run in opposite directions.

Each reading is a separate timestamped `ValueSnapshot`. Reading history is append-oriented so CloudKit can merge updates made on different devices.

A reading fetched from a source is recorded only when it is genuinely new: newer than the latest reading already held, and a different value at the unit's own precision. A source that reports historic readings carries its own timestamp into the record — an Apple Health weigh-in appears on the chart at the time it was taken, not the time it was collected — and a reading dated before the tracker's start is not recorded at all.

A tracker's `name` must be unique (case-insensitive) among the user's other trackers; Add/Edit Tracker blocks Save on a collision.

### Pace calculation

For a point in time inside the tracking period:

```text
elapsedFraction = elapsedTime / totalPeriod
expectedConsumption = totalAllowance × elapsedFraction
```

For a decreasing tracker:

```text
actualConsumption = startingValue - currentValue
```

For an increasing tracker:

```text
actualConsumption = currentValue - startingValue
```

Consumption alone cannot say whether a tracker is doing well, because consumption is the point for a goal type: saving faster than planned, or losing weight faster than planned, is the good case. Status is therefore decided by a polarity-aware figure:

```text
goodness = higherIsBetter ? (currentValue - targetValueToday)
                          : (targetValueToday - currentValue)
```

`goodness >= 0` is on or ahead of pace. For a decreasing "higher is better" tracker this reduces algebraically to `expectedConsumption - actualConsumption`, so Spending Money behaves exactly as before. Direction is still used for ring fill, consumption, and the chart's reference line.

The traffic light is green at or ahead of pace, amber within the early-warning band behind it, and red beyond that:

```text
amberBand = max(0.05 × totalAllowance, unit.amberFloor)
```

There is no grace zone before green turns amber: any shortfall means the actual figure has already slipped past the target figure printed beside it. The per-unit floor matters only for weight, where day-to-day variation of about ±1 kg from water, food in transit and sodium would otherwise push a user who is exactly on pace into red. Guidance about weighing weekly lives in the reminder default rather than in the thresholds.

Values are clamped where needed for presentation, but stored readings remain unchanged.

## 4. Sources

`SourceProvider` isolates provider-specific behavior from tracker calculations and UI. Each provider declares the tracker types it can back, so the relationship lives with the provider rather than being hard-coded per type: Starling supplies the two account-balance money types, Apple Health supplies Weight loss, Manual Entry suits them all, and a future vehicle source would declare its own. Spending Credit is deliberately outside Starling's set: Starling reports an amount held rather than an amount owed, so a synced balance would travel the wrong way against a credit limit. Add Tracker filters its source list through that declaration once a type is chosen.

### Manual Entry

Every tracker accepts manual readings from Balance History, including trackers connected to an external source. Any reading can be edited or deleted there regardless of how it was created. Manual trackers additionally retain their pull-to-update entry gesture. The internal Manual Entry `ConnectedSource` is plumbing rather than an external connection. Duplicate manual records are consolidated automatically without deleting trackers.

### Starling

The Starling provider uses a user-supplied personal access token and supports:

- Account discovery
- Main account balances
- Savings goals and spending spaces
- Manual refresh and scheduled background refresh
- Request-budget and cooldown handling

Requests go directly to `https://api.starlingbank.com` over HTTPS. The app does not operate an intermediary server and does not initiate payments.

### Apple Health

The Apple Health provider reads one figure — the latest body-mass sample — and backs Weight loss trackers only. It is read-only in the strongest sense: the app requests no write access, so a weight typed by hand in Balance History stays in Wiggle Room and is never pushed into Health. HealthKit only ever exposes the Health store of the person signed in on the device; there is no API for anyone else's health data and none is sought.

There is no credential. A Health source's `credentialToken` stays empty and is never read, because authorisation lives in the system's own Health permissions, per device, and cannot be synced or inspected by the app. HealthKit never reports read permission back either, so a refusal is indistinguishable from an empty Health store: both look like no samples, no error, and no reading logged, and no screen claims to know which happened. Exactly one Health source exists, since it is the one Health store the device owner already has; Add Source stops offering it once one exists.

HealthKit is unavailable on macOS. It exists on iOS, iPadOS, watchOS, Mac Catalyst and visionOS, and this project builds neither Catalyst nor visionOS, so Health is an iPhone and iPad feature here. Elsewhere a Health-backed tracker is a read-only view of readings those devices fetched (see Platform behavior).

A tracker's unit is editable after creation, so the unit can't be encoded into `sourceTargetId` the way Starling encodes an account and Space — it travels with each request on `SourceTarget.unit` instead, and the provider reads body mass in kilograms or pounds accordingly. Values are rounded at the unit's own precision before anything compares or stores them, since Health holds a weight as a double and an unrounded 84.6 kg would otherwise register as a change on every poll.

Additional providers should conform to `SourceProvider` and remain isolated from the core tracker model. `SourceProvider` also declares the word a provider uses for one of its targets ("Account" for a bank, "Measurement" for Health), and whether it can be read on the device running right now.

### Safeguards

A connected source's `displayName` must be unique (case-insensitive) among the user's other sources; adding, reconnecting, or renaming one blocks on a collision. A source cannot be removed while any tracker still points at it — its detail/edit screen lists every tracker currently using it, and removal must be preceded by deleting or reassigning them.

## 5. Persistence and sync

Every process uses one SwiftData schema, `WiggleRoomSchema`, containing:

- `Tracker`
- `ValueSnapshot`
- `ConnectedSource`
- `StarlingRequestLogEntry`

The persistent store uses the app's CloudKit container and App Group. CloudKit syncs between devices signed into the same Apple ID; the App Group lets the app, widgets, and related extensions share current data on one device.

CloudKit synchronization is asynchronous. UI must tolerate temporarily empty or stale local stores and must not treat a short delay as data loss.

Every process registers for remote (silent push) notifications so an already-running, foregrounded app picks up another device's changes promptly rather than only on its own next periodic or opportunistic import.

If the CloudKit-backed container cannot be created, the app records that state in its diagnostics and may fall back to local persistence rather than crash.

A process opens exactly one CloudKit-mirrored container for the store. A second one in the same process fails CloudKit setup (Cocoa error 134422, "another instance of this persistent store actively syncing with CloudKit in this process") and competes with the first. Inside the app, App Intents, Spotlight indexing and notification actions therefore use the app's own container and `TrackerStore`, which the app registers with `IntentDataStore` as it launches. A process in which the app never ran opens its own. Widgets, the complication and the watch app each run in their own process with their own container.

A container loading with CloudKit does not mean sync is working: the server can reject every upload while downloads still arrive, so each device drifts quietly away from the others. The CloudKit Sync screen therefore reports the last setup, download and upload event CloudKit has posted since the app launched (`NSPersistentCloudKitContainer.eventChangedNotification`, which SwiftData's mirroring posts too), with when it finished and, for a failure, why. For a partial failure the reason is the per-record errors, because that is where CloudKit names the actual problem, such as a field missing from the Production schema. A failed result stays on screen while CloudKit retries, until another result replaces it. The watch app has no diagnostics screen, so it does not record these events.

Widget and complication configuration pickers read tracker names from a small snapshot cached in the App Group container, refreshed whenever any process fetches current tracker data, rather than always waiting on a fresh CloudKit round trip before showing a list.

### Live queries and view nesting

Views read the tracker and source lists with `@Query`, which stays live and republishes as the store changes.

A screen pushed or presented from a `@Query`-backed view must not observe SwiftData from its `body` — no live query, no relationship traversal, no model property read during `body`. Such a screen seeds local state in `init` or on appear, and reads the model only in the action that saves; validation needing current data uses a one-shot fetch at that point.

Breaking this rule is a hang, not a redundancy: the two views rebuild each other indefinitely and iOS kills the app on the watchdog. See [`swiftdata-update-loops.md`](swiftdata-update-loops.md) for the mechanism, the diagnostic signature, and how to reproduce it.

Live `@Query` remains correct and preferred for a view that is not itself rebuilt by another view's query.

## 6. Visual language

The interface should feel calm and informative rather than punitive.

- The outer ring represents elapsed time.
- The inner ring represents consumed allowance.
- Green indicates on pace or better, whichever side of the pace line the tracker's type treats as good.
- Amber indicates a small shortfall, never narrower than the unit's own floor.
- Red indicates a larger shortfall.
- Status wording comes from the tracker type's terminology table, so no surface can drift from another.
- Tracker identity colours do not replace status colours.
- Fraunces is used for names and headings; Nunito is the primary text face.
- Numeric values remain the source of truth and accompany visual indicators.

### Tracker colours and status colours

Each tracker carries an identity colour from a fixed palette, used for its badge, row and card washes, header glow and widget background.

A few surfaces draw that identity colour immediately against a status colour: the chart's pace line beside the green/red actual line, the rings' unfilled track beneath the green/amber/red arc, and the pace figure card beside the status-tinted current figure card. On those, a palette colour that is itself a status hue cannot be read — a green tracker's pace line looks like "ahead of pace", a red one's like "behind".

Every palette entry therefore has a second value, its **reference colour**, and those surfaces use it. It is the identity colour itself for entries already clear of the status hues, and a stand-in for those that are not. A stand-in keeps its entry's lightness and weight, so the tracker still reads as itself, and clears green, amber and red by a wide margin in both appearances. Peach, Toffee, Forest, Sunshine and Cherry currently need one; the remaining seven do not. Everything else keeps the identity colour, so a tracker still looks like the colour that was chosen for it.

The palette is audited against the status colours whenever either changes. Only green, amber and red take part: the stale/error colour is text-only and never drawn on a ring or a chart.

### Zoom

A tracker whose period is longer than five days can be zoomed. Zoom magnifies the rings and chart like a pinch-zoom on a static image. It never changes stored data, the centre figure, the status colour, or the figure cards, which all stay whole-period.

- **Window.** Five local calendar days: two days before today, today, and two days after. The window slides, keeping its length, so it never extends outside the tracking period, and it moves forward at local midnight.
- **Eligibility.** A completed tracker, or one whose period is five days or fewer, renders unzoomed. Its stored `isZoomed` flag is kept but ignored.
- **Rings.** Each ring shows only the part of its whole-period ring that falls inside the window, stretched to fill the circle. The outer ring is the share of the window elapsed. The inner ring maps the pace line's expected consumption at the window's start and end onto empty and full, so a tracker on pace has both rings level. A value outside that slice pins the inner ring at empty or full, and a chevron marks it where the ring is wide enough.
- **Chart.** The x-axis covers the window with daily ticks. The y-axis is fitted to the pace line, the readings and the carried-forward "now" point inside the window. Lines crossing the window's edges are interpolated to the edge before reaching Swift Charts.
- **State.** `isZoomed` syncs with the tracker and is included in exports. Archives without it import as not zoomed.

The app's rings, cards, and chart strokes use a deliberately irregular, hand-drawn style. Accessibility labels must communicate the same information without relying on colour or geometry alone.

### Ring motion

The rings say *why* they moved. Each change has one of three causes, each cause has its own animation, and only one plays at a time. `RingMotion.reason` decides which from the old and new state: the two fractions, the latest reading's id, and the zoom flag.

- **Arrival: the tracker was opened.** Both rings grow from empty with an overshoot spring, the inner ring 40–90ms behind the outer. It is deferred 0.05s past the system's own launch or push transaction, which would otherwise swallow it. A change landing before the arrival settles redirects it rather than playing a second animation, so a connected tracker's on-open refresh grows the rings straight to the refreshed figure.
- **Update: a new latest reading.** Both rings drain to empty and refill. Keyed on the reading's identity, not its value, so re-logging the same figure still registers.
- **Drift: the target moved, the reading did not.** Never from empty. Each ring that moved dips to 94% of where it was drawn and springs to its new value, while its outline's `wobble` swells to 0.6 and settles over about 0.6s. Drift plays only once a ring has moved at least 0.0025 of a turn since it was last drawn, so the 30-second clock leaves slow trackers' rows still. Each surface waits a random 0–400ms before drifting, so a list never wobbles in unison.
- **Zoom** slides both rings straight to their new fills.

Every scheduled step carries a token, so a newer change never leaves an older refill or drift return queued behind it. The arrival, refill and drift springs vary by up to ±10% per play. A full ring's closing overlap is latched on its target fraction, so it holds through a drift's dip. An update's drain still removes it.

While a refresh the user asked for is in flight (pulling down on iOS and iPadOS, or the Update button on macOS), both ring outlines hold a slow wobble in place of the system spinner. The wobble swings to 0.5 and back, 0.9s each way, on top of any drift wobble, and settles when the fetch lands. `.refreshable` cannot restyle its spinner, and keeps it up exactly as long as its action runs, so a connected tracker's pull starts the fetch and returns straight away. Meanwhile the pull hint reads "Updating current …", which is the only sign under Reduce Motion, where the rings stay still. The refresh that runs when a tracker is opened does not wobble, because the rings are playing their arrival then. Manual trackers are unchanged: pulling opens the log sheet.

Live figures move with the rings. The ring's centre figure, the tracker screen's two figure cards and the list row's three figures roll their digits (`.contentTransition(.numericText(value:))`), up for a rising value and down for a falling one. Each carries its own animation keyed on its formatted text, because neither the pace clock nor a reading arriving through SwiftData changes it inside an animation. When the pace status changes, the status colour cross-fades on the rings, the figures and the cards, and the status word takes a single spring of emphasis. Both are keyed on `PaceStatus` itself.

Under Reduce Motion the rings draw at their final value with no growth, an update goes straight to the new value, drift does nothing, figures swap without rolling and the status word stays still. The status colour still cross-fades.

Widgets, complications and the Live Activity render a static snapshot before any deferred animation could run, so they pass `isAnimated: false` and draw the real value with none of this motion and no randomness.

The empty-state mark (`EmptyRingsMark`) breathes on live screens: its outline's `wobble` swings between 0.7 and 1.3 around its resting 1 over a four-second cycle, so the lines look redrawn by hand. It is opt-in through `breathes`, which defaults to off, because a widget or complication snapshot would catch the breath at an arbitrary point and flicker between reloads. The list and shared empty states, the macOS menu bar dropdown and the watch list opt in. The widgets and the complication do not. The breath is a SwiftUI phase animation rather than a timer, so it runs only while the mark is on screen and the app is active. It stops under Reduce Motion and while the display is dimmed, such as the always-on watch face.

### Haptics

Two moments are felt as well as seen, on the same triggers the rings use:

- **A reading lands.** A light impact when a tracker's latest reading changes, whether it was logged or fetched.
- **The pace status changes.** Feedback weighted by the status the tracker lands on: warning into amber, error into red, success back to green. A crossing takes the place of the reading tap when one reading causes both.

Each event is felt once, however many surfaces show the tracker. The haptics are driven from one view per device that stays alive whenever a tracker is on screen: the iOS tracker list's navigation stack and the watch's root list. They are never driven from a row or from `RingsView`. If several trackers change together, as in a background refresh, one haptic plays for the most severe change. A tracker with no readings has no pace to cross.

Drift has no haptic: a tap in the hand twice a minute would not be subtle. Haptics are not gated on Reduce Motion, so these moments stay marked for someone who has turned the ring animation off. macOS has no haptics, and `.sensoryFeedback` is a no-op there. The completion celebration's success haptic uses the same `.sensoryFeedback` mechanism.

### Tracker screen layout

A tracker's own screen is headed by its name and nothing else. It carries the same badge — glyph and colour — that the tracker wears in the list, so the screen is recognisably the row that opened it, and the badge sits immediately beside the name in the heading on every platform: in the navigation bar itself on iOS and iPadOS, and in the in-content header on macOS, where the window title cannot take the app's own typeface.

The period's date range and, for a connected tracker, its connection and account sit with the days-remaining line below the figures, not under the heading. They were previously drawn beneath the title, which never closed the gap above them: the iOS system navigation subtitle shows only one line and reserves space whether or not it is used, so a two-line strip had to be drawn separately and always left a gap. Keeping all three lines together, away from the heading, removes the constraint rather than working around it.

### Tracker list row

On iOS and iPadOS a list row is the tracker's own dashboard in miniature, in two bands sharing one leading gutter:

- **Identity.** The badge, the tracker's name across the full width of the card, the zoom marker, and one caption line giving how much of the period is left and the date it ends on. The name wraps to a second line rather than truncating: it is the one thing on the row the user chose themselves.
- **Data.** The rings, then the status wording with the ahead/behind figure in the status colour, then the current figure and the current pace figure side by side, each named with the type's own noun.

The row shows both of the figures the ahead/behind figure is the difference between, because a difference alone cannot say whether a tracker is nearly finished or barely started. Wording and figures come from the same `TrackerPace` and terminology table the dashboard uses, so the row and the screen it opens can never disagree.

The badge and the rings share the gutter's width and so sit concentric down the card, which also lines every row's rings up down the list. That alignment used to need a fixed-width trailing column holding the rings clear of a variable-width status column; anchoring them to the leading edge gets it for free, and the status text is free to use the width it needs.

A newly created tracker's row arrives with character. The tracker is saved while the add sheet still covers the list, so the list holds its row back until the sheet has gone. It then inserts the row, the other rows move aside, and the new row springs from 92% size with a slight tilt as its rings play their own arrival. The row's spring is quicker and calmer than it would be alone, so the rings' overshoot stays the main event. Only the new row animates. Under Reduce Motion it simply appears. Deleting a row keeps the system animation, and reordering keeps the platform's own editing behaviour.

macOS keeps its own compact sidebar row, which is a navigation list rather than a dashboard.

## 7. Platform behavior

### iOS and iPadOS

- Tracker list and detail navigation
- A toolbar zoom toggle on eligible trackers' detail screens, with the zoomed date range shown under the rings; list rows, the menu bar, and medium and larger widgets mark zoomed trackers with a small magnifier
- Pull-to-refresh/update behavior
- Add and edit trackers and connected sources, reached from a `+` in the tracker list's top-right toolbar; the empty state keeps its own prominent button, since there is no list for a `+` to sit above yet
- Settings for General app preferences, sources, ordering, CloudKit diagnostics, Siri phrases, and an About screen reporting the running version, build number and source commit, with a separate Danger Zone menu for reset operations
- JSON export and import of tracker configuration and complete reading history
- Spotlight, notification actions, Live Activities, and widgets

The connected-source editor on iOS shows a name field, a Connected/Not Connected indicator, a personal-access-token field, save, the trackers using the source, and the shared Starling request count. It carries no provider badge.

Tracker exports contain every field needed to preserve appearance, pace, completion state, ordering, reminders, and reading history. They identify external source types but exclude credentials. Import requires each external source to be mapped to an existing source of the same type or explicitly imported read-only; a read-only tracker can later be connected from Edit Tracker.

It is reached from a `@Query`-backed list, so its body observes no SwiftData at all (see Persistence and sync). Every store-derived value on it is a one-time read taken as the screen opens — connection state, tracker names, and request count alike — held as plain values rather than model references, and none of them updates while the screen stays open. That is intentional rather than a limitation: nothing can change them underneath the user in practice, since saving dismisses the screen. macOS keeps the richer inline editor, which is not reached that way and does show them live.

### Device-bound sources

A source that is read from the device itself rather than over the network — Apple Health today — can only be read where that data exists. Every surface asks the provider (`isAvailableOnThisDevice`) rather than checking the platform, so one rule covers macOS, watchOS and any future device-bound source.

Where the answer is no, the tracker is a read-only view: it displays exactly as it does anywhere else, computed from synced readings, and the update control gives way to a line saying the readings come from the user's iPhone or iPad. Nothing is fetched, no check is recorded, and no error is shown, because nothing failed. Everything that isn't a fetch still works — Balance History adds, edits and deletes readings by hand, and Edit Tracker behaves as it does for any connected tracker. A Mac can create a Health-backed tracker (the source is a synced record and its measurement resolves without touching HealthKit; the starting weight is typed in), but it cannot add the source itself, since authorisation only exists on the device that grants it.

### macOS

- Sidebar-based tracker interface, with a `+` in the sidebar's toolbar alongside the existing new-tracker menu command
- Dedicated Settings window
- Menu bar presentation for a selected tracker. The status item itself shows only that tracker's badge — its glyph in its own colour — and no figure; the figures live in the dropdown, where they have room to be labelled. The badge is rendered to a non-template image, since a status item's image is otherwise filled flat with the menu bar's own foreground colour and the colour would be lost
- Explicit update controls where pull-to-refresh is unavailable
- JSON export and import of tracker configuration and complete reading history

### watchOS

- Tracker list and compact detail presentation, including the zoom toggle
- Manual reading entry
- WidgetKit complication

### Widgets and intents

- Single-tracker status and chart widgets
- All-trackers widget
- Small, medium, large and extra-large sizes. Extra-large is offered on iPad, and on iPhone and Mac from iOS and macOS 27; the system leaves it out of the widget gallery on earlier versions.
- Configurable tracker selection through App Intents
- Siri intents for opening trackers, checking status, and logging readings

## 8. Background work

- Background refresh is opportunistic and must never be the only way data is updated.
- Polling cadence follows the provider behind each tracker. A bank balance can move at any moment, so Starling keeps its time-of-day bands and burst detection. A weight moves once a day, so Apple Health is read once per local day at 20:00 — late enough to have caught a morning weigh-in — with burst detection deliberately not applied.
- A daily source is also read when the app becomes active and its slot has passed, because a background wake-up may never come. That read is local, costs nothing, and cannot raise a permission prompt.
- Provider calls respect request budgets and server cooldowns.
- Multiple trackers targeting the same provider value reuse short-lived cached results where possible.
- Widget timelines reload after relevant local or CloudKit changes.
- Manual reminders use local notifications.

## 9. Security and privacy

- Never commit credentials or real financial data.
- Provider credentials are stored on the user's private CloudKit-synced `ConnectedSource` record so the connection can work across their devices.
- Credentials must never be logged or included in diagnostics.
- Credentials must never be included in tracker exports.
- Starling traffic is sent only to Starling's HTTPS API.
- Apple Health is read-only and body mass only: no write access is requested, no other quantity type is read, and nothing is ever written back to Health. The Info.plist still carries both Health purpose strings, because App Store upload validation rejects a build holding the HealthKit entitlement without them; the write string states plainly that the app doesn't write, and can never be shown since no write authorisation is ever requested. Health data is never sent anywhere — Starling remains the app's only outbound traffic.
- Weight values never appear in diagnostics or logs, exactly as no other tracker figure does.
- Health-derived readings are stored in the app's own CloudKit private database like every other reading, because cross-device history is the point of the feature. App Store Review Guideline 5.1.3 says apps using HealthKit must not store health information in iCloud, so a public App Store submission would need that decision revisited; for personal and TestFlight use it is the owner's own data in their own private database.
- The macOS app requires the outbound network client sandbox entitlement.
- Reset operations require explicit user confirmation.
- Diagnostic screens may show identifiers and counts, but not credentials or financial values unrelated to normal tracker UI.

## 10. Deployment

The main app and every embedded extension must use matching marketing and build versions. TestFlight distribution requires separate iOS and macOS archives.

Automated builds may use a monotonically increasing CI run number for `CURRENT_PROJECT_VERSION`, provided it is applied consistently to the app, watch app, widgets, and complications.

Signing, provisioning, CloudKit containers, App Groups, and bundle identifiers must be configured for the developer account performing the build.

A provisioning profile carries the capabilities its App ID had when the profile was generated, so a new entitlement means enabling the capability and regenerating the affected profiles. The iOS app's App ID needs HealthKit; macOS must not have it, since a macOS App ID cannot carry it. An unsigned build check cannot catch a mismatch here — only an archive can.

### CloudKit schema

Development-signed builds sync against the Development CloudKit schema. TestFlight and App Store builds sync against Production, which changes only when someone deploys to it.

- A change that adds a SwiftData model, or adds or renames a stored property on one, needs **CloudKit Console → Deploy Schema Changes** (Development → Production) before its TestFlight build ships. Until then the server rejects every upload batch containing the new field, while downloads keep working.
- The Development schema only gains a field once a development-signed build has uploaded a record containing it.
- Fields deployed to Production cannot be removed.

`cloudkit/schema.ckdb` is the committed schema: every record type and field the app syncs, exported from Development. It is a superset of the models, because it keeps retired fields such as `CD_direction` that Production can never drop. Every process opens its store with the one model list in `WiggleRoomSchema`.

When a model changes, the file needs updating only if CloudKit gains something:

| Model change | Update `cloudkit/schema.ckdb` and deploy? |
|---|---|
| Add a stored property | Yes. |
| Rename a stored property | Yes. CloudKit sees a new field; the old one stays in Production, unused. |
| Add a model | Yes. It is a new record type. |
| Remove a stored property | No. Production keeps the field for good, so the file keeps it too; the app simply stops writing it. |
| Change a stored property's type | Avoid. A deployed field's type cannot change, so add a property under a new name instead, which is an addition. |
| Computed properties, `@Transient` properties, logic or UI | No. None of them reach CloudKit. |

The file is replaced by a fresh export, never edited by hand, except as a stand-in until the owner can export (see below).

Two checks enforce the schema, each catching a different mistake:

- **Model changed, schema file not updated.** `CloudKitSchemaTests` runs in the pull-request build check, with no secrets. For every model it expects `CD_entityName`, `CD_<name>` for each stored attribute and each to-one relationship, and `CD_<name>_ckAsset` for externally stored data (a to-many relationship has no field). It fails if any of these is missing from the committed file. It compares names only.
- **Schema not deployed.** Both TestFlight workflows export the Production schema with `xcrun cktool` before installing any signing material, and `.github/scripts/check-cloudkit-schema.py` fails the run if Production lacks a record type or `CD_` field from the committed file, or types one differently. Extra fields in Production are fine. The step authenticates with the `CLOUDKIT_MANAGEMENT_TOKEN` repository secret, a CloudKit management token that expires after a year; an expired token fails the step with a message saying so.

Neither check deploys anything. A Production deploy is only possible in CloudKit Console. CI also does not import the committed file into Development.

A model change therefore goes:

1. Change the model.
2. Run a development-signed build that saves a record, so Development gains the field. Alternatively, add the field by hand in CloudKit Console → Development → Record Types.
3. Export Development's schema into `cloudkit/schema.ckdb` (CloudKit Console → Development → **Export Schema…**, or `xcrun cktool export-schema --environment development`) and commit it with the model change. Clean any experimental fields out of Development first, since Deploy Schema Changes pushes everything in it.
4. In CloudKit Console, **Deploy Schema Changes**, before merging or after the gate fails.
5. Merge. If step 4 was skipped, both TestFlight workflows fail at the schema check; deploy, then re-run the failed jobs.

Never test the gate by deploying a fake field to Production. To see it fail, add a fake field to a local copy of the committed file and run the script against a local Production export.

## 11. Verification

Before distribution:

1. Build the active Xcode project successfully with Xcode 27 or later.
2. Run unit tests for tracker calculations, providers, request limits, and persistence actions.
3. Verify an iOS archive and a macOS archive.
4. Confirm embedded extensions use the parent's build number.
5. If a SwiftData model changed, update `cloudkit/schema.ckdb` and deploy the CloudKit schema to Production (see CloudKit schema).
6. Test manual entry and Starling failure states without real credentials in source or fixtures.
7. Test Apple Health with synthetic weight samples: a first connection, refused access (which must stay quiet rather than erroring), and a Mac or watch showing the read-only view.
8. Test CloudKit sync using fictional tracker names and values, and confirm the CloudKit Sync screen reports successful downloads and uploads.
9. Confirm widgets and watch surfaces handle an empty or delayed local store.

## 12. Out of scope

- Cross-Apple-ID sharing
- Payment initiation
- Transaction-level banking history or categorisation
- Additional connected providers until implemented deliberately
- visionOS and Mac Catalyst
