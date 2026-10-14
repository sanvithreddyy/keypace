import SwiftUI
import KeypaceCore

struct AppsPage: View {
    let tracker: LiveTracker
    @AppStorage("appsPeriod") private var period = Period.month
    @State private var pendingDeletion: String?

    var body: some View {
        let data = { _ = tracker.revision; return PeriodData(period, tracker: tracker) }()
        let apps = Statistics.byApp(data.sessions)
        let previous = Dictionary(uniqueKeysWithValues: Statistics.byApp(data.previousSessions ?? []).map { ($0.appID, $0.totals) })
        let total = max(data.totals.duration, 1)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Apps", period: $period).padding(.bottom, 16)
                if apps.isEmpty {
                    Text("No typing recorded in this period.").foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("App")
                            Text("Typing time").gridColumnAlignment(.trailing)
                            Text("Share").gridColumnAlignment(.trailing)
                            Text("WPM").gridColumnAlignment(.trailing)
                            Text("Change").gridColumnAlignment(.trailing)
                            Text("Corrections").gridColumnAlignment(.trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Divider()
                        ForEach(apps, id: \.appID) { app in
                            GridRow {
                                HStack(spacing: 8) {
                                    if let icon = AppInfo.icon(app.appID) { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                                    Text(AppInfo.name(app.appID)).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(Format.duration(app.totals.duration))
                                Text(Format.percent(app.totals.duration / total)).foregroundStyle(.secondary)
                                Text(Format.wpm(app.totals.wpm))
                                changeText(app.totals.wpm, previous[app.appID]?.wpm)
                                Text(Format.percent(app.totals.correctionRate)).foregroundStyle(.secondary)
                            }
                            .contextMenu {
                                Button("Stop Tracking \(AppInfo.name(app.appID))…") { pendingDeletion = app.appID }
                            }
                        }
                    }
                    .monospacedDigit()
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

    private func changeText(_ now: Double?, _ before: Double?) -> Text {
        guard let now, let before else { return Text("–").foregroundStyle(.secondary) }
        let change = now - before
        return Text(Format.signed(change)).foregroundStyle(abs(change) < 0.5 ? .secondary : change > 0 ? Color.green : Color.red)
    }
}
