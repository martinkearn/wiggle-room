# Wiggle Room

Wiggle Room is a SwiftUI app for tracking a limited allowance against the pace needed to reach a target at the end of a fixed period. A tracker can represent a monthly budget, annual mileage allowance, or any other quantity that decreases or increases over time.

The app runs on iPhone, iPad, Mac, and Apple Watch. SwiftData and CloudKit keep a user's trackers and reading history in sync across their own devices.

## Features

- Generic increasing and decreasing trackers
- Manual readings and optional Starling Bank balance integration
- Pace, budget, and projected-final calculations
- Reading history and trend charts
- iOS and macOS apps, Apple Watch companion app, widgets, complications, Live Activities, Siri Shortcuts, and Spotlight integration
- Cross-device sync through the user's private CloudKit database
- Per-tracker colours, symbols, reminders, and custom ordering

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

The app can be used entirely with manual trackers. Starling credentials are entered at runtime under **Settings → Connected Sources**. Never hard-code or commit personal access tokens.

CloudKit, App Groups, signing identities, and bundle identifiers are tied to the original developer account. Forks must configure their own Apple Developer identifiers and capabilities before CloudKit or device builds work.

## TestFlight deployment

Pushes to `main` start separate GitHub Actions workflows for iOS and macOS. Both workflows also support manual dispatch from the GitHub Actions interface.

Every workflow attempt receives a new build number derived from the monotonic GitHub Actions workflow run number, workflow attempt, and platform. This keeps iOS and macOS archive numbers distinct, including reruns. The number is applied consistently to the app and all embedded extensions before the workflow creates a signed archive and uploads it to the existing App Store Connect record.

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
