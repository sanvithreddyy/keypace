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
