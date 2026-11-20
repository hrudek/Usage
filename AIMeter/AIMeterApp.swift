import SwiftUI
import UsageKit

@main
struct AIMeterApp: App {
    @State private var model = UsageModel()
    @State private var prefs: PreferencesModel

    init() {
        let prefs = PreferencesModel()
        _prefs = State(initialValue: prefs)
    }

    var body: some Scene {
        WindowGroup(id: Self.dashboardWindowID) {
            ContentView()
                .environment(model)
                .environment(prefs)
                .tint(Theme.accent)
                .preferredColorScheme(prefs.appearance.colorScheme)
        }
        .backgroundTask(.appRefresh(AppConfig.refreshTaskID)) {
            await BackgroundRefresh.scheduleNext()
            await UsageModel.refreshAllInBackground()
        }

    }

    /// Identifies the dashboard scene.
    static let dashboardWindowID = "dashboard"
}
