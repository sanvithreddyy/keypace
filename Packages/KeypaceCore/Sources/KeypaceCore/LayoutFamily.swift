/// The key arrangement behind a macOS input source.
public enum LayoutFamily: String, Sendable, CaseIterable {
    case qwerty = "QWERTY", qwertz = "QWERTZ", azerty = "AZERTY"
    case dvorak = "Dvorak", colemak = "Colemak", workman = "Workman"
    case other = "Other"

    /// - Parameter inputSourceID: e.g. "com.apple.keylayout.US", "com.apple.keylayout.German".
    public static func detect(inputSourceID: String) -> LayoutFamily {
        let id = inputSourceID.lowercased()
        let name = id.split(separator: ".").last.map(String.init) ?? id
        if name.contains("dvorak") { return .dvorak }
        if name.contains("colemak") { return .colemak }
        if name.contains("workman") { return .workman }
        guard id.contains("keylayout") else { return .other }
        if name.hasPrefix("canadian") { return .qwerty }
        if ["french", "belgian"].contains(where: name.hasPrefix) { return .azerty }
        if ["german", "swiss", "austrian", "czech", "slovak", "hungarian", "croatian", "slovenian"].contains(where: name.hasPrefix) {
            return .qwertz
        }
        return .qwerty
    }
}
