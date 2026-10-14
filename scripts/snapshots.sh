#!/bin/sh
# Runs the app tests, which render every screen with sample history to build/snapshots.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild build-for-testing -project Keypace.xcodeproj -scheme Keypace -derivedDataPath build -quiet
rm -rf build/snapshots
xcrun xctest build/Build/Products/Debug/KeypaceTests.xctest
