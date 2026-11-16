import SwiftUI

struct MainWindowView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case cleaner = "Cleaner"
        case appManager = "App Manager"
        var id: String { rawValue }
    }

    @State private var selection: Tab = .cleaner
    @State private var cleaner = CleanerViewModel()
    @State private var appManager = AppManagerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selection) {
                ForEach(Tab.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .padding(10)
            Divider()
            switch selection {
            case .cleaner: ScanView(model: cleaner)
            case .appManager: AppManagerView(model: appManager)
            }
        }
    }
}
