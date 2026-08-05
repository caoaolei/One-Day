import SwiftUI

@main
@MainActor
struct YiRiApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("一日") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 960, minHeight: 680)
                .tint(YiRiTheme.accent)
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified)

        Settings {
            ReminderSettingsView()
                .environmentObject(store)
                .frame(width: 560, height: 380)
                .padding()
        }
    }
}
