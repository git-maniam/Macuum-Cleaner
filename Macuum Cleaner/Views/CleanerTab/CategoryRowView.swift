import SwiftUI
import MacuumCore

struct CategoryRowView: View {
    let category: JunkCategory
    @Bindable var model: CleanerViewModel

    private var files: [JunkFile] { model.files(in: category) }
    private var hasResult: Bool { model.result != nil }
    private var enabled: Bool { model.isEnabled(category) }
    private var isDimmed: Bool { hasResult && files.isEmpty && enabled }

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: category.symbol, tint: category.tint)
                .saturation(enabled ? 1 : 0.2)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.displayName).font(.body).lineLimit(1)
                detail
            }
            Spacer(minLength: 4)
            if model.isScanning && model.pendingCategories.contains(category) {
                ProgressView().controlSize(.small)
            } else if hasResult, enabled, !files.isEmpty {
                Text(ByteFormatter.string(from: files.reduce(Int64(0)) { $0 + $1.size }))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Toggle("", isOn: Binding(get: { enabled }, set: { model.setEnabled(category, $0) }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .disabled(model.isScanning)
                .accessibilityLabel("Include \(category.displayName) in scan")
        }
        .padding(.vertical, 3)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .opacity(isDimmed || !enabled ? 0.55 : 1)
        .help(category.summary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var detail: some View {
        if model.isScanning, let n = model.liveCounts[category] {
            Text("\(n.formatted()) found…").font(.caption).foregroundStyle(.secondary)
        } else if let reason = model.result?.skipped[category] {
            Label(reason, systemImage: "lock").font(.caption).foregroundStyle(.orange)
        } else if hasResult, enabled {
            Text(files.isEmpty ? "Nothing found" : "\(files.count.formatted()) files")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text(category.risk == .safe ? "Safe to remove" : category.risk == .caution ? "Review first" : "Your data — manual review")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}
