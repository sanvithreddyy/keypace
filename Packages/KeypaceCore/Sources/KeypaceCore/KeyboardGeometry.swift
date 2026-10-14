/// Physical layout of a Mac ANSI keyboard and the touch-typing finger for each key.
/// Finger statistics are an assumption about technique, not an observation.
public enum KeyboardGeometry {
    public enum Hand: Sendable { case left, right, thumbs }

    public enum Finger: Int, Sendable, CaseIterable, Comparable {
        case leftPinky, leftRing, leftMiddle, leftIndex, thumb, rightIndex, rightMiddle, rightRing, rightPinky

        public var hand: Hand {
            switch self {
            case .leftPinky, .leftRing, .leftMiddle, .leftIndex: .left
            case .thumb: .thumbs
            default: .right
            }
        }

        public var name: String {
            switch self {
            case .leftPinky: "Left pinky"
            case .leftRing: "Left ring"
            case .leftMiddle: "Left middle"
            case .leftIndex: "Left index"
            case .thumb: "Thumbs"
            case .rightIndex: "Right index"
            case .rightMiddle: "Right middle"
            case .rightRing: "Right ring"
            case .rightPinky: "Right pinky"
            }
        }

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Key: Sendable, Equatable {
        public var keyCode: UInt16
        /// Row from the top: 0 numbers, 1 top letters, 2 home, 3 bottom, 4 space.
        public var row: Int
        /// Left edge and width, in key units.
        public var x: Double
        public var width: Double
        public var finger: Finger

        public var centerX: Double { x + width / 2 }
    }

    /// Centre-to-centre distance between adjacent keys, in millimetres.
    public static let keyPitch = 19.05

    public static let keys: [Key] = {
        var keys: [Key] = []
        func row(_ index: Int, startingAt start: Double, _ codes: [(UInt16, Finger)]) {
            for (offset, (code, finger)) in codes.enumerated() {
                keys.append(Key(keyCode: code, row: index, x: start + Double(offset), width: 1, finger: finger))
            }
        }
        let lp = Finger.leftPinky, lr = Finger.leftRing, lm = Finger.leftMiddle, li = Finger.leftIndex
        let ri = Finger.rightIndex, rm = Finger.rightMiddle, rr = Finger.rightRing, rp = Finger.rightPinky
        // ` 1 2 3 4 5 6 7 8 9 0 - =
        row(0, startingAt: 0, [(50, lp), (18, lp), (19, lr), (20, lm), (21, li), (23, li), (22, ri), (26, ri), (28, rm), (25, rr), (29, rp), (27, rp), (24, rp)])
        keys.append(Key(keyCode: 51, row: 0, x: 13, width: 2, finger: rp)) // delete
        keys.append(Key(keyCode: 48, row: 1, x: 0, width: 1.5, finger: lp)) // tab
        // Q W E R T Y U I O P [ ] \
        row(1, startingAt: 1.5, [(12, lp), (13, lr), (14, lm), (15, li), (17, li), (16, ri), (32, ri), (34, rm), (31, rr), (35, rp), (33, rp), (30, rp)])
        keys.append(Key(keyCode: 42, row: 1, x: 13.5, width: 1.5, finger: rp))
        keys.append(Key(keyCode: 57, row: 2, x: 0, width: 1.75, finger: lp)) // caps lock
        // A S D F G H J K L ; '
        row(2, startingAt: 1.75, [(0, lp), (1, lr), (2, lm), (3, li), (5, li), (4, ri), (38, ri), (40, rm), (37, rr), (41, rp), (39, rp)])
        keys.append(Key(keyCode: 36, row: 2, x: 12.75, width: 2.25, finger: rp)) // return
        keys.append(Key(keyCode: 56, row: 3, x: 0, width: 2.25, finger: lp)) // shift
        // Z X C V B N M , . /
        row(3, startingAt: 2.25, [(6, lp), (7, lr), (8, lm), (9, li), (11, li), (45, ri), (46, ri), (43, rm), (47, rr), (44, rp)])
        keys.append(Key(keyCode: 60, row: 3, x: 12.25, width: 2.75, finger: rp)) // right shift
        keys.append(Key(keyCode: 49, row: 4, x: 4, width: 6, finger: .thumb)) // space
        return keys
    }()

    private static let byCode = Dictionary(uniqueKeysWithValues: keys.map { ($0.keyCode, $0) })

    /// Where each finger rests: A S D F for the left hand, J K L ; for the right.
    public static let homeKeys: [Finger: UInt16] = [
        .leftPinky: 0, .leftRing: 1, .leftMiddle: 2, .leftIndex: 3,
        .rightIndex: 38, .rightMiddle: 40, .rightRing: 37, .rightPinky: 41,
    ]

    public static func key(_ keyCode: UInt16) -> Key? { byCode[keyCode] }

    /// Distance from the key's finger's home key, in millimetres; zero for home keys and Space.
    public static func reach(_ keyCode: UInt16) -> Double? {
        guard let key = byCode[keyCode] else { return nil }
        guard let homeCode = homeKeys[key.finger], let home = byCode[homeCode] else { return 0 }
        let dx = key.centerX - home.centerX
        let dy = Double(key.row - home.row)
        return (dx * dx + dy * dy).squareRoot() * keyPitch
    }
}

/// Finger and hand statistics derived from key and pair counts.
public struct FingerStats: Sendable, Equatable {
    /// Share of presses per finger, over keys on the layout.
    public var load: [KeyboardGeometry.Finger: Double]
    public var leftShare: Double
    public var rightShare: Double
    /// Share of letter-area presses that land on the eight home keys.
    public var homeRowShare: Double
    /// Fingertip distance to reach keys and return to home, in metres.
    public var travelMetres: Double
    /// Share of non-thumb pairs typed with alternating hands.
    public var handAlternation: Double?
    /// Share of non-thumb pairs of different keys typed with the same finger.
    public var sameFinger: Double?

    public init(keys: [UInt16: KeyCount], pairs: [KeyPair: PairTiming]) {
        typealias G = KeyboardGeometry
        var perFinger: [G.Finger: Int] = [:]
        var travel = 0.0
        var home = 0
        var letterArea = 0
        for (code, count) in keys {
            guard let key = G.key(code) else { continue }
            perFinger[key.finger, default: 0] += count.presses
            travel += 2 * (G.reach(code) ?? 0) * Double(count.presses)
            if key.finger != .thumb, (1...3).contains(key.row) {
                letterArea += count.presses
                if G.homeKeys.values.contains(code) { home += count.presses }
            }
        }
        let total = perFinger.values.reduce(0, +)
        load = perFinger.mapValues { total > 0 ? Double($0) / Double(total) : 0 }
        let left = perFinger.filter { $0.key.hand == .left }.values.reduce(0, +)
        let right = perFinger.filter { $0.key.hand == .right }.values.reduce(0, +)
        leftShare = left + right > 0 ? Double(left) / Double(left + right) : 0
        rightShare = left + right > 0 ? Double(right) / Double(left + right) : 0
        homeRowShare = letterArea > 0 ? Double(home) / Double(letterArea) : 0
        travelMetres = travel / 1000

        var handPairs = 0, alternating = 0, sameFingerPairs = 0
        for (pair, timing) in pairs {
            guard let from = G.key(pair.from), let to = G.key(pair.to), from.finger != .thumb, to.finger != .thumb else { continue }
            handPairs += timing.count
            if from.finger.hand != to.finger.hand { alternating += timing.count }
            if from.finger == to.finger, pair.from != pair.to { sameFingerPairs += timing.count }
        }
        handAlternation = handPairs > 0 ? Double(alternating) / Double(handPairs) : nil
        sameFinger = handPairs > 0 ? Double(sameFingerPairs) / Double(handPairs) : nil
    }
}
