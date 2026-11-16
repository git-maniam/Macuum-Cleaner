import SwiftUI
import MacuumCore

struct CleanConfirmView: View {
    @Bindable var model: CleanerViewModel
    @State private var confirmingPermanent = false

    private var breakdown: [(JunkCategory, Int, Int64)] { model.selectedByCategory }
    private var warnings: [String] { Array(Set(breakdown.compactMap { $0.0.warning })).sorted() }
    private var includesTrash: Bool { breakdown.contains { $0.0 == .trash } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You are about to remove \(model.selectedFiles.count.formatted()) files totalling \(ByteFormatter.string(from: model.selectedSize))")
                .font(.headline)

            Table(breakdown.map { Row(category: $0.0, count: $0.1, size: $0.2) }) {
                TableColumn("Category") { Text($0.category.displayName) }
                TableColumn("Files") { Text($0.count.formatted()).monospacedDigit() }.width(70)
                TableColumn("Size to delete") { Text(ByteFormatter.string(from: $0.size)).monospacedDigit() }.width(110)
            }
            .frame(minHeight: 140)

            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout) }
                }
            }
            if includesTrash {
                Label("Emptying the Trash can't be undone.", systemImage: "trash").font(.callout).foregroundStyle(.red)
            }

            if confirmingPermanent {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Are you sure? This cannot be undone.").font(.headline).foregroundStyle(.red)
                    HStack {
                        Button("Back") { confirmingPermanent = false }
                        Button("Yes, Delete Permanently", role: .destructive) { model.clean(method: .permanentDelete) }
                            .buttonStyle(.primaryAction(.red))
                    }
                }
            } else {
                HStack {
                    Button("Cancel", role: .cancel) { model.showConfirm = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    if model.settings.permanentDeleteEnabled {
                        Button("Delete Permanently", role: .destructive) { confirmingPermanent = true }
                            .accessibilityHint("Requires a second confirmation")
                    }
                    Button("Move to Trash") { model.clean(method: .moveToTrash) }
                        .buttonStyle(.primaryAction()).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private struct Row: Identifiable { let category: JunkCategory; let count: Int; let size: Int64; var id: JunkCategory { category } }
}
