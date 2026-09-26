# Wiggle Room

Wiggle Room is a SwiftUI app for tracking a quantity against the pace needed to reach a target at the end of a fixed period. Every tracker is one of four types — Spending Money, Saving Money, Mileage, or Weight loss — chosen when it is created. The type sets the units, which way the number travels, which side of the pace line is the good side, and the wording used everywhere it appears.

The app runs on iPhone, iPad, Mac, and Apple Watch. SwiftData and CloudKit keep a user's trackers and reading history in sync across their own devices.

## Features

- Four tracker types: Spending Money, Saving Money, Mileage, and Weight loss
- Manual readings and optional Starling Bank balance integration
- Pace, target, and projected-final calculations, with a traffic-light status that knows whether higher or lower is better
- Reading history and trend charts, with a five-day zoom for long trackers
- iOS and macOS apps, Apple Watch companion app, widgets, complications, Live Activities, Siri Shortcuts, and Spotlight integration
- Cross-device sync through the user's private CloudKit database
- Per-tracker colours, symbols, reminders, and custom ordering
- JSON export and import of complete trackers and reading history

## Requirements

- A current stable version of Xcode
- An Apple ID configured in Xcode
- Apple Developer Program membership for CloudKit on physical devices and TestFlight distribution
- An optional Starling personal access token to use the Starling provider

## Getting started

1. Open `src/WiggleRoom.xcodeproj` in Xcode.
2. Select the `WiggleRoom` scheme.
3. Choose an iOS simulator, a Mac, or a connected device.
4. Build and run.

The app can be used entirely with manual trackers. Starling credentials are entered at runtime under **Settings → Connected Sources**, and app appearance can be set to System, Light, or Dark under **Settings → General**. Never hard-code or commit personal access tokens.

CloudKit, App Groups, signing identities, and bundle identifiers are tied to the original developer account. Forks must configure their own Apple Developer identifiers and capabilities before CloudKit or device builds work.

**Settings → About** identifies the running build: marketing version, the build number TestFlight shows, and the commit it was built from, including the commit subject, branch and a link to the originating workflow run. Builds made locally say so instead of offering a run link.

Tracker backups and transfers are available under **Settings → Export & Import**. Exports contain tracker configuration and reading history, but never connected-source credentials. During import, external trackers can be reassigned to an existing source of the same type or imported read-only until a source is connected from Edit Tracker.

## Continuous integration

Pull requests targeting `main` run a build check that compiles the app for iOS and macOS in the Release configuration, unsigned. It needs no repository secrets, so it also covers pull requests raised from forks and by coding agents. Merging a branch that does not compile is what this check exists to prevent, since the distribution workflows below only run after a merge has already landed.

## TestFlight deployment

Pushes to `main` start separate GitHub Actions workflows for iOS and macOS. Both workflows also support manual dispatch from the GitHub Actions interface.

Every workflow attempt receives a new build number derived from the monotonic GitHub Actions workflow run number, workflow attempt, and platform. This keeps iOS and macOS archive numbers distinct, including reruns. The number is applied consistently to the app and all embedded extensions before the workflow creates a signed archive and uploads it to the existing App Store Connect record.

Each archive carries the triggering commit into TestFlight's "What to Test" notes, written as `TestFlight/WhatToTest.en-US.txt` inside the archive before export, so testers can see which change the build contains. The notes hold the commit message, the short commit hash and branch, and a link to the workflow run that produced the build.

The workflows require GitHub repository secrets for App Store Connect authentication and signing. For the complete list, purpose, setup, certificate export, fork configuration, rotation, and troubleshooting instructions, see the [GitHub Actions TestFlight setup guide](docs/github-actions-setup.md).

## Project structure

```text
wiggle-room/
├── docs/
│   ├── github-actions-setup.md
│   └── wiggleroom-build-spec.md
├── scripts/                    # Project maintenance and icon generation
├── src/
│   ├── WiggleRoom.xcodeproj
│   ├── WiggleRoom/             # iOS, iPadOS and macOS app
│   ├── WiggleRoomShared/       # Shared models, services and UI
│   ├── WiggleRoomWidgets/      # iOS/macOS widgets and Live Activity
│   ├── WiggleRoomWatch/        # watchOS companion app
│   ├── WiggleRoomComplication/ # watchOS complication
│   ├── WiggleRoomTests/
│   └── WiggleRoomUITests/
└── README.md
```

The concise product and architecture specification is in [`docs/wiggleroom-build-spec.md`](docs/wiggleroom-build-spec.md).

## Security and privacy

- User data is stored locally with SwiftData and synced through the user's private CloudKit database.
- Starling requests go directly from the app to Starling over HTTPS.
- The project contains no API credentials. Test credentials are synthetic.
- Do not include real balances, account identifiers, tokens, screenshots, or other personal data in issues, tests, documentation, or commits.

## Licence

Wiggle Room is available under the [MIT Licence](LICENSE). Bundled fonts retain their own SIL Open Font Licence files under `src/WiggleRoomShared/Fonts`.
