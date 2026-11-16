import SwiftUI
import AppKit
import MacuumCore

struct FileListView: View {
    let category: JunkCategory
    @Bindable var model: CleanerViewModel
    @State private var sortOrder = [KeyPathComparator(\JunkFile.size, order: .reverse)]

    private var files: [JunkFile] { model.files(in: category).sorted(using: sortOrder) }
    private var selectableFiles: [JunkFile] { files.filter { !$0.isAdvisoryOnly } }
    private var allSelected: Bool { !selectableFiles.isEmpty && selectableFiles.allSatisfy(\.isSelected) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let warning = category.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(.orange.opacity(0.1))
            }
            if category == .iOSBackups, model.files(in: category).count > 1 {
                Label("Keep your most recent backup. Nothing here is selected automatically.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 6)
            }
            Table(files, sortOrder: $sortOrder) {
                TableColumn("") { file in
                    Toggle("", isOn: Binding(get: { file.isSelected },
                                             set: { model.setSelected($0, fileID: file.id, in: category) }))
                        .toggleStyle(.checkbox).labelsHidden()
                        .disabled(file.isAdvisoryOnly)
                        .accessibilityLabel("Select \(file.displayName)")
                }.width(28)
                TableColumn("Name", value: \.displayName) { file in
                    HStack(spacing: 6) {
                        Image(nsImage: icon(for: file)).resizable().frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(file.displayName).lineLimit(1)
                            if let note = file.metadata["recommendation"] {
                                Text(note).font(.caption2).foregroundStyle(.orange)
                            } else if file.isAdvisoryOnly {
                                Text("Advisory only — cannot be removed here").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }.help(file.url.path)
                }
                TableColumn("Path") { file in
                    Text(abbreviated(file.url.deletingLastPathComponent().path))
                        .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        .help(file.url.path)
                }
                TableColumn("Size", value: \.size) { file in
                    Text(ByteFormatter.string(from: file.size)).monospacedDigit()
                }.width(min: 70, ideal: 80)
                TableColumn("Modified", value: \.lastModified) { file in
                    Text(file.lastModified.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                }.width(min: 90, ideal: 110)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(category.displayName).font(.title3.bold())
                Text(category.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(allSelected ? "Deselect All" : "Select All") { model.setAll(!allSelected, in: category) }
                .disabled(selectableFiles.isEmpty)
                .accessibilityLabel(allSelected ? "Deselect all files" : "Select all files")
        }
        .padding(10)
    }

    private func icon(for file: JunkFile) -> NSImage {
        file.isFileSystemItem ? NSWorkspace.shared.icon(forFile: file.url.path) : NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil) ?? NSImage()
    }

    private func abbreviated(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
}
