import Testing
@testable import KeypaceCore

struct KeyClassifierTests {
    @Test(arguments: ["a", "Z", "7", " ", ".", "é", "\r", "\t", "©"])
    func `text-producing keys are characters`(text: String) {
        #expect(KeyClassifier.kind(keyCode: 0, commandOrControl: false, text: text) == .character)
    }

    @Test func `delete key is a backspace`() {
        #expect(KeyClassifier.kind(keyCode: 51, commandOrControl: false, text: "\u{7F}") == .backspace)
    }

    @Test func `shortcuts are other, including Command-Delete`() {
        #expect(KeyClassifier.kind(keyCode: 8, commandOrControl: true, text: "c") == .other)
        #expect(KeyClassifier.kind(keyCode: 51, commandOrControl: true, text: "\u{7F}") == .other)
    }

    @Test(arguments: ["\u{F702}", "\u{F704}", "\u{1B}", ""])
    func `arrows, function keys, Escape and dead keys are other`(text: String) {
        #expect(KeyClassifier.kind(keyCode: 123, commandOrControl: false, text: text) == .other)
    }

    @Test func `option and command turn delete into word and line deletes`() {
        #expect(KeyClassifier.kind(keyCode: 51, commandOrControl: false, option: true, text: "\u{7F}") == .deleteWord)
        #expect(KeyClassifier.kind(keyCode: 51, commandOrControl: true, command: true, text: "\u{7F}") == .deleteLine)
        // Control-Delete isn't a text delete.
        #expect(KeyClassifier.kind(keyCode: 51, commandOrControl: true, text: "\u{7F}") == .other)
    }
}
