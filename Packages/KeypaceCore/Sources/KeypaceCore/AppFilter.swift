/// Which apps are tracked: everything except a list, or only a list.
public struct AppFilter: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case allExcept, only
    }

    public var mode: Mode
    /// Bundle identifiers.
    public var appIDs: [String]

    public init(mode: Mode = .allExcept, appIDs: [String] = []) {
        self.mode = mode
        self.appIDs = appIDs
    }

    public func tracks(_ appID: String) -> Bool {
        switch mode {
        case .allExcept: !appIDs.contains(appID)
        case .only: appIDs.contains(appID)
        }
    }
}
