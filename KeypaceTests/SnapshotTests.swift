import AppKit
import SwiftUI
import Testing
import KeypaceCore

/// Renders each screen with sample history to PNGs in build/snapshots for review.
@MainActor
@Suite(.serialized)
struct SnapshotTests {
    static let output = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "build/snapshots", directoryHint: .isDirectory)

    let tracker: LiveTracker

    init() throws {
        let clock = TestClock(date: .now)
        tracker = try makeTracker(clock: clock)
        SampleData.fill(tracker, clock: clock, days: 45, endingAt: .now)
        SampleData.typeToday(tracker, clock: clock)
    }

    /// Pages are rendered without the window's sidebar: offscreen rendering skips translucent backgrounds.
    @Test(arguments: MainWindow.Page.allCases)
    func `main window page`(page: MainWindow.Page) throws {
        try render(MainWindow.detail(for: page, tracker: tracker), size: CGSize(width: 780, height: 900), name: "page-\(page)")
    }

    @Test func `live metrics`() throws {
        try render(LiveMetrics(tracker: tracker), size: CGSize(width: 220, height: 100), name: "live-metrics")
    }

    @Test(arguments: [(Dropdown.Tab.speed, Period.today), (.speed, .week), (.speed, .month), (.keys, .week), (.apps, .week), (.records, .today)])
    func dropdown(tab: Dropdown.Tab, period: Period) throws {
        UserDefaults.standard.set(tab.rawValue, forKey: "dropdownTab")
        UserDefaults.standard.set(period.rawValue, forKey: "dropdownPeriod")
        defer {
            UserDefaults.standard.removeObject(forKey: "dropdownTab")
            UserDefaults.standard.removeObject(forKey: "dropdownPeriod")
        }
        try render(Dropdown(tracker: tracker), size: CGSize(width: 340, height: 640), name: "dropdown-\(tab)-\(period)")
    }

    private func render(_ view: some View, size: CGSize, name: String) throws {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: .now.addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()

        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        try png.write(to: Self.output.appending(path: "\(name).png"))
    }
}
