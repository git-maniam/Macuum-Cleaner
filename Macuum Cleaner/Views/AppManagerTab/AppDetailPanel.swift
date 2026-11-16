import SwiftUI
import AppKit
import MacuumCore

struct AppDetailPanel: View {
    let app: InstalledApp?
    @Bindable var model: AppManagerViewModel

    var body: some View {
        if let app { content(app) }
        else {
            VStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 44)).foregroundStyle(.tertiary)
                Text("Select an app").font(.title3.weight(.semibold))
                Text("See its size and leftover files, and uninstall it cleanly.").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func stat(_ title: String, _ value: Int64, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(ByteFormatter.string(from: value)).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func content(_ app: InstalledApp) -> some View {
        let removable = model.canUninstall(app)
        let leftovers = app.remnants.reduce(Int64(0)) { $0 + $1.size }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path)).resizable().frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.displayName).font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Version \(app.version) · \(app.vendorName)").font(.callout).foregroundStyle(.secondary)
                        Text(app.bundleIdentifier).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
                    }
                }
                Text(app.bundleURL.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).help(app.bundleURL.path)

                HStack(spacing: 10) {
                    stat("App", app.bundleSize)
                    stat("Leftovers", leftovers)
                    stat("Total", app.totalSizeOnDisk, tint: .accentColor)
                }

                Text("LEFTOVER FILES").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 4)
                if app.remnants.isEmpty {
                    Text(app.isSystemApp ? "Leftovers aren't scanned for system apps." : "No leftover files found.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).card()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(app.remnants.enumerated()), id: \.element.id) { i, r in
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(get: { r.isSelected }, set: { model.setRemnant($0, remnantID: r.id, appID: app.id) }))
                                    .toggleStyle(.checkbox).labelsHidden().disabled(!removable)
                                    .accessibilityLabel("Include \(r.kind.rawValue) leftovers")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.kind.rawValue).font(.callout.weight(.medium))
                                    Text((r.url.path as NSString).abbreviatingWithTildeInPath)
                                        .font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary).help(r.url.path)
                                }
                                Spacer()
                                Text(ByteFormatter.string(from: r.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8).padding(.horizontal, 12)
                            if i < app.remnants.count - 1 { Divider().padding(.leading, 38) }
                        }
                    }
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Total to remove if uninstalled").foregroundStyle(.secondary)
                        Spacer()
                        Text(ByteFormatter.string(from: model.selectedTotal(for: app))).font(.system(.title2, design: .rounded).weight(.bold))
                    }
                    HStack(spacing: 10) {
                        Button { model.requestUninstall(app, includeLeftovers: true) } label: {
                            Label("Uninstall App + Leftovers", systemImage: "trash.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.primaryAction(.red)).disabled(!removable)
                        Button { model.requestUninstall(app, includeLeftovers: false) } label: {
                            Text("App Only")
                        }.buttonStyle(.bordered).controlSize(.large).disabled(!removable)
                        Button { model.revealInFinder(app) } label: {
                            Image(systemName: "folder")
                        }.buttonStyle(.bordered).controlSize(.large).help("Open in Finder").accessibilityLabel("Open in Finder")
                    }
                    if !removable { Label("System apps cannot be removed.", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.top, 6)
            }
            .padding(20)
        }
    }
}
