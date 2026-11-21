import SwiftUI
import SwiftData

@main
struct NotesApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

private struct AppRootView: View {
    var body: some View {
        let environment = AppEnvironmentProvider.shared
        RootView()
            .environment(environment)
            .modelContainer(environment.container)
            .tint(.accentColor)
    }
}
