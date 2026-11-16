import SwiftUI
import AppKit
import MacuumCore

struct FullDiskAccessSheet: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Full Disk Access", systemImage: "lock.shield").font(.title2.bold())
            Text("Macuum Cleaner can scan your user folders right away. To also scan protected locations such as /Library, system logs, temporary folders, the Trash and iPhone backups, grant Full Disk Access:")
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Open System Settings → Privacy & Security → Full Disk Access")
                Text("2. Switch on Macuum Cleaner (add it with + if it isn't listed)")
                Text("3. Reopen Macuum Cleaner if macOS asks you to")
            }.foregroundStyle(.secondary)
            Text("Without it those locations are skipped; everything else still works. Nothing leaves your Mac.").font(.callout)
            HStack {
                Button("Open System Settings") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                Spacer()
                Button("Scan Without It", action: onContinue).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
