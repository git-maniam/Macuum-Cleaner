import SwiftUI
import AppKit
import MacuumCore

struct AppDetailPanel: View {
    let app: InstalledApp?
    @Bindable var model: AppManagerViewModel

    var body: some View {
        if let app { content(app) }
        else {
            VStack(spacing: 8) {
                Image(systemName: "shippingbox").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("Select an app to see its details and leftover files.").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(_ app: InstalledApp) -> some View {
        let removable = model.canUninstall(app)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path)).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.displayName).font(.title2.bold())
                        Text("Version \(app.version) · Bundle ID: \(app.bundleIdentifier)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(app.bundleURL.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(app.bundleURL.path)
                    }
                }
                HStack {
                    Text("App bundle").bold(); Spacer()
                    Text(ByteFormatter.string(from: app.bundleSize)).monospacedDigit()
                }
                Divider()
                HStack {
                    Text("LEFTOVER FILES").font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(ByteFormatter.string(from: app.remnants.reduce(0) { $0 + $1.size })) total").font(.caption).foregroundStyle(.secondary)
                }
                if app.remnants.isEmpty {
                    Text(app.isSystemApp ? "Leftovers aren't scanned for system apps." : "No leftover files found.").foregroundStyle(.secondary)
                }
                ForEach(app.remnants) { r in
                    HStack {
                        Toggle("", isOn: Binding(get: { r.isSelected }, set: { model.setRemnant($0, remnantID: r.id, appID: app.id) }))
                            .toggleStyle(.checkbox).labelsHidden().disabled(!removable)
                            .accessibilityLabel("Include \(r.kind.rawValue) leftovers")
                        Text(r.kind.rawValue).frame(width: 150, alignment: .leading)
                        Text((r.url.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary).help(r.url.path)
                        Spacer()
                        Text(ByteFormatter.string(from: r.size)).monospacedDigit()
                    }
                    .font(.callout)
                }
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total to remove if uninstalled:").font(.callout).foregroundStyle(.secondary)
                    Text(ByteFormatter.string(from: model.selectedTotal(for: app))).font(.title2.bold())
                }
                VStack(spacing: 8) {
                    Button { model.requestUninstall(app, includeLeftovers: true) } label: {
                        Text("Uninstall App + Leftovers").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).disabled(!removable)
                    Button { model.requestUninstall(app, includeLeftovers: false) } label: {
                        Text("Uninstall App Only").frame(maxWidth: .infinity)
                    }.disabled(!removable)
                    Button { model.revealInFinder(app) } label: {
                        Text("Open in Finder").frame(maxWidth: .infinity)
                    }
                }
                .controlSize(.large)
                .help(removable ? "" : "System apps cannot be removed.")
            }
            .padding(16)
        }
    }
}
