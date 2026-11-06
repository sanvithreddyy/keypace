import Foundation
import Testing
import KeypaceCore

/// Dictation through the app path: microphone changes, posted keys, the clipboard and storage.
@MainActor
struct VoicePipelineTests {
    let clock = TestClock(date: Date(timeIntervalSince1970: 1_791_810_000)) // 2026-10-12 13:00 UTC

    private func key(_ text: String, keyCode: UInt16, command: Bool = false, from processID: Int64) -> ObservedKey {
        ObservedKey(keyCode: keyCode, time: clock.uptime, text: text, commandOrControl: command, command: command,
                    option: false, isRepeat: false, sourceStateID: 0, sourceProcessID: processID)
    }

    private func paste(_ tracker: LiveTracker, from processID: Int64, into appID: String = "com.apple.mail") {
        tracker.handle(key("v", keyCode: 9, command: true, from: processID), appID: appID, keyboard: nil, inputSource: nil)
    }

    @Test func `a dictation app's paste is saved with its words and speaking time`() throws {
        let tracker = try makeTracker(clock: clock)
        clock.owners = [77: "com.example.dictation"]
        tracker.microphoneChanged(.init(processID: 77, isRecording: true))
        clock.advance(63)
        tracker.microphoneChanged(.init(processID: 77, isRecording: false))
        clock.advance(0.2)
        clock.clipboard = Array(repeating: "word", count: 160).joined(separator: " ")
        paste(tracker, from: 77)

        let saved = try #require(tracker.allDictations().first)
        #expect(tracker.allDictations().count == 1)
        #expect(saved.words == 160)
        #expect(saved.speakingSeconds == 63)
        #expect(saved.appID == "com.apple.mail")
        #expect(saved.sourceID == "com.example.dictation")
        #expect(saved.end == clock.date)
        #expect(saved.start == clock.date.addingTimeInterval(-63.2))
        // Posted keys still count as filtered input, never as typing.
        #expect(tracker.allSessions().isEmpty)
    }

    @Test func `pastes without a recording first, and recordings without a paste, save nothing`() throws {
        let tracker = try makeTracker(clock: clock)
        clock.clipboard = "copied from somewhere else"
        paste(tracker, from: 12)
        tracker.microphoneChanged(.init(processID: 30, isRecording: true))
        clock.advance(600)
        tracker.microphoneChanged(.init(processID: 30, isRecording: false))
        clock.advance(20)
        tracker.tick()
        #expect(tracker.allDictations().isEmpty)
    }

    @Test func `text an app types out after recording is one dictation`() throws {
        let tracker = try makeTracker(clock: clock)
        tracker.microphoneChanged(.init(processID: 50, isRecording: true))
        clock.advance(4)
        tracker.microphoneChanged(.init(processID: 50, isRecording: false))
        for character in "hello there friend" {
            clock.advance(0.005)
            tracker.handle(key(String(character), keyCode: USKeys.code(for: character), from: 50), appID: "com.apple.Notes", keyboard: nil, inputSource: nil)
        }
        clock.advance(1)
        tracker.tick()
        let saved = try #require(tracker.allDictations().first)
        #expect(saved.words == 3)
        #expect(saved.appID == "com.apple.Notes")
        #expect(saved.sourceID == "pid:50")
    }

    @Test func `voice off ignores dictation, typing off ignores typing`() throws {
        let tracker = try makeTracker(clock: clock)
        tracker.measure = .typing
        clock.clipboard = "two words"
        tracker.microphoneChanged(.init(processID: 77, isRecording: true))
        clock.advance(2)
        tracker.microphoneChanged(.init(processID: 77, isRecording: false))
        paste(tracker, from: 77)
        #expect(tracker.allDictations().isEmpty)

        tracker.measure = .voice
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type("the quick brown fox jumps over the lazy dog")
        typist.pause()
        #expect(tracker.allSessions().isEmpty)
        #expect(tracker.pressCounts(in: DateInterval(start: .distantPast, end: .distantFuture)).isEmpty)
    }

    @Test func `dictation into an app that isn't tracked is not saved`() throws {
        let tracker = try makeTracker(clock: clock)
        tracker.filter = AppFilter(mode: .allExcept, appIDs: ["com.apple.Notes"])
        clock.clipboard = "private note"
        tracker.microphoneChanged(.init(processID: 77, isRecording: true))
        clock.advance(2)
        tracker.microphoneChanged(.init(processID: 77, isRecording: false))
        paste(tracker, from: 77, into: "com.apple.Notes")
        #expect(tracker.allDictations().isEmpty)
    }
}
