import Testing
@testable import KeypaceCore

struct LayoutFamilyTests {
    @Test(arguments: [
        ("com.apple.keylayout.US", LayoutFamily.qwerty),
        ("com.apple.keylayout.ABC", .qwerty),
        ("com.apple.keylayout.British", .qwerty),
        ("com.apple.keylayout.Canadian-CSA", .qwerty),
        ("com.apple.keylayout.German", .qwertz),
        ("com.apple.keylayout.SwissFrench", .qwertz),
        ("com.apple.keylayout.French", .azerty),
        ("com.apple.keylayout.Belgian", .azerty),
        ("com.apple.keylayout.Dvorak", .dvorak),
        ("com.apple.keylayout.DVORAK-QWERTYCMD", .dvorak),
        ("com.apple.keylayout.Colemak", .colemak),
        ("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", .other),
    ])
    func `families from input source identifiers`(id: String, family: LayoutFamily) {
        #expect(LayoutFamily.detect(inputSourceID: id) == family)
    }
}
