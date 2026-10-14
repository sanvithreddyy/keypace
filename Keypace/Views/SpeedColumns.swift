import SwiftUI
import KeypaceCore

/// Speed as one column per hour or day, starting from zero. The fastest column is solid ink with its
/// value, the current one is outlined, and the average is a dashed line. Empty slots are short stubs.
struct SpeedColumns: View {
    struct Slot: Identifiable {
        let id: Int
        /// Axis label, or nil for slots without one.
        var label: String?
        var wpm: Double?
        /// Slots still to come, like later hours today, draw nothing.
        var isFuture = false
    }

    let slots: [Slot]
    let average: Double?
    /// Whether the last slot is the hour or day in progress.
    var lastIsCurrent = true

    var body: some View {
        let best = slots.compactMap(\.wpm).max()
        // Only the first fastest slot is highlighted when several tie.
        let bestIndex = slots.firstIndex { $0.wpm != nil && $0.wpm == best }
        let currentIndex = lastIsCurrent ? slots.lastIndex { !$0.isFuture } : nil
        let top = Self.scaleTop(best ?? 60)
        GeometryReader { proxy in
            let plot = CGRect(x: 0, y: 14, width: proxy.size.width - 22, height: proxy.size.height - 30)
            let slotWidth = plot.width / CGFloat(max(slots.count, 1))
            let y = { (wpm: Double) in plot.maxY - plot.height * wpm / top }
            ZStack(alignment: .topLeading) {
                ForEach([top / 3, top * 2 / 3, top], id: \.self) { value in
                    Path { $0.addLines([CGPoint(x: 0, y: y(value)), CGPoint(x: plot.maxX, y: y(value))]) }
                        .stroke(.quaternary, lineWidth: 0.5)
                    Text("\(Int(value))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .position(x: proxy.size.width - 9, y: y(value))
                }
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    let x = CGFloat(index) * slotWidth
                    let width = max(slotWidth - 4, 2)
                    let isBest = index == bestIndex
                    let isCurrent = index == currentIndex
                    if let wpm = slot.wpm {
                        let height = plot.maxY - y(wpm)
                        RoundedRectangle(cornerRadius: min(3, width / 3))
                            .fill(isBest ? Color.primary : Color.primary.opacity(0.28))
                            .overlay {
                                if isCurrent && !isBest {
                                    RoundedRectangle(cornerRadius: min(3, width / 3)).strokeBorder(Color.primary, lineWidth: 1.2)
                                }
                            }
                            .frame(width: width, height: max(height, 2))
                            .position(x: x + slotWidth / 2, y: plot.maxY - height / 2)
                        if isBest || isCurrent {
                            Text(isBest ? Format.wpm(wpm) : "now \(Format.wpm(wpm))")
                                .font(.system(size: 10, weight: isBest ? .semibold : .regular))
                                .foregroundStyle(isBest ? .primary : .secondary)
                                .fixedSize()
                                .position(x: x + slotWidth / 2, y: y(wpm) - 8)
                        }
                    } else if !slot.isFuture {
                        Capsule().fill(.quaternary)
                            .frame(width: width, height: 2)
                            .position(x: x + slotWidth / 2, y: plot.maxY - 1)
                    }
                    if let label = slot.label {
                        Text(label)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .position(x: x + slotWidth / 2, y: proxy.size.height - 6)
                    }
                }
                if let average {
                    Path { $0.addLines([CGPoint(x: 0, y: y(average)), CGPoint(x: plot.maxX, y: y(average))]) }
                        .stroke(Color.primary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .monospacedDigit()
    }

    /// A round top for the scale, a little above the fastest column.
    static func scaleTop(_ best: Double) -> Double {
        let step = 30.0
        return max(step, (best * 1.12 / step).rounded(.up) * step)
    }

    /// Slots for a period: all 24 hours of today, or the period's days.
    static func slots(for data: PeriodData, now: Date = .now, calendar: Calendar = .current) -> [Slot] {
        guard let interval = data.interval else { return [] }
        if data.period == .today {
            let byHour = Statistics.byHourOfDay(data.sessions, calendar: calendar).compactMapValues(\.wpm)
            let currentHour = calendar.component(.hour, from: now)
            return (0..<24).map { hour in
                let label = hour % 6 == 0 ? calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!.formatted(.dateTime.hour()) : nil
                return Slot(id: hour, label: label, wpm: byHour[hour], isFuture: hour > currentHour)
            }
        }
        let byDay = Statistics.byDay(data.sessions, calendar: calendar).compactMapValues(\.wpm)
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        return (0..<days).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: interval.start)!
            // Weekly labels sit a few days in from each edge so they're never clipped.
            let label: String? = days <= 7
                ? day.formatted(.dateTime.weekday(.abbreviated))
                : (offset % 7 == 3 ? day.formatted(.dateTime.month(.abbreviated).day()) : nil)
            return Slot(id: offset, label: label, wpm: byDay[day])
        }
    }
}
