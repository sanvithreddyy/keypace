import SwiftUI
import KeypaceCore

/// Personal bests across all history.
struct RecordsPage: View {
    let tracker: LiveTracker

    var body: some View {
        let _ = tracker.revision
        let sessions = tracker.allSessions()
        let records = Records(sessions, calendar: .current)
        let streaks = Statistics.streaks(sessions, today: .now, calendar: .current)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Records").font(.title2.weight(.semibold)).padding(.bottom, 16)
                if sessions.isEmpty {
                    Text("No typing recorded yet.").foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        Divider()
                        HStack(alignment: .top, spacing: 0) {
                            block("Fastest session", records.fastestSession.map { "\(Format.wpm($0.totals.wpm)) wpm" }, records.fastestSession)
                            Divider()
                            block("Cleanest session", records.cleanestSession.map { $0.backspaces == 0 ? "No corrections" : "\(Format.percent($0.totals.correctionRate)) corrected" }, records.cleanestSession)
                            Divider()
                            block("Longest session", records.longestSession.map { Format.duration($0.totals.duration) }, records.longestSession)
                            Divider()
                            StatBlock(label: "Streak", value: "\(streaks.current) \(streaks.current == 1 ? "day" : "days")", change: "best \(streaks.longest)")
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Divider()
                    }

                    SectionHeading(title: "Best days")
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        if let day = records.fastestDay {
                            dayRow("Fastest day", day: day.day, value: "\(Format.wpm(day.totals.wpm)) wpm", detail: Format.duration(day.totals.duration))
                        }
                        if let day = records.busiestDay {
                            dayRow("Most typing", day: day.day, value: Format.duration(day.totals.duration), detail: "\(Format.wpm(day.totals.wpm)) wpm")
                        }
                    }
                    .font(.callout)
                    .monospacedDigit()

                    if !records.fastestByApp.isEmpty {
                        SectionHeading(title: "Fastest by app")
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            ForEach(records.fastestByApp, id: \.appID) { session in
                                GridRow {
                                    Text(AppInfo.name(session.appID)).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(Format.wpm(session.totals.wpm)) wpm").gridColumnAlignment(.trailing)
                                    Text(Format.day(session.start)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                }
                            }
                        }
                        .font(.callout)
                        .monospacedDigit()
                    }

                    Text("Speed records count sessions of at least \(Int(Records.minimumDuration)) seconds and \(Records.minimumCharacters) characters; a fastest day needs \(Int(Records.minimumDayDuration / 60)) minutes of typing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                }
            }
            .padding(24)
        }
    }

    private func block(_ label: String, _ value: String?, _ session: SessionRecord?) -> some View {
        StatBlock(label: label, value: value ?? "–", change: session.map { "\(AppInfo.name($0.appID)) · \(Format.day($0.start))" })
    }

    private func dayRow(_ label: String, day: Date, value: String, detail: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(day.formatted(date: .complete, time: .omitted)).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).gridColumnAlignment(.trailing)
            Text(detail).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
        }
    }
}
