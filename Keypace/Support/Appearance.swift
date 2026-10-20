import AppKit

/// Keypace's look: the system's, or always light or dark.
enum Appearance: String, CaseIterable {
    case system, light, dark

    static let key = "appearance"

    /// The saved choice; light until one is made.
    static var saved: Appearance {
        UserDefaults.standard.string(forKey: key).flatMap(Appearance.init) ?? .light
    }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Sets the look of every window, including the menu-bar dropdown.
    func apply() {
        NSApplication.shared.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
