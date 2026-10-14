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
        case .liveThenToday: "Shows the current session once you've typed a few words, then today's speed."
        case .today: "Always shows today's speed."
        }
    }
}
