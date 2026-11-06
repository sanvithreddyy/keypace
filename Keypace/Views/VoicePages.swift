import Charts
import SwiftUI
import KeypaceCore

/// The Overview page's content in voice mode.
struct VoiceOverview: View {
    let tracker: LiveTracker
    let data: PeriodData

    var body: some View {
        if data.dictations.isEmpty {
            Text(data.period == .today ? "No dictation recorded today." : "No dictation recorded in this period.")
                .foregroundStyle(.secondary)
        } else {
            let typing = tracker.measure.typing ? PeriodData(data.period, tracker: tracker) : nil
            VoiceStatRow(data: data, typing: typing, streaks: Statistics.streaks(starts: tracker.allDictations().map(\.start), today: .now, calendar: .current))
            SectionHeading(title: data.period == .today ? "Words by hour" : "Words by day",
                           detail: typing == nil ? nil : "Spoken in ink, typed in gray")
            WordsChart(data: data, typing: typing)
            if !data.sessions.isEmpty {
                SectionHeading(title: data.period == .today ? "Speed by hour" : "Speed by day",
                               detail: (data.previousSessions ?? []).isEmpty ? nil : "This period in full ink, the previous one in gray")
                SpeedChart(data: data)
                SectionHeading(title: "When you talk fastest", detail: "Average speaking wpm by weekday and hour")
                WeekHourHeatmap(sessions: data.sessions, mode: .voice)
                SectionHeading(title: "Apps", detail: "Talking time · wpm")
                AppBars(apps: Array(Statistics.byApp(data.sessions).prefix(5)))
            }
            SectionHeading(title: "Dictation apps", detail: "Words · dictations · wpm")
            SourceBars(sources: VoiceStatistics.bySource(data.dictations))
        }
    }
}

/// Each dictation app over a thin bar sized by words, with words, dictations and speed in right-hand columns.
private struct SourceBars: View {
    let sources: [(sourceID: String, totals: VoiceTotals)]

    var body: some View {
        let most = Double(sources.map(\.totals.words).max() ?? 1)
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(Array(sources.enumerated()), id: \.element.sourceID) { index, source in
                GridRow {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if let icon = AppInfo.icon(source.sourceID) { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                            Text(AppInfo.name(source.sourceID)).lineLimit(1)
                        }
                        Bar(fraction: Double(source.totals.words) / most, emphasized: index == 0)
                    }
                    Text(source.totals.words.formatted()).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(source.totals.dictations.formatted()).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(Format.wpm(source.totals.wpm)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.callout)
        .monospacedDigit()
    }
}

/// Five stat blocks for dictation, each with its change or its typing counterpart.
private struct VoiceStatRow: View {
    let data: PeriodData
    /// The same period's typing, when typing is measured.
    let typing: PeriodData?
    let streaks: (current: Int, longest: Int)

    var body: some View {
        let now = data.voice
        let before = data.previousVoice
        let typed = typing.map { $0.totals.netCharacters / 5 }
        let typingWPM = typing?.totals.wpm
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 0) {
                let speedChange = now.wpm.flatMap { now in before?.wpm.map { now - $0 } }
                StatBlock(label: "Speaking speed", value: "\(Format.wpm(now.wpm)) wpm",
                          change: typingWPM.map { "typing \(Format.wpm($0))" } ?? speedChange.map { Format.signed($0) },
                          changeColor: typingWPM == nil ? tone(speedChange) : .secondary)
                    .help("Words per minute of open microphone, thinking pauses included.")
                Divider()
                StatBlock(label: "Words spoken", value: now.words.formatted(),
                          change: typed.map { "typed \($0.formatted())" } ?? before.map { "\(Format.signed(Double(now.words - $0.words))) words" })
                Divider()
                StatBlock(label: "Talking time", value: Format.duration(now.speakingSeconds),
                          change: typing.map { "typing \(Format.duration($0.totals.duration))" }
                            ?? before.map { Format.signed((now.speakingSeconds - $0.speakingSeconds) / 60) + " min" })
                Divider()
                StatBlock(label: "Dictations", value: now.dictations.formatted(),
                          change: now.averageWords.map { "avg \(Int($0.rounded())) words" })
                Divider()
                if let typingWPM, typingWPM > 0, now.speakingSeconds > 0 {
                    let saved = Double(now.timedWords) / typingWPM * 60 - now.speakingSeconds
                    StatBlock(label: "Time saved", value: saved > 0 ? Format.duration(saved) : "None",
                              change: "vs typing at \(Format.wpm(typingWPM)) wpm")
                        .help("How much longer these words would have taken at your typing speed.")
                } else {
                    StatBlock(label: "Streak", value: "\(streaks.current) \(streaks.current == 1 ? "day" : "days")", change: "best \(streaks.longest)")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider()
        }
        .monospacedDigit()
    }

    private func tone(_ change: Double?) -> Color {
        guard let change, abs(change) >= 0.5 else { return .secondary }
        return change > 0 ? .green : .red
    }
}

/// Words spoken per hour or day in ink, with words typed beside them in gray.
private struct WordsChart: View {
    let data: PeriodData
    let typing: PeriodData?
    @State private var hovered: Int?

    private struct Bar: Identifiable {
        var kind: String
        var index: Int
        var words: Int
        var id: String { "\(kind)\(index)" }
    }

    var body: some View {
        let spoken = bars(data.dictations.map { ($0.start, $0.words) }, kind: "Spoken")
        let typed = typing.map { bars($0.sessions.map { ($0.start, $0.totals.netCharacters / 5) }, kind: "Typed") } ?? []
        Chart {
            ForEach(typed + spoken) { bar in
                BarMark(x: .value("Position", bar.index), y: .value("Words", bar.words), width: .ratio(typing == nil ? 0.6 : 0.8))
                    .position(by: .value("Kind", bar.kind), axis: .horizontal)
                    .foregroundStyle(bar.kind == "Spoken" ? Color.primary : Color.primary.opacity(0.22))
                    .cornerRadius(2)
            }
            if let hovered {
                RuleMark(x: .value("Position", hovered)).foregroundStyle(.quaternary).lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                AxisValueLabel { Text((value.as(Int.self) ?? 0).formatted(.number.notation(.compactName))) }
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, max(slots - 1, 0)]) { value in
                AxisValueLabel(anchor: value.index == 0 ? .topLeading : .topTrailing) { Text(label(for: value.as(Int.self) ?? 0)) }
            }
        }
        .chartXScale(domain: -0.5...Double(max(slots, 1)) - 0.5)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
                Rectangle().fill(.clear).contentShape(.rect)
                    .onContinuousHover { phase in
                        guard case .active(let location) = phase, let x = proxy.value(atX: location.x - plot.minX, as: Double.self) else {
                            hovered = nil
                            return
                        }
                        hovered = min(max(Int(x.rounded()), 0), max(slots - 1, 0))
                    }
                if let hovered {
                    let x = proxy.position(forX: hovered) ?? 0
                    let words = spoken.first { $0.index == hovered }?.words ?? 0
                    let typedWords = typed.first { $0.index == hovered }?.words
                    HoverLabel(text: [label(for: hovered), "\(words.formatted()) spoken"].joined(separator: " · ")
                                   + (typedWords.map { " · \($0.formatted()) typed" } ?? ""),
                               target: CGRect(x: plot.minX + x, y: plot.minY + 8, width: 0, height: 0))
                }
            }
        }
        .frame(height: 150)
    }

    private var isHourly: Bool { data.period == .today }

    private var slots: Int {
        guard let interval = data.interval else { return 1 }
        return isHourly ? 24 : Calendar.current.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1
    }

    private func bars(_ items: [(Date, Int)], kind: String) -> [Bar] {
        guard let start = data.interval?.start else { return [] }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            isHourly ? calendar.component(.hour, from: item.0)
                : calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: item.0)).day ?? 0
        }
        return grouped.map { Bar(kind: kind, index: $0.key, words: $0.value.map(\.1).reduce(0, +)) }
            .filter { $0.words > 0 }
            .sorted { $0.index < $1.index }
    }

    private func label(for index: Int) -> String {
        guard let start = data.interval?.start else { return "" }
        if isHourly { return Calendar.current.date(bySettingHour: index, minute: 0, second: 0, of: start)!.formatted(.dateTime.hour()) }
        return Calendar.current.date(byAdding: .day, value: index, to: start)!.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// The Records page's content in voice mode.
struct VoiceRecordsContent: View {
    let tracker: LiveTracker

    var body: some View {
        let dictations = tracker.allDictations()
        let records = VoiceRecords(dictations, calendar: .current)
        let streaks = Statistics.streaks(starts: dictations.map(\.start), today: .now, calendar: .current)
        if dictations.isEmpty {
            Text("No dictation recorded yet.").foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    block("Fastest dictation", records.fastest.map { "\(Format.wpm($0.wpm)) wpm" }, records.fastest)
                    Divider()
                    block("Most words", records.mostWords.map { "\($0.words.formatted()) words" }, records.mostWords)
                    Divider()
                    block("Longest dictation", records.longest.flatMap(\.speakingSeconds).map(Format.duration), records.longest)
                    Divider()
                    StatBlock(label: "Streak", value: "\(streaks.current) \(streaks.current == 1 ? "day" : "days")", change: "best \(streaks.longest)")
                }
                .fixedSize(horizontal: false, vertical: true)
                Divider()
            }

            SectionHeading(title: "Best days")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                if let day = records.fastestDay {
                    dayRow("Fastest day", day: day.day, value: "\(Format.wpm(day.totals.wpm)) wpm", detail: Format.duration(day.totals.speakingSeconds))
                }
                if let day = records.mostWordsDay {
                    dayRow("Most words", day: day.day, value: "\(day.totals.words.formatted()) words", detail: "\(day.totals.dictations) dictations")
                }
            }
            .font(.callout)
            .monospacedDigit()

            if !records.fastestByApp.isEmpty {
                SectionHeading(title: "Fastest by app")
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(records.fastestByApp, id: \.appID) { dictation in
                        GridRow {
                            Text(AppInfo.name(dictation.appID)).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(Format.wpm(dictation.wpm)) wpm").gridColumnAlignment(.trailing)
                            Text(Format.day(dictation.start)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        }
                    }
                }
                .font(.callout)
                .monospacedDigit()
            }

            Text("Speed records count dictations of at least \(Int(VoiceRecords.minimumSeconds)) seconds and \(VoiceRecords.minimumWords) words; a fastest day needs \(Int(VoiceRecords.minimumDaySeconds / 60)) minutes of talking.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 24)
        }
    }

    private func block(_ label: String, _ value: String?, _ dictation: DictationRecord?) -> some View {
        StatBlock(label: label, value: value ?? "–", change: dictation.map { "\(AppInfo.name($0.appID)) · \(Format.day($0.start))" })
    }

    private func dayRow(_ label: String, day: Date, value: String, detail: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(day.formatted(date: .complete, time: .omitted)).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).gridColumnAlignment(.trailing)
            Text(detail).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
        }
    }
}
