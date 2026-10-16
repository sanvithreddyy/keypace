import Foundation
import Testing

@MainActor
struct CaptureHealthTests {
    private let start = Date(timeIntervalSince1970: 1_791_810_000)

    @Test func `capture health starts once with no recorded losses`() {
        let suite = "KeypaceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = TestClock(date: start)
        let health = CaptureHealth(defaults: defaults, now: clock.clock.now)
        #expect(health.startedAt == start)
        #expect(health.listenerPauses == 0)
        #expect(health.unreadableKeys == 0)
        #expect(health.lastOccurrence == nil)
        clock.advance(60)
        let reopened = CaptureHealth(defaults: defaults, now: clock.clock.now)
        #expect(reopened.startedAt == start)
        #expect(reopened.lastOccurrence == nil)
    }

    @Test func `capture issues count separately with the date of the most recent occurrence`() {
        let suite = "KeypaceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = TestClock(date: start)
        let health = CaptureHealth(defaults: defaults, now: clock.clock.now)
        clock.advance(10)
        health.record(.listenerPaused)
        health.record(.listenerPaused)
        #expect(health.listenerPauses == 2)
        #expect(health.unreadableKeys == 0)
        #expect(health.lastOccurrence == start.addingTimeInterval(10))
        clock.advance(20)
        health.record(.unreadableKey)
        #expect(health.listenerPauses == 2)
        #expect(health.unreadableKeys == 1)
        #expect(health.startedAt == start)
        #expect(health.lastOccurrence == start.addingTimeInterval(30))
    }

    @Test func `capture counts and dates persist across defaults instances`() {
        let suite = "KeypaceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = TestClock(date: start)
        let health = CaptureHealth(defaults: defaults, now: clock.clock.now)
        clock.advance(10)
        health.record(.listenerPaused)
        health.record(.unreadableKey)
        clock.advance(20)
        let reopened = CaptureHealth(defaults: UserDefaults(suiteName: suite)!, now: clock.clock.now)
        #expect(reopened.startedAt == start)
        #expect(reopened.listenerPauses == 1)
        #expect(reopened.unreadableKeys == 1)
        #expect(reopened.lastOccurrence == start.addingTimeInterval(10))
        reopened.record(.unreadableKey)
        let latest = CaptureHealth(defaults: defaults, now: clock.clock.now)
        #expect(latest.unreadableKeys == 2)
        #expect(latest.lastOccurrence == start.addingTimeInterval(30))
    }
}
