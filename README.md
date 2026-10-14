# Keypace

A quiet macOS menu-bar app that measures how fast you really type, everywhere
on your Mac, and keeps every number on your machine.

- Live words per minute in the menu bar while you type.
- Sessions split automatically by pauses and app switches.
- Speed, corrections and typing time by day, hour, weekday and app, compared
  with the previous period.
- Never stores what you type: only counts and timings.

## Requirements

- macOS 15 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

```sh
xcodegen generate
open Keypace.xcodeproj
```

Or from the command line:

```sh
xcodegen generate
xcodebuild -project Keypace.xcodeproj -scheme Keypace -derivedDataPath build build
open build/Build/Products/Debug/Keypace.app
```

On first launch, allow Keypace under System Settings → Privacy & Security →
Input Monitoring.

The project signs ad hoc by default. macOS ties Input Monitoring to the
signature, so an ad hoc build asks again after every rebuild. To keep the
permission, copy `Config/Signing.local.example.xcconfig` to
`Config/Signing.local.xcconfig` and fill in your signing identity.

## Test

```sh
cd Packages/KeypaceCore
swift test
```

## How it measures

| Metric | Definition |
| --- | --- |
| WPM | (characters − backspaces) ÷ 5, per minute of typing |
| CPM | characters − backspaces, per minute |
| KPM | physical key presses per minute |
| Corrections | backspaces ÷ characters typed |

A session runs from its first to its last keystroke and ends after 5 seconds
without typing or when you switch apps. Sessions under 10 characters are
discarded. Both limits are adjustable in Settings. Combined figures weight each
session by its length.

Corrections count every deletion, including deliberate rewrites, so the app
calls them corrections rather than accuracy.

## Privacy

Keypace listens to key events without blocking or changing them. It classifies
each press as a character, a deletion or another key, then discards the
character. The database (`~/Library/Application Support/Keypace/typing.sqlite`)
holds session times, app identifiers and counts. Nothing leaves the Mac.

## Layout

```
Keypace/                 App target
  Capture/               Keyboard event tap
  Tracking/              Session lifecycle, storage and settings
  Views/                 Menu-bar dropdown, main window, settings
  Support/               Formatting and shared view data
Packages/KeypaceCore/    Session engine, storage, statistics, tests
Config/                  Signing configuration
docs/                    Spec, roadmap, design mockups
```

## License

[MIT](LICENSE)
