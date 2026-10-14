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
