import SwiftUI
import MacuumCore

struct AppManagerView: View {
    @Bindable var model: AppManagerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search apps…", text: $model.search).textFieldStyle(.plain)
                        .accessibilityLabel("Search apps by name or bundle ID")
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(.quaternary.opacity(0.6), in: Capsule()).frame(maxWidth: 300)
                Spacer()
                Menu {
                    Picker("Sort", selection: $model.sort) { ForEach(AppSortOrder.menuOrder, id: \.self) { Text($0.title).tag($0) } }
                } label: { Label(model.sort.title, systemImage: "arrow.up.arrow.down") }
                    .menuStyle(.button).fixedSize()
                Menu {
                    Picker("Filter", selection: $model.filter) { ForEach(AppFilter.allCases) { Text($0.rawValue).tag($0) } }
                } label: { Label(model.filter.rawValue, systemImage: "line.3.horizontal.decrease.circle") }
                    .menuStyle(.button).fixedSize()
            }
            .padding(12)
            Divider()
            HStack(spacing: 0) {
                AppListView(model: model).frame(width: 340)
                Divider()
                AppDetailPanel(app: model.selectedApp, model: model).frame(maxWidth: .infinity)
            }
            Divider()
            statusBar
        }
        .task { if model.apps.isEmpty { await model.load() } }
        .sheet(isPresented: $model.showConfirm) { UninstallConfirmView(model: model) }
        .sheet(item: $model.summary) { UninstallSummaryView(summary: $0) }
        .alert("Quit \(model.runningPrompt?.displayName ?? "the app") before uninstalling?",
               isPresented: Binding(get: { model.runningPrompt != nil }, set: { _ in })) {
            Button("Quit and Continue") { model.answerQuitPrompt(true) }
            Button("Cancel", role: .cancel) { model.answerQuitPrompt(false) }
        }
        .alert(model.alertMessage ?? "", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK") { model.alertMessage = nil }
        }
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                Text(t).padding(10).background(.thinMaterial, in: Capsule()).padding(.bottom, 56).transition(.opacity)
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if model.isUninstalling {
                ProgressView().controlSize(.small)
                Text(model.progressText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("\(model.apps.count) apps  ·  Total: \(ByteFormatter.string(from: model.totalSize))").font(.caption)
            }
            Spacer()
            Button("Refresh") { Task { await model.load() } }.disabled(model.isLoading || model.isUninstalling)
            if !model.checkedIDs.isEmpty {
                Button { model.requestBatchUninstall() } label: { Label("Uninstall Selected (\(model.checkedIDs.count))", systemImage: "trash.fill") }
                    .buttonStyle(.primaryAction(.red)).disabled(model.isUninstalling)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

struct UninstallSummaryView: View {
    let summary: UninstallSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(summary.permissionDenied.isEmpty && summary.otherErrors.isEmpty ? "Done" : "Finished with some problems",
                  systemImage: summary.permissionDenied.isEmpty && summary.otherErrors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2.bold())
            if !summary.removedApps.isEmpty {
                Text("\(summary.removedApps.joined(separator: ", ")) uninstalled. \(ByteFormatter.string(from: summary.bytes)) moved to Trash.")
            }
            if !summary.permissionDenied.isEmpty {
                Text("Some files could not be removed (permission denied):").foregroundStyle(.orange)
                ScrollView { VStack(alignment: .leading) { ForEach(summary.permissionDenied, id: \.self) { Text($0).font(.caption).textSelection(.enabled) } } }.frame(maxHeight: 90)
            }
            ForEach(summary.otherErrors, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("OK") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 480)
    }
}
