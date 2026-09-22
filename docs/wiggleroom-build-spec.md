# Wiggle Room — Build Specification

## 1. Product

Wiggle Room tracks a quantity against the pace required to reach a defined
budget at the end of a fixed period. Example trackers include:

- **Holiday spending** — a decreasing currency balance.
- **Family car mileage** — an increasing distance allowance.
- **Coffee subscription** — a decreasing count entered manually.

The product is designed for one person's use across their own Apple devices.
It does not provide cross-account sharing or collaborative editing.

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
| `unit` | Currency or measurement unit |
| `direction` | Increasing or decreasing |
| `startDate`, `endDate` | Tracking period |
| `startingValue` | Value at the beginning of the period |
| `totalAllowance` | Planned movement over the period |
| `connectedSource` | Manual or external data source |
| `sourceTargetId` | Provider-specific account or target identifier |
| `sortOrder` | Synced custom ordering |
| `colorIndex`, `glyph` | Visual identity |
| `reminderCadenceMinutes` | Optional manual-entry reminder |

Each reading is a separate timestamped `ValueSnapshot`. Reading history is
append-oriented so CloudKit can merge updates made on different devices.

A tracker's `name` must be unique (case-insensitive) among the user's other
trackers; Add/Edit Tracker blocks Save on a collision.

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

The difference between expected and actual consumption determines whether the
tracker is on budget, slightly over, or over budget. Values are clamped where
needed for presentation, but stored readings remain unchanged.

## 4. Sources

`SourceProvider` isolates provider-specific behavior from tracker calculations
and UI.

### Manual Entry

Manual trackers accept readings entered by the user. The internal Manual Entry
`ConnectedSource` is plumbing rather than an external connection. Duplicate
manual records are consolidated automatically without deleting trackers.

### Starling

The Starling provider uses a user-supplied personal access token and supports:

- Account discovery
- Main account balances
- Savings goals and spending spaces
- Manual refresh and scheduled background refresh
- Request-budget and cooldown handling

Requests go directly to `https://api.starlingbank.com` over HTTPS. The app does
not operate an intermediary server and does not initiate payments.

Additional providers should conform to `SourceProvider` and remain isolated
from the core tracker model.

### Safeguards

A connected source's `displayName` must be unique (case-insensitive) among the
user's other sources; adding, reconnecting, or renaming one blocks on a
collision. A source cannot be removed while any tracker still points at it —
its detail/edit screen lists every tracker currently using it, and removal
must be preceded by deleting or reassigning them.

## 5. Persistence and sync

The main app uses one SwiftData schema containing:

- `Tracker`
- `ValueSnapshot`
- `ConnectedSource`
- `StarlingRequestLogEntry`

The persistent store uses the app's CloudKit container and App Group. CloudKit
syncs between devices signed into the same Apple ID; the App Group lets the app,
widgets, and related extensions share current data on one device.

CloudKit synchronization is asynchronous. UI must tolerate temporarily empty
or stale local stores and must not treat a short delay as data loss.

Every process registers for remote (silent push) notifications so an
already-running, foregrounded app picks up another device's changes promptly
rather than only on its own next periodic or opportunistic import.

If the CloudKit-backed container cannot be created, the app records that state
in its diagnostics and may fall back to local persistence rather than crash.

Widget and complication configuration pickers read tracker names from a small
snapshot cached in the App Group container, refreshed whenever any process
fetches current tracker data, rather than always waiting on a fresh CloudKit
round trip before showing a list.

### Live queries and view nesting

A view reads the tracker and source lists with `@Query`, which stays live and
republishes as the store changes. Two live queries over the **same model type**
must not be nested across a parent/child view boundary, where the parent builds
the child inside its own `body` — a `NavigationLink` destination, a `.sheet`,
or a plain child view.

This is a hang, not a redundancy. The child's query fetches on the shared main
`ModelContext`; that fetch notifies SwiftData's change observers, which
invalidates the parent's query on the same type; the parent rebuilds its body,
which constructs a fresh child (a new query, and new `State(initialValue:)`
storage, so the child can never compare equal to its predecessor); the child
fetches again. The loop sustains itself at display-refresh rate with no user
input, memory grows with every pass, and iOS eventually kills the app on the
scene-update watchdog.

A transient editor screen therefore takes a **one-shot snapshot** of what it
needs from a type its presenter already queries — plain values, not model
references — loaded when the screen appears, and revalidates against a fresh
fetch at the point of saving, where correctness actually matters. Live queries
remain correct and preferred for a type the presenting view does not itself
query.

## 6. Visual language

The interface should feel calm and informative rather than punitive.

- The outer ring represents elapsed time.
- The inner ring represents consumed allowance.
- Green indicates on-budget or better.
- Amber indicates a small shortfall.
- Red indicates a larger shortfall.
- Tracker identity colours do not replace status colours.
- Fraunces is used for names and headings; Nunito is the primary text face.
- Numeric values remain the source of truth and accompany visual indicators.

The app's rings, cards, and chart strokes use a deliberately irregular,
hand-drawn style. Accessibility labels must communicate the same information
without relying on colour or geometry alone.

## 7. Platform behavior

### iOS and iPadOS

- Tracker list and detail navigation
- Pull-to-refresh/update behavior
- Add and edit trackers and connected sources
- Settings for sources, ordering, CloudKit diagnostics, and Siri phrases,
  with a separate Danger Zone menu for reset operations
- Spotlight, notification actions, Live Activities, and widgets

### macOS

- Sidebar-based tracker interface
- Dedicated Settings window
- Menu bar presentation for a selected tracker
- Explicit update controls where pull-to-refresh is unavailable

### watchOS

- Tracker list and compact detail presentation
- Manual reading entry
- WidgetKit complication

### Widgets and intents

- Single-tracker status and chart widgets
- All-trackers widget
- Configurable tracker selection through App Intents
- Siri intents for opening trackers, checking status, and logging readings

## 8. Background work

- Background refresh is opportunistic and must never be the only way data is
  updated.
- Provider calls respect request budgets and server cooldowns.
- Multiple trackers targeting the same provider value reuse short-lived cached
  results where possible.
- Widget timelines reload after relevant local or CloudKit changes.
- Manual reminders use local notifications.

## 9. Security and privacy

- Never commit credentials or real financial data.
- Provider credentials are stored on the user's private CloudKit-synced
  `ConnectedSource` record so the connection can work across their devices.
- Credentials must never be logged or included in diagnostics.
- Starling traffic is sent only to Starling's HTTPS API.
- The macOS app requires the outbound network client sandbox entitlement.
- Reset operations require explicit user confirmation.
- Diagnostic screens may show identifiers and counts, but not credentials or
  financial values unrelated to normal tracker UI.

## 10. Deployment

The main app and every embedded extension must use matching marketing and build
versions. TestFlight distribution requires separate iOS and macOS archives.

Automated builds may use a monotonically increasing CI run number for
`CURRENT_PROJECT_VERSION`, provided it is applied consistently to the app,
watch app, widgets, and complications.

Signing, provisioning, CloudKit containers, App Groups, and bundle identifiers
must be configured for the developer account performing the build.

## 11. Verification

Before distribution:

1. Build the active Xcode project successfully.
2. Run unit tests for tracker calculations, providers, request limits, and
   persistence actions.
3. Verify an iOS archive and a macOS archive.
4. Confirm embedded extensions use the parent's build number.
5. Test manual entry and Starling failure states without real credentials in
   source or fixtures.
6. Test CloudKit sync using fictional tracker names and values.
7. Confirm widgets and watch surfaces handle an empty or delayed local store.

## 12. Out of scope

- Cross-Apple-ID sharing
- Payment initiation
- Transaction-level banking history or categorisation
- Additional connected providers until implemented deliberately
- visionOS and Mac Catalyst
