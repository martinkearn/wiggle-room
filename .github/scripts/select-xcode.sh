#!/usr/bin/env bash
# Select the newest released Xcode on the runner for every later step.
#
# Shared by every workflow so builds, tests and TestFlight archives all use
# the same Xcode. The runner image's default Xcode lags behind: left alone,
# CI built against an SDK older than the one used locally, and only warned
# that the platform "only knows how to compile for" an older iOS.
#
# The deployment targets stay lower than this so the app still installs on
# older systems. The minimum here is about the SDK the app is built with:
# iOS and macOS 27 bring the extra-large widget to iPhone and Mac, and the
# app only offers it there when built with that SDK. Fails, rather than
# quietly building with an older Xcode, when the runner has nothing new
# enough.
set -euo pipefail

MINIMUM_MAJOR_VERSION=27

echo "Xcode versions on this runner:"
ls -d /Applications/Xcode*.app

# Betas and release candidates can't upload to App Store Connect.
XCODE="$(ls -d /Applications/Xcode_*.app \
  | grep -viE 'beta|release_candidate|_rc' \
  | sort -V \
  | tail -n 1)"
sudo xcode-select --switch "$XCODE"
xcodebuild -version

VERSION="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
if (( ${VERSION%%.*} < MINIMUM_MAJOR_VERSION )); then
  echo "::error title=Xcode version::The newest released Xcode on this runner is $VERSION, but WiggleRoom builds with Xcode $MINIMUM_MAJOR_VERSION or later. Move the workflow to a runner image that has it."
  exit 1
fi
