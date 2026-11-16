import SwiftUI
import AppKit
import MacuumCore

struct AppRowView: View {
    let app: InstalledApp
    @Bindable var model: AppManagerViewModel

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { model.checkedIDs.contains(app.id) }, set: { model.setChecked($0, app) }))
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(!model.canUninstall(app))
                .accessibilityLabel("Select \(app.displayName) for uninstall")
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path)).resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(app.displayName).lineLimit(1)
                    if app.isSystemApp { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("System app") }
                }
                Text("\(app.vendorName.isEmpty ? "—" : app.vendorName) · \(ByteFormatter.string(from: app.totalSizeOnDisk))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let badge = unusedBadge {
                    Text(badge).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: Capsule()).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .opacity(app.isSystemApp ? 0.6 : 1)
        .contentShape(Rectangle())
    }

    private var unusedBadge: String? {
        guard !app.isSystemApp else { return nil }
        let threshold = SettingsStore().load().unusedAppThresholdDays
        guard app.isUnused(thresholdDays: threshold) else { return nil }
        guard let used = app.lastUsedDate else { return "Never opened" }
        let days = Int(Date().timeIntervalSince(used) / 86_400)
        return days >= 60 ? "Not opened in \(days / 30) months" : "Not opened in \(days) days"
    }
}
