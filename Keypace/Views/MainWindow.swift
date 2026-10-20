import SwiftUI
import KeypaceCore

struct MainWindow: View {
    let tracker: LiveTracker

    enum Page: String, Hashable, CaseIterable {
        case overview = "Overview", statistics = "Statistics", apps = "Apps", keys = "Keys", records = "Records"
        case keyboards = "Keyboards", layouts = "Layouts", general = "General", tracking = "Tracking"
    }

    @State private var page: Page?
    @Environment(\.openWindow) private var openWindow

    init(tracker: LiveTracker, page: Page = .overview) {
        self.tracker = tracker
        _page = State(initialValue: page)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Text(Page.overview.rawValue).tag(Page.overview)
                Text(Page.statistics.rawValue).tag(Page.statistics)
                Text(Page.apps.rawValue).tag(Page.apps)
                Text(Page.keys.rawValue).tag(Page.keys)
                Text(Page.records.rawValue).tag(Page.records)
                Text(Page.keyboards.rawValue).tag(Page.keyboards)
                Text(Page.layouts.rawValue).tag(Page.layouts)
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
        case .general: GeneralSettingsPage(tracker: tracker)
        case .tracking: TrackingSettingsPage(tracker: tracker)
        }
    }
}
