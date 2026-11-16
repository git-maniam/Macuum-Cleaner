import SwiftUI
import AppKit
import MacuumCore

struct AppRowView: View {
    let app: InstalledApp
    @Bindable var model: AppManagerViewModel

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { model.checkedIDs.contains(app.id) }, set: { model.setChecked($0, app) }))
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(!model.canUninstall(app))
                .accessibilityLabel("Select \(app.displayName) for uninstall")
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path)).resizable().frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(app.displayName).font(.body.weight(.medium)).lineLimit(1)
                    if app.isSystemApp { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("System app") }
                }
                Text(app.vendorName.isEmpty ? "—" : app.vendorName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let badge = unusedBadge {
                    Text(badge).font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.orange.opacity(0.18), in: Capsule()).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 4)
            Text(ByteFormatter.string(from: app.totalSizeOnDisk)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 52)
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
