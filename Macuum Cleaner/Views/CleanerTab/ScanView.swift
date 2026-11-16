import SwiftUI
import AppKit
import MacuumCore

struct ScanView: View {
    @Bindable var model: CleanerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                sidebar.frame(minWidth: 250, idealWidth: 290, maxWidth: 360)
                detail.frame(minWidth: 400)
            }
            Divider()
            bottomBar
        }
        .sheet(isPresented: $model.showConfirm) { CleanConfirmView(model: model) }
        .sheet(isPresented: $model.showFDASheet) { FullDiskAccessSheet { model.fdaSheetDismissed() } }
        .sheet(item: $model.cleanSummary) { summary in CleanSummaryView(summary: summary, model: model) }
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
                    Label("Some locations were skipped because Full Disk Access isn't granted.", systemImage: "lock")
                    Spacer()
                    Button("Grant Access…") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                }
                .padding(8).background(.orange.opacity(0.12))
            }
            if let c = model.selectedCategory, model.result != nil, !model.files(in: c).isEmpty {
                FileListView(category: c, model: model)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: model.result == nil ? "sparkles" : "checkmark.circle").font(.system(size: 40)).foregroundStyle(.secondary)
            Text(model.result == nil ? "Select a category to see files, or run a scan to get started."
                                     : "Nothing to clean in this category.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func banner(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(color.opacity(0.15))
    }

    private var bottomBar: some View {
        VStack(spacing: 4) {
            if model.isScanning || model.isCleaning {
                HStack(spacing: 8) {
                    if model.isCleaning { ProgressView(value: model.cleanFraction).frame(width: 160) }
                    Text(model.isCleaning ? "Cleaning…" : model.statusLine)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                }
            }
            HStack {
                if model.isScanning {
                    Button { model.cancelScan() } label: { Label("Cancel", systemImage: "xmark.circle") }
                    ProgressView().controlSize(.small)
                    Text("Scanning…")
                } else {
                    Button { model.startScan() } label: { Label("Scan Now", systemImage: "magnifyingglass") }
                        .keyboardShortcut("r")
                        .disabled(model.isCleaning)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text("Last scan: \(model.lastScanDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")")
                    Text("Total found: \(ByteFormatter.string(from: model.result?.totalSize ?? 0))").bold()
                }
                .font(.caption)
                Spacer()
                Button { model.requestClean() } label: {
                    Label("Clean Selected (\(ByteFormatter.string(from: model.selectedSize)))", systemImage: "trash")
                }
                .disabled(model.selectedFiles.isEmpty || model.isScanning || model.isCleaning)
            }
        }
        .padding(10)
    }
}

struct CleanSummaryView: View {
    let summary: CleanSummary
    let model: CleanerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(summary.failures.isEmpty ? "Done" : "Finished with some problems",
                  systemImage: summary.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").font(.title2.bold())
            Text("\(summary.removedCount.formatted()) items · \(ByteFormatter.string(from: summary.bytes)) \(summary.permanent ? "permanently deleted" : "moved to Trash").")
            if summary.diskFull {
                Text("The disk is full, so some items couldn't be moved to Trash." + (model.settings.permanentDeleteEnabled ? " You can delete them permanently instead." : " Enable permanent delete in Settings to remove them directly."))
                    .foregroundStyle(.orange)
            }
            ForEach(summary.postNotes, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
            if !summary.failures.isEmpty {
                Text("Couldn't remove \(summary.failures.count) item(s):").font(.callout)
                ScrollView { VStack(alignment: .leading) { ForEach(summary.failures, id: \.self) { Text($0).font(.caption) } } }
                    .frame(maxHeight: 100)
            }
            HStack { Spacer(); Button("OK") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 480)
    }
}
