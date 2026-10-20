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

    @Test func `README showcase windows`() throws {
        let now = Date.now
        let clock = TestClock(date: now)
        let tracker = try makeTracker(clock: clock)
        try ReadmeHistory.fill(tracker, endingAt: now)
        let data = PeriodData(.month, tracker: tracker, now: now)
        let cells = Statistics.byWeekdayAndHour(data.sessions, calendar: .current)
        #expect(cells.keys.filter { (2...6).contains($0.weekday) && (8...23).contains($0.hour) }.count == 80)
        #expect(cells.keys.filter { $0.weekday == 1 || $0.weekday == 7 }.count < 20)
        let peak = try #require(cells.max { ($0.value.wpm ?? 0) < ($1.value.wpm ?? 0) })
        #expect((10...12).contains(peak.key.hour))
        let weekend = data.sessions.filter { [1, 7].contains(Calendar.current.component(.weekday, from: $0.start)) }
        #expect((peak.value.wpm ?? 0) > (Statistics.totals(weekend).wpm ?? 0) + 3)
        let daily = Statistics.byDay(data.sessions, calendar: .current).sorted { $0.key < $1.key }
        #expect(daily.count == 30)
        #expect(abs((daily.first?.value.wpm ?? 0) - 62) < 2.5)
        #expect(abs((daily.last?.value.wpm ?? 0) - 72) < 2.5)
        // Days wobble around a rising trend; the previous period stays flatter and slower.
        let half = daily.count / 2
        let firstHalf = daily.prefix(half).compactMap(\.value.wpm), secondHalf = daily.suffix(half).compactMap(\.value.wpm)
        #expect(secondHalf.reduce(0, +) / Double(secondHalf.count) > firstHalf.reduce(0, +) / Double(firstHalf.count) + 4)
        #expect((data.previousTotals?.wpm ?? 0) < 61)
        let previousSpeeds = Statistics.byDay(data.previousSessions ?? [], calendar: .current).values.compactMap(\.wpm)
        #expect(previousSpeeds.count == 30)
        #expect((previousSpeeds.max() ?? 0) - (previousSpeeds.min() ?? 0) < 6.5)
        #expect((0.02...0.06).contains(data.totals.correctionRate ?? 0))
        let presses = tracker.pressCounts(in: try #require(data.interval))
        #expect(presses[USKeys.code(for: "e"), default: 0] > presses[USKeys.code(for: "z"), default: 0] * 5)
        #expect(Statistics.byApp(data.sessions).count == SampleData.apps.count)

        let defaults = UserDefaults.standard
        let savedPeriods = ["overviewPeriod", "keysPeriod"].map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in savedPeriods {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(Period.month.rawValue, forKey: "overviewPeriod")
        defaults.set(Period.month.rawValue, forKey: "keysPeriod")
        for page in [MainWindow.Page.overview, .keys] {
            try renderWindow(page: page, tracker: tracker)
        }
    }

    /// Focused page renders; the README showcase above captures the full window too.
    @Test(arguments: MainWindow.Page.allCases)
    func `main window page`(page: MainWindow.Page) throws {
        try render(MainWindow.detail(for: page, tracker: tracker), size: CGSize(width: 780, height: 900), name: "page-\(page)")
    }

    @Test func `overview today`() throws {
        UserDefaults.standard.set(Period.today.rawValue, forKey: "overviewPeriod")
        defer { UserDefaults.standard.removeObject(forKey: "overviewPeriod") }
        try render(MainWindow.detail(for: .overview, tracker: tracker), size: CGSize(width: 780, height: 900), name: "page-overview-today")
    }

    @Test func `press history without saved sessions`() throws {
        let tracker = try makeTracker(clock: clock, minimumCharacters: nil)
        Typist(tracker: tracker, clock: clock).type("quick reply")
        tracker.endSession()
        #expect(tracker.allSessions().isEmpty)
        for page in [MainWindow.Page.keys, .overview] {
            try render(MainWindow.detail(for: page, tracker: tracker), size: CGSize(width: 780, height: 900), name: "page-\(page)-short-burst")
        }
    }

    @Test func `capture issues in settings`() throws {
        tracker.captureHealth.record(.listenerPaused)
        tracker.captureHealth.record(.listenerPaused)
        tracker.captureHealth.record(.unreadableKey)
        try render(GeneralSettingsPage(tracker: tracker), size: CGSize(width: 780, height: 1000), name: "page-general-capture-issues")
    }

    @Test func `live metrics`() throws {
        try renderMetrics(name: "live-metrics")
    }

    @Test(arguments: ["typing", "correcting", "paused"])
    func `live speed states`(state: String) throws {
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type(state == "correcting" ? "teh⌫⌫he quick brown fox jumps" : "the quick brown fox jumps", interval: 0.12)
        if state == "paused" { typist.pause(2.1) } else { tracker.tick() }
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

    /// Capture the real split view and native title bar without screen-recording permissions.
    private func renderWindow(page: MainWindow.Page, tracker: LiveTracker) throws {
        // Fit the complete content, including all five apps and all finger rows.
        let size = CGSize(width: 1100, height: page == .keys ? 1020 : 840)
        // Literal dark-mode ink avoids the black masks used by native vibrant text offscreen.
        let hosting = NSHostingController(rootView: MainWindow(tracker: tracker, page: page)
            .foregroundStyle(Color(white: 0.87)).environment(\.colorScheme, .dark))
        let window = ReadmeSnapshotWindow(contentRect: CGRect(origin: .zero, size: size),
                                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                         backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "Keypace"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(white: 0.13, alpha: 1)
        window.contentViewController = hosting
        window.setFrame(CGRect(x: -20000, y: -20000, width: size.width, height: size.height), display: true)
        window.orderBack(nil)
        defer { window.close() }
        RunLoop.main.run(until: .now.addingTimeInterval(0.5))
        let frameView = try #require(window.contentView?.superview)
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let views = descendants(frameView)
        for view in views {
            if let effect = view as? NSVisualEffectView {
                effect.blendingMode = .withinWindow
            }
        }
        RunLoop.main.run(until: .now.addingTimeInterval(0.2))
        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        #expect(frameView.bounds.size == size)
        func capture(_ view: NSView) throws -> NSBitmapImageRep {
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
                                                     pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8,
                                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            bitmap.size = view.bounds.size
            window.appearance?.performAsCurrentDrawingAppearance {
                view.cacheDisplay(in: view.bounds, to: bitmap)
            }
            return bitmap
        }
        let windowImage = try capture(frameView)
        // Glass skips its descendants during a frame capture. Capture the actual List below that
        // compositing boundary, preserving native cells, section header, spacing and selection.
        let list = try #require(views.compactMap { $0 as? NSOutlineView }.first)
        #expect(list.numberOfRows == 10)
        #expect(list.selectedRow == (page == .overview ? 0 : 3))
        let selectedRow = try #require(list.rowView(atRow: list.selectedRow, makeIfNecessary: false))
        for effect in descendants(selectedRow).compactMap({ $0 as? NSVisualEffectView }) { effect.isHidden = true }
        let listImage = try capture(list)
        let pixels = try #require(listImage.bitmapData)
        let readableInk = stride(from: 0, to: listImage.bytesPerRow * listImage.pixelsHigh, by: 4).contains {
            pixels[$0] > 180 && pixels[$0 + 1] > 180 && pixels[$0 + 2] > 180 && pixels[$0 + 3] > 180
        }
        #expect(readableInk, "The native sidebar must contain readable light text, not black vibrancy masks")
        let listRect = frameView.convert(list.bounds, from: list)
        let selectionRect = frameView.convert(list.rect(ofRow: list.selectedRow), from: list).insetBy(dx: 10, dy: 0)
        let windowCGImage = try #require(windowImage.cgImage)
        let listCGImage = try #require(listImage.cgImage)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                                 pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(white: 0.13, alpha: 1).setFill()
        CGRect(origin: .zero, size: size).fill()
        context.cgContext.draw(windowCGImage, in: CGRect(origin: .zero, size: size))
        NSColor(white: 0.15, alpha: 1).setFill()
        listRect.fill()
        // Only the vibrant selection material is composited; its row geometry and all text are real.
        NSColor(white: 0.24, alpha: 1).setFill()
        NSBezierPath(roundedRect: selectionRect, xRadius: 7, yRadius: 7).fill()
        context.cgContext.draw(listCGImage, in: listRect)
        NSGraphicsContext.restoreGraphicsState()
        #expect(bitmap.colorAt(x: 80, y: 200)?.alphaComponent == 1)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        try png.write(to: Self.output.appending(path: "readme-\(page.rawValue.lowercased()).png"))
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

/// Keep AppKit from shrinking an offscreen capture to the physical display's available height.
private final class ReadmeSnapshotWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
