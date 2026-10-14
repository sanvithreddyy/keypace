import Charts
import SwiftUI
import KeypaceCore

struct MainWindow: View {
    let tracker: LiveTracker

    enum Page: String, Hashable, CaseIterable {
        case overview = "Overview", apps = "Apps", general = "General", tracking = "Tracking"
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
        case .general: GeneralSettingsPage(tracker: tracker)
        case .tracking: TrackingSettingsPage(tracker: tracker)
        }
    }
}

/// Page title on the left, period picker on the right.
struct PageHeader: View {
    let title: String
    @Binding var period: Period

    var body: some View {
        HStack {
            Text(title).font(.title2.weight(.semibold))
            Spacer()
            Picker("Period", selection: $period) {
                ForEach(Period.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
    }
}

// MARK: Overview

struct OverviewPage: View {
    let tracker: LiveTracker
    @AppStorage("overviewPeriod") private var period = Period.month

    var body: some View {
        let data = { _ = tracker.revision; return PeriodData(period, tracker: tracker) }()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Overview", period: $period).padding(.bottom, 16)
                if data.sessions.isEmpty {
                    Text(period == .today ? "No typing recorded today." : "No typing recorded in this period.")
                        .foregroundStyle(.secondary)
                } else {
                    StatRow(data: data, streaks: streaks)
                    SectionHeading(title: period == .today ? "Speed by hour" : "Speed by day",
                                   detail: data.previousSessions == nil ? nil : "This period in full ink, the previous one in gray")
                    SpeedChart(data: data)
                    SectionHeading(title: "When you type fastest", detail: "Average wpm by weekday and hour")
                    WeekHourHeatmap(sessions: data.sessions)
                    SectionHeading(title: "Apps", detail: "Typing time · wpm")
                    AppBars(apps: Array(Statistics.byApp(data.sessions).prefix(5)))
                }
            }
            .padding(24)
        }
    }

    private var streaks: (current: Int, longest: Int) {
        _ = tracker.revision
        return Statistics.streaks(tracker.allSessions(), today: .now, calendar: .current)
    }
}

/// Five stat blocks divided by hairlines, each with its change against the previous period.
/// Green and red mean better and worse, so only speed and corrections are colored.
private struct StatRow: View {
    let data: PeriodData
    let streaks: (current: Int, longest: Int)

    private enum Tone { case better, worse, neutral }

    var body: some View {
        let now = data.totals
        let before = data.previousTotals
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 0) {
                block("Speed", "\(Format.wpm(now.wpm)) wpm", change: difference(now.wpm, before?.wpm).map {
                    (Format.signed($0), tone($0, threshold: 0.5, higherIsBetter: true))
                })
                Divider()
                block("Corrections", Format.percent(now.correctionRate), change: difference(now.correctionRate, before?.correctionRate).map {
                    (Format.signed($0 * 100, decimals: 1) + " pts", tone($0, threshold: 0.0005, higherIsBetter: false))
                })
                Divider()
                block("Typing time", Format.duration(now.duration), change: before.map {
                    (Format.signed((now.duration - $0.duration) / 60) + " min", .neutral)
                })
                Divider()
                block("Keystrokes", Format.count(now.keystrokes), change: before.flatMap { before in
                    before.keystrokes > 0
                        ? (Format.signed(Double(now.keystrokes - before.keystrokes) / Double(before.keystrokes) * 100) + "%", .neutral)
                        : nil
                })
                Divider()
                block("Streak", "\(streaks.current) \(streaks.current == 1 ? "day" : "days")", change: ("best \(streaks.longest)", .neutral))
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider()
        }
        .monospacedDigit()
    }

    private func difference(_ now: Double?, _ before: Double?) -> Double? {
        guard let now, let before else { return nil }
        return now - before
    }

    private func tone(_ change: Double, threshold: Double, higherIsBetter: Bool) -> Tone {
        guard abs(change) >= threshold else { return .neutral }
        return (change > 0) == higherIsBetter ? .better : .worse
    }

    private func block(_ label: String, _ value: String, change: (text: String, tone: Tone)?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold))
            if let change {
                Text(change.text).font(.caption).foregroundStyle(
                    change.tone == .better ? Color.green : change.tone == .worse ? Color.red : Color.secondary
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}

/// This period's speed in full ink with the previous period overlaid in gray, aligned by position.
private struct SpeedChart: View {
    let data: PeriodData

    private struct Point: Identifiable {
        var series: String
        var index: Int
        var wpm: Double
        var id: String { "\(series)\(index)" }
    }

    var body: some View {
        let current = points(data.sessions, start: data.interval?.start, series: "This period")
        let previous = data.previousSessions.map { points($0, start: data.period.previous(now: .now, calendar: .current)?.start, series: "Previous") } ?? []
        Chart(previous + current) { point in
            LineMark(x: .value("Position", point.index), y: .value("WPM", point.wpm), series: .value("Series", point.series))
                .interpolationMethod(.monotone)
                .foregroundStyle(point.series == "Previous" ? Color.secondary.opacity(0.5) : Color.primary)
                .lineStyle(StrokeStyle(lineWidth: point.series == "Previous" ? 1.2 : 1.6))
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, max(slots - 1, 0)]) { value in
                AxisValueLabel { Text(label(for: value.as(Int.self) ?? 0)) }
            }
        }
        .chartXScale(domain: 0...max(slots - 1, 1))
        .frame(height: 150)
    }

    private var isHourly: Bool { data.period == .today }

    private var slots: Int {
        guard let interval = data.interval else { return 1 }
        return isHourly ? 24 : Calendar.current.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1
    }

    private func points(_ sessions: [SessionRecord], start: Date?, series: String) -> [Point] {
        guard let start else { return [] }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { session in
            isHourly ? calendar.component(.hour, from: session.start)
                : calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: session.start)).day ?? 0
        }
        return grouped.compactMap { index, sessions in Statistics.totals(sessions).wpm.map { Point(series: series, index: index, wpm: $0) } }
            .sorted { $0.index < $1.index }
    }

    private func label(for index: Int) -> String {
        guard let start = data.interval?.start else { return "" }
        if isHourly { return Calendar.current.date(bySettingHour: index, minute: 0, second: 0, of: start)!.formatted(.dateTime.hour()) }
        return Calendar.current.date(byAdding: .day, value: index, to: start)!.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Weekday rows by hour columns. Shade is average wpm; empty cells are outlines; the fastest cell is solid with its value.
private struct WeekHourHeatmap: View {
    let sessions: [SessionRecord]

    var body: some View {
        let calendar = Calendar.current
        let cells = Statistics.byWeekdayAndHour(sessions, calendar: calendar).compactMapValues(\.wpm)
        let fastest = cells.max { $0.value < $1.value }
        let slowest = cells.values.min() ?? 0
        let span = max((fastest?.value ?? 0) - slowest, 1)
        let hours = hourRange(cells)
        // Monday first.
        let weekdays = (0..<7).map { ($0 + 1) % 7 + 1 }

        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                ForEach(hours, id: \.self) { hour in
                    Text(hour % 3 == 0 ? hourLabel(hour) : "")
                        .font(.caption2)
                        .fontWeight(hour == fastest?.key.hour ? .semibold : .regular)
                        .foregroundStyle(hour == fastest?.key.hour ? .primary : .secondary)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(weekdays, id: \.self) { weekday in
                GridRow {
                    Text(calendar.shortWeekdaySymbols[weekday - 1])
                        .font(.caption)
                        .fontWeight(weekday == fastest?.key.weekday ? .semibold : .regular)
                        .foregroundStyle(weekday == fastest?.key.weekday ? .primary : .secondary)
                        .gridColumnAlignment(.leading)
                    ForEach(hours, id: \.self) { hour in
                        let key = Statistics.WeekdayHour(weekday: weekday, hour: hour)
                        cell(wpm: cells[key], isFastest: key == fastest?.key, shade: cells[key].map { ($0 - slowest) / span } ?? 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(wpm: Double?, isFastest: Bool, shade: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        if let wpm {
            shape.fill(isFastest ? Color.primary : Color.primary.opacity(0.12 + shade * 0.5))
                .overlay {
                    if isFastest { Text(Format.wpm(wpm)).font(.caption2.weight(.semibold)).foregroundStyle(Color(nsColor: .windowBackgroundColor)) }
                }
                .frame(height: 20)
        } else {
            shape.strokeBorder(.quaternary, lineWidth: 1).frame(height: 20)
        }
    }

    /// Hours that have typing, widened to at least 8 AM–8 PM.
    private func hourRange(_ cells: [Statistics.WeekdayHour: Double]) -> [Int] {
        let typed = cells.keys.map(\.hour)
        return Array(min(typed.min() ?? 8, 8)...max(typed.max() ?? 20, 20))
    }

    private func hourLabel(_ hour: Int) -> String {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!.formatted(.dateTime.hour())
    }
}

// MARK: Apps

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
