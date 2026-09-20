# Wiggle Room

Wiggle Room is a SwiftUI app for tracking a limited allowance against the
pace needed to reach a target at the end of a fixed period. A tracker can
represent a monthly budget, annual mileage allowance, or any other quantity
that decreases or increases over time.

The app runs on iPhone, iPad, Mac, and Apple Watch. SwiftData and CloudKit
keep a user's trackers and reading history in sync across their own devices.

## Features

- Generic increasing and decreasing trackers
- Manual readings and optional Starling Bank balance integration
- Pace, budget, and projected-final calculations
- Reading history and trend charts
- iOS and macOS apps, Apple Watch companion app, widgets, complications,
  Live Activities, Siri Shortcuts, and Spotlight integration
- Cross-device sync through the user's private CloudKit database
- Per-tracker colours, symbols, reminders, and custom ordering

## Requirements

- A current stable version of Xcode
- An Apple ID configured in Xcode
- Apple Developer Program membership for CloudKit on physical devices and
  TestFlight distribution
- An optional Starling personal access token to use the Starling provider

## Getting started

1. Open `src/WiggleRoom.xcodeproj` in Xcode.
2. Select the `WiggleRoom` scheme.
3. Choose an iOS simulator, a Mac, or a connected device.
4. Build and run.

The app can be used entirely with manual trackers. Starling credentials are
entered at runtime under **Settings → Connected Sources**. Never hard-code or
commit personal access tokens.

CloudKit, App Groups, signing identities, and bundle identifiers are tied to
the original developer account. Forks must configure their own Apple
Developer identifiers and capabilities before CloudKit or device builds work.

## TestFlight deployment

Pushes to `main` start separate GitHub Actions workflows for iOS and macOS.
Each workflow gives every app and embedded extension the same CI build number,
creates a signed archive, and uploads it to the existing App Store Connect
record.

Add the following repository secrets under **Settings → Secrets and variables
→ Actions → New repository secret**:

| Secret | Value and source |
|---|---|
| `APPLE_TEAM_ID` | The Team ID shown on the [Apple Developer membership page](https://developer.apple.com/account#MembershipDetailsCard). |
| `APP_STORE_CONNECT_API_KEY_ID` | The Key ID shown for a team API key under **App Store Connect → Users and Access → Integrations → App Store Connect API**. |
| `APP_STORE_CONNECT_ISSUER_ID` | The Issuer ID shown on the same App Store Connect API page. |
| `APP_STORE_CONNECT_API_PRIVATE_KEY` | The complete contents of the `AuthKey_<key-id>.p8` file. Apple permits this file to be downloaded only once when the API key is created. |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | A base64-encoded `.p12` export containing the Apple Distribution certificate and its private key. Create the certificate under **Apple Developer → Certificates, Identifiers & Profiles → Certificates**, install it, then export it from Keychain Access. |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | The password chosen when exporting the Apple Distribution `.p12` file. |
| `MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_BASE64` | A base64-encoded `.p12` export containing the Mac Installer Distribution certificate and its private key, obtained and exported in the same way. |
| `MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PASSWORD` | The password chosen when exporting the Mac Installer Distribution `.p12` file. |

Create the App Store Connect API key with access to this app and to
Certificates, Identifiers & Profiles; the **App Manager** role is sufficient
for uploading builds. On macOS, encode each certificate export for its secret
with:

```sh
base64 -i Certificate.p12 | tr -d '\n' | pbcopy
```

Paste the copied output into the corresponding `*_BASE64` secret. Never commit
the `.p8`, `.p12`, or their passwords. The workflows use the API key to obtain
the existing provisioning profiles through Xcode automatic signing.

## Project structure

```text
wiggle-room/
├── docs/
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

The concise product and architecture specification is in
[`docs/wiggleroom-build-spec.md`](docs/wiggleroom-build-spec.md).

## Security and privacy

- User data is stored locally with SwiftData and synced through the user's
  private CloudKit database.
- Starling requests go directly from the app to Starling over HTTPS.
- The project contains no API credentials. Test credentials are synthetic.
- Do not include real balances, account identifiers, tokens, screenshots, or
  other personal data in issues, tests, documentation, or commits.

## Licence

Wiggle Room is available under the [MIT Licence](LICENSE). Bundled fonts retain
their own SIL Open Font Licence files under `src/WiggleRoomShared/Fonts`.
