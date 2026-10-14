import Charts
import SwiftUI
import KeypaceCore

struct StatisticsPage: View {
    let tracker: LiveTracker

    enum Metric: String, CaseIterable {
        case wpm = "WPM", cpm = "CPM", kpm = "KPM", corrections = "Corrections"

        func value(_ totals: TypingTotals) -> Double? {
            switch self {
            case .wpm: totals.wpm
            case .cpm: totals.cpm
            case .kpm: totals.kpm
            case .corrections: totals.correctionRate
            }
        }

        func format(_ value: Double?) -> String {
            self == .corrections ? Format.percent(value) : Format.wpm(value)
        }
    }

    @AppStorage("statisticsPeriod") private var period = Period.month
    @State private var isCustom = false
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: .now))!
    @State private var customEnd = Calendar.current.startOfDay(for: .now)
    @State private var metric = Metric.wpm
    @State private var appID: String?
    @State private var keyboardID: String?
    @State private var inputSourceID: String?

    var body: some View {
        let _ = tracker.revision
        let interval = self.interval
        let sessions = interval.map { tracker.sessions(in: $0).filter(matchesFilters) } ?? []
        let totals = Statistics.totals(sessions)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 12)
                filters(apps: interval.map { Statistics.byApp(tracker.sessions(in: $0)).map(\.appID) } ?? [])
                if sessions.isEmpty {
                    Text("No typing recorded in this range.").foregroundStyle(.secondary).padding(.top, 16)
                } else {
                    statRow(totals: totals, interval: interval).padding(.top, 16)
                    HStack(alignment: .firstTextBaseline) {
                        Text(isHourly ? "By hour" : "By day").font(.headline)
                        Spacer()
                        Picker("Metric", selection: $metric) {
                            ForEach(Metric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 10)
                    MetricChart(sessions: sessions, metric: metric, hourly: isHourly)
                    if !isHourly, let interval {
                        SectionHeading(title: "Daily speed", detail: "Each day shaded by its average wpm")
                        CalendarHeatmap(sessions: sessions, interval: interval)
                    }
                    SectionHeading(title: "By weekday", detail: "Typing time · wpm, fastest in bold")
                    WeekdayBars(sessions: sessions)
                    if !isHourly {
                        SectionHeading(title: "By month", detail: "Typing time")
                        MonthBars(sessions: sessions)
                    }
                }
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack {
            Text("Statistics").font(.title2.weight(.semibold))
            Spacer()
            Picker("Range", selection: Binding(
                get: { isCustom ? nil : Optional(period) },
                set: { if let value = $0 { period = value; isCustom = false } else { isCustom = true } }
            )) {
                ForEach(Period.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                Text("Custom").tag(Period?.none)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    @ViewBuilder
    private func filters(apps: [String]) -> some View {
        HStack(spacing: 12) {
            if isCustom {
                DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
            }
            // Stays visible while an app is selected, even if the new range has only one app.
            if apps.count > 1 || appID != nil {
                Picker("App", selection: $appID) {
                    Text("All apps").tag(String?.none)
                    ForEach(apps, id: \.self) { Text(AppInfo.name($0)).tag(Optional($0)) }
                }
                .labelsHidden()
            }
            DeviceFilters(tracker: tracker, keyboardID: $keyboardID, inputSourceID: $inputSourceID)
        }
        .fixedSize()
    }

    private func statRow(totals: TypingTotals, interval: DateInterval?) -> some View {
        // Software-sent keystrokes have no keyboard or layout, so they can't be narrowed to one.
        let byDevice = keyboardID != nil || inputSourceID != nil
        let synthetic = byDevice ? nil : interval.map { tracker.syntheticCount(in: $0, appID: appID) }
        let filteredShare = synthetic.map { $0 + totals.keystrokes > 0 ? Double($0) / Double($0 + totals.keystrokes) : 0 }
        return VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 0) {
                StatBlock(label: "Net WPM", value: Format.wpm(totals.wpm))
                    .help("Average speed after corrections, weighted by typing time.")
                Divider()
                StatBlock(label: "CPM", value: Format.wpm(totals.cpm))
                Divider()
                StatBlock(label: "KPM", value: Format.wpm(totals.kpm))
                Divider()
                StatBlock(label: "Corrections", value: Format.percent(totals.correctionRate))
                Divider()
                StatBlock(label: "Filtered input", value: synthetic.map(Format.count) ?? "–",
                          change: (synthetic ?? 0) > 0 ? "\(Format.percent(filteredShare)) of key presses" : nil)
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider()
        }
    }

    private var isHourly: Bool { !isCustom && period == .today }

    private var interval: DateInterval? {
        let calendar = Calendar.current
        if isCustom {
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd))!
            return DateInterval(start: calendar.startOfDay(for: customStart), end: end)
        }
        return period.interval(now: .now, calendar: calendar, firstSession: tracker.firstSessionStart())
    }

    private func matchesFilters(_ session: SessionRecord) -> Bool {
        (appID == nil || session.appID == appID)
            && (keyboardID == nil || session.keyboardID == keyboardID)
            && (inputSourceID == nil || session.inputSourceID == inputSourceID)
    }
}

/// The chosen metric per day (or per hour for today), in ink.
private struct MetricChart: View {
    let sessions: [SessionRecord]
    let metric: StatisticsPage.Metric
    let hourly: Bool

    var body: some View {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) {
            hourly ? calendar.dateInterval(of: .hour, for: $0.start)!.start : calendar.startOfDay(for: $0.start)
        }
        let points = grouped.compactMap { date, sessions in metric.value(Statistics.totals(sessions)).map { (date: date, value: $0) } }
            .sorted { $0.date < $1.date }
        Chart(points, id: \.date) { point in
            LineMark(x: .value("Date", point.date, unit: hourly ? .hour : .day), y: .value(metric.rawValue, point.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.primary)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
            PointMark(x: .value("Date", point.date, unit: hourly ? .hour : .day), y: .value(metric.rawValue, point.value))
                .symbolSize(12)
                .foregroundStyle(Color.primary)
        }
        .chartYScale(domain: .automatic(includesZero: metric == .corrections))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                AxisValueLabel { Text(metric.format(value.as(Double.self))) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel(format: hourly ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 170)
    }
}

/// Weeks as columns, Monday to Sunday as rows. Empty days are outlines; the fastest day is solid with its value.
private struct CalendarHeatmap: View {
    let sessions: [SessionRecord]
    let interval: DateInterval

    var body: some View {
        var calendar = Calendar.current
        let _ = calendar.firstWeekday = 2
        let days = Statistics.byDay(sessions, calendar: calendar).compactMapValues(\.wpm)
        let fastest = days.max { $0.value < $1.value }
        let slowest = days.values.min() ?? 0
        let span = max((fastest?.value ?? 0) - slowest, 1)
        // At most 26 weeks, ending with the interval.
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        let firstShown = max(interval.start, calendar.date(byAdding: .weekOfYear, value: -25, to: lastDay)!)
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstShown)!.start
        let weeks = (calendar.dateComponents([.weekOfYear], from: firstWeek, to: lastDay).weekOfYear ?? 0) + 1

        HStack(alignment: .top, spacing: 3) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<7, id: \.self) { row in
                    Text(row % 2 == 0 ? calendar.shortWeekdaySymbols[(row + 1) % 7] : "")
                        .font(.caption2).foregroundStyle(.secondary).frame(height: Self.cell)
                }
            }
            ForEach(0..<weeks, id: \.self) { week in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { row in
                        let day = calendar.date(byAdding: .day, value: week * 7 + row, to: firstWeek)!
                        cell(day: day, wpm: days[day], isFastest: day == fastest?.key, inRange: day >= firstShown && day <= lastDay,
                             shade: days[day].map { ($0 - slowest) / span } ?? 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cell(day: Date, wpm: Double?, isFastest: Bool, inRange: Bool, shade: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        Group {
            if !inRange {
                Color.clear
            } else if let wpm {
                shape.fill(isFastest ? Color.primary : Color.primary.opacity(0.12 + shade * 0.5))
                    .overlay {
                        if isFastest {
                            Text(Format.wpm(wpm)).font(.system(size: 9, weight: .bold)).foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        }
                    }
                    .help("\(day.formatted(date: .abbreviated, time: .omitted)): \(Format.wpm(wpm)) wpm")
            } else {
                shape.strokeBorder(.quaternary, lineWidth: 1)
            }
        }
        .frame(width: Self.cell, height: Self.cell)
    }

    private static let cell: CGFloat = 20
}

private struct WeekdayBars: View {
    let sessions: [SessionRecord]

    var body: some View {
        let calendar = Calendar.current
        let byWeekday = Statistics.byWeekday(sessions, calendar: calendar)
        let longest = byWeekday.values.map(\.duration).max() ?? 1
        let busiest = byWeekday.max { $0.value.duration < $1.value.duration }?.key
        let fastest = byWeekday.max { ($0.value.wpm ?? 0) < ($1.value.wpm ?? 0) }?.key
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                let totals = byWeekday[weekday] ?? TypingTotals()
                GridRow {
                    Text(calendar.weekdaySymbols[weekday - 1]).foregroundStyle(.secondary)
                    Bar(fraction: totals.duration / longest, emphasized: weekday == busiest)
                    Text(Format.duration(totals.duration)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(Format.wpm(totals.wpm)).fontWeight(weekday == fastest ? .semibold : .regular).gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.callout)
        .monospacedDigit()
    }
}

private struct MonthBars: View {
    let sessions: [SessionRecord]

    var body: some View {
        let calendar = Calendar.current
        let months = Dictionary(grouping: sessions) { calendar.dateInterval(of: .month, for: $0.start)!.start }
            .mapValues { Statistics.totals($0).duration }
            .sorted { $0.key < $1.key }
        let longest = months.map(\.value).max() ?? 1
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(months, id: \.key) { month, duration in
                GridRow {
                    Text(month.formatted(.dateTime.month(.wide).year())).foregroundStyle(.secondary)
                    Bar(fraction: duration / longest, emphasized: duration == longest)
                    Text(Format.duration(duration)).gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.callout)
        .monospacedDigit()
    }
}
