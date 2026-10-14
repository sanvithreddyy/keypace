import Foundation
import Testing
@testable import KeypaceCore

struct PeriodTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    let afternoon = monday.addingTimeInterval(15 * 3600)
    let day = 86_400.0

    @Test func `ranges end at the end of today and cover whole days`() throws {
        let today = try #require(Period.today.interval(now: afternoon, calendar: utc, firstSession: nil))
        #expect(today == DateInterval(start: monday, duration: day))
        let week = try #require(Period.week.interval(now: afternoon, calendar: utc, firstSession: nil))
        #expect(week == DateInterval(start: monday.addingTimeInterval(-6 * day), end: monday.addingTimeInterval(day)))
        let month = try #require(Period.month.interval(now: afternoon, calendar: utc, firstSession: nil))
        #expect(month.duration == 30 * day)
    }

    @Test func `the previous range is the same number of days just before`() {
        #expect(Period.today.previous(now: afternoon, calendar: utc) == DateInterval(start: monday.addingTimeInterval(-day), duration: day))
        #expect(Period.week.previous(now: afternoon, calendar: utc) == DateInterval(start: monday.addingTimeInterval(-13 * day), duration: 7 * day))
        #expect(Period.allTime.previous(now: afternoon, calendar: utc) == nil)
    }

    @Test func `all time starts on the day of the first session`() throws {
        #expect(Period.allTime.interval(now: afternoon, calendar: utc, firstSession: nil) == nil)
        let all = try #require(Period.allTime.interval(now: afternoon, calendar: utc, firstSession: monday.addingTimeInterval(-3 * day + 500)))
        #expect(all.start == monday.addingTimeInterval(-3 * day))
    }

    @Test func `weekday-by-hour groups by both`() {
        let cells = Statistics.byWeekdayAndHour([
            record(at: monday.addingTimeInterval(9 * 3600)),
            record(at: monday.addingTimeInterval(9 * 3600 + 1800)),
            record(at: monday.addingTimeInterval(7 * day + 9 * 3600)),
            record(at: monday.addingTimeInterval(day + 9 * 3600)),
        ], calendar: utc)
        #expect(cells[.init(weekday: 2, hour: 9)]?.duration == 180)
        #expect(cells[.init(weekday: 3, hour: 9)]?.duration == 60)
    }
}
