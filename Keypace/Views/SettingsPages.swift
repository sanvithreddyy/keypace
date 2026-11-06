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
    @AppStorage("menuBarNumber") private var menuBarNumber = MenuBarNumber.liveThenToday
    @AppStorage("menuBarSpeeds") private var menuBarSpeeds = MenuBarSpeeds.both
    @AppStorage(Appearance.key) private var appearance = Appearance.light
    @State private var confirmingVoiceReset = false
    @Bindable private var updates = Updates.shared

    var body: some View {
        SettingsPage(title: "General") {
            SettingsSection("Measure") {
                SettingsRow("Measure", description: tracker.measure.description) {
                    Picker("Measure", selection: $tracker.measure) {
                        ForEach(Measure.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .segmentedStyle()
                }
            }
            SettingsSection("Appearance") {
                SettingsRow("Theme") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .segmentedStyle()
                    .onChange(of: appearance) { _, appearance in appearance.apply() }
                }
            }
            SettingsSection("Speed") {
                SettingsRow("New session after a pause of", value: "\(Int(tracker.inactivityTimeout)) s",
                            description: "A longer pause ends the session; switching apps, keyboards or layouts does too.") {
                    TickedSlider(value: $tracker.inactivityTimeout, range: 2...15, step: 1, low: "2 s", high: "15 s")
                }
                SettingsRow("Ignore sessions shorter than", value: "\(tracker.minimumCharacters) characters",
                            description: "A few quick keystrokes can't swing your speed.") {
                    TickedSlider(value: minimumCharacters, range: 5...100, step: 5, low: "5", high: "100")
                }
            }
            SettingsSection("Menu bar") {
                if tracker.measure == .both {
                    SettingsRow("Speeds", description: "Speaking speed shows after a microphone icon, as today's average.") {
                        Picker("Speeds", selection: $menuBarSpeeds) {
                            ForEach(MenuBarSpeeds.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .segmentedStyle()
                    }
                }
                SettingsRow("Show") {
                    Picker("Show", selection: $menuBarFormat) {
                        ForEach(MenuBarFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .segmentedStyle()
                }
                SettingsRow("Number", description: menuBarNumber.description) {
                    Picker("Number", selection: $menuBarNumber) {
                        ForEach(MenuBarNumber.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .segmentedStyle()
                }
                SettingsRow("Open at login", description: loginError) {
                    Toggle("Open at login", isOn: launchAtLogin).toggleStyle(.switch).labelsHidden()
                }
            }
            if tracker.measure.voice {
                SettingsSection("Voice") {
                    SettingsRow("Dictation apps", description: "Any app that records and then pastes or types its text counts. Keypace counts the words and keeps no text or audio. macOS Dictation isn't counted.") { EmptyView() }
                    SettingsRow("Delete all voice history", description: "Removes every dictation from this Mac. Typing history stays.") {
                        Button("Delete…", role: .destructive) { confirmingVoiceReset = true }
                    }
                }
            }
            SettingsSection("Input from other software") {
                SettingsRow("Ignore", description: filterDescription) {
                    Picker("Ignore", selection: $tracker.syntheticStrength) {
                        Text("Off").tag(SyntheticFilter.Strength.off)
                        Text("Standard").tag(SyntheticFilter.Strength.normal)
                        Text("Strict").tag(SyntheticFilter.Strength.strict)
                    }
                    .segmentedStyle()
                }
            }
            SettingsSection("Capture") {
                SettingsRow("Listener", description: captureDescription) { EmptyView() }
            }
            SettingsSection("Data") {
                SettingsRow("Export every session as CSV", description: exportError) {
                    Button("Export…", action: export)
                }
                SettingsRow("Delete all history", description: "Removes every session, dictation and statistic from this Mac. This can't be undone.") {
                    Button("Delete…", role: .destructive) { confirmingReset = true }
                }
            }
            SettingsSection("Updates") {
                SettingsRow("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") { EmptyView() }
                SettingsRow("Check for updates automatically", description: "Once a day.") {
                    Toggle("Check for updates automatically", isOn: $updates.checksAutomatically).toggleStyle(.switch).labelsHidden()
                }
                SettingsRow("Check now", description: updateStatus) {
                    if updates.release != nil {
                        Button("Show Update") { updates.checkNow() }
                    } else {
                        Button("Check for Updates") { updates.checkNow() }
                            .disabled(!updates.canCheck || updates.check == .checking)
                    }
                }
            }
        }
        .onAppear { updates.refreshLastChecked() }
        .confirmationDialog("Delete all history?", isPresented: $confirmingReset) {
            Button("Delete All History", role: .destructive) { tracker.deleteAllHistory() }
        } message: {
            Text("This can't be undone.")
        }
        .confirmationDialog("Delete all voice history?", isPresented: $confirmingVoiceReset) {
            Button("Delete Voice History", role: .destructive) { tracker.deleteVoiceHistory() }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var updateStatus: String? {
        if let release = updates.release { return "Keypace \(release.version) is available." }
        switch updates.check {
        case .checking: return "Checking…"
        case .upToDate: return "Keypace is up to date."
        case .failed: return "Couldn't check. Try again in a moment."
        case .idle:
            guard let date = updates.lastChecked else { return nil }
            return "Last checked \(date.formatted(.relative(presentation: .named)))."
        }
    }

    private var minimumCharacters: Binding<Double> {
        Binding(get: { Double(tracker.minimumCharacters) }, set: { tracker.minimumCharacters = Int($0) })
    }

    private var captureDescription: String {
        let health = tracker.captureHealth
        let since = health.startedAt.formatted(date: .abbreviated, time: .omitted)
        let summary: String
        if let last = health.lastOccurrence {
            let pauses = health.listenerPauses
            let unreadable = health.unreadableKeys
            summary = "Since \(since), macOS paused the listener \(pauses) \(pauses == 1 ? "time" : "times") and \(unreadable) key \(unreadable == 1 ? "event couldn't" : "events couldn't") be read. Last occurrence: \(last.formatted(date: .abbreviated, time: .shortened))."
        } else {
            summary = "No capture issues recorded since \(since)."
        }
        return summary + " Presses during a pause can't be counted."
    }

    private var filterDescription: String {
        switch tracker.syntheticStrength {
        case .off: "Every keystroke counts, including ones sent by text expanders and automation."
        case .normal: "Keystrokes sent by other apps, such as text expanders, don't count toward your speed."
        case .strict: "Also drops keystrokes that arrive faster than a person can type."
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
    @State private var offerDeletion: String?

    var body: some View {
        SettingsPage(title: "Tracking") {
            SettingsSection("Apps") {
                SettingsRow("Track", description: tracker.filter.mode == .allExcept
                            ? "Typing in the apps below isn't recorded."
                            : "Only typing in the apps below is recorded.") {
                    Picker("Track", selection: $tracker.filter.mode) {
                        Text("Every app except these").tag(AppFilter.Mode.allExcept)
                        Text("Only these apps").tag(AppFilter.Mode.only)
                    }
                    .segmentedStyle()
                }
                ForEach(tracker.filter.appIDs, id: \.self) { appID in
                    SettingsRow(AppInfo.name(appID), icon: AppInfo.icon(appID)) {
                        Button("Remove") { tracker.filter.appIDs.removeAll { $0 == appID } }
                    }
                }
                SettingsRow(tracker.filter.appIDs.isEmpty ? "No apps yet" : "Add another app") {
                    Button("Add App…", action: addApp)
                }
            }
        }
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

/// The newer version, Update Now, and what changed, as System Settings shows a macOS update.
struct UpdatePage: View {
    private let updates = Updates.shared

    var body: some View {
        SettingsPage(title: "Software Update") {
            if let release = updates.release {
                SettingsSection("") {
                    HStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keypace \(release.version)").font(.headline)
                            Text(status(of: release))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 12)
                        action
                            .frame(minWidth: 120, alignment: .trailing)
                    }
                    .padding(.vertical, 12)
                    if !release.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(release.notes, id: \.self) { note in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(note).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    @ViewBuilder private var action: some View {
        switch updates.phase {
        case .ready:
            Button("Update Now") { updates.install() }
                .buttonStyle(.borderedProminent)
        case .downloading(let received, let total):
            ProgressView(value: Double(received), total: Double(max(total, received, 1)))
                .frame(width: 120)
        case .installing:
            ProgressView()
                .progressViewStyle(.linear)
                .frame(width: 120)
        case .failed:
            Button("Try Again") { updates.install() }
        }
    }

    private func status(of release: Updates.Release) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // "0 KB", not "Zero KB", as the download starts.
        formatter.allowsNonnumericFormatting = false
        let size = { (bytes: Int64) in formatter.string(fromByteCount: bytes) }
        return switch updates.phase {
        case .ready: size(release.size)
        case .downloading(let received, let total): "Downloading… \(size(received)) of \(size(max(total, received)))"
        case .installing: "Installing… Keypace will reopen."
        case .failed: "The update didn't finish."
        }
    }
}

// MARK: Building blocks

/// A scrolling settings page with a title.
private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.title2.weight(.semibold))
                content
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(title)
    }
}

/// A titled group of rows on one rounded surface, with hairlines between rows.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty { Text(title).font(.headline) }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider() }
                        row
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.group, in: .rect(cornerRadius: 12))
        }
        .padding(.top, 20)
    }
}

/// Label on the left with a value or a small control on the right; a wide control such as a slider
/// goes on its own line below. A plain description closes the row.
private struct SettingsRow<Control: View>: View {
    let title: String
    var value: String?
    var description: String?
    var icon: NSImage?
    @ViewBuilder var control: Control

    init(_ title: String, value: String? = nil, description: String? = nil, icon: NSImage? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.value = value
        self.description = description
        self.icon = icon
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                Text(title)
                Spacer(minLength: 12)
                if let value {
                    Text(value).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    control
                }
            }
            if value != nil { control }
            if let description {
                Text(description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 11)
    }
}

/// A slider with its end values written under each end.
private struct TickedSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let low: String
    let high: String

    var body: some View {
        VStack(spacing: 2) {
            Slider(value: $value, in: range, step: step).labelsHidden()
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }
}

private extension View {
    func segmentedStyle() -> some View {
        pickerStyle(.segmented).labelsHidden().fixedSize()
    }
}
