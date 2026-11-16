import SwiftUI
import MacuumCore

struct CategoryRowView: View {
    let category: JunkCategory
    @Bindable var model: CleanerViewModel

    private var files: [JunkFile] { model.files(in: category) }
    private var hasResult: Bool { model.result != nil }
    private var isDimmed: Bool { hasResult && files.isEmpty && model.isEnabled(category) }

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { model.isEnabled(category) }, set: { model.setEnabled(category, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(model.isScanning)
                .accessibilityLabel("Include \(category.displayName) in scan")
            VStack(alignment: .leading, spacing: 1) {
                Text(category.displayName).font(.body)
                detail
            }
            Spacer(minLength: 0)
            if model.isScanning && model.pendingCategories.contains(category) { ProgressView().controlSize(.small) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .opacity(isDimmed || !model.isEnabled(category) ? 0.5 : 1)
        .help(category.summary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var detail: some View {
        if model.isScanning, let n = model.liveCounts[category] {
            Text("\(n.formatted()) found…").font(.caption).foregroundStyle(.secondary)
        } else if let reason = model.result?.skipped[category] {
            Label(reason, systemImage: "lock").font(.caption).foregroundStyle(.orange)
        } else if hasResult, model.isEnabled(category) {
            let size = files.reduce(Int64(0)) { $0 + $1.size }
            Text(files.isEmpty ? "Nothing found" : "\(files.count.formatted()) files · \(ByteFormatter.string(from: size))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
