import Charts
import SwiftUI
import KeypaceCore

/// The menu-bar dropdown: the period's speed against the one before, its shape, and where you typed.
struct Dropdown: View {
    let tracker: LiveTracker
    @AppStorage("dropdownPeriod") private var period = Period.today
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tracker.status == .needsPermission {
                PermissionPrompt(tracker: tracker)
            } else {
                let data = { _ = tracker.revision; return PeriodData(period, tracker: tracker) }()
                Header(data: data, live: liveWPM)
                SpeedShape(data: data).padding(.top, 12)
                Grid(alignment: .leading, verticalSpacing: 6) {
                    ValueRow("Corrections", Format.percent(data.totals.correctionRate))
                    ValueRow("Typing time", Format.duration(data.totals.duration))
                }
                .padding(.top, 12)
                TopApps(sessions: data.sessions).padding(.top, 16)
            }
            if let error = tracker.storageError {
                Text("Not saving history: \(error)").font(.caption).foregroundStyle(.red).padding(.top, 12)
            }
            Footer(openMain: openMain).padding(.top, 16)
        }
        .padding(16)
        .frame(width: 340)
    }

    private var liveWPM: Double? {
        guard let current = tracker.current, current.duration >= 3 else { return nil }
        return current.totals.wpm
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }

    private struct Header: View {
        let data: PeriodData
        let live: Double?
        @AppStorage("dropdownPeriod") private var period = Period.today

        var body: some View {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Format.wpm(data.totals.wpm)).font(.system(size: 34, weight: .semibold))
                        Text("wpm").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                    }
                    subtitle.font(.caption).foregroundStyle(.secondary)
                }
                .monospacedDigit()
                Spacer()
                Picker("Period", selection: $period) {
                    ForEach([Period.today, .week, .month], id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }

        private var subtitle: Text {
            var parts: [Text] = []
            if let wpm = data.totals.wpm, let previous = data.previousTotals?.wpm {
                let change = wpm - previous
                parts.append(Text(Format.signed(change)).foregroundStyle(change >= 0.5 ? .green : change <= -0.5 ? .red : .secondary)
                    + Text(" \(data.period.comparison)"))
            }
            if let live { parts.append(Text("now \(Format.wpm(live))")) }
            guard let first = parts.first else { return Text(data.sessions.isEmpty ? "No typing yet" : " ") }
            return parts.dropFirst().reduce(first) { $0 + Text(" · ") + $1 }
        }
    }

    /// Speed by hour for today, by day for longer periods.
    private struct SpeedShape: View {
        let data: PeriodData

        var body: some View {
            let points = self.points
            if points.count >= 2 {
                Chart(points, id: \.date) { point in
                    LineMark(x: .value("Time", point.date), y: .value("WPM", point.wpm))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .foregroundStyle(.primary)
                    if point.date == points.last?.date {
                        PointMark(x: .value("Time", point.date), y: .value("WPM", point.wpm))
                            .symbolSize(20)
                            .foregroundStyle(.primary)
                    }
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: [points.first!.date, points.last!.date]) { _ in
                        AxisValueLabel(format: data.period == .today ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 64)
            }
        }

        private var points: [(date: Date, wpm: Double)] {
            let groups = data.period == .today
                ? Dictionary(grouping: data.sessions) { Calendar.current.dateInterval(of: .hour, for: $0.start)!.start }
                : Dictionary(grouping: data.sessions) { Calendar.current.startOfDay(for: $0.start) }
            return groups.compactMap { date, sessions in Statistics.totals(sessions).wpm.map { (date, $0) } }
                .sorted { $0.date < $1.date }
        }
    }

    private struct TopApps: View {
        let sessions: [SessionRecord]

        var body: some View {
            let apps = Array(Statistics.byApp(sessions).prefix(3))
            if !apps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Where you typed").font(.caption).foregroundStyle(.secondary)
                    AppBars(apps: apps, nameWidth: nil)
                }
            }
        }
    }

    private struct Footer: View {
        let openMain: () -> Void

        var body: some View {
            HStack(spacing: 10) {
                Button(action: openMain) { Label("Open Keypace", systemImage: "macwindow") }
                Button { NSApplication.shared.terminate(nil) } label: { Label("Quit", systemImage: "power") }
            }
            .buttonStyle(FooterButtonStyle())
        }
    }
}

/// Equal-width bordered buttons, like the footer of macOS system-stats menus.
private struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(.white.opacity(configuration.isPressed ? 0.1 : 0.04), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1)))
            .contentShape(.rect(cornerRadius: 8))
    }
}

private struct PermissionPrompt: View {
    let tracker: LiveTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input Monitoring is off").font(.headline)
            Text("Keypace counts key presses to measure speed. It never stores what you type.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Allow…") { tracker.requestPermission() }
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
            }
        }
    }
}

/// Label on the left, value right-aligned, for use inside a `Grid`.
struct ValueRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        GridRow {
            Text(label)
            Text(value).monospacedDigit().foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.callout)
    }
}

/// App name over a thin bar sized by typing time, with time and wpm in right-hand columns.
struct AppBars: View {
    let apps: [(appID: String, totals: TypingTotals)]
    var nameWidth: CGFloat?

    var body: some View {
        let longest = apps.map(\.totals.duration).max() ?? 1
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(Array(apps.enumerated()), id: \.element.appID) { index, app in
                GridRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppInfo.name(app.appID)).lineLimit(1)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule().fill(index == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                    .frame(width: proxy.size.width * app.totals.duration / longest)
                            }
                        }
                        .frame(height: 2)
                    }
                    Text(Format.duration(app.totals.duration)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(Format.wpm(app.totals.wpm)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.callout)
        .monospacedDigit()
    }
}
