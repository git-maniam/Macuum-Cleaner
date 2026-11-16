import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Macuum Cleaner").font(.title.bold())
            Text(version).foregroundStyle(.secondary)
            Text("A focused, honest disk cleaner. It shows you exactly what will be removed and never deletes without your approval.")
                .multilineTextAlignment(.center).font(.callout)
            Divider()
            Text("Macuum Cleaner does not collect, transmit, or store any personal data. All scanning and cleaning happens entirely on your device. No analytics, no telemetry, no network connections.")
                .multilineTextAlignment(.center).font(.caption).foregroundStyle(.secondary)
            Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(24).frame(width: 420)
    }
}
