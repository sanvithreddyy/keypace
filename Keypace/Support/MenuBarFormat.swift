/// How the number in the menu bar reads.
enum MenuBarFormat: String, CaseIterable {
    case withUnit, number, icon

    var title: String {
        switch self {
        case .withUnit: "72 wpm"
        case .number: "72"
        case .icon: "Icon only"
        }
    }
}

/// Which speed the menu-bar number shows.
enum MenuBarNumber: String, CaseIterable {
    case liveThenToday, today

    var title: String {
        switch self {
        case .liveThenToday: "Live, then today"
        case .today: "Today"
        }
    }

    var description: String {
        switch self {
        case .liveThenToday: "Shows speed over the last 8 seconds while you type, then today's average."
        case .today: "Always shows today's average of saved sessions."
        }
    }
}

/// Which speeds the menu bar shows when both typing and voice are measured.
enum MenuBarSpeeds: String, CaseIterable {
    case typing, voice, both

    var title: String {
        switch self {
        case .typing: "Typing"
        case .voice: "Voice"
        case .both: "Both"
        }
    }

    /// What it shows given what is measured.
    func shown(for measure: Measure) -> MenuBarSpeeds {
        switch measure {
        case .typing: .typing
        case .voice: .voice
        case .both: self
        }
    }
}
