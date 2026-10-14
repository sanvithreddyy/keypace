import SwiftUI
import KeypaceCore

/// A small always-on-top window with speed as you type.
struct LiveMetrics: View {
    let tracker: LiveTracker

    var body: some View {
        let _ = tracker.revision
        let session = tracker.current
        let today = PeriodData(.today, tracker: tracker).totals
        let live = tracker.liveWPM

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.wpm(live ?? today.wpm)).font(.system(size: 44, weight: .semibold)).contentTransition(.numericText())
                Text(live == nil ? "wpm today" : "wpm").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            }
            Group {
                if let session {
                    Text("\(Format.duration(session.duration)) · \(Format.percent(session.totals.correctionRate)) corrected")
                } else {
                    Text("\(Format.duration(today.duration)) typed today")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .animation(.easeOut(duration: 0.2), value: live)
        .padding(16)
        .frame(width: 220, alignment: .leading)
    }
}
