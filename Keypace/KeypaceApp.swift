import AppKit
import SwiftUI
import KeypaceCore

@main
struct KeypaceApp: App {
    @State private var tracker = LiveTracker.live()

    init() {
        // Before any window opens, so the chosen look shows from the first frame.
        Appearance.saved.apply()
    }

    var body: some Scene {
        MenuBarExtra {
            Dropdown(tracker: tracker).frame(width: Dropdown.width)
        } label: {
            MenuBarLabel(tracker: tracker)
        }
        .menuBarExtraStyle(.window)

        Window("Keypace", id: "main") {
            MainWindow(tracker: tracker)
                // A menu-bar app has no menus, and macOS hides the menu bar while one is in front.
                // Act as a regular app while this window is open.
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
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

/// Typing speed live while typing (unless set to today only), otherwise today's; speaking speed is
/// today's, after a microphone glyph.
private struct MenuBarLabel: View {
    let tracker: LiveTracker
    @AppStorage("menuBarFormat") private var format = MenuBarFormat.withUnit
    @AppStorage("menuBarNumber") private var number = MenuBarNumber.liveThenToday
    @AppStorage("menuBarSpeeds") private var speeds = MenuBarSpeeds.both

    var body: some View {
        let shown = speeds.shown(for: tracker.measure)
        let typing = shown == .voice ? nil : typingWPM
        let voice = shown == .typing ? nil : voiceWPM
        if tracker.status == .needsPermission {
            Image(systemName: "keyboard.badge.exclamationmark")
        } else if format != .icon, typing != nil || voice != nil {
            label(typing: typing, voice: voice).monospacedDigit()
                .help(help(typing: typing, voice: voice))
        } else {
            Image("MenuBarIcon")
        }
    }

    private func label(typing: Double?, voice: Double?) -> Text {
        var text = Text("")
        if let typing { text = text + Text(Format.wpm(typing)) }
        if let voice {
            if typing != nil { text = text + Text("  ") }
            text = text + Text(Image(systemName: "mic")) + Text(" \(Format.wpm(voice))")
        }
        return format == .withUnit ? text + Text(" wpm") : text
    }

    private func help(typing: Double?, voice: Double?) -> String {
        var parts: [String] = []
        if typing != nil {
            parts.append(number == .liveThenToday && tracker.liveWPM != nil ? "Live net speed · last 8 seconds" : "Today's average net speed")
        }
        if voice != nil { parts.append("Today's speaking speed") }
        return parts.joined(separator: " · ")
    }

    private var typingWPM: Double? {
        if number == .liveThenToday, let live = tracker.liveWPM { return live }
        _ = tracker.revision
        return PeriodData(.today, tracker: tracker).totals.wpm
    }

    private var voiceWPM: Double? {
        _ = tracker.revision
        return PeriodData(.today, tracker: tracker, mode: .voice).voice.wpm
    }
}
