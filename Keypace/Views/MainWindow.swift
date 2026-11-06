import SwiftUI
import KeypaceCore

struct MainWindow: View {
    let tracker: LiveTracker

    enum Page: String, Hashable, CaseIterable {
        case overview = "Overview", statistics = "Statistics", apps = "Apps", keys = "Keys", records = "Records"
        case keyboards = "Keyboards", layouts = "Layouts", general = "General", tracking = "Tracking"

        /// Pages about keys and keyboards, which voice has none of.
        var isTypingOnly: Bool { self == .keys || self == .keyboards || self == .layouts }
    }

    @State private var page: Page?
    @AppStorage("mode") private var mode = Mode.typing
    @Environment(\.openWindow) private var openWindow

    init(tracker: LiveTracker, page: Page = .overview) {
        self.tracker = tracker
        _page = State(initialValue: page)
    }

    var body: some View {
        let shown = mode.shown(for: tracker.measure)
        NavigationSplitView {
            List(selection: $page) {
                Text(Page.overview.rawValue).tag(Page.overview)
                Text(Page.statistics.rawValue).tag(Page.statistics)
                Text(Page.apps.rawValue).tag(Page.apps)
                if shown == .typing { Text(Page.keys.rawValue).tag(Page.keys) }
                Text(Page.records.rawValue).tag(Page.records)
                if shown == .typing {
                    Text(Page.keyboards.rawValue).tag(Page.keyboards)
                    Text(Page.layouts.rawValue).tag(Page.layouts)
                }
                Section("Settings") {
                    Text(Page.general.rawValue).tag(Page.general)
                    Text(Page.tracking.rawValue).tag(Page.tracking)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            Self.detail(for: page ?? .overview, tracker: tracker, mode: shown)
        }
        .frame(minWidth: 760, minHeight: 560)
        // Otherwise a solid bar appears behind the toolbar after the sidebar is toggled and while inactive.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            if tracker.measure == .both {
                ToolbarItem(placement: .principal) {
                    ModePicker(mode: $mode).help("Show typing or voice statistics")
                }
            }
            ToolbarItem {
                Button("Live Metrics", systemImage: "gauge.with.needle") { openWindow(id: "live") }
                    .help("Show speed as you type in a floating window")
            }
        }
        .onChange(of: shown) { _, shown in
            if shown == .voice, page?.isTypingOnly == true { page = .overview }
        }
    }

    @ViewBuilder
    static func detail(for page: Page, tracker: LiveTracker, mode: Mode = .typing) -> some View {
        switch page {
        case .overview: OverviewPage(tracker: tracker, mode: mode)
        case .statistics: StatisticsPage(tracker: tracker, mode: mode)
        case .apps: AppsPage(tracker: tracker, mode: mode)
        case .keys: KeysPage(tracker: tracker)
        case .records: RecordsPage(tracker: tracker, mode: mode)
        case .keyboards: KeyboardsPage(tracker: tracker)
        case .layouts: LayoutsPage(tracker: tracker)
        case .general: GeneralSettingsPage(tracker: tracker)
        case .tracking: TrackingSettingsPage(tracker: tracker)
        }
    }
}

/// Typing or voice.
struct ModePicker: View {
    @Binding var mode: Mode

    var body: some View {
        Picker("Show", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}
