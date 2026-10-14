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
                Text(live == nil ? "avg wpm" : "live wpm").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            .help(live == nil ? "Today's average of saved sessions after corrections."
                             : "Speed after corrections over the last 8 seconds, with thinking pauses excluded.")
            Group {
                if live != nil, let session {
                    Text("Session: \(Format.percent(session.totals.correctionRate)) corrected")
                } else {
                    Text("Today · \(Format.duration(today.duration)) typing")
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
