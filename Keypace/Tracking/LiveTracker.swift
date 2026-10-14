import AppKit
import Observation
import KeypaceCore

/// Connects the keyboard tap to the session engine, saves finished sessions,
/// and owns the settings that change what gets recorded.
@Observable
final class LiveTracker {
    enum Status { case needsPermission, running }

    private(set) var status = Status.needsPermission
    private(set) var current: TypingSession?
    /// Bumped whenever stored history changes, so views reload.
    private(set) var revision = 0
    /// Set when the database can't be opened or written; sessions are not being saved.
    private(set) var storageError: String?

    var inactivityTimeout: Double {
        didSet {
            engine.inactivityTimeout = inactivityTimeout
            defaults.set(inactivityTimeout, forKey: Keys.inactivityTimeout)
        }
    }

    var minimumCharacters: Int {
        didSet {
            engine.minimumCharacters = minimumCharacters
            defaults.set(minimumCharacters, forKey: Keys.minimumCharacters)
        }
    }

    var filter: AppFilter {
        didSet { defaults.set(try? JSONEncoder().encode(filter), forKey: Keys.filter) }
    }

    let store: SessionStore?
    private var engine: SessionTracker
    private let monitor = KeyboardMonitor()
    private let defaults = UserDefaults.standard
    private var idleTimer: Timer?
    private var permissionTimer: Timer?

    private enum Keys {
        static let inactivityTimeout = "inactivityTimeout"
        static let minimumCharacters = "minimumCharacters"
        static let filter = "appFilter"
    }

    init() {
        let timeout = defaults.object(forKey: Keys.inactivityTimeout) as? Double ?? 5
        let minimum = defaults.object(forKey: Keys.minimumCharacters) as? Int ?? 10
        inactivityTimeout = timeout
        minimumCharacters = minimum
        filter = defaults.data(forKey: Keys.filter).flatMap { try? JSONDecoder().decode(AppFilter.self, from: $0) } ?? AppFilter()
        engine = SessionTracker(inactivityTimeout: timeout, minimumCharacters: minimum)

        do {
            let folder = URL.applicationSupportDirectory.appending(path: "Keypace", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            store = try SessionStore(path: folder.appending(path: "typing.sqlite").path)
        } catch {
            store = nil
            storageError = error.localizedDescription
        }
        startIfPermitted()
        observeSleep()
    }

    func requestPermission() {
        KeyboardMonitor.requestPermission()
    }

    // MARK: History

    func sessions(in interval: DateInterval) -> [SessionRecord] {
        guard let store else { return [] }
        return attempt { try store.sessions(in: interval) } ?? []
    }

    func firstSessionStart() -> Date? {
        guard let store else { return nil }
        return attempt { try store.firstSessionStart() } ?? nil
    }

    func allSessions() -> [SessionRecord] {
        guard let store else { return [] }
        return attempt { try store.allSessions() } ?? []
    }

    func deleteHistory(appID: String) {
        attempt { try store?.deleteSessions(appID: appID) }
        revision += 1
    }

    func deleteAllHistory() {
        engine = SessionTracker(inactivityTimeout: inactivityTimeout, minimumCharacters: minimumCharacters)
        current = nil
        attempt { try store?.deleteAll() }
        revision += 1
    }

    @discardableResult
    private func attempt<T>(_ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            storageError = error.localizedDescription
            return nil
        }
    }

    // MARK: Capture

    private func startIfPermitted() {
        if monitor.start(onKey: { [weak self] in self?.record($0) }) {
            status = .running
            permissionTimer?.invalidate()
            idleTimer = .scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } else {
            status = .needsPermission
            guard permissionTimer == nil else { return }
            permissionTimer = .scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.startIfPermitted() }
            }
        }
    }

    private func record(_ key: ObservedKey) {
        let appID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        guard filter.tracks(appID) else {
            endSession()
            return
        }
        let press = KeyPress(
            time: key.time,
            keyCode: key.keyCode,
            kind: KeyClassifier.kind(keyCode: key.keyCode, commandOrControl: key.commandOrControl, text: key.text),
            isRepeat: key.isRepeat
        )
        if let closed = engine.record(press, in: TypingContext(appID: appID)) { save(closed) }
        current = engine.current
    }

    private func tick() {
        if let closed = engine.closeIfIdle(at: ProcessInfo.processInfo.systemUptime) { save(closed) }
        current = engine.current
    }

    private func endSession() {
        if let closed = engine.end() { save(closed) }
        current = nil
    }

    private func save(_ session: TypingSession) {
        // Session times are seconds since boot; anchor the last press to the wall clock.
        let end = Date.now.addingTimeInterval(session.end - ProcessInfo.processInfo.systemUptime)
        attempt { try store?.insert(SessionRecord(session, endingAt: end)) }
        revision += 1
    }

    private func observeSleep() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endSession() }
        }
    }
}
