import SwiftUI
import MacuumCore

@main
struct MacuumCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Macuum Cleaner") {
            MainWindowView()
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 920, height: 600)
    }
}
