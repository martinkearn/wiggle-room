# Ringet

A personal iOS/iPadOS/macOS/watchOS app that tracks any allowance —
a bank balance against a monthly budget, a car's mileage against a
lease — against the pace needed to land exactly on target by the end
of the period. Visualized as two concentric rings: an outer ring for
time elapsed, an inner ring for how much of the allowance has actually
been used.

This is a private household project, not intended for public
distribution — see the spec for why (Starling/Tesla API access is
scoped to personal use, not a public multi-user product).

## Documentation

The full build specification lives at
[`docs/ringet-build-spec.md`](docs/ringet-build-spec.md). It's the
source of truth for how the app should work — data model, the source
provider architecture, visual/UX direction, platform-specific UI, and
what's explicitly out of scope for v1. Read it before making any
non-trivial change.

## Status

See [`docs/progress-notes.md`](docs/progress-notes.md) for the detailed,
continuously-updated log of what's built, key decisions, and known gaps.
Rough shape of what's implemented vs. still to come:

- [x] Core Tracker model & pace/consumption calculations
- [ ] Starling provider (not started — deliberately out of scope so far)
- [x] Manual entry provider
- [ ] Tesla provider (not started — deliberately out of scope so far)
- [x] SwiftData + CloudKit sync
- [x] iOS dashboard & rings visual
- [x] Widgets (Home Screen, Lock Screen — configurable per tracker)
- [x] macOS UI (sidebar, menu bar item)
- [x] watchOS companion app (embedded in the iOS app)
- [ ] watchOS complication (companion app only so far — see progress notes)
- [x] Siri/Shortcuts (log a reading, check a tracker's status)
- [ ] Live Activities (deliberately skipped — see progress notes for why)
- [ ] §4.6 zoom levels (This year/This month/This week sub-periods)

## Requirements

- Xcode (current stable release)
- An Apple ID added to Xcode for local builds; the Apple Developer
  Program ($99/year) is needed later for CloudKit sync and TestFlight
  distribution — not required to build and run locally
- A Starling personal access token (developer.starlingbank.com) for
  testing the Starling provider
- A Tesla developer account (developer.tesla.com) for testing the
  Tesla provider

## Getting started

1. Open `src/Ringet.xcodeproj` (or `.xcworkspace`, if present) in Xcode.
2. Build and run on the iOS, macOS, or watchOS simulator — pick the
   `Ringet` scheme for the iPhone/Mac app (the watch app and widgets embed
   automatically), or `RingetWatch`/`RingetWidgets` directly to iterate on
   just one of them.
3. Provider credentials are entered in-app under Settings → Connected
   Sources — never hardcode tokens in source or commit them to this
   repo. (Not yet relevant in practice — no real provider ships yet.)

## Project structure

```
ringet/
├── docs/
│   ├── ringet-build-spec.md   — the build spec (source of truth)
│   └── progress-notes.md      — what's actually been built, decisions, gaps
├── scripts/                   — one-off Xcode-project-surgery scripts (see
│                                 progress-notes.md; not part of the app)
├── src/                       — Xcode project & app source
│   ├── Ringet.xcodeproj
│   ├── Ringet/                — the iOS/iPadOS/macOS app + Shortcuts intents
│   ├── RingetShared/          — model/pace layer + RingsView, shared by
│   │                             every target below (no App Group — each
│   │                             target syncs independently via CloudKit)
│   ├── RingetWidgets/         — WidgetKit extension (Home Screen, Lock Screen)
│   ├── RingetWatch/           — watchOS companion app
│   ├── RingetTests/
│   └── RingetUITests/
└── README.md
```
