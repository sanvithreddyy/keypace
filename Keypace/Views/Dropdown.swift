import SwiftUI
import KeypaceCore

/// The menu-bar dropdown: icon tabs for speed, keys, apps and records, over a shared period.
struct Dropdown: View {
    /// The panel's width; content must fit inside it.
    static let width: CGFloat = 340

    let tracker: LiveTracker
    @AppStorage("dropdownTab") private var tab = Tab.speed
    @AppStorage("dropdownPeriod") private var period = Period.today
    @Environment(\.openWindow) private var openWindow

    enum Tab: String, CaseIterable {
        case speed, keys, apps, records

        var symbol: String {
            switch self {
            case .speed: "gauge.with.needle"
            case .keys: "keyboard"
            case .apps: "square.grid.2x2"
            case .records: "trophy"
            }
        }

        var title: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tracker.status == .needsPermission {
                PermissionPrompt(tracker: tracker)
            } else {
                TabBar(selection: $tab)
                let data = { _ = tracker.revision; return PeriodData(period, tracker: tracker) }()
                switch tab {
                case .speed: SpeedTab(tracker: tracker, data: data, period: $period)
                case .keys: KeysTab(tracker: tracker, data: data, period: $period)
                case .apps: AppsTab(data: data, period: $period)
                case .records: RecordsTab(tracker: tracker)
                }
            }
            if let error = tracker.storageError {
                Text("Not saving history: \(error)").font(.caption).foregroundStyle(.red).padding(.top, 12)
            }
            Footer(openMain: openMain).padding(.top, 12)
        }
        .padding(14)
        .monospacedDigit()
        .background(Theme.panelTint)
        .environment(\.colorScheme, .dark)
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

// MARK: Chrome

private struct TabBar: View {
    @Binding var selection: Dropdown.Tab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Dropdown.Tab.allCases, id: \.self) { tab in
                Button { selection = tab } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                        .background(selection == tab ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 8))
                        .contentShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(4)
        .background(Theme.surface, in: .rect(cornerRadius: 11))
    }
}

/// Small uppercase section title with an optional control or note on the right.
private struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 2)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

private struct PeriodPicker: View {
    @Binding var period: Period

    var body: some View {
        Picker("Period", selection: $period) {
            Text("Today").tag(Period.today)
            Text("7 d").tag(Period.week)
            Text("30 d").tag(Period.month)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }
}

/// A rounded surface that groups related content.
private struct Panel<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.05)))
    }
}

private struct Tile: View {
    let title: String
    let value: String
    var unit: String?
    var detail: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 22, weight: .semibold))
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
            if let detail { detail.font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: .rect(cornerRadius: 9))
    }
}

/// Label and value on one line, with optional hairline above.
private struct PanelRow: View {
    let label: String
    let value: String
    var divider = true

    var body: some View {
        VStack(spacing: 0) {
            if divider { Divider().opacity(0.6) }
            HStack {
                Text(label)
                Spacer()
                Text(value).foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.vertical, 6)
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

/// Equal-width bordered buttons.
private struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.05), in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.1)))
            .contentShape(.rect(cornerRadius: 9))
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

// MARK: Tabs

private struct SpeedTab: View {
    let tracker: LiveTracker
    let data: PeriodData
    @Binding var period: Period

    var body: some View {
        let totals = data.totals
        PanelHeader(title: "Net speed") { PeriodPicker(period: $period) }
        Panel {
            HStack(spacing: 6) {
                Tile(title: "\(data.period.title) average", value: Format.wpm(totals.wpm), unit: "wpm", detail: change)
                    .help("Average speed of saved sessions after corrections. Thinking pauses are excluded from new sessions.")
                session
            }
            if totals.duration > 0 {
                HStack {
                    Text(data.period == .today ? "Speed by hour" : "Speed by day").font(.callout)
                    Spacer()
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 2)
                SpeedColumns(slots: SpeedColumns.slots(for: data), average: totals.wpm)
                    .frame(height: 110)
            }
        }
        Panel(spacing: 0) {
            HStack {
                Text("Corrections").font(.callout)
                    .help("Characters deleted again as a share of characters typed. Intentional rewrites count too.")
                Spacer()
                Text(Format.percent(totals.correctionRate)).font(.callout).foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)
            Bar(fraction: (totals.correctionRate ?? 0) / 0.1, emphasized: true).padding(.bottom, 8)
            PanelRow(label: "Typing time", value: Format.duration(totals.duration))
            PanelRow(label: "Keystrokes", value: data.presses.formatted())
            if let interval = data.interval {
                PanelRow(label: "Filtered input", value: tracker.syntheticCount(in: interval).formatted())
            }
        }
        .padding(.top, 8)
    }

    /// Speed over the last few seconds while typing, else the last session.
    @ViewBuilder private var session: some View {
        if let live = tracker.liveWPM {
            Tile(title: "Live", value: Format.wpm(live), unit: "wpm", detail: Text("last 8 seconds"))
                .help("Speed after corrections over the last 8 seconds. Thinking pauses are excluded.")
        } else if let last = data.sessions.last {
            Tile(title: "Last session", value: Format.wpm(last.totals.wpm), unit: "wpm",
                 detail: Text(last.end.formatted(date: .omitted, time: .shortened)))
        } else {
            Tile(title: "This session", value: "–", detail: Text("Not typing"))
        }
    }

    private var change: Text {
        guard let now = data.totals.wpm, let before = data.previousTotals?.wpm else {
            return Text(data.sessions.isEmpty ? "No typing yet" : "Nothing to compare")
        }
        let change = now - before
        if abs(change) < 0.5 { return Text("same as \(data.period.comparisonNoun)") }
        return Text(Format.signed(change)).foregroundStyle(change > 0 ? .green : .red) + Text(" \(data.period.comparison)")
    }

    private var summary: String {
        let best = SpeedColumns.slots(for: data).compactMap(\.wpm).max()
        return "avg \(Format.wpm(data.totals.wpm))" + (best.map { " · best \(Format.wpm($0))" } ?? "")
    }
}

private struct KeysTab: View {
    let tracker: LiveTracker
    let data: PeriodData
    @Binding var period: Period

    var body: some View {
        let keys = data.interval.map { tracker.keyStats(in: $0) } ?? [:]
        let presses = (data.interval.map { tracker.pressCounts(in: $0) } ?? [:]).mapValues { KeyCount(presses: $0) }
        let pairs = data.interval.map { tracker.pairStats(in: $0) } ?? [:]
        let fingers = FingerStats(keys: presses, pairs: pairs)
        PanelHeader(title: "Keys") { PeriodPicker(period: $period) }
        if presses.isEmpty {
            Panel { Text("No key presses yet.").foregroundStyle(.secondary).font(.callout) }
        } else {
            Panel {
                HStack(spacing: 6) {
                    Tile(title: "Left hand", value: Format.percent(fingers.leftShare, decimals: 0),
                         detail: Text("\(Format.percent(fingers.rightShare, decimals: 0)) right hand"))
                    Tile(title: "Home row", value: Format.percent(fingers.homeRowShare, decimals: 0),
                         detail: Text("of letter-area presses"))
                }
                chips("Most corrected keys", correctedKeys(keys))
                chips("Slowest pairs", slowPairs(pairs))
            }
        }
    }

    private func correctedKeys(_ keys: [UInt16: KeyCount]) -> [(String, String)] {
        KeyRankings.corrected(keys, sources: tracker.inputSources, limit: 4)
            .map { (KeyLabels.label($0.key, using: tracker.inputSources), Format.percent($0.count.correctionRate, decimals: 0)) }
    }

    private func slowPairs(_ pairs: [KeyPair: PairTiming]) -> [(String, String)] {
        KeyRankings.pairs(pairs, slowest: true, sources: tracker.inputSources, limit: 3)
            .map {
                (KeyLabels.pair(($0.pair.from, $0.pair.to), using: tracker.inputSources).replacingOccurrences(of: " ", with: "\u{202F}"),
                 "\(Int(($0.timing.averageMilliseconds ?? 0).rounded())) ms")
            }
    }

    private func chips(_ title: String, _ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if items.isEmpty {
                Text("Not enough typing yet").font(.callout).foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(items, id: \.0) { label, value in
                        HStack(spacing: 4) {
                            Text(label).font(.system(.callout, design: .monospaced))
                            Text(value).font(.caption).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.raised, in: .rect(cornerRadius: 6))
                    }
                }
            }
        }
    }
}

private struct AppsTab: View {
    let data: PeriodData
    @Binding var period: Period

    var body: some View {
        let apps = Array(Statistics.byApp(data.sessions).prefix(6))
        let longest = apps.first?.totals.duration ?? 1
        PanelHeader(title: "Apps") { PeriodPicker(period: $period) }
        Panel(spacing: 8) {
            if apps.isEmpty {
                Text("No typing yet.").foregroundStyle(.secondary).font(.callout)
            }
            ForEach(Array(apps.enumerated()), id: \.element.appID) { index, app in
                HStack(spacing: 8) {
                    if let icon = AppInfo.icon(app.appID) { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppInfo.name(app.appID)).font(.callout).lineLimit(1)
                        Bar(fraction: app.totals.duration / longest, emphasized: index == 0)
                    }
                    Text(Format.duration(app.totals.duration)).font(.callout).foregroundStyle(.secondary).frame(width: 54, alignment: .trailing)
                    Text(Format.wpm(app.totals.wpm)).font(.callout).foregroundStyle(.secondary).frame(width: 26, alignment: .trailing)
                }
            }
        }
    }
}

private struct RecordsTab: View {
    let tracker: LiveTracker

    var body: some View {
        let _ = tracker.revision
        let sessions = tracker.allSessions()
        let records = Records(sessions, calendar: .current)
        PanelHeader(title: "Records") { Text("all time").font(.caption).foregroundStyle(.tertiary) }
        Panel(spacing: 0) {
            row("Fastest session", records.fastestSession.map { "\(Format.wpm($0.totals.wpm)) wpm" }, records.fastestSession, first: true)
            row("Cleanest session", records.cleanestSession.map { $0.backspaces == 0 ? "no corrections" : Format.percent($0.totals.correctionRate) }, records.cleanestSession)
            row("Longest session", records.longestSession.map { Format.duration($0.totals.duration) }, records.longestSession)
            if let day = records.fastestDay {
                record("Fastest day", "\(Format.wpm(day.totals.wpm)) wpm", detail: Format.day(day.day))
            }
            if let day = records.busiestDay {
                record("Most typing", Format.duration(day.totals.duration), detail: Format.day(day.day))
            }
        }
    }

    private func row(_ label: String, _ value: String?, _ session: SessionRecord?, first: Bool = false) -> some View {
        record(label, value ?? "–", detail: session.map { "\(AppInfo.name($0.appID)) · \(Format.day($0.start))" }, divider: !first)
    }

    private func record(_ label: String, _ value: String, detail: String?, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            if divider { Divider().opacity(0.6) }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.callout)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                Text(value).font(.callout.weight(.medium))
            }
            .padding(.vertical, 6)
        }
    }
}
