import SwiftUI
import KeypaceCore

/// Speed and corrections per physical keyboard.
struct KeyboardsPage: View {
    let tracker: LiveTracker
    @AppStorage("keyboardsPeriod") private var period = Period.month
    @State private var renaming: KeyboardRecord?
    @State private var newName = ""

    var body: some View {
        let data = { _ = tracker.revision; return PeriodData(period, tracker: tracker) }()
        let keyboards = Dictionary(uniqueKeysWithValues: tracker.keyboards().map { ($0.id, $0) })
        let connected = tracker.connectedKeyboardIDs
        let previous = Dictionary(uniqueKeysWithValues: Statistics.byKeyboard(data.previousSessions ?? []).map { ($0.id, $0.totals) })
        let rows = Statistics.byKeyboard(data.sessions).map { entry in
            let keyboard = keyboards[entry.id]
            let kind = keyboard.map { $0.isBuiltIn ? "Built-in" : "External" }
            return BreakdownRow(
                id: entry.id,
                title: keyboard?.displayName ?? "Unknown keyboard",
                detail: [kind, connected.contains(entry.id) ? "connected" : nil].compactMap { $0 }.joined(separator: ", "),
                totals: entry.totals,
                previous: previous[entry.id]
            )
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Keyboards", period: $period).padding(.bottom, 16)
                if rows.isEmpty {
                    Text("No typing recorded in this period.").foregroundStyle(.secondary)
                } else {
                    BreakdownTable(heading: "Keyboard", rows: rows) { row in
                        if let keyboard = keyboards[row.id] {
                            Button("Rename…") {
                                newName = keyboard.displayName
                                renaming = keyboard
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .alert("Rename keyboard", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let keyboard = renaming {
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    tracker.renameKeyboard(id: keyboard.id, to: trimmed.isEmpty ? nil : trimmed)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Speed and corrections per keyboard layout.
struct LayoutsPage: View {
    let tracker: LiveTracker
    @AppStorage("layoutsPeriod") private var period = Period.month

    var body: some View {
        let data = { _ = tracker.revision; return PeriodData(period, tracker: tracker) }()
        let sources = Dictionary(uniqueKeysWithValues: tracker.inputSourceRecords().map { ($0.id, $0) })
        let previous = Dictionary(uniqueKeysWithValues: Statistics.byInputSource(data.previousSessions ?? []).map { ($0.id, $0.totals) })
        let rows = Statistics.byInputSource(data.sessions).map { entry in
            BreakdownRow(
                id: entry.id,
                title: sources[entry.id]?.name ?? entry.id,
                detail: LayoutFamily.detect(inputSourceID: entry.id).rawValue,
                totals: entry.totals,
                previous: previous[entry.id]
            )
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Layouts", period: $period).padding(.bottom, 16)
                if rows.isEmpty {
                    Text("No typing recorded in this period.").foregroundStyle(.secondary)
                } else {
                    BreakdownTable(heading: "Layout", rows: rows) { _ in EmptyView() }
                }
            }
            .padding(24)
        }
    }
}
