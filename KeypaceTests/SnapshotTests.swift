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
    let clock: TestClock

    init() throws {
        clock = TestClock(date: .now)
        tracker = try makeTracker(clock: clock)
        SampleData.fill(tracker, clock: clock, days: 45, endingAt: .now)
        SampleData.typeToday(tracker, clock: clock)
    }

    /// Pages are rendered without the window's sidebar: offscreen rendering skips translucent backgrounds.
    @Test(arguments: MainWindow.Page.allCases)
    func `main window page`(page: MainWindow.Page) throws {
        try render(MainWindow.detail(for: page, tracker: tracker), size: CGSize(width: 780, height: 900), name: "page-\(page)")
    }

    @Test func `overview today`() throws {
        UserDefaults.standard.set(Period.today.rawValue, forKey: "overviewPeriod")
        defer { UserDefaults.standard.removeObject(forKey: "overviewPeriod") }
        try render(MainWindow.detail(for: .overview, tracker: tracker), size: CGSize(width: 780, height: 900), name: "page-overview-today")
    }

    @Test func `live metrics`() throws {
        try renderMetrics(name: "live-metrics")
    }

    @Test(arguments: ["typing", "correcting", "paused"])
    func `live speed states`(state: String) throws {
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type(state == "correcting" ? "teh⌫⌫he quick brown fox jumps" : "the quick brown fox jumps", interval: 0.12)
        if state == "paused" { typist.pause(2.1) }
        #expect((tracker.liveWPM != nil) == (state != "paused"))
        #expect(tracker.current != nil)

        try renderMetrics(name: "live-metrics-\(state)")

        UserDefaults.standard.set(Dropdown.Tab.speed.rawValue, forKey: "dropdownTab")
        UserDefaults.standard.set(Period.today.rawValue, forKey: "dropdownPeriod")
        defer {
            UserDefaults.standard.removeObject(forKey: "dropdownTab")
            UserDefaults.standard.removeObject(forKey: "dropdownPeriod")
        }
        let dropdown = Dropdown(tracker: tracker)
        let dropdownSize = NSHostingController(rootView: dropdown).sizeThatFits(in: CGSize(width: Dropdown.width, height: 2000))
        #expect(dropdownSize.width <= Dropdown.width + 0.5)
        try render(dropdown.frame(width: Dropdown.width), size: CGSize(width: Dropdown.width, height: 640), name: "dropdown-speed-\(state)")
    }

    @Test(arguments: [(Dropdown.Tab.speed, Period.today), (.speed, .week), (.speed, .month), (.keys, .week), (.keys, .today), (.apps, .week), (.records, .today)])
    func dropdown(tab: Dropdown.Tab, period: Period) throws {
        UserDefaults.standard.set(tab.rawValue, forKey: "dropdownTab")
        UserDefaults.standard.set(period.rawValue, forKey: "dropdownPeriod")
        defer {
            UserDefaults.standard.removeObject(forKey: "dropdownTab")
            UserDefaults.standard.removeObject(forKey: "dropdownPeriod")
        }
        // The content must fit the panel's width, whatever the labels inside it.
        let needed = NSHostingController(rootView: Dropdown(tracker: tracker))
            .sizeThatFits(in: CGSize(width: Dropdown.width, height: 2000))
        #expect(needed.width <= Dropdown.width + 0.5, "\(tab) tab needs \(needed.width) pt")
        try render(Dropdown(tracker: tracker).frame(width: Dropdown.width), size: CGSize(width: Dropdown.width, height: 640), name: "dropdown-\(tab)-\(period)")
    }

    private func renderMetrics(name: String) throws {
        let metrics = LiveMetrics(tracker: tracker)
        let needed = NSHostingController(rootView: metrics).sizeThatFits(in: CGSize(width: 220, height: 2000))
        #expect(needed.width <= 220.5)
        // The real window sizes to its content, so the snapshot must use its full height too.
        try render(metrics, size: CGSize(width: 220, height: needed.height.rounded(.up)), name: name)
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
