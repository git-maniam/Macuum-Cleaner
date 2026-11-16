import SwiftUI
import AppKit
import MacuumCore

struct SettingsView: View {
    @Bindable var model: CleanerViewModel
    let appManager: AppManagerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmPermanent = false
    @State private var confirmReset = false
    @State private var scheduleError: String?

    private func bind<T>(_ kp: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: kp] }, set: { v in model.updateSettings { $0[keyPath: kp] = v } })
    }

    private var scheduleKey: String {
        let s = model.settings
        return "\(s.scheduledScanEnabled)-\(s.scheduledScanDayOfWeek)-\(s.scheduledScanHour)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Scanning") {
                    Toggle("Show hidden files in results", isOn: bind(\.showHiddenFiles))
                    Toggle("Include system-level paths", isOn: bind(\.scanSystemPaths))
                    if model.settings.scanSystemPaths && !model.hasFullDiskAccess {
                        HStack {
                            Label("Full Disk Access is required for system paths.", systemImage: "lock").foregroundStyle(.orange)
                            Spacer()
                            Button("Open System Settings") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                        }.font(.callout)
                    }
                    Toggle("Include com.apple.* preferences in Orphaned Preferences", isOn: bind(\.includeApplePreferences))
                    Stepper("Old screenshots: older than \(model.settings.oldScreenshotThresholdDays) days",
                            value: bind(\.oldScreenshotThresholdDays), in: 1...365)
                    Stepper("Old downloads: older than \(model.settings.oldDownloadThresholdDays) days",
                            value: bind(\.oldDownloadThresholdDays), in: 1...365)
                }

                Section("Scheduled scan") {
                    Toggle("Weekly scan with notification", isOn: bind(\.scheduledScanEnabled))
                    if model.settings.scheduledScanEnabled {
                        Picker("Day", selection: bind(\.scheduledScanDayOfWeek)) {
                            ForEach(Self.days, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        Picker("Time", selection: bind(\.scheduledScanHour)) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }
                        Text("A background agent runs a scan and notifies you. It never cleans anything on its own.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let e = scheduleError { Text(e).font(.caption).foregroundStyle(.red) }
                }

                Section("Exclusions — never scanned or deleted") {
                    ForEach(model.settings.excludedPaths, id: \.self) { path in
                        HStack {
                            Text((path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle).help(path)
                            Spacer()
                            Button { model.updateSettings { $0.excludedPaths.removeAll { $0 == path } } } label: {
                                Image(systemName: "minus.circle")
                            }.buttonStyle(.borderless).accessibilityLabel("Remove \(path) from exclusions")
                        }
                    }
                    Button("Add Folder or File…") { addExclusion() }
                }

                Section("App Manager") {
                    Toggle("Show system apps", isOn: bind(\.appManagerShowSystemApps))
                    Toggle("Look for Launch Daemons (needs Full Disk Access)", isOn: bind(\.appManagerScanLaunchDaemons))
                    Stepper("Unused apps: not opened in \(model.settings.unusedAppThresholdDays) days",
                            value: bind(\.unusedAppThresholdDays), in: 7...730)
                    Picker("Default sort", selection: bind(\.appManagerDefaultSort)) {
                        ForEach(AppSortOrder.menuOrder, id: \.self) { Text($0.title).tag($0) }
                    }
                }

                Section("Danger zone") {
                    Toggle("Enable “Delete Permanently”", isOn: Binding(
                        get: { model.settings.permanentDeleteEnabled },
                        set: { on in if on { confirmPermanent = true } else { model.updateSettings { $0.permanentDeleteEnabled = false } } }))
                    Text("Adds an irreversible delete option to the clean confirmation. Uninstalling apps always uses the Trash.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(10)
        }
        .frame(width: 580, height: 660)
        .onChange(of: scheduleKey) { _, _ in applySchedule() }
        .alert("Enable permanent delete?", isPresented: $confirmPermanent) {
            Button("Enable", role: .destructive) { model.updateSettings { $0.permanentDeleteEnabled = true } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Permanently deleted files cannot be recovered.") }
        .alert("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { reset() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This restores defaults and removes the scheduled scan. Your files are not affected.") }
    }

    static let days: [(Int, String)] = [(1, "Monday"), (2, "Tuesday"), (3, "Wednesday"), (4, "Thursday"), (5, "Friday"), (6, "Saturday"), (0, "Sunday")]

    private func addExclusion() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        model.updateSettings { s in
            for u in panel.urls where !s.excludedPaths.contains(u.path) { s.excludedPaths.append(u.path) }
        }
    }

    private func applySchedule() {
        let settings = model.settings
        scheduleError = nil
        Task {
            do {
                try await ScheduleManager.apply(settings)
                if settings.scheduledScanEnabled { Notifier.requestAuthorization() }
            } catch { scheduleError = "Couldn't update the schedule: \(error.localizedDescription)" }
        }
    }

    private func reset() {
        SettingsStore().reset()
        model.reloadSettings()
        Task { try? await ScheduleManager.apply(AppSettings()) }
    }
}
