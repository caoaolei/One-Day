import SwiftUI

@main
@MainActor
struct YiRiApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var worktime = WorktimeController()

    var body: some Scene {
        WindowGroup("一日") {
            RootView()
                .environmentObject(store)
                .environmentObject(worktime)
                .frame(minWidth: 960, minHeight: 680)
                .tint(YiRiTheme.accent)
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified)

        Settings {
            ScrollView {
                VStack(spacing: 16) {
                    ReminderSettingsView()
                    WorktimeSettingsPanel()
                }
                .padding()
            }
            .environmentObject(store)
            .environmentObject(worktime)
            .frame(width: 620, height: 650)
        }
    }
}
