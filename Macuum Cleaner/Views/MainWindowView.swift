import SwiftUI

struct MainWindowView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case cleaner = "Cleaner"
        case appManager = "App Manager"
        var id: String { rawValue }
        var symbol: String { self == .cleaner ? "sparkles" : "square.grid.2x2.fill" }
    }

    @State private var selection: Tab = Self.initialTab
    @State private var cleaner = CleanerViewModel()
    @State private var appManager = AppManagerViewModel()
    @State private var showSettings = false
    @State private var showAbout = false

    private static var initialTab: Tab {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MACUUM_TAB"] == "appManager" { return .appManager }
        #endif
        return .cleaner
    }

    var body: some View {
        Group {
            switch selection {
            case .cleaner: ScanView(model: cleaner)
            case .appManager: AppManagerView(model: appManager)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $selection) {
                    ForEach(Tab.allCases) { Label(LocalizedStringKey($0.rawValue), systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
                .frame(width: 300)
                .accessibilityLabel("Section")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    .help("Settings").accessibilityLabel("Settings")
                Button { showAbout = true } label: { Label("About", systemImage: "questionmark.circle") }
                    .help("About Macuum Cleaner").accessibilityLabel("About Macuum Cleaner")
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView(model: cleaner, appManager: appManager) }
        .sheet(isPresented: $showAbout) { AboutView() }
    }
}
