import SwiftUI
import KeypaceCore

struct KeysPage: View {
    let tracker: LiveTracker
    @AppStorage("keysPeriod") private var period = Period.month
    @State private var mode = KeyboardHeatmap.Mode.usage
    @State private var keyboardID: String?
    @State private var inputSourceID: String?

    var body: some View {
        let _ = tracker.revision
        let interval = period.interval(now: .now, calendar: .current, firstSession: tracker.firstSessionStart())
        let filter = StatFilter(keyboardID: keyboardID, inputSourceID: inputSourceID)
        let keys = interval.map { tracker.keyStats(in: $0, filter: filter) } ?? [:]
        let pairs = interval.map { tracker.pairStats(in: $0, filter: filter) } ?? [:]
        let layout = inputSourceID.flatMap { id in tracker.inputSourceRecords().first { $0.id == id } }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Keys", period: $period).padding(.bottom, 12)
                DeviceFilters(tracker: tracker, keyboardID: $keyboardID, inputSourceID: $inputSourceID)
                if keys.isEmpty {
                    Text("No key presses recorded in this period.").foregroundStyle(.secondary).padding(.top, 16)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Keyboard").font(.headline)
                        Spacer()
                        Picker("Show", selection: $mode) {
                            Text("Usage").tag(KeyboardHeatmap.Mode.usage)
                            Text("Corrections").tag(KeyboardHeatmap.Mode.corrections)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 10)
                    KeyboardHeatmap(keys: keys, mode: mode) { KeyLabels.label($0, using: tracker.inputSources, layout: layout) }

                    HStack(alignment: .top, spacing: 32) {
                        CorrectedKeys(keys: keys, sources: tracker.inputSources, layout: layout)
                        PairList(title: "Slowest pairs", pairs: pairs, slowest: true, sources: tracker.inputSources, layout: layout)
                        PairList(title: "Fastest pairs", pairs: pairs, slowest: false, sources: tracker.inputSources, layout: layout)
                    }

                    SectionHeading(title: "Fingers", detail: "Assumes touch-typing finger assignments")
                    FingerSection(stats: FingerStats(keys: keys, pairs: pairs))
                }
            }
            .padding(24)
        }
    }
}

/// Menus that narrow statistics to one keyboard or layout.
struct DeviceFilters: View {
    let tracker: LiveTracker
    @Binding var keyboardID: String?
    @Binding var inputSourceID: String?

    var body: some View {
        let keyboards = tracker.keyboards()
        let sources = tracker.inputSourceRecords()
        if keyboards.count > 1 || sources.count > 1 {
            HStack(spacing: 12) {
                if keyboards.count > 1 {
                    Picker("Keyboard", selection: $keyboardID) {
                        Text("All keyboards").tag(String?.none)
                        ForEach(keyboards, id: \.id) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    .fixedSize()
                }
                if sources.count > 1 {
                    Picker("Layout", selection: $inputSourceID) {
                        Text("All layouts").tag(String?.none)
                        ForEach(sources, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .fixedSize()
                }
            }
            .labelsHidden()
        }
    }
}

/// The Mac keyboard drawn from its real geometry. Usage shades keys by presses; corrections by the share
/// of their characters deleted. Keys with too few presses to judge are outlines; the top key is solid ink.
struct KeyboardHeatmap: View {
    enum Mode { case usage, corrections }

    let keys: [UInt16: KeyCount]
    let mode: Mode
    let label: (UInt16) -> String

    /// Presses a key needs before its correction rate is shown.
    static let minimumPresses = KeyRankings.minimumPresses

    var body: some View {
        let values = self.values
        let top = values.max { $0.value < $1.value }
        let highest = max(top?.value ?? 0, .leastNonzeroMagnitude)

        GeometryReader { proxy in
            let unit = proxy.size.width / 15
            ZStack(alignment: .topLeading) {
                ForEach(KeyboardGeometry.keys, id: \.keyCode) { key in
                    let value = values[key.keyCode]
                    let isTop = key.keyCode == top?.key
                    cap(label: label(key.keyCode), value: value.map { $0 / highest }, isTop: isTop, caption: isTop ? caption(top!.value) : nil)
                        .frame(width: key.width * unit - 4, height: unit - 4)
                        .offset(x: key.x * unit + 2, y: Double(key.row) * unit + 2)
                }
            }
        }
        .aspectRatio(3, contentMode: .fit)
    }

    private var values: [UInt16: Double] {
        switch mode {
        case .usage:
            keys.filter { $0.value.presses > 0 }.mapValues { Double($0.presses) }
        case .corrections:
            keys.filter { $0.value.presses >= Self.minimumPresses && $0.key != 51 }.compactMapValues(\.correctionRate)
        }
    }

    private func caption(_ value: Double) -> String {
        switch mode {
        case .usage: Format.count(Int(value))
        case .corrections: Format.percent(value)
        }
    }

    @ViewBuilder
    private func cap(label: String, value: Double?, isTop: Bool, caption: String?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        ZStack {
            if let value {
                shape.fill(isTop ? Color.primary : Color.primary.opacity(0.06 + 0.5 * pow(value, 0.6)))
            } else {
                shape.strokeBorder(.quaternary, lineWidth: 1)
            }
            VStack(spacing: 1) {
                Text(label).font(.system(size: 11, weight: isTop ? .semibold : .regular))
                if let caption { Text(caption).font(.system(size: 9, weight: .semibold)).monospacedDigit() }
            }
            .foregroundStyle(isTop ? Color(nsColor: .windowBackgroundColor) : value == nil ? Color.secondary : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}

private struct CorrectedKeys: View {
    let keys: [UInt16: KeyCount]
    let sources: InputSources?
    let layout: InputSourceRecord?

    var body: some View {
        let ranked = KeyRankings.corrected(keys, sources: sources, layout: layout, limit: 6)
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Most corrected keys")
            if ranked.isEmpty {
                Text("Not enough presses yet.").foregroundStyle(.secondary).font(.callout)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(Array(ranked), id: \.key) { code, count in
                        GridRow {
                            Text(KeyLabels.label(code, using: sources, layout: layout))
                            Text(Format.percent(count.correctionRate)).gridColumnAlignment(.trailing)
                            Text("of \(Format.count(count.presses))").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        }
                    }
                }
                .font(.callout)
                .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PairList: View {
    let title: String
    let pairs: [KeyPair: PairTiming]
    let slowest: Bool
    let sources: InputSources?
    let layout: InputSourceRecord?

    var body: some View {
        let ranked = KeyRankings.pairs(pairs, slowest: slowest, sources: sources, layout: layout, limit: 6)
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: title)
            if ranked.isEmpty {
                Text("Not enough pairs yet.").foregroundStyle(.secondary).font(.callout)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(Array(ranked), id: \.pair) { pair, timing in
                        GridRow {
                            Text(KeyLabels.pair((pair.from, pair.to), using: sources, layout: layout))
                            Text("\(Int((timing.averageMilliseconds ?? 0).rounded())) ms").gridColumnAlignment(.trailing)
                        }
                    }
                }
                .font(.callout)
                .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FingerSection: View {
    let stats: FingerStats

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    StatBlock(label: "Hands", value: "\(Format.percent(stats.leftShare, decimals: 0)) left · \(Format.percent(stats.rightShare, decimals: 0)) right")
                    Divider()
                    StatBlock(label: "Home row", value: Format.percent(stats.homeRowShare, decimals: 0))
                    Divider()
                    StatBlock(label: "Hand alternation", value: Format.percent(stats.handAlternation, decimals: 0))
                    Divider()
                    StatBlock(label: "Same-finger pairs", value: Format.percent(stats.sameFinger))
                    Divider()
                    StatBlock(label: "Finger travel", value: Format.distance(stats.travelMetres))
                }
                .fixedSize(horizontal: false, vertical: true)
                Divider()
            }
            let top = stats.load.values.max() ?? 1
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(KeyboardGeometry.Finger.allCases, id: \.self) { finger in
                    let share = stats.load[finger] ?? 0
                    GridRow {
                        Text(finger.name).foregroundStyle(.secondary)
                        Bar(fraction: share / top, emphasized: share == top)
                        Text(Format.percent(share, decimals: 0)).gridColumnAlignment(.trailing)
                    }
                }
            }
            .font(.callout)
            .monospacedDigit()
        }
    }
}
