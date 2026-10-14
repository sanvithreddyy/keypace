import Testing
@testable import KeypaceCore

struct AppFilterTests {
    @Test func `all-except tracks everything but the list`() {
        let filter = AppFilter(mode: .allExcept, appIDs: ["com.1password.1password"])
        #expect(filter.tracks("com.apple.Notes"))
        #expect(!filter.tracks("com.1password.1password"))
        #expect(AppFilter().tracks("anything"))
    }

    @Test func `only tracks just the list, and nothing when it's empty`() {
        let filter = AppFilter(mode: .only, appIDs: ["com.apple.Notes"])
        #expect(filter.tracks("com.apple.Notes"))
        #expect(!filter.tracks("com.apple.mail"))
        #expect(!AppFilter(mode: .only).tracks("com.apple.Notes"))
    }
}
