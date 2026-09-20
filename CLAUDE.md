# Instructions for an AI agent working in this repo

## Keep public documentation current

The repository has two public-facing documents:

- [`README.md`](README.md) — the project overview and contributor entry point.
- [`docs/wiggleroom-build-spec.md`](docs/wiggleroom-build-spec.md) — the
  concise product and architecture specification.

When app behavior changes, update the relevant document to describe the current
state. Do not turn either document into a chronological development log; Git
history is the record of individual changes.

Never add real names, balances, account identifiers, credentials, screenshots,
device identifiers, or private testing history to source, tests, documentation,
commit messages, or issues. Use clearly fictional examples and synthetic test
values.

Before non-trivial work, read the build specification and inspect the code in
the affected area.

## Verifying changes

This is an Xcode multiplatform SwiftUI project for iOS, iPadOS, macOS, and
watchOS, with WidgetKit extensions and SwiftData/CloudKit persistence.

Use Xcode builds and tests when available. If they are unavailable, say so
explicitly. A syntax-only check is not equivalent to a successful Xcode build,
simulator run, or on-device verification.

For distribution builds, ensure the parent app and every embedded app or
extension use the same build number.

## Siri phrases

Whenever a phrase is added, removed, or reworded in
`src/WiggleRoom/Intents/WiggleRoomShortcuts.swift`, update
`src/WiggleRoom/Views/SiriPhrasesView.swift` in the same change. The settings
page is maintained manually because App Shortcut phrases cannot be read back at
runtime.
