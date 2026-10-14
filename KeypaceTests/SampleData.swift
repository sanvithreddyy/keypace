import Foundation
import KeypaceCore

/// Fills a tracker with realistic history by typing through the real pipeline:
/// several sessions a day across apps, faster in the morning, with occasional typos.
@MainActor
enum SampleData {
    static let sentences = [
        "the quick brown fox jumps over the lazy dog",
        "can you send me the notes from this morning before the call",
        "i think we should ship the smaller version first and measure it",
        "thanks, that looks right to me. let's merge it after lunch",
        "the build is green again, the flaky test was a timezone issue",
        "please review the pricing page copy when you get a chance",
        "we can move the sync to friday if that works better for everyone",
        "running a little late, start without me and i'll catch up",
    ]

    static let apps = ["com.tinyspeck.slackmacgap", "com.apple.Notes", "com.t3tools.t3code", "com.apple.mail", "com.apple.MobileSMS"]
    static let builtIn = KeyboardRecord(id: "1452:834", name: "Apple Internal Keyboard / Trackpad", isBuiltIn: true, lastSeen: .now)
    static let mxKeys = KeyboardRecord(id: "1133:50475", name: "MX Keys", isBuiltIn: false, lastSeen: .now)
    static let british = InputSourceRecord(id: "com.apple.keylayout.British", name: "British", lastSeen: .now)

    /// - Returns: the tracker's clock, positioned at `end`.
    static func fill(_ tracker: LiveTracker, clock: TestClock, days: Int, endingAt end: Date) {
        var generator = SeededGenerator(seed: 42)
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: end.addingTimeInterval(-Double(days - 1) * 86_400))
        for dayIndex in 0..<days {
            let day = calendar.date(byAdding: .day, value: dayIndex, to: firstDay)!
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            if isWeekend, Double.random(in: 0...1, using: &generator) < 0.4 { continue }
            let hours = isWeekend ? [11, 20] : [9, 10, 11, 14, 15, 16, 21]
            for hour in hours where Double.random(in: 0...1, using: &generator) < 0.75 {
                let start = calendar.date(bySettingHour: hour, minute: Int.random(in: 0...40, using: &generator), second: 0, of: day)!
                guard start < end else { continue }
                clock.date = start
                // Mornings are quicker; the trend improves slowly over the period.
                let pace = (hour < 12 ? 0.16 : 0.19) - Double(dayIndex) * 0.0006
                var typist = Typist(tracker: tracker, clock: clock)
                typist.appID = apps[Int.random(in: 0..<apps.count, using: &generator)]
                typist.keyboard = dayIndex % 3 == 0 ? mxKeys : builtIn
                if dayIndex % 5 == 4 { typist.inputSource = british }
                for _ in 0..<Int.random(in: 2...6, using: &generator) {
                    var text = sentences[Int.random(in: 0..<sentences.count, using: &generator)] + " "
                    if Double.random(in: 0...1, using: &generator) < 0.5 {
                        let index = text.index(text.startIndex, offsetBy: Int.random(in: 3..<20, using: &generator))
                        let typo = "qwertyuiopasdfghjklzxcvbnm".randomElement(using: &generator)!
                        text.insert(contentsOf: "\(typo)⌫", at: index)
                    }
                    for character in text {
                        typist.type(String(character), interval: pace * Double.random(in: 0.6...1.5, using: &generator))
                    }
                }
                typist.pause()
            }
        }
        clock.date = end
    }
}

extension SampleData {
    /// A few sessions in the hours before now, so today's views have something to show at any time of day.
    static func typeToday(_ tracker: LiveTracker, clock: TestClock) {
        let now = clock.date
        for (hoursAgo, pace) in [(3.0, 0.17), (2.0, 0.15), (1.0, 0.16), (0.2, 0.14)] {
            clock.date = now.addingTimeInterval(-hoursAgo * 3600)
            let typist = Typist(tracker: tracker, clock: clock)
            for sentence in sentences.prefix(4) { typist.type(sentence + " ", interval: pace) }
            // Slow paragraph breaks, so key pairs with named keys show up among the slowest.
            for _ in 0..<6 { typist.type("\n\n", interval: 0.6) }
            typist.pause()
        }
        clock.date = now
    }
}

/// Deterministic random numbers so snapshots don't change between runs.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
