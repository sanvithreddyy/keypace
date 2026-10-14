import AppKit

/// Display names and icons for bundle identifiers.
enum AppInfo {
    private static var names: [String: String] = [:]

    static func name(_ bundleID: String) -> String {
        if let cached = names[bundleID] { return cached }
        let name = url(bundleID).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
        names[bundleID] = name
        return name
    }

    static func icon(_ bundleID: String) -> NSImage? {
        url(bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    private static func url(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}
