import SwiftUI
import KeypaceCore

struct MainWindow: View {
    let tracker: LiveTracker

    enum Page: String, Hashable, CaseIterable {
        case overview = "Overview", apps = "Apps", keys = "Keys", general = "General", tracking = "Tracking"
    }

    @State private var page: Page?

    init(tracker: LiveTracker, page: Page = .overview) {
        self.tracker = tracker
        _page = State(initialValue: page)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Text(Page.overview.rawValue).tag(Page.overview)
                Text(Page.apps.rawValue).tag(Page.apps)
                Text(Page.keys.rawValue).tag(Page.keys)
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
    }

    @ViewBuilder
    static func detail(for page: Page, tracker: LiveTracker) -> some View {
        switch page {
        case .overview: OverviewPage(tracker: tracker)
        case .apps: AppsPage(tracker: tracker)
        case .keys: KeysPage(tracker: tracker)
        case .general: GeneralSettingsPage(tracker: tracker)
        case .tracking: TrackingSettingsPage(tracker: tracker)
        }
    }
}
