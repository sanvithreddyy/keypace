import SwiftUI
import KeypaceCore

/// The Overview page's content in voice mode: speaking speed against typing, then where the words,
/// the pace and the time go.
struct VoiceOverview: View {
    let tracker: LiveTracker
    let data: PeriodData

    var body: some View {
        if data.dictations.isEmpty {
            Text(data.period == .today ? "No dictation recorded today." : "No dictation recorded in this period.")
                .foregroundStyle(.secondary)
        } else {
            let typing = tracker.measure.typing ? PeriodData(data.period, tracker: tracker) : nil
            let typingWPM = typing?.totals.wpm
            let all = tracker.allDictations()
            VoiceHero(wpm: data.voice.wpm, typingWPM: typingWPM).padding(.top, 4).padding(.bottom, 18)
            VoiceStatRow(data: data, typing: typing, allDictations: all)
            SectionHeading(title: data.period == .today ? "By hour" : "By day",
                           detail: typing == nil ? "Words spoken · speaking wpm on top" : "Spoken in ink, typed in gray · speaking wpm on top")
            WordColumns(data: data, typing: typing)
            if !VoiceStatistics.paced(data.dictations).isEmpty {
                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeading(title: "Your pace", detail: "Dictations by speed")
                        PaceHistogram(dictations: data.dictations, typingWPM: typingWPM)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeading(title: "Longer is faster", detail: "wpm by length")
                        LengthRows(dictations: data.dictations)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if data.period != .today {
                SectionHeading(title: "When you talk", detail: "Words by hour")
                HourColumns(dictations: data.dictations)
            }
            SectionHeading(title: "Where your words go", detail: "Words · share")
            WordShares(rows: VoiceStatistics.byApp(data.dictations).prefix(5).map { ($0.appID, $0.totals.words) },
                       total: data.voice.words)
            SectionHeading(title: "Dictation apps", detail: "Words · dictations · wpm")
            SourceBars(sources: VoiceStatistics.bySource(data.dictations))
            SectionHeading(title: "Records", detail: "All time")
            VoiceRecordStrip(dictations: all)
        }
    }
}

/// The speaking speed large, and against typing speed when typing is measured.
private struct VoiceHero: View {
    let wpm: Double?
    let typingWPM: Double?

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Format.wpm(wpm)).font(.system(size: 46, weight: .semibold)).tracking(-0.8)
                    Text("wpm speaking").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                }
                if let wpm, let typingWPM, typingWPM > 0 {
                    (Text("\((wpm / typingWPM).formatted(.number.precision(.fractionLength(1))))×").fontWeight(.semibold)
                        + Text(" your typing speed").foregroundStyle(.secondary))
                } else {
                    Text("Words per minute of open microphone").foregroundStyle(.secondary)
                }
            }
            .fixedSize()
            if let wpm, let typingWPM {
                let top = max(wpm, typingWPM) * 1.45
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    row("Speaking", wpm, fraction: wpm / top, emphasized: true)
                    row("Typing", typingWPM, fraction: typingWPM / top, emphasized: false)
                }
            }
        }
        .monospacedDigit()
    }

    private func row(_ label: String, _ value: Double, fraction: Double, emphasized: Bool) -> some View {
        GridRow {
            Text(label).font(.caption).foregroundStyle(.secondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(emphasized ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: proxy.size.width * min(fraction, 1))
                }
            }
            .frame(height: 8)
            Text(Format.wpm(value)).fontWeight(emphasized ? .semibold : .regular)
                .foregroundStyle(emphasized ? .primary : .secondary).gridColumnAlignment(.trailing)
        }
    }
}

/// Five stat blocks for dictation, each set against typing when it's measured.
private struct VoiceStatRow: View {
    let data: PeriodData
    let typing: PeriodData?
    let allDictations: [DictationRecord]

    var body: some View {
        let now = data.voice
        let typed = typing.map { $0.totals.netCharacters / 5 }
        let typingWPM = typing?.totals.wpm
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 0) {
                StatBlock(label: "Words spoken", value: now.words.formatted(),
                          change: typed.flatMap { typed in now.words + typed > 0
                              ? "\(Format.percent(Double(now.words) / Double(now.words + typed), decimals: 0)) of all you wrote" : nil })
                Divider()
                StatBlock(label: "Talking time", value: Format.duration(now.speakingSeconds),
                          change: typing.map { "typing \(Format.duration($0.totals.duration))" })
                Divider()
                if let typingWPM, typingWPM > 0 {
                    let saved = Double(now.timedWords) / typingWPM * 60 - now.speakingSeconds
                    StatBlock(label: "Time saved", value: saved > 0 ? Format.duration(saved) : "None", change: "vs typing it all")
                        .help("How much longer these words would have taken at your typing speed.")
                } else {
                    let streaks = Statistics.streaks(starts: allDictations.map(\.start), today: .now, calendar: .current)
                    StatBlock(label: "Streak", value: "\(streaks.current) \(streaks.current == 1 ? "day" : "days")", change: "best \(streaks.longest)")
                }
                Divider()
                StatBlock(label: "Dictations", value: now.dictations.formatted(),
                          change: now.averageWords.map { "avg \(Int($0.rounded())) words" })
                Divider()
                if let typingWPM, case let faster = VoiceStatistics.faster(than: typingWPM, data.dictations), faster.of > 0 {
                    StatBlock(label: "Beat your typing", value: Format.percent(Double(faster.count) / Double(faster.of), decimals: 0),
                              change: "\(faster.count) of \(faster.of)")
                        .help("Dictations of at least \(Int(VoiceStatistics.paceMinimumSeconds)) seconds that were faster than your typing speed.")
                } else {
                    StatBlock(label: "Median pace", value: VoiceStatistics.medianWPM(data.dictations).map { "\(Format.wpm($0)) wpm" } ?? "–")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider()
        }
        .monospacedDigit()
    }
}

/// Words per day (or hour) as columns: spoken in ink at the bottom, typed in gray on top, with the
/// speaking speed written over each column when they're wide enough, else over the busiest one.
private struct WordColumns: View {
    let data: PeriodData
    let typing: PeriodData?

    private struct Slot: Identifiable {
        let id: Int
        let name: String
        let label: String?
        var spoken = 0
        var typed = 0
        var wpm: Double?
    }

    var body: some View {
        let slots = self.slots
        let most = max(slots.map { $0.spoken + $0.typed }.max() ?? 1, 1)
        let busiest = slots.max { $0.spoken < $1.spoken }?.id
        let labelled = slots.count <= 8
        let plot: CGFloat = 130
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: labelled ? 16 : 3) {
                ForEach(slots) { slot in
                    let spoken = plot * CGFloat(slot.spoken) / CGFloat(most)
                    let typed = plot * CGFloat(slot.typed) / CGFloat(most)
                    VStack(spacing: 2) {
                        Spacer(minLength: 0)
                        if labelled || slot.id == busiest {
                            Text(slot.wpm.map { "\(Format.wpm($0)) wpm" } ?? (slot.spoken > 0 ? "no timing" : "–"))
                                .font(.system(size: 10.5, weight: slot.wpm == nil ? .regular : .semibold))
                                .foregroundStyle(slot.wpm == nil ? .tertiary : .primary)
                                .fixedSize()
                            Text(slot.spoken > 0 ? "\(slot.spoken.formatted()) spoken" : "none spoken")
                                .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize()
                                .padding(.bottom, 4)
                        }
                        if slot.typed > 0 {
                            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.18)).frame(height: max(typed, 1.5))
                        }
                        if slot.spoken > 0 {
                            RoundedRectangle(cornerRadius: 2).fill(Color.primary).frame(height: max(spoken, 1.5))
                        }
                        if slot.spoken == 0 && slot.typed == 0 {
                            RoundedRectangle(cornerRadius: 1).fill(.quaternary).frame(height: 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .hoverValue(hoverText(slot), cornerRadius: 3)
                }
            }
            .frame(height: plot + 36)
            HStack(spacing: labelled ? 16 : 3) {
                ForEach(slots) { slot in
                    Text(slot.label ?? "").font(.caption).foregroundStyle(.secondary).fixedSize().frame(maxWidth: .infinity)
                }
            }
        }
        .hoverValues()
        .monospacedDigit()
    }

    private func hoverText(_ slot: Slot) -> String {
        var parts = [slot.name, "\(slot.spoken.formatted()) spoken"]
        if typing != nil { parts.append("\(slot.typed.formatted()) typed") }
        if let wpm = slot.wpm { parts.append("\(Format.wpm(wpm)) wpm") }
        return parts.joined(separator: " · ")
    }

    private var isHourly: Bool { data.period == .today }

    private var slots: [Slot] {
        guard let interval = data.interval else { return [] }
        let calendar = Calendar.current
        let count = isHourly ? 24 : calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1
        let index = { (date: Date) in
            isHourly ? calendar.component(.hour, from: date)
                : calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: date)).day ?? 0
        }
        var slots = (0..<count).map { i in
            let date = isHourly ? calendar.date(bySettingHour: i, minute: 0, second: 0, of: interval.start)!
                : calendar.date(byAdding: .day, value: i, to: interval.start)!
            let name = isHourly ? date.formatted(.dateTime.hour()) : date.formatted(.dateTime.month(.abbreviated).day())
            let showLabel = count <= 8 || i == 0 || i == count - 1 || (isHourly && i % 6 == 0)
            return Slot(id: i, name: name, label: showLabel ? name : nil)
        }
        let dictations = Dictionary(grouping: data.dictations) { index($0.start) }
        for (i, group) in dictations where slots.indices.contains(i) {
            let totals = VoiceTotals(group)
            slots[i].spoken = totals.words
            slots[i].wpm = totals.wpm
        }
        for session in typing?.sessions ?? [] {
            let i = index(session.start)
            if slots.indices.contains(i) { slots[i].typed += session.totals.netCharacters / 5 }
        }
        return slots
    }
}

/// How many dictations ran at each speed, with typing speed marked: the fullest band is ink with its count.
private struct PaceHistogram: View {
    let dictations: [DictationRecord]
    let typingWPM: Double?
    static let band = 20

    var body: some View {
        let bands = VoiceStatistics.paceBands(dictations, width: Self.band)
        let low = min(bands.first?.lower ?? 0, typingWPM.map { Int($0) / Self.band * Self.band } ?? Int.max)
        let high = (bands.last?.lower ?? 100) + Self.band
        let most = max(bands.map(\.count).max() ?? 1, 1)
        let fullest = bands.max { $0.count < $1.count }?.lower
        let median = VoiceStatistics.medianWPM(dictations)
        GeometryReader { proxy in
            let plot = CGRect(x: 0, y: 16, width: proxy.size.width, height: proxy.size.height - 34)
            let x = { (wpm: Double) in plot.minX + plot.width * CGFloat((wpm - Double(low)) / Double(high - low)) }
            let bandWidth = plot.width * CGFloat(Self.band) / CGFloat(high - low)
            ZStack(alignment: .topLeading) {
                ForEach(bands, id: \.lower) { band in
                    let height = max(plot.height * CGFloat(band.count) / CGFloat(most), band.count > 0 ? 2 : 0)
                    let slower = typingWPM.map { Double(band.lower + Self.band) <= $0 } ?? false
                    RoundedRectangle(cornerRadius: 2)
                        .fill(band.lower == fullest ? Color.primary : Color.primary.opacity(slower ? 0.1 : 0.22))
                        .frame(width: max(bandWidth - 3, 1), height: height)
                        .hoverValue("\(band.lower)–\(band.lower + Self.band) wpm · \(band.count) \(band.count == 1 ? "dictation" : "dictations")", cornerRadius: 2)
                        .position(x: x(Double(band.lower)) + bandWidth / 2, y: plot.maxY - height / 2)
                    if band.lower == fullest {
                        Text("\(band.count)").font(.system(size: 10, weight: .bold))
                            .position(x: x(Double(band.lower)) + bandWidth / 2, y: plot.maxY - height - 8)
                    }
                }
                if let typingWPM {
                    Path { path in
                        path.move(to: CGPoint(x: x(typingWPM), y: plot.minY - 6))
                        path.addLine(to: CGPoint(x: x(typingWPM), y: plot.maxY))
                    }
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Text("typing \(Format.wpm(typingWPM))").font(.system(size: 10)).fixedSize()
                        .position(x: x(typingWPM) + 30, y: plot.minY - 4)
                }
                if let median {
                    Text("median \(Format.wpm(median))").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
                        .frame(width: plot.width, alignment: .trailing)
                        .position(x: plot.midX, y: plot.minY - 4)
                }
                ForEach(Array(stride(from: low, through: high, by: Self.band * 2)), id: \.self) { edge in
                    Text("\(edge)").font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize()
                        .position(x: x(Double(edge)), y: plot.maxY + 10)
                }
            }
        }
        .frame(height: 150)
        .hoverValues()
        .monospacedDigit()
    }
}

/// Speaking speed by dictation length, the fastest in ink.
private struct LengthRows: View {
    let dictations: [DictationRecord]

    var body: some View {
        // The same dictations as the pace histogram, so a few-second burst can't skew a length.
        let paced = VoiceStatistics.paced(dictations)
        let rows = VoiceStatistics.byLength(paced).filter { $0.totals.wpm != nil }
        let fastest = rows.compactMap(\.totals.wpm).max() ?? 1
        let long = VoiceTotals(paced.filter { $0.words > 30 })
        VStack(alignment: .leading, spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(rows, id: \.length) { row in
                    let wpm = row.totals.wpm ?? 0
                    GridRow {
                        Text(title(row.length)).foregroundStyle(.secondary).fixedSize()
                        Bar(fraction: wpm / fastest, emphasized: wpm == fastest)
                        Text(Format.wpm(wpm)).fontWeight(wpm == fastest ? .semibold : .regular).gridColumnAlignment(.trailing)
                    }
                    .help("\(row.totals.dictations) \(row.totals.dictations == 1 ? "dictation" : "dictations")")
                }
            }
            if let longWPM = long.wpm, rows.count > 1 {
                Text("Dictations over 30 words average \(Format.wpm(longWPM)) wpm.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
            }
        }
        .font(.callout)
        .monospacedDigit()
    }

    private func title(_ length: VoiceStatistics.Length) -> String {
        switch length {
        case .short: "1–10 words"
        case .medium: "11–30"
        case .long: "31–100"
        case .veryLong: "100+"
        }
    }
}

/// Words dictated in each hour of the day across the period, the busiest hour in ink with its count.
private struct HourColumns: View {
    let dictations: [DictationRecord]

    var body: some View {
        let hours = VoiceStatistics.byHourOfDay(dictations, calendar: .current).mapValues(\.words)
        let most = max(hours.values.max() ?? 1, 1)
        let busiest = hours.max { $0.value < $1.value }?.key
        let plot: CGFloat = 70
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<24, id: \.self) { hour in
                    let words = hours[hour] ?? 0
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        if hour == busiest {
                            Text(words.formatted()).font(.system(size: 10, weight: .bold)).fixedSize()
                        }
                        RoundedRectangle(cornerRadius: 2)
                            .fill(words == 0 ? AnyShapeStyle(.quaternary) : hour == busiest ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.22)))
                            .frame(height: words == 0 ? 2 : max(plot * CGFloat(words) / CGFloat(most), 2))
                    }
                    .frame(maxWidth: .infinity)
                    .hoverValue(words == 0 ? nil : "\(hourName(hour)) · \(words.formatted()) words", cornerRadius: 2)
                }
            }
            .frame(height: plot + 16)
            HStack(spacing: 4) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(hour % 6 == 0 ? hourName(hour) : "").font(.caption2).foregroundStyle(.tertiary).fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .hoverValues()
        .monospacedDigit()
    }

    private func hourName(_ hour: Int) -> String {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!.formatted(.dateTime.hour())
    }
}

/// Apps by words dictated into them, with each one's share.
private struct WordShares: View {
    let rows: [(appID: String, words: Int)]
    let total: Int

    var body: some View {
        let most = Double(rows.first?.words ?? 1)
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.element.appID) { index, row in
                GridRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppInfo.name(row.appID)).lineLimit(1)
                        Bar(fraction: Double(row.words) / most, emphasized: index == 0)
                    }
                    Text(row.words.formatted()).gridColumnAlignment(.trailing)
                    Text(share(row.words)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.callout)
        .monospacedDigit()
    }

    private func share(_ words: Int) -> String {
        guard total > 0 else { return "–" }
        let share = Double(words) / Double(total)
        return share < 0.005 ? "<1%" : Format.percent(share, decimals: 0)
    }
}

/// Four all-time bests in a row of stat blocks.
private struct VoiceRecordStrip: View {
    let dictations: [DictationRecord]

    var body: some View {
        let records = VoiceRecords(dictations, calendar: .current)
        let streaks = Statistics.streaks(starts: dictations.map(\.start), today: .now, calendar: .current)
        let days = Set(dictations.map { Calendar.current.startOfDay(for: $0.start) }).count
        let total = VoiceTotals(dictations)
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 0) {
                StatBlock(label: "Fastest dictation", value: records.fastest.map { "\(Format.wpm($0.wpm)) wpm" } ?? "–",
                          change: records.fastest.map { "\($0.words) words · \(Format.day($0.start))" })
                Divider()
                StatBlock(label: "Longest dictation", value: records.longest?.speakingSeconds.map(Self.length) ?? "–",
                          change: records.longest.map { "\($0.words) words · \(Format.day($0.start))" })
                Divider()
                StatBlock(label: "Streak", value: "\(streaks.current) \(streaks.current == 1 ? "day" : "days")",
                          change: "\(days) \(days == 1 ? "day" : "days") with dictation")
                Divider()
                StatBlock(label: "All time", value: "\(total.words.formatted()) words",
                          change: dictations.first.map { "\(total.dictations.formatted()) dictations since \(Format.day($0.start))" })
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider()
        }
    }

    /// "2 min 57 s", "48 s".
    static func length(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60) min \(total % 60) s" : "\(total) s"
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
