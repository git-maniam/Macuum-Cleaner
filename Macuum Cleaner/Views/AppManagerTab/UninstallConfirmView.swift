import SwiftUI
import MacuumCore

struct UninstallConfirmView: View {
    @Bindable var model: AppManagerViewModel
    private var targets: [UninstallTarget] { model.pendingTargets }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(targets.count == 1 ? "Uninstall \(targets[0].app.displayName)?" : "Uninstall \(targets.count) Applications?").font(.headline)
            Table(targets) {
                TableColumn("App") { Text($0.app.displayName) }
                TableColumn("Bundle + Leftovers") { Text(ByteFormatter.string(from: $0.totalSize)).monospacedDigit() }.width(140)
            }
            .frame(minHeight: 100, maxHeight: 220)
            Text("Total to remove: \(ByteFormatter.string(from: targets.reduce(0) { $0 + $1.totalSize }))").bold()
            Text("Files will be moved to Trash and can be recovered until you empty the Trash.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.showConfirm = false; model.pendingTargets = [] }.keyboardShortcut(.cancelAction)
                Button("Move to Trash") { model.confirmUninstall() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 480)
    }
}
