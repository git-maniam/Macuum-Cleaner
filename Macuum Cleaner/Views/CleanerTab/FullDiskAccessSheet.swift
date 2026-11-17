import SwiftUI
import AppKit
import MacuumCore

enum AppRelaunch {
    /// Starts a fresh instance after this one exits (macOS applies Full Disk Access only to newly started processes).
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}

struct FullDiskAccessSheet: View {
    let onContinue: () -> Void
    @State private var granted = FullDiskAccess.isGranted()
    @State private var openedSettings = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(symbol: granted ? "checkmark.shield.fill" : "lock.shield.fill", tint: granted ? .green : .blue, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(granted ? "Full Disk Access is on" : "Allow Full Disk Access").font(.title2.bold())
                    Text("Optional, but it lets Macuum Cleaner scan protected locations.").font(.callout).foregroundStyle(.secondary)
                }
            }

            if granted {
                Text("You're all set. Protected locations such as /Library, system logs, temporary folders, the Trash and iPhone backups will be included in scans.")
            } else {
                Text("Without it, those locations are skipped and everything else still works. macOS only lets you turn this on yourself, and nothing leaves your Mac.")
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Click **Open System Settings** below.")
                    step(2, "Switch on **Macuum Cleaner** in the Full Disk Access list. If it isn't listed, drag the icon below into the list, or click **+**.")
                    step(3, "Click **Relaunch**. macOS applies the permission to newly started apps.")
                }
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                        .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
                        .help("Drag into System Settings → Full Disk Access")
                        .accessibilityLabel("Macuum Cleaner app icon. Drag it into the Full Disk Access list.")
                    Text("Drag this icon into the Full Disk Access list").font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                }
                .card()
            }

            HStack {
                if granted {
                    Spacer()
                    Button("Continue", action: onContinue).buttonStyle(.primaryAction()).keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue Without", action: onContinue)
                    Spacer()
                    if openedSettings {
                        Button("Relaunch") { AppRelaunch.relaunch() }.buttonStyle(.bordered).controlSize(.large)
                            .help("Quit and reopen Macuum Cleaner so the new permission takes effect")
                    }
                    Button { NSWorkspace.shared.open(FullDiskAccess.settingsURL); openedSettings = true } label: {
                        Label("Open System Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.primaryAction()).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .onReceive(timer) { _ in granted = FullDiskAccess.isGranted() }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.caption.bold()).foregroundStyle(.white).frame(width: 20, height: 20)
                .background(Circle().fill(.blue))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
