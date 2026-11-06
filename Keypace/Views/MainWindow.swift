import SwiftUI
import KeypaceCore

struct MainWindow: View {
    let tracker: LiveTracker

    enum Page: String, Hashable, CaseIterable {
        case overview = "Overview", statistics = "Statistics", apps = "Apps", keys = "Keys", records = "Records"
        case keyboards = "Keyboards", layouts = "Layouts", voice = "Voice", general = "General", tracking = "Tracking"
        case update = "Software Update"
    }

    @State private var page: Page?
    @Bindable private var updates = Updates.shared
    @Environment(\.openWindow) private var openWindow

    init(tracker: LiveTracker, page: Page = .overview) {
        self.tracker = tracker
        _page = State(initialValue: page)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                if updates.release != nil { UpdateSidebarRow().tag(Page.update) }
                Text(Page.overview.rawValue).tag(Page.overview)
                Text(Page.statistics.rawValue).tag(Page.statistics)
                Text(Page.apps.rawValue).tag(Page.apps)
                Text(Page.keys.rawValue).tag(Page.keys)
                Text(Page.records.rawValue).tag(Page.records)
                Text(Page.keyboards.rawValue).tag(Page.keyboards)
                Text(Page.layouts.rawValue).tag(Page.layouts)
                if tracker.measure.voice { Text(Page.voice.rawValue).tag(Page.voice) }
                Section("Settings") {
                    Text(Page.general.rawValue).tag(Page.general)
                    Text(Page.tracking.rawValue).tag(Page.tracking)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            Self.detail(for: page ?? .overview, tracker: tracker)
        }
        .frame(minWidth: 760, minHeight: 560)
        .onChange(of: updates.requestedPage, initial: true) { _, requested in
            guard let requested else { return }
            updates.requestedPage = nil
            page = requested
        }
        .onChange(of: updates.release == nil) { _, gone in
            if gone, page == .update { page = .general }
        }
        // Otherwise a solid bar appears behind the toolbar after the sidebar is toggled and while inactive.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            Button("Live Metrics", systemImage: "gauge.with.needle") { openWindow(id: "live") }
                .help("Show speed as you type in a floating window")
        }
    }

    @ViewBuilder
    static func detail(for page: Page, tracker: LiveTracker) -> some View {
        switch page {
        case .overview: OverviewPage(tracker: tracker)
        case .statistics: StatisticsPage(tracker: tracker)
        case .apps: AppsPage(tracker: tracker)
        case .keys: KeysPage(tracker: tracker)
        case .records: RecordsPage(tracker: tracker)
        case .keyboards: KeyboardsPage(tracker: tracker)
        case .layouts: LayoutsPage(tracker: tracker)
        case .voice: VoicePage(tracker: tracker)
        case .general: GeneralSettingsPage(tracker: tracker)
        case .tracking: TrackingSettingsPage(tracker: tracker)
        case .update: UpdatePage()
        }
    }
}

/// At the top of the sidebar while there's a newer version, as System Settings shows a macOS update.
private struct UpdateSidebarRow: View {
    var body: some View {
        // A dot instead of a numbered badge, so the label fits the narrow sidebar.
        HStack(spacing: 6) {
            Text("Update Available").lineLimit(1)
            Spacer(minLength: 0)
            Circle().fill(.red).frame(width: 8, height: 8)
        }
    }
}
