import AppKit
import SwiftUI
import KeypaceCore

@main
struct KeypaceApp: App {
    @State private var tracker = LiveTracker.live()

    var body: some Scene {
        MenuBarExtra {
            Dropdown(tracker: tracker)
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

/// Live session speed while typing, otherwise today's speed.
private struct MenuBarLabel: View {
    let tracker: LiveTracker
    @AppStorage("menuBarFormat") private var format = MenuBarFormat.withUnit

    var body: some View {
        if tracker.status == .needsPermission {
            Image(systemName: "keyboard.badge.exclamationmark")
        } else if format != .icon, let wpm = wpm {
            Text(format == .withUnit ? "\(Format.wpm(wpm)) wpm" : Format.wpm(wpm)).monospacedDigit()
        } else {
            Image(systemName: "keyboard")
        }
    }

    private var wpm: Double? {
        if let current = tracker.current, current.duration >= 3, let wpm = current.totals.wpm { return wpm }
        _ = tracker.revision
        return PeriodData(.today, tracker: tracker).totals.wpm
    }
}
