import ServiceManagement
import SwiftUI
import KeypaceCore
import UniformTypeIdentifiers

struct GeneralSettingsPage: View {
    @Bindable var tracker: LiveTracker
    @State private var confirmingReset = false
    @State private var exportError: String?
    @State private var loginError: String?
    @AppStorage("menuBarFormat") private var menuBarFormat = MenuBarFormat.withUnit

    private var filterDescription: String {
        switch tracker.syntheticStrength {
        case .off: "Every keystroke counts, including ones sent by text expanders and automation."
        case .normal: "Keystrokes sent by other apps, such as text expanders and automation, don't count toward your speed."
        case .strict: "Also ignores keystrokes that arrive faster than a person can type."
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginError = nil
                } catch {
                    loginError = "Couldn't change: \(error.localizedDescription)"
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("Sessions") {
                Stepper(value: $tracker.inactivityTimeout, in: 2...30, step: 1) {
                    LabeledContent("End a session after", value: "\(Int(tracker.inactivityTimeout)) s without typing")
                }
                Stepper(value: $tracker.minimumCharacters, in: 1...200, step: 5) {
                    LabeledContent("Save sessions with at least", value: "\(tracker.minimumCharacters) characters")
                }
            }
            Section("Menu bar") {
                Picker("Show", selection: $menuBarFormat) {
                    ForEach(MenuBarFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Open at login", isOn: launchAtLogin)
                if let loginError { Text(loginError).foregroundStyle(.red) }
            }
            Section {
                Picker("Ignore input from other software", selection: $tracker.syntheticStrength) {
                    Text("Off").tag(SyntheticFilter.Strength.off)
                    Text("Standard").tag(SyntheticFilter.Strength.normal)
                    Text("Strict").tag(SyntheticFilter.Strength.strict)
                }
            } footer: {
                Text(filterDescription).font(.caption).foregroundStyle(.secondary)
            }
            Section("Data") {
                LabeledContent("Export every session as CSV") {
                    Button("Export…", action: export)
                }
                if let exportError { Text(exportError).foregroundStyle(.red) }
                LabeledContent("Delete all typing history") {
                    Button("Delete…", role: .destructive) { confirmingReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .confirmationDialog("Delete all typing history?", isPresented: $confirmingReset) {
            Button("Delete All History", role: .destructive) { tracker.deleteAllHistory() }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Keypace sessions \(Date.now.formatted(.iso8601.year().month().day())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SessionCSV.make(tracker.allSessions()).write(to: url, atomically: true, encoding: .utf8)
            exportError = nil
        } catch {
            exportError = "Couldn't export: \(error.localizedDescription)"
        }
    }
}

struct TrackingSettingsPage: View {
    @Bindable var tracker: LiveTracker
    @State private var selection: String?
    @State private var offerDeletion: String?

    var body: some View {
        Form {
            Section {
                Picker("Track", selection: $tracker.filter.mode) {
                    Text("Every app except these").tag(AppFilter.Mode.allExcept)
                    Text("Only these apps").tag(AppFilter.Mode.only)
                }
                .pickerStyle(.radioGroup)
            }
            Section {
                if tracker.filter.appIDs.isEmpty {
                    Text("No apps").foregroundStyle(.secondary)
                } else {
                    List(tracker.filter.appIDs, id: \.self, selection: $selection) { appID in
                        HStack(spacing: 8) {
                            if let icon = AppInfo.icon(appID) { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                            Text(AppInfo.name(appID))
                        }
                    }
                    .frame(minHeight: 160)
                }
                HStack {
                    Button("Add App…", action: addApp)
                    Button("Remove") {
                        tracker.filter.appIDs.removeAll { $0 == selection }
                        selection = nil
                    }
                    .disabled(selection == nil)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Tracking")
        .confirmationDialog(
            "Delete the typing history recorded in \(offerDeletion.map(AppInfo.name) ?? "")?",
            isPresented: Binding(get: { offerDeletion != nil }, set: { if !$0 { offerDeletion = nil } })
        ) {
            if let appID = offerDeletion {
                Button("Delete History", role: .destructive) { tracker.deleteHistory(appID: appID) }
                Button("Keep History") {}
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { !tracker.filter.appIDs.contains($0) }
        tracker.filter.appIDs.append(contentsOf: added)
        if tracker.filter.mode == .allExcept, added.count == 1, let appID = added.first,
           tracker.allSessions().contains(where: { $0.appID == appID }) {
            offerDeletion = appID
        }
    }
}
