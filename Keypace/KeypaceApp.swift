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
    }
}

/// Live session speed while typing, otherwise today's speed.
private struct MenuBarLabel: View {
    let tracker: LiveTracker

    var body: some View {
        if tracker.status == .needsPermission {
            Image(systemName: "keyboard.badge.exclamationmark")
        } else if let wpm = wpm {
            Text("\(Format.wpm(wpm)) wpm").monospacedDigit()
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
