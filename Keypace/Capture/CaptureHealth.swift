import Foundation
import Observation

/// Persistent counts of capture interruptions and key-downs the listener couldn't read.
@Observable
final class CaptureHealth {
    enum Event { case listenerPaused, unreadableKey }

    let startedAt: Date
    private(set) var listenerPauses: Int
    private(set) var unreadableKeys: Int
    private(set) var lastOccurrence: Date?

    private let defaults: UserDefaults
    private let now: () -> Date

    private enum Keys {
        static let startedAt = "captureStartedAt"
        static let listenerPauses = "captureListenerPauses"
        static let unreadableKeys = "captureUnreadableKeys"
        static let lastOccurrence = "captureLastOccurrence"
    }

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { .now }) {
        self.defaults = defaults
        self.now = now
        startedAt = defaults.object(forKey: Keys.startedAt) as? Date ?? now()
        listenerPauses = defaults.integer(forKey: Keys.listenerPauses)
        unreadableKeys = defaults.integer(forKey: Keys.unreadableKeys)
        lastOccurrence = defaults.object(forKey: Keys.lastOccurrence) as? Date
        defaults.set(startedAt, forKey: Keys.startedAt)
    }

    func record(_ event: Event) {
        switch event {
        case .listenerPaused:
            listenerPauses += 1
            defaults.set(listenerPauses, forKey: Keys.listenerPauses)
        case .unreadableKey:
            unreadableKeys += 1
            defaults.set(unreadableKeys, forKey: Keys.unreadableKeys)
        }
        lastOccurrence = now()
        defaults.set(lastOccurrence, forKey: Keys.lastOccurrence)
    }
}
