import Foundation
import Testing
@testable import KeypaceCore

struct RecordsTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func `bests skip sessions too short to count`() throws {
        let sprint = record(at: monday, seconds: 10, characters: 120) // 144 wpm but only 10 s
        let fast = record(at: monday.addingTimeInterval(3600), seconds: 60, characters: 450) // 90 wpm
        let long = record("com.apple.mail", at: monday.addingTimeInterval(7200), seconds: 900, characters: 4500, backspaces: 90) // 58.8 wpm
        let records = Records([sprint, fast, long], calendar: utc)
        #expect(records.fastestSession == fast)
        #expect(records.longestSession == long)
        #expect(records.cleanestSession == fast)
        #expect(records.fastestByApp.map(\.appID) == ["com.apple.Notes", "com.apple.mail"])
    }

    @Test func `fastest day needs ten minutes of typing`() throws {
        let quickDay = record(at: monday, seconds: 120, characters: 1000) // 100 wpm, 2 min
        let fullDay = record(at: monday.addingTimeInterval(86_400), seconds: 900, characters: 4500) // 60 wpm, 15 min
        let records = Records([quickDay, fullDay], calendar: utc)
        #expect(records.fastestDay?.day == monday.addingTimeInterval(86_400))
        #expect(records.busiestDay?.day == monday.addingTimeInterval(86_400))
    }

    @Test func `no sessions, no records`() {
        let records = Records([], calendar: utc)
        #expect(records.fastestSession == nil)
        #expect(records.fastestDay == nil)
        #expect(records.fastestByApp.isEmpty)
    }
}
