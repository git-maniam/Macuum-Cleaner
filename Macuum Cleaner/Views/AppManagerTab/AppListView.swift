import SwiftUI
import MacuumCore

struct AppListView: View {
    @Bindable var model: AppManagerViewModel

    var body: some View {
        List(selection: $model.selectedID) {
            ForEach(model.visibleApps) { app in
                AppRowView(app: app, model: model).tag(app.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if model.isLoading && model.apps.isEmpty { ProgressView("Discovering apps…") }
            else if model.visibleApps.isEmpty { Text("No apps match.").foregroundStyle(.secondary) }
        }
    }
}
