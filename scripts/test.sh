#!/bin/sh
# Runs the engine tests, then the app tests (pipeline and screen snapshots).
# The app test bundle is run with xctest directly; it compiles the app's code and needs no host app.
set -eu
cd "$(dirname "$0")/.."

(cd Packages/KeypaceCore && swift test)

xcodegen generate --quiet
xcodebuild build-for-testing -project Keypace.xcodeproj -scheme Keypace -derivedDataPath build -quiet
xcrun xctest build/Build/Products/Debug/KeypaceTests.xctest
