/// Separates keystrokes from a physical keyboard from ones posted by software:
/// text expanders, automation and scripted typing.
///
/// Hardware events arrive with the HID system event source (state 1) and no posting process.
/// Strict mode also drops presses that follow the previous one faster than a person can type.
public struct SyntheticFilter: Sendable {
    public enum Strength: String, Codable, Sendable, CaseIterable {
        case off, normal, strict
    }

    public static let hidSystemState: Int64 = 1
    /// Two different keys pressed closer together than this are not human typing.
    public static let burstInterval = 0.005

    public var strength: Strength
    private var previousTime: Double?

    public init(strength: Strength = .normal) {
        self.strength = strength
    }

    public mutating func isSynthetic(sourceStateID: Int64, sourceProcessID: Int64, time: Double, isRepeat: Bool) -> Bool {
        defer { if !isRepeat { previousTime = time } }
        switch strength {
        case .off:
            return false
        case .normal:
            return !Self.isHardware(sourceStateID: sourceStateID, sourceProcessID: sourceProcessID)
        case .strict:
            if !Self.isHardware(sourceStateID: sourceStateID, sourceProcessID: sourceProcessID) { return true }
            guard !isRepeat, let previousTime else { return false }
            return time - previousTime < Self.burstInterval
        }
    }

    public static func isHardware(sourceStateID: Int64, sourceProcessID: Int64) -> Bool {
        sourceStateID == hidSystemState && sourceProcessID == 0
    }
}
