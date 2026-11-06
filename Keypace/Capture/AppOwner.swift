import AppKit
import Darwin

/// The app a process belongs to: the bundle ID of the outermost app bundle holding its
/// executable, so a helper process counts as its app.
enum AppOwner {
    private static var cache: [Int32: String] = [:]

    static func bundleID(of processID: Int32) -> String {
        if let cached = cache[processID] { return cached }
        let owner = outermostBundleID(of: processID)
            ?? NSRunningApplication(processIdentifier: processID)?.bundleIdentifier
            ?? "pid:\(processID)"
        cache[processID] = owner
        return owner
    }

    /// Drops a process that has exited, since its ID can be reused.
    static func forget(_ processID: Int32) {
        cache[processID] = nil
    }

    private static func outermostBundleID(of processID: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(processID, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard let range = path.range(of: ".app/") else { return nil }
        return Bundle(path: String(path[..<range.lowerBound]) + ".app")?.bundleIdentifier
    }
}
