import Foundation

/// Pairs a microphone session with the text the same app puts in afterwards.
///
/// Any app that records and then pastes or types counts as dictation; a call that uses the
/// microphone but never puts text in counts as nothing. Apps are matched by their app bundle, not
/// process, so a helper that records and a main process that pastes still pair. Times are seconds since boot.
public struct DictationDetector: Sendable {
    /// Text must arrive within this many seconds of the microphone closing.
    public static let pasteWindow = 10.0
    /// Typed-out text ends after this long without another posted character.
    public static let typingGap = 0.6

    public struct Detected: Sendable, Equatable {
        public var sourceID: String
        public var words: Int
        /// When the microphone opened and when the text arrived.
        public var start: Double
        public var end: Double
        public var speakingSeconds: Double
    }

    private struct MicSession {
        var processID: Int64
        var sourceID: String
        var start: Double
        var end: Double?
    }

    private struct Typed {
        var text = ""
        var last: Double
    }

    private var sessions: [MicSession] = []
    private var typed: [String: Typed] = [:]

    public init() {}

    /// Whether any process is recording now.
    public var isRecording: Bool { sessions.contains { $0.end == nil } }

    public mutating func microphoneStarted(processID: Int64, sourceID: String, at time: Double) {
        guard !sessions.contains(where: { $0.processID == processID && $0.end == nil }) else { return }
        sessions.append(MicSession(processID: processID, sourceID: sourceID, start: time))
    }

    public mutating func microphoneStopped(processID: Int64, at time: Double) {
        for index in sessions.indices where sessions[index].processID == processID && sessions[index].end == nil {
            sessions[index].end = time
        }
        prune(at: time)
    }

    /// Whether text posted by the app now could be dictation, so the clipboard is worth reading.
    public func expectsText(from sourceID: String, at time: Double) -> Bool {
        hasSession(for: sourceID, at: time)
    }

    /// A paste posted by the app, with the words on the clipboard at that moment.
    public mutating func pasted(words: Int, by sourceID: String, at time: Double) -> Detected? {
        claim(words: words, by: sourceID, at: time)
    }

    /// A character posted by the app. Typed-out text is counted once it stops; see `flush`.
    public mutating func typed(_ text: String, by sourceID: String, at time: Double) {
        guard hasSession(for: sourceID, at: time) || typed[sourceID] != nil else { return }
        typed[sourceID, default: Typed(last: time)].text += text
        typed[sourceID]?.last = time
    }

    /// Ends typed-out text that has gone quiet, and forgets old microphone sessions.
    public mutating func flush(at time: Double) -> [Detected] {
        var found: [Detected] = []
        for (sourceID, buffer) in typed where time - buffer.last >= Self.typingGap {
            typed[sourceID] = nil
            if let detected = claim(words: WordCount.count(buffer.text), by: sourceID, at: buffer.last) {
                found.append(detected)
            }
        }
        prune(at: time)
        return found
    }

    private func hasSession(for sourceID: String, at time: Double) -> Bool {
        sessions.contains { $0.sourceID == sourceID && ($0.end.map { time - $0 <= Self.pasteWindow } ?? true) }
    }

    /// Uses up the app's latest microphone session for this text, so it's counted once.
    private mutating func claim(words: Int, by sourceID: String, at time: Double) -> Detected? {
        guard words > 0,
              let index = sessions.lastIndex(where: {
                  $0.sourceID == sourceID && $0.start <= time && ($0.end.map { time - $0 <= Self.pasteWindow } ?? true)
              })
        else { return nil }
        let session = sessions.remove(at: index)
        let end = min(session.end ?? time, time)
        return Detected(sourceID: session.sourceID, words: words, start: session.start, end: time, speakingSeconds: end - session.start)
    }

    private mutating func prune(at time: Double) {
        sessions.removeAll { session in session.end.map { time - $0 > Self.pasteWindow } ?? false }
    }
}
