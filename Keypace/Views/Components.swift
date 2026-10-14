import SwiftUI
import KeypaceCore

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

/// One labelled value in a row of stat blocks divided by hairlines.
struct StatBlock: View {
    let label: String
    let value: String
    var change: String?
    var changeColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            if let change { Text(change).font(.caption).foregroundStyle(changeColor) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .monospacedDigit()
    }
}

/// A 2-point bar; the emphasized one is full ink, the rest gray.
struct Bar: View {
    let fraction: Double
    var emphasized = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(emphasized ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 2)
    }
}

/// One row of a breakdown: an app, keyboard or layout with its totals for the period.
struct BreakdownRow: Identifiable {
    let id: String
    let title: String
    var detail: String?
    var icon: NSImage?
    let totals: TypingTotals
    /// Totals for the previous period, for the speed change.
    var previous: TypingTotals?
}

/// Typing time, share, speed, change and corrections per row, most typing first.
struct BreakdownTable<RowMenu: View>: View {
    let heading: String
    let rows: [BreakdownRow]
    @ViewBuilder var menu: (BreakdownRow) -> RowMenu

    var body: some View {
        let total = max(rows.map(\.totals.duration).reduce(0, +), 1)
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                Text(heading)
                Text("Typing time").gridColumnAlignment(.trailing)
                Text("Share").gridColumnAlignment(.trailing)
                Text("WPM").gridColumnAlignment(.trailing)
                Text("Change").gridColumnAlignment(.trailing)
                Text("Corrections").gridColumnAlignment(.trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
            ForEach(rows) { row in
                GridRow {
                    HStack(spacing: 8) {
                        if let icon = row.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                        Text(row.title).lineLimit(1)
                        if let detail = row.detail { Text(detail).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Format.duration(row.totals.duration))
                    Text(Format.percent(row.totals.duration / total)).foregroundStyle(.secondary)
                    Text(Format.wpm(row.totals.wpm))
                    change(row.totals.wpm, row.previous?.wpm)
                    Text(Format.percent(row.totals.correctionRate)).foregroundStyle(.secondary)
                }
                .contextMenu { menu(row) }
            }
        }
        .monospacedDigit()
    }

    private func change(_ now: Double?, _ before: Double?) -> Text {
        guard let now, let before else { return Text("–").foregroundStyle(.secondary) }
        let change = now - before
        return Text(Format.signed(change)).foregroundStyle(abs(change) < 0.5 ? .secondary : change > 0 ? Color.green : Color.red)
    }
}

/// Lays children out left to right and wraps onto new lines, never wider than the space offered.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
