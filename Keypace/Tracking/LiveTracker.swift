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
        /// The clipboard's text, read only when a dictation app pastes.
        var clipboard: () -> String? = { NSPasteboard.general.string(forType: .string) }
        /// The app a process belongs to.
        var appOwner: (Int32) -> String = { AppOwner.bundleID(of: $0) }
    }

    private(set) var status = Status.needsPermission
    /// The open session and live speed are published once a second by `tick`, not per keystroke:
    /// every menu-bar redraw costs about 10 ms of CPU.
    private(set) var current: TypingSession?
    /// Speed over the last few seconds of typing, in whole words per minute as shown; nil when not typing.
    private(set) var liveWPM: Double?
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

    /// Typing, voice or both.
    var measure: Measure {
        didSet {
            defaults.set(measure.rawValue, forKey: Keys.measure)
            if !measure.typing {
                endSession()
                engine.resetLive()
                liveWPM = nil
            }
            if !measure.voice { dictations = DictationDetector() }
            updateMicrophones()
        }
    }

    let store: SessionStore?
    let inputSources: InputSources?
    let captureHealth: CaptureHealth
    private let devices: KeyboardDevices?
    private var engine: SessionTracker
    private var synthetic: SyntheticFilter
    /// Synthetic presses not yet written, per hour received and app.
    private var pendingSynthetic: [SyntheticBucket: Int] = [:]
    /// Accepted physical presses, independent of whether a session is saved.
    private var pendingPresses: [PressBucket: Int] = [:]

    private struct PressBucket: Hashable {
        var hour: Int
        var appID: String
        var keyboardID: String?
        var inputSourceID: String?
        var keyCode: UInt16
    }

    private struct SyntheticBucket: Hashable {
        var hour: Int
        var appID: String
    }
    /// Keyboards and layouts typed on since the last save.
    private var seenKeyboards: [String: KeyboardRecord] = [:]
    private var seenInputSources: [String: InputSourceRecord] = [:]
    private let monitor: KeyboardMonitor
    private let microphones = MicrophoneMonitor()
    private var dictations = DictationDetector()
    /// Where typed-out dictation is going, per dictation app.
    private var dictationTargets: [String: String] = [:]
    private let capture: Bool
    private let defaults: UserDefaults
    private let clock: Clock
    private var timer: Timer?
    private var ticks = 0

    private enum Keys {
        static let inactivityTimeout = "inactivityTimeout"
        static let minimumCharacters = "minimumCharacters"
        static let filter = "appFilter"
        static let syntheticStrength = "syntheticStrength"
        static let measure = "measure"
    }

    /// ANSI V, posted with Command by apps that paste.
    private static let pasteKeyCode: UInt16 = 9

    /// - Parameter capture: false for tests and previews: no keyboard tap, no device or layout watching.
    init(store: SessionStore?, defaults: UserDefaults = .standard, clock: Clock = Clock(), capture: Bool = true) {
        self.store = store
        self.defaults = defaults
        self.clock = clock
        self.capture = capture
        measure = defaults.string(forKey: Keys.measure).flatMap(Measure.init) ?? .both
        let health = CaptureHealth(defaults: defaults, now: clock.now)
        captureHealth = health
        monitor = KeyboardMonitor(health: health)
        let timeout = defaults.object(forKey: Keys.inactivityTimeout) as? Double ?? 5
        let minimum = defaults.object(forKey: Keys.minimumCharacters) as? Int ?? 25
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
            observeTermination()
        } else {
            // Key events arrive through `handle` instead of the tap.
            status = .running
        }
    }

    /// The tracker for the running app, saving to Application Support.
    static func live() -> LiveTracker {
        do {
            var folder = URL.applicationSupportDirectory.appending(path: "Keypace", directoryHint: .isDirectory)
            #if DEBUG
            // -data-folder <path>: a test copy keeps its own history, away from the real one.
            if let i = CommandLine.arguments.firstIndex(of: "-data-folder"), i + 1 < CommandLine.arguments.count {
                folder = URL(filePath: CommandLine.arguments[i + 1], directoryHint: .isDirectory)
            }
            #endif
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

    func firstHistoryStart() -> Date? {
        guard let store else { return nil }
        return attempt { try store.firstHistoryStart() } ?? nil
    }

    func allSessions() -> [SessionRecord] {
        guard let store else { return [] }
        return attempt { try store.allSessions() } ?? []
    }

    func keyStats(in interval: DateInterval, filter: StatFilter = StatFilter()) -> [UInt16: KeyCount] {
        guard let store else { return [:] }
        return attempt { try store.keyStats(in: interval, filter: filter) } ?? [:]
    }

    func pressCounts(in interval: DateInterval, filter: StatFilter = StatFilter()) -> [UInt16: Int] {
        guard let store else { return [:] }
        return attempt { try store.pressCounts(in: interval, filter: filter) } ?? [:]
    }

    func pairStats(in interval: DateInterval, filter: StatFilter = StatFilter()) -> [KeyPair: PairTiming] {
        guard let store else { return [:] }
        return attempt { try store.pairStats(in: interval, filter: filter) } ?? [:]
    }

    func syntheticCount(in interval: DateInterval, appID: String? = nil) -> Int {
        guard let store else { return 0 }
        return attempt { try store.syntheticCount(in: interval, appID: appID) } ?? 0
    }

    func dictations(in interval: DateInterval) -> [DictationRecord] {
        guard let store else { return [] }
        return attempt { try store.dictations(in: interval) } ?? []
    }

    func allDictations() -> [DictationRecord] {
        guard let store else { return [] }
        return attempt { try store.allDictations() } ?? []
    }

    func firstDictationStart() -> Date? {
        guard let store else { return nil }
        return attempt { try store.firstDictationStart() } ?? nil
    }

    func deleteVoiceHistory() {
        dictations = DictationDetector()
        dictationTargets = [:]
        attempt { try store?.deleteAllDictations() }
        revision += 1
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
        pendingPresses = pendingPresses.filter { $0.key.appID != appID }
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
        pendingPresses = [:]
        seenKeyboards = [:]
        seenInputSources = [:]
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
    /// Keys posted by software also go to dictation detection.
    func handle(_ key: ObservedKey, appID: String, keyboard: KeyboardRecord?, inputSource: InputSourceRecord?) {
        if measure.voice, !SyntheticFilter.isHardware(sourceStateID: key.sourceStateID, sourceProcessID: key.sourceProcessID) {
            noteDictationText(key, appID: appID)
        }
        guard measure.typing else { return }
        guard filter.tracks(appID) else {
            endSession()
            return
        }
        if synthetic.isSynthetic(sourceStateID: key.sourceStateID, sourceProcessID: key.sourceProcessID, time: key.time, isRepeat: key.isRepeat) {
            pendingSynthetic[SyntheticBucket(hour: Hour.index(clock.now()), appID: appID), default: 0] += 1
            return
        }
        // Modifier-only events aren't key-downs, so they never enter this path.
        if !key.isRepeat {
            let bucket = PressBucket(hour: Hour.index(clock.now()), appID: appID, keyboardID: keyboard?.id,
                                     inputSourceID: inputSource?.id, keyCode: key.keyCode)
            pendingPresses[bucket, default: 0] += 1
        }
        let press = KeyPress(
            time: key.time,
            keyCode: key.keyCode,
            kind: KeyClassifier.kind(keyCode: key.keyCode, commandOrControl: key.commandOrControl, command: key.command, option: key.option, text: key.text),
            isRepeat: key.isRepeat,
            textCategory: KeyClassifier.textCategory(key.text)
        )
        let context = TypingContext(appID: appID, keyboardID: keyboard?.id, inputSourceID: inputSource?.id)
        if let keyboard { seenKeyboards[keyboard.id] = keyboard }
        if let inputSource { seenInputSources[inputSource.id] = inputSource }
        if let closed = engine.record(press, in: context) { save(closed) }
    }

    /// A key posted by another process. A paste from an app that just recorded counts the words on
    /// the clipboard at that moment; posted characters are collected until they stop. The text is
    /// never kept. Times are when Keypace sees the event, the clock microphone changes use.
    private func noteDictationText(_ key: ObservedKey, appID: String) {
        guard key.sourceProcessID > 0, filter.tracks(appID) else { return }
        let source = clock.appOwner(Int32(truncatingIfNeeded: key.sourceProcessID))
        let time = clock.uptime()
        if key.command, key.keyCode == Self.pasteKeyCode || key.text.lowercased() == "v" {
            guard dictations.expectsText(from: source, at: time) else { return }
            let words = WordCount.count(clock.clipboard() ?? "")
            if let found = dictations.pasted(words: words, by: source, at: time) { save(found, appID: appID) }
        } else if !key.commandOrControl, !key.isRepeat, !key.text.isEmpty {
            dictations.typed(key.text, by: source, at: time)
            dictationTargets[source] = appID
        }
    }

    /// A process started or stopped recording.
    func microphoneChanged(_ change: MicrophoneMonitor.Change) {
        let source = clock.appOwner(change.processID)
        if change.isRecording {
            dictations.microphoneStarted(processID: Int64(change.processID), sourceID: source, at: clock.uptime())
        } else {
            dictations.microphoneStopped(processID: Int64(change.processID), at: clock.uptime())
        }
    }

    private func save(_ found: DictationDetector.Detected, appID: String) {
        let now = clock.now()
        let uptime = clock.uptime()
        let record = DictationRecord(
            start: now.addingTimeInterval(found.start - uptime), end: now.addingTimeInterval(found.end - uptime),
            appID: appID, sourceID: found.sourceID, words: found.words, speakingSeconds: found.speakingSeconds
        )
        attempt { try store?.save(record) }
        revision += 1
    }

    /// Closes an idle session, publishes the open session and live speed, and writes pending counts.
    /// Runs every second while capturing.
    func tick() {
        for found in dictations.flush(at: clock.uptime()) {
            save(found, appID: dictationTargets.removeValue(forKey: found.sourceID) ?? "unknown")
        }
        if let closed = engine.closeIfIdle(at: clock.uptime()) { save(closed) }
        current = engine.current
        // Rounded, so an unchanged number doesn't redraw the menu bar.
        liveWPM = engine.live.wordsPerMinute(at: clock.uptime())?.rounded()
        ticks += 1
        if ticks % 60 == 0 { flushCounts() }
    }

    func endSession() {
        if let closed = engine.end() { save(closed) }
        current = nil
        flushCounts()
    }

    private func save(_ session: TypingSession) {
        // Session times are seconds since boot; anchor the last press to the wall clock.
        let end = clock.now().addingTimeInterval(session.end - clock.uptime())
        attempt { try store?.save(session, endingAt: end) }
        flushCounts()
        revision += 1
    }

    private func flushCounts() {
        for keyboard in seenKeyboards.values { attempt { try store?.noteKeyboard(keyboard) } }
        for source in seenInputSources.values { attempt { try store?.noteInputSource(source) } }
        seenKeyboards = [:]
        seenInputSources = [:]
        guard !pendingSynthetic.isEmpty || !pendingPresses.isEmpty else { return }
        if let store {
            for (bucket, count) in pendingPresses {
                if attempt({ try store.addPresses(count: count, keyCode: bucket.keyCode, appID: bucket.appID,
                                                  keyboardID: bucket.keyboardID, inputSourceID: bucket.inputSourceID, hour: bucket.hour) }) != nil {
                    pendingPresses.removeValue(forKey: bucket)
                }
            }
        }
        for (bucket, count) in pendingSynthetic {
            attempt { try store?.addSynthetic(count: count, appID: bucket.appID, hour: bucket.hour) }
        }
        pendingSynthetic = [:]
        revision += 1
    }

    // MARK: Capture

    /// Watches the microphone while capturing and measuring voice.
    private func updateMicrophones() {
        if capture, status == .running, measure.voice {
            microphones.start { [weak self] in self?.microphoneChanged($0) }
        } else {
            microphones.stop()
        }
    }

    private func startCapture() {
        if startMonitor() {
            status = .running
            devices?.start()
            updateMicrophones()
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
            captureStopped()
            status = .needsPermission
            updateMicrophones()
        case .running:
            tick()
        case .needsPermission:
            if startMonitor() {
                status = .running
                devices?.start()
                updateMicrophones()
            }
        }
    }

    private func startMonitor() -> Bool {
        monitor.start(onKey: { [weak self] in self?.record($0) }, onClick: { [weak self] in self?.engine.cursorMoved() })
    }

    /// Saves what's open and clears live speed when capture stops; nothing can update them until it restarts.
    func captureStopped() {
        endSession()
        engine.resetLive()
        liveWPM = nil
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

    private func observeTermination() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endSession() }
        }
    }
}
