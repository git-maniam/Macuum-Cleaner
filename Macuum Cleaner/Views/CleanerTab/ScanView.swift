import SwiftUI
import AppKit
import MacuumCore

struct ScanView: View {
    @Bindable var model: CleanerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar.frame(width: 300)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ActionBar(model: model)
        }
        .sheet(isPresented: $model.showConfirm) { CleanConfirmView(model: model) }
        .sheet(isPresented: $model.showFDASheet) { FullDiskAccessSheet { model.fdaSheetDismissed() } }
        .sheet(item: $model.cleanSummary) { summary in CleanSummaryView(summary: summary, model: model) }
        #if DEBUG
        .task { if ProcessInfo.processInfo.environment["MACUUM_AUTOSCAN"] == "1" { model.startScan() } }
        #endif
    }

    private var sidebar: some View {
        List(selection: $model.selectedCategory) {
            ForEach(CategoryGroup.allCases, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(JunkCategory.allCases.filter { $0.group == group && $0 != .languageFiles }) { c in
                        CategoryRowView(category: c, model: model).tag(c)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private var detail: some View {
        VStack(spacing: 0) {
            if let r = model.result, r.wasCancelled {
                banner("Scan incomplete — showing partial results.", systemImage: "exclamationmark.circle", color: .yellow)
            }
            if model.skippedForFullDiskAccess {
                HStack {
                    Label("Some locations were skipped because Full Disk Access isn't granted.", systemImage: "lock.fill")
                    Spacer()
                    Button("Grant Access…") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                }
                .font(.callout).padding(10).background(.orange.opacity(0.14))
            }
            if model.isScanning {
                ScanningHero(model: model)
            } else if let c = model.selectedCategory, model.result != nil, !model.files(in: c).isEmpty {
                FileListView(category: c, model: model)
            } else if let r = model.result {
                ResultsSummaryView(model: model, result: r)
            } else {
                WelcomeHero(model: model)
            }
        }
    }

    private func banner(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage).font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(color.opacity(0.16))
    }
}

// MARK: - States

private struct WelcomeHero: View {
    @Bindable var model: CleanerViewModel
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            Text("Reclaim your disk space").font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Scan for caches, logs, leftovers and more. You review everything before anything is removed.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button { model.startScan() } label: { Label("Scan Now", systemImage: "sparkle.magnifyingglass") }
                .buttonStyle(.primaryAction()).controlSize(.large).padding(.top, 6)
            Text("Nothing leaves your Mac · Files go to the Trash by default").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScanningHero: View {
    @Bindable var model: CleanerViewModel
    private var found: Int { model.liveCounts.values.reduce(0, +) }
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).scaleEffect(1.4).padding(.bottom, 8)
            Text("Scanning your Mac…").font(.system(size: 24, weight: .bold, design: .rounded))
            Text("\(found.formatted()) items found so far").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            Text(model.statusLine).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 420)
        }
        .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ResultsSummaryView: View {
    @Bindable var model: CleanerViewModel
    let result: ScanResult

    private var rows: [(JunkCategory, Int64)] {
        JunkCategory.allCases.map { ($0, result.size(of: $0)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        if rows.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text("Your Mac is tidy").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Nothing to clean in the selected categories.").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 2) {
                        Text(ByteFormatter.string(from: result.totalSize))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                        Text("found in \(result.totalFileCount.formatted()) items · pick a category to review").foregroundStyle(.secondary)
                    }.padding(.top, 28)

                    VStack(spacing: 0) {
                        ForEach(rows, id: \.0) { cat, size in
                            Button { model.selectedCategory = cat } label: {
                                HStack(spacing: 12) {
                                    IconTile(symbol: cat.symbol, tint: cat.tint, size: 28)
                                    Text(cat.displayName)
                                    Spacer()
                                    GeometryReader { geo in
                                        Capsule().fill(cat.tint.opacity(0.25))
                                            .overlay(alignment: .leading) {
                                                Capsule().fill(cat.tint).frame(width: max(4, geo.size.width * CGFloat(size) / CGFloat(rows[0].1)))
                                            }
                                    }.frame(width: 110, height: 6)
                                    Text(ByteFormatter.string(from: size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 8).padding(.horizontal, 12).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if cat != rows.last?.0 { Divider().padding(.leading, 52) }
                        }
                    }
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 24).padding(.bottom, 20)
                }
            }
        }
    }
}

// MARK: - Action bar

private struct ActionBar: View {
    @Bindable var model: CleanerViewModel

    var body: some View {
        HStack(spacing: 16) {
            if model.isScanning {
                Button { model.cancelScan() } label: { Label("Cancel", systemImage: "xmark") }
                    .buttonStyle(.bordered).controlSize(.large)
                Label { Text("Scanning…") } icon: { ProgressView().controlSize(.small) }
                    .font(.headline).foregroundStyle(.secondary)
            } else {
                Button { model.startScan() } label: { Label(model.result == nil ? "Scan Now" : "Scan Again", systemImage: "sparkle.magnifyingglass") }
                    .buttonStyle(.primaryAction())
                    .keyboardShortcut("r")
                    .disabled(model.isCleaning)
                    .accessibilityLabel("Scan now")
            }

            VStack(alignment: .leading, spacing: 1) {
                if model.isCleaning {
                    ProgressView(value: model.cleanFraction).frame(width: 140)
                    Text("Cleaning…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(ByteFormatter.string(from: model.result?.totalSize ?? 0) + " found")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text("Last scan: \(model.lastScanDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button { model.requestClean() } label: {
                Label(model.selectedSize > 0 ? "Clean Selected · \(ByteFormatter.string(from: model.selectedSize))" : "Clean Selected",
                      systemImage: "trash.fill")
            }
            .buttonStyle(.primaryAction(.red))
            .disabled(model.selectedFiles.isEmpty || model.isScanning || model.isCleaning)
            .accessibilityLabel("Clean selected files")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

struct CleanSummaryView: View {
    let summary: CleanSummary
    let model: CleanerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: summary.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 44)).foregroundStyle(summary.failures.isEmpty ? .green : .orange)
            Text(summary.failures.isEmpty ? "All done" : "Finished with some problems").font(.title2.bold())
            Text("\(summary.removedCount.formatted()) items · \(ByteFormatter.string(from: summary.bytes)) \(summary.permanent ? "permanently deleted" : "moved to Trash").")
                .foregroundStyle(.secondary)
            if summary.diskFull {
                Text("The disk is full, so some items couldn't be moved to Trash." + (model.settings.permanentDeleteEnabled ? " You can delete them permanently instead." : " Enable permanent delete in Settings to remove them directly."))
                    .foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            ForEach(summary.postNotes, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
            if !summary.failures.isEmpty {
                Text("Couldn't remove \(summary.failures.count) item(s):").font(.callout)
                ScrollView { VStack(alignment: .leading) { ForEach(summary.failures, id: \.self) { Text($0).font(.caption) } } }
                    .frame(maxHeight: 100)
            }
            Button("OK") { dismiss() }.buttonStyle(.primaryAction()).keyboardShortcut(.defaultAction).padding(.top, 6)
        }
        .padding(24).frame(width: 460)
    }
}
