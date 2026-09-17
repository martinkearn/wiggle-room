# Wiggle Room

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
[`docs/wiggleroom-build-spec.md`](docs/wiggleroom-build-spec.md). It's the
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
- [x] iOS dashboard & rings visual, incl. a completed-tracker presentation
- [x] Widgets (Home Screen incl. extra-large, Lock Screen — configurable per tracker)
- [x] macOS UI (sidebar, menu bar item, Dock badge)
- [x] watchOS companion app (embedded in the iOS app)
- [x] watchOS complication
- [x] Siri/Shortcuts (log a reading, check a tracker's status)
- [ ] Live Activities (deliberately skipped — see progress notes for why)
- [x] §4.5 zoom levels (This year/This month/This week sub-periods) — on the dashboard; not yet per-widget
- [ ] visionOS / Mac Catalyst (deliberately removed — iOS and macOS only, see progress notes)

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

1. Open `src/WiggleRoom.xcodeproj` (or `.xcworkspace`, if present) in Xcode.
2. Build and run on the iOS, macOS, or watchOS simulator — pick the
   `WiggleRoom` scheme for the iPhone/Mac app (the watch app and widgets embed
   automatically), or `WiggleRoomWatch`/`WiggleRoomWidgets` directly to iterate on
   just one of them.
3. Provider credentials are entered in-app under Settings → Connected
   Sources — never hardcode tokens in source or commit them to this
   repo. (Not yet relevant in practice — no real provider ships yet.)

## Project structure

```
wiggle-room/
├── CLAUDE.md                  — instructions for an AI agent working in this repo
├── docs/
│   ├── wiggleroom-build-spec.md — the build spec (source of truth)
│   └── progress-notes.md      — what's actually been built, decisions, gaps
├── scripts/                   — one-off Xcode-project-surgery scripts (see
│                                 progress-notes.md; not part of the app)
├── src/                       — Xcode project & app source
│   ├── WiggleRoom.xcodeproj
│   ├── WiggleRoom/                — the iOS/iPadOS/macOS app + Shortcuts intents
│   ├── WiggleRoomShared/          — model/pace/scheduling layer + RingsView,
│   │                             shared by every target below (no App Group —
│   │                             each target syncs independently via CloudKit)
│   ├── WiggleRoomWidgets/         — WidgetKit extension (Home Screen, Lock Screen)
│   ├── WiggleRoomWatch/           — watchOS companion app
│   ├── WiggleRoomComplication/    — watchOS complication (WidgetKit extension,
│   │                             embedded inside WiggleRoomWatch)
│   ├── WiggleRoomTests/
│   └── WiggleRoomUITests/
└── README.md
```
