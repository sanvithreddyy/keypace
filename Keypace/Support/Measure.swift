/// What Keypace measures: typing, voice or both.
enum Measure: String, CaseIterable {
    case typing, voice, both

    var typing: Bool { self != .voice }
    var voice: Bool { self != .typing }

    var title: String {
        switch self {
        case .typing: "Typing"
        case .voice: "Voice"
        case .both: "Both"
        }
    }

    var description: String {
        switch self {
        case .typing: "Measures typing only. Dictation isn't recorded."
        case .voice: "Measures dictation only. Typing isn't recorded."
        case .both: "Measures typing and dictation separately."
        }
    }
}

/// Typing or voice, for pages and the panel when both are measured.
enum Mode: String, CaseIterable {
    case typing, voice

    var title: String { self == .typing ? "Typing" : "Voice" }

    /// The mode to show: the chosen one when both are measured, else the one that is.
    func shown(for measure: Measure) -> Mode {
        switch measure {
        case .typing: .typing
        case .voice: .voice
        case .both: self
        }
    }
}
