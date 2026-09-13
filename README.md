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

Early build. See the spec's own section list for the rough shape of
what's implemented vs. still to come:

- [ ] Core Tracker model & pace/consumption calculations
- [ ] Starling provider
- [ ] Manual entry provider
- [ ] Tesla provider
- [ ] SwiftData + CloudKit sync
- [ ] iOS dashboard & rings visual
- [ ] Widgets (Home Screen, Lock Screen)
- [ ] macOS UI (sidebar, menu bar item)
- [ ] watchOS companion app & complication

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
2. Build and run on the iOS or macOS simulator.
3. Provider credentials are entered in-app under Settings → Connected
   Sources — never hardcode tokens in source or commit them to this
   repo.

## Project structure

```
ringet/
├── docs/
│   └── ringet-build-spec.md   — the build spec (source of truth)
├── src/                       — Xcode project & app source
│   └── Ringet.xcodeproj
└── README.md
```
