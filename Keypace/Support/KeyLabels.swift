import KeypaceCore

/// Labels for key caps. A specific layout uses the labels saved when it was in use, then the installed
/// layout; otherwise the active layout labels keys. The US layout is the last resort.
/// Statistics combined across layouts are labeled with the active layout.
enum KeyLabels {
    static func label(_ keyCode: UInt16, using sources: InputSources?, layout: InputSourceRecord? = nil) -> String {
        if let named = named[keyCode] { return named }
        if let saved = layout?.labels?[keyCode], !saved.isEmpty { return saved }
        if let label = sources?.label(for: keyCode, inputSourceID: layout?.id), !label.isEmpty { return label }
        return us[keyCode] ?? "?"
    }

    /// A key pair as it reads in text: "T → H", with Space shown as ␣.
    static func pair(_ pair: (from: UInt16, to: UInt16), using sources: InputSources?, layout: InputSourceRecord? = nil) -> String {
        func short(_ code: UInt16) -> String { code == 49 ? "␣" : label(code, using: sources, layout: layout) }
        return "\(short(pair.from)) → \(short(pair.to))"
    }

    /// Keys that type nothing visible are labeled by name.
    private static let named: [UInt16: String] = [
        36: "return", 48: "tab", 49: "space", 51: "delete", 53: "esc", 56: "shift", 57: "caps lock", 60: "shift",
    ]

    private static let us: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E",
        15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-",
        28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "return", 37: "L", 38: "J", 39: "'",
        40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
    ]
}
