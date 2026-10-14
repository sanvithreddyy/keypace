# Keypace

A quiet macOS menu-bar app that measures how fast you really type, everywhere
on your Mac, and keeps every number on your machine.

- Live words per minute in the menu bar while you type, and a floating Live
  Metrics window.
- Sessions split automatically by pauses, app switches, keyboards and layouts.
- Speed, corrections and typing time by day, hour, weekday, app, keyboard and
  layout, compared with the previous period.
- A keyboard heatmap, most corrected keys, slowest and fastest key pairs, and
  finger statistics.
- Personal records and streaks.
- Keystrokes sent by other software (text expanders, automation) are left out.
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
scripts/test.sh        # engine tests, then app pipeline and screen tests
scripts/snapshots.sh   # renders every screen with sample history to build/snapshots
```

The app tests compile the app's code into the test bundle and run it with
`xctest` directly, so they never launch the menu-bar app or touch real history.

## How it measures

| Metric | Definition |
| --- | --- |
| WPM | characters that stayed (typed minus deleted again) ÷ 5, per minute of typing time |
| CPM | characters that stayed, per minute of typing time |
| KPM | physical key presses per minute of typing time |
| Corrections | characters deleted again ÷ characters typed |

Typing time leaves out pauses. Each gap between keystrokes counts as typing
when it's under four times your usual gap for that key pair (or that key, or
overall), kept between 250 ms and 3 s; before there's any history, gaps up to
600 ms count. The keystroke that starts a burst is given one usual gap, so
short bursts aren't overstated.

A session ends after 5 seconds without typing, or when you switch apps,
keyboards or layouts. Sessions under 25 characters are discarded. Both limits
are adjustable in Settings. Combined figures weight each session by its typing
time.

Deletions only count when they remove characters typed in the same session
and still right before the cursor; deleting text that was already there, or
after a click, arrow key or shortcut moved the cursor, is editing. Option-Delete and
Command-Delete count every character they remove. Corrections include
deliberate rewrites, so the app calls them corrections rather than accuracy.
Each deletion is charged to the key whose character it removed. Key-pair
timings cover consecutive characters whose gap counted as typing. Finger
statistics assume touch-typing finger assignments. Shortcuts and navigation
keys count as keystrokes but not per key.

The live number covers the last 8 seconds of typing and clears 2 seconds after
you stop.

Sessions saved before typing time was measured keep their original numbers:
elapsed time and every backspace.

Keyboards are told apart by model and, when the keyboard reports one, a unique
device ID or serial number. Two keyboards of the same model that report neither
share one history.

Keystrokes from a physical keyboard arrive from the HID system with no posting
process; anything else (text expanders, automation, scripted typing) is counted
separately as filtered input. Paste and AI autocomplete insert text without
keystrokes, so they never count toward speed.

## Privacy

Keypace listens to key events without blocking or changing them. It classifies
each press as a character, a deletion or another key, then discards the
character. The database (`~/Library/Application Support/Keypace/typing.sqlite`)
holds session times, app, keyboard and layout identifiers, per-session key and
key-pair counts, hourly counts of filtered input, and each layout's key labels.
Nothing leaves the Mac.

## Layout

```
Keypace/                 App target
  Capture/               Keyboard event tap, keyboard devices, input sources
  Tracking/              Session lifecycle, filtering, storage and settings
  Views/                 Menu-bar dropdown, main window pages, Live Metrics
  Support/               Formatting, labels and shared view data
KeypaceTests/            Pipeline and screen tests with sample history
Packages/KeypaceCore/    Session engine, storage, statistics, records, tests
Config/                  Signing configuration
scripts/                 Test and snapshot scripts
docs/                    Spec, roadmap, design mockups
```

## License

[MIT](LICENSE)
