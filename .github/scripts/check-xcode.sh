#!/usr/bin/env bash
# Fail unless the runner's selected Xcode is new enough to build WiggleRoom.
#
# Shared by every workflow so builds, tests and TestFlight archives all use
# the same Xcode. The workflows run on GitHub's `xcode-27` runner image,
# whose default Xcode is a released 27.x. The general `macos-latest` image
# stopped at Xcode 26.6, which built against older SDKs and only warned
# that the platform "only knows how to compile for" an older iOS.
#
# The image's default is used rather than the newest Xcode installed:
# images also carry betas, some under release-looking symlinks such as
# Xcode_27.2.app, and a beta build can't upload to App Store Connect.
#
# The deployment targets stay lower than this so the app still installs on
# older systems. The minimum here is about the SDK the app is built with:
# iOS and macOS 27 bring the extra-large widget to iPhone and Mac.
set -euo pipefail

MINIMUM_MAJOR_VERSION=27

echo "Selected: $(xcode-select --print-path)"
xcodebuild -version

VERSION="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
if (( ${VERSION%%.*} < MINIMUM_MAJOR_VERSION )); then
  echo "::error title=Xcode version::This runner's Xcode is $VERSION, but WiggleRoom builds with Xcode $MINIMUM_MAJOR_VERSION or later. Run the workflow on a runner image that has it (runs-on)."
  exit 1
fi
