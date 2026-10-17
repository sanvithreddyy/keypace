import AppKit
import SwiftUI
import KeypaceCore

@main
struct KeypaceApp: App {
    @State private var tracker = LiveTracker.live()

    var body: some Scene {
        MenuBarExtra {
            Dropdown(tracker: tracker).frame(width: Dropdown.width)
        } label: {
            MenuBarLabel(tracker: tracker)
        }
        .menuBarExtraStyle(.window)

        Window("Keypace", id: "main") {
            MainWindow(tracker: tracker)
        }
        .defaultSize(width: 900, height: 680)

        Window("Live Metrics", id: "live") {
            LiveMetrics(tracker: tracker)
        }
        .windowLevel(.floating)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.topTrailing)
    }
}

/// Live session speed while typing (unless set to today only), otherwise today's speed.
private struct MenuBarLabel: View {
    let tracker: LiveTracker
    @AppStorage("menuBarFormat") private var format = MenuBarFormat.withUnit
    @AppStorage("menuBarNumber") private var number = MenuBarNumber.liveThenToday

    var body: some View {
        if tracker.status == .needsPermission {
            Image(systemName: "keyboard.badge.exclamationmark")
        } else if format != .icon, let wpm = wpm {
            Text(format == .withUnit ? "\(Format.wpm(wpm)) wpm" : Format.wpm(wpm)).monospacedDigit()
                .help(number == .liveThenToday && tracker.liveWPM != nil
                      ? "Live net speed · last 8 seconds" : "Today's average net speed")
        } else {
            Image("MenuBarIcon")
        }
    }

    private var wpm: Double? {
        if number == .liveThenToday, let live = tracker.liveWPM { return live }
        _ = tracker.revision
        return PeriodData(.today, tracker: tracker).totals.wpm
    }
}
