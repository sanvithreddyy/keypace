import AppKit
import Observation
import KeypaceCore

/// Connects keyboard capture to the session engine, saves finished sessions,
/// and owns the settings that change what gets recorded.
@Observable
final class LiveTracker {
    enum Status { case needsPermission, running }

    /// Where the event came from and when, as seen by the app.
    struct Clock {
        var now: () -> Date = { .now }
        /// Seconds since boot; key events use the same clock.
        var uptime: () -> Double = { ProcessInfo.processInfo.systemUptime }
    }

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

    var syntheticStrength: SyntheticFilter.Strength {
        didSet {
            synthetic.strength = syntheticStrength
            defaults.set(syntheticStrength.rawValue, forKey: Keys.syntheticStrength)
        }
    }

    let store: SessionStore?
    let inputSources: InputSources?
    private let devices: KeyboardDevices?
    private var engine: SessionTracker
    private var synthetic: SyntheticFilter
    /// Synthetic presses not yet written, per day received and app.
    private var pendingSynthetic: [SyntheticBucket: Int] = [:]

    private struct SyntheticBucket: Hashable {
        var day: String
        var appID: String
    }
    /// Keyboards and layouts typed on since the last save.
    private var seenKeyboards: [String: KeyboardRecord] = [:]
    private var seenInputSources: [String: InputSourceRecord] = [:]
    private let monitor = KeyboardMonitor()
    private let defaults: UserDefaults
    private let clock: Clock
    private var timer: Timer?
    private var ticks = 0

    private enum Keys {
        static let inactivityTimeout = "inactivityTimeout"
        static let minimumCharacters = "minimumCharacters"
        static let filter = "appFilter"
        static let syntheticStrength = "syntheticStrength"
    }

    /// - Parameter capture: false for tests and previews: no keyboard tap, no device or layout watching.
    init(store: SessionStore?, defaults: UserDefaults = .standard, clock: Clock = Clock(), capture: Bool = true) {
        self.store = store
        self.defaults = defaults
        self.clock = clock
        let timeout = defaults.object(forKey: Keys.inactivityTimeout) as? Double ?? 5
        let minimum = defaults.object(forKey: Keys.minimumCharacters) as? Int ?? 10
        let strength = defaults.string(forKey: Keys.syntheticStrength).flatMap(SyntheticFilter.Strength.init) ?? .normal
        inactivityTimeout = timeout
        minimumCharacters = minimum
        syntheticStrength = strength
        filter = defaults.data(forKey: Keys.filter).flatMap { try? JSONDecoder().decode(AppFilter.self, from: $0) } ?? AppFilter()
        engine = SessionTracker(inactivityTimeout: timeout, minimumCharacters: minimum)
        synthetic = SyntheticFilter(strength: strength)
        devices = capture ? KeyboardDevices() : nil
        inputSources = capture ? InputSources() : nil
        if capture {
            startCapture()
            observeSleep()
        } else {
            // Key events arrive through `handle` instead of the tap.
            status = .running
        }
    }

    /// The tracker for the running app, saving to Application Support.
    static func live() -> LiveTracker {
        do {
            let folder = URL.applicationSupportDirectory.appending(path: "Keypace", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return LiveTracker(store: try SessionStore(path: folder.appending(path: "typing.sqlite").path))
        } catch {
            let tracker = LiveTracker(store: nil)
            tracker.storageError = error.localizedDescription
            return tracker
        }
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

    func keyStats(in interval: DateInterval, filter: StatFilter = StatFilter()) -> [UInt16: KeyCount] {
        guard let store else { return [:] }
        return attempt { try store.keyStats(in: interval, calendar: .current, filter: filter) } ?? [:]
    }

    func pairStats(in interval: DateInterval, filter: StatFilter = StatFilter()) -> [KeyPair: PairTiming] {
        guard let store else { return [:] }
        return attempt { try store.pairStats(in: interval, calendar: .current, filter: filter) } ?? [:]
    }

    func syntheticCount(in interval: DateInterval) -> Int {
        guard let store else { return 0 }
        return attempt { try store.syntheticCount(in: interval, calendar: .current) } ?? 0
    }

    func keyboards() -> [KeyboardRecord] {
        guard let store else { return [] }
        return attempt { try store.keyboards() } ?? []
    }

    var connectedKeyboardIDs: Set<String> { devices?.connectedIDs ?? [] }

    func renameKeyboard(id: String, to name: String?) {
        attempt { try store?.renameKeyboard(id: id, to: name) }
        revision += 1
    }

    func inputSourceRecords() -> [InputSourceRecord] {
        guard let store else { return [] }
        return attempt { try store.inputSources() } ?? []
    }

    func deleteHistory(appID: String) {
        // Drop anything not yet saved for the app, so it can't be written back afterwards.
        pendingSynthetic = pendingSynthetic.filter { $0.key.appID != appID }
        if engine.current?.context.appID == appID {
            engine = SessionTracker(inactivityTimeout: inactivityTimeout, minimumCharacters: minimumCharacters)
            current = nil
        }
        attempt { try store?.deleteSessions(appID: appID) }
        revision += 1
    }

    func deleteAllHistory() {
        engine = SessionTracker(inactivityTimeout: inactivityTimeout, minimumCharacters: minimumCharacters)
        current = nil
        pendingSynthetic = [:]
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

    // MARK: Pipeline

    /// Runs one key-down through the app filter, the synthetic filter and the session engine.
    func handle(_ key: ObservedKey, appID: String, keyboard: KeyboardRecord?, inputSource: InputSourceRecord?) {
        guard filter.tracks(appID) else {
            endSession()
            return
        }
        if synthetic.isSynthetic(sourceStateID: key.sourceStateID, sourceProcessID: key.sourceProcessID, time: key.time, isRepeat: key.isRepeat) {
            pendingSynthetic[SyntheticBucket(day: Day.key(clock.now(), calendar: .current), appID: appID), default: 0] += 1
            return
        }
        let press = KeyPress(
            time: key.time,
            keyCode: key.keyCode,
            kind: KeyClassifier.kind(keyCode: key.keyCode, commandOrControl: key.commandOrControl, text: key.text),
            isRepeat: key.isRepeat
        )
        let context = TypingContext(appID: appID, keyboardID: keyboard?.id, inputSourceID: inputSource?.id)
        if let closed = engine.record(press, in: context) { save(closed) }
        if let keyboard { seenKeyboards[keyboard.id] = keyboard }
        if let inputSource { seenInputSources[inputSource.id] = inputSource }
        current = engine.current
    }

    /// Closes an idle session and writes pending counts. Runs every second while capturing.
    func tick() {
        if let closed = engine.closeIfIdle(at: clock.uptime()) { save(closed) }
        current = engine.current
        ticks += 1
        if ticks % 60 == 0 { flushSynthetic() }
    }

    func endSession() {
        if let closed = engine.end() { save(closed) }
        current = nil
        flushSynthetic()
    }

    private func save(_ session: TypingSession) {
        // Session times are seconds since boot; anchor the last press to the wall clock.
        let end = clock.now().addingTimeInterval(session.end - clock.uptime())
        attempt { try store?.save(session, endingAt: end, calendar: .current) }
        for keyboard in seenKeyboards.values { attempt { try store?.noteKeyboard(keyboard) } }
        for source in seenInputSources.values { attempt { try store?.noteInputSource(source) } }
        seenKeyboards = [:]
        seenInputSources = [:]
        flushSynthetic()
        revision += 1
    }

    private func flushSynthetic() {
        guard !pendingSynthetic.isEmpty else { return }
        for (bucket, count) in pendingSynthetic {
            attempt { try store?.addSynthetic(count: count, appID: bucket.appID, day: bucket.day) }
        }
        pendingSynthetic = [:]
        revision += 1
    }

    // MARK: Capture

    private func startCapture() {
        if monitor.start(onKey: { [weak self] in self?.record($0) }) {
            status = .running
            devices?.start()
        } else {
            status = .needsPermission
        }
        timer = .scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFired() }
        }
    }

    private func timerFired() {
        switch status {
        case .running where !KeyboardMonitor.hasPermission:
            // Input Monitoring was turned off while running.
            monitor.stop()
            endSession()
            status = .needsPermission
        case .running:
            tick()
        case .needsPermission:
            if monitor.start(onKey: { [weak self] in self?.record($0) }) {
                status = .running
                devices?.start()
            }
        }
    }

    private func record(_ key: ObservedKey) {
        let appID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        handle(key, appID: appID, keyboard: devices?.lastUsed, inputSource: inputSources?.current)
    }

    private func observeSleep() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endSession() }
        }
    }
}
