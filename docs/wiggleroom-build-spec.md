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

`TrackerType` owns a terminology table covering every type-dependent phrase — the current figure, today's pace figure, the whole-period figure, the final figure, the three status labels, the remaining-amount caption, and the completion celebration. Each type needs a whole-period noun and a today noun, because the dashboard shows both figures side by side.

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

`SourceProvider` isolates provider-specific behavior from tracker calculations and UI. Each provider declares the tracker types it can back, so the relationship lives with the provider rather than being hard-coded per type: Starling supplies the two account-balance money types, Manual Entry suits them all, and a future vehicle or health source would declare its own. Spending Credit is deliberately outside Starling's set: Starling reports an amount held rather than an amount owed, so a synced balance would travel the wrong way against a credit limit. Add Tracker filters its source list through that declaration once a type is chosen.

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

Additional providers should conform to `SourceProvider` and remain isolated from the core tracker model.

### Safeguards

A connected source's `displayName` must be unique (case-insensitive) among the user's other sources; adding, reconnecting, or renaming one blocks on a collision. A source cannot be removed while any tracker still points at it — its detail/edit screen lists every tracker currently using it, and removal must be preceded by deleting or reassigning them.

## 5. Persistence and sync

The main app uses one SwiftData schema containing:

- `Tracker`
- `ValueSnapshot`
- `ConnectedSource`
- `StarlingRequestLogEntry`

The persistent store uses the app's CloudKit container and App Group. CloudKit syncs between devices signed into the same Apple ID; the App Group lets the app, widgets, and related extensions share current data on one device.

CloudKit synchronization is asynchronous. UI must tolerate temporarily empty or stale local stores and must not treat a short delay as data loss.

Every process registers for remote (silent push) notifications so an already-running, foregrounded app picks up another device's changes promptly rather than only on its own next periodic or opportunistic import.

If the CloudKit-backed container cannot be created, the app records that state in its diagnostics and may fall back to local persistence rather than crash.

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

### Tracker screen layout

A tracker's own screen is headed by its name and nothing else. It carries the same badge — glyph and colour — that the tracker wears in the list, so the screen is recognisably the row that opened it, and the badge sits immediately beside the name in the heading on every platform: in the navigation bar itself on iOS and iPadOS, and in the in-content header on macOS, where the window title cannot take the app's own typeface.

The period's date range and, for a connected tracker, its connection and account sit with the days-remaining line below the figures, not under the heading. They were previously drawn beneath the title, which never closed the gap above them: the iOS system navigation subtitle shows only one line and reserves space whether or not it is used, so a two-line strip had to be drawn separately and always left a gap. Keeping all three lines together, away from the heading, removes the constraint rather than working around it.

In the tracker list, each row's trailing status and figure column is a fixed width, so every row's ring sits the same distance from the edge and the rings line up down the list. Both the figure and the status word scale down within that width rather than widening it.

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
- Configurable tracker selection through App Intents
- Siri intents for opening trackers, checking status, and logging readings

## 8. Background work

- Background refresh is opportunistic and must never be the only way data is updated.
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
- The macOS app requires the outbound network client sandbox entitlement.
- Reset operations require explicit user confirmation.
- Diagnostic screens may show identifiers and counts, but not credentials or financial values unrelated to normal tracker UI.

## 10. Deployment

The main app and every embedded extension must use matching marketing and build versions. TestFlight distribution requires separate iOS and macOS archives.

Automated builds may use a monotonically increasing CI run number for `CURRENT_PROJECT_VERSION`, provided it is applied consistently to the app, watch app, widgets, and complications.

Signing, provisioning, CloudKit containers, App Groups, and bundle identifiers must be configured for the developer account performing the build.

## 11. Verification

Before distribution:

1. Build the active Xcode project successfully.
2. Run unit tests for tracker calculations, providers, request limits, and persistence actions.
3. Verify an iOS archive and a macOS archive.
4. Confirm embedded extensions use the parent's build number.
5. Test manual entry and Starling failure states without real credentials in source or fixtures.
6. Test CloudKit sync using fictional tracker names and values.
7. Confirm widgets and watch surfaces handle an empty or delayed local store.

## 12. Out of scope

- Cross-Apple-ID sharing
- Payment initiation
- Transaction-level banking history or categorisation
- Additional connected providers until implemented deliberately
- visionOS and Mac Catalyst
