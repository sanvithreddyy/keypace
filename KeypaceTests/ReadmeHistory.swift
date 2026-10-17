import Foundation
import KeypaceCore

/// Showcase-only history. The ordinary SampleData fixtures keep their original behavior.
@MainActor
enum ReadmeHistory {
    static func fill(_ tracker: LiveTracker, endingAt end: Date, calendar: Calendar = .current) throws {
        guard let store = tracker.store else { preconditionFailure("Showcase history needs an in-memory store") }
        var generator = SeededGenerator(seed: 20261016)
        let firstDay = calendar.date(byAdding: .day, value: -59, to: calendar.startOfDay(for: end))!
        try store.noteKeyboard(SampleData.builtIn)
        try store.noteKeyboard(SampleData.mxKeys)
        try store.noteInputSource(InputSourceRecord(id: "com.apple.keylayout.US", name: "U.S.", lastSeen: end))
        try store.noteInputSource(SampleData.british)

        for dayIndex in 0..<60 {
            let day = calendar.date(byAdding: .day, value: dayIndex, to: firstDay)!
            let weekday = calendar.component(.weekday, from: day)
            let weekend = weekday == 1 || weekday == 7
            let hours = weekend ? (weekday == 7 ? [11, 14, 16, 20, 22] : [10, 13, 17, 21]) : Array(8...23)
            let progress = Double(max(dayIndex - 30, 0)) / 29
            let target = dayIndex < 30 ? 59.5 + 0.6 * sin(Double(dayIndex) * 0.24)
                : 62 + 10 * progress + 0.25 * sin(progress * .pi * 3)
            var sessions: [(session: TypingSession, start: Date)] = []

            for hour in hours {
                if weekend && Double.random(in: 0...1, using: &generator) < 0.18 && hour != hours.first! { continue }
                let start = calendar.date(bySettingHour: hour, minute: Int.random(in: 4...22, using: &generator), second: 0, of: day)!
                let appIndex = appIndex(hour: hour, generator: &generator)
                let context = TypingContext(
                    appID: SampleData.apps[appIndex],
                    keyboardID: dayIndex % 3 == 0 ? SampleData.mxKeys.id : SampleData.builtIn.id,
                    inputSourceID: dayIndex % 6 == 0 ? SampleData.british.id : "com.apple.keylayout.US"
                )
                var engine = SessionTracker()
                var time = 0.0
                var previous: Character?
                // Written prose produces natural letter and pair frequencies, rather than random keys.
                let paragraphs = Int.random(in: 3...5, using: &generator)
                for _ in 0..<paragraphs {
                    let text = SampleData.sentences[Int.random(in: 0..<SampleData.sentences.count, using: &generator)] + " "
                    for character in text {
                        let code = USKeys.code(for: character)
                        // Corrections are a few percent, with harder keys more likely to be rewritten.
                        let chance = "ypgb".contains(character) ? 0.10 : 0.033
                        let correction = Double.random(in: 0...1, using: &generator) < chance
                        let pair = previous.map { "\($0)\(character)" } ?? ""
                        let rhythm = ["th", "he", "in", "er", "on", "an", "re", "st"].contains(pair) ? 0.72
                            : previous == character || ",.'".contains(character) ? 1.45 : 1.0
                        let gap = Double.random(in: 0.11...0.21, using: &generator) * rhythm
                        time += gap
                        _ = engine.record(KeyPress(time: time, keyCode: code, kind: .character), in: context)
                        if correction {
                            time += 0.21
                            _ = engine.record(KeyPress(time: time, keyCode: 51, kind: .backspace), in: context)
                            time += gap
                            _ = engine.record(KeyPress(time: time, keyCode: code, kind: .character), in: context)
                        }
                        previous = character
                    }
                }
                var session = engine.end()!
                // Repeat these measured paragraphs in aggregate so rendering does not replay a million keys.
                let repeats = weekend ? 1 : Int.random(in: 4...5, using: &generator)
                session.characters *= repeats
                session.backspaces *= repeats
                session.deletions *= repeats
                session.keystrokes *= repeats
                session.keys = session.keys.mapValues {
                    KeyCount(presses: $0.presses * repeats, corrections: $0.corrections * repeats)
                }
                session.pairs = session.pairs.mapValues {
                    PairTiming(count: $0.count * repeats, totalMilliseconds: $0.totalMilliseconds * Double(repeats))
                }
                session.activeDuration *= Double(repeats)
                let hourlyOffset = weekend ? Double(hour % 3) - 1
                    : 9 * exp(-pow((Double(hour) - 11) / 2.3, 2)) - 0.45 * Double(hour - 8)
                let variation = Double.random(in: -3...3, using: &generator)
                let duration = Double(session.totals.netCharacters) * 12 / (target + hourlyOffset + variation)
                let timingScale = duration / session.activeDuration
                session.pairs = session.pairs.mapValues {
                    PairTiming(count: $0.count, totalMilliseconds: $0.totalMilliseconds * timingScale)
                }
                session.activeDuration = duration
                session.end = session.start + session.activeDuration * 1.12
                sessions.append((session, start))
            }

            // Keep the day-by-day line smooth even though the mix of morning/evening sessions varies.
            let totals = sessions.reduce(TypingTotals()) { $0 + $1.session.totals }
            let scale = (totals.wpm ?? target) / target
            for item in sessions {
                var session = item.session
                session.activeDuration *= scale
                session.end = session.start + session.activeDuration * 1.12
                session.pairs = session.pairs.mapValues {
                    PairTiming(count: $0.count, totalMilliseconds: $0.totalMilliseconds * scale)
                }
                _ = try store.save(session, endingAt: item.start.addingTimeInterval(session.duration))
                for (code, count) in session.keys {
                    try store.addPresses(count: count.presses, keyCode: code, appID: session.context.appID,
                                         keyboardID: session.context.keyboardID, inputSourceID: session.context.inputSourceID,
                                         hour: Hour.index(item.start))
                }
            }
        }
    }

    private static func appIndex(hour: Int, generator: inout SeededGenerator) -> Int {
        let draw = Int.random(in: 0..<100, using: &generator)
        if draw < 38 { return 2 } // T3 Code
        if draw < 64 { return 0 } // Slack
        if draw < 81 { return 1 } // Notes
        return hour < 18 && draw < 94 ? 3 : 4 // Mail / Messages
    }
}
