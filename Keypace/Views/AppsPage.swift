import SwiftUI
import KeypaceCore

struct AppsPage: View {
    let tracker: LiveTracker
    @AppStorage("appsPeriod") private var period = Period.month
    @State private var pendingDeletion: String?

    var body: some View {
        let data = { _ = tracker.revision; return PeriodData(period, tracker: tracker) }()
        let previous = Dictionary(uniqueKeysWithValues: Statistics.byApp(data.previousSessions ?? []).map { ($0.appID, $0.totals) })
        let rows = Statistics.byApp(data.sessions).map {
            BreakdownRow(id: $0.appID, title: AppInfo.name($0.appID), icon: AppInfo.icon($0.appID), totals: $0.totals, previous: previous[$0.appID])
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Apps", period: $period).padding(.bottom, 16)
                if rows.isEmpty {
                    Text("No typing recorded in this period.").foregroundStyle(.secondary)
                } else {
                    BreakdownTable(heading: "App", rows: rows) { row in
                        Button("Stop Tracking \(row.title)…") { pendingDeletion = row.id }
                    }
                }
            }
            .padding(24)
        }
        .confirmationDialog(
            "Stop tracking \(pendingDeletion.map(AppInfo.name) ?? "")?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            if let appID = pendingDeletion {
                Button("Stop Tracking and Delete History", role: .destructive) {
                    stopTracking(appID)
                    tracker.deleteHistory(appID: appID)
                }
                Button("Stop Tracking, Keep History") { stopTracking(appID) }
            }
        }
    }

    private func stopTracking(_ appID: String) {
        switch tracker.filter.mode {
        case .allExcept: if !tracker.filter.appIDs.contains(appID) { tracker.filter.appIDs.append(appID) }
        case .only: tracker.filter.appIDs.removeAll { $0 == appID }
        }
    }
}
