import SwiftUI
import UsageKit

@main
struct AIMeterApp: App {
    @State private var model = UsageModel()
    @State private var prefs: PreferencesModel

    init() {
        let prefs = PreferencesModel()
        _prefs = State(initialValue: prefs)
        // The notch island lives outside the scene graph, and gets the app's
        // one `PreferencesModel` here, before any window: a launch that
        // restores some other window instead of the Dashboard (whose
        // `onAppear` hands it over as well) must still start the island.
        // iCloud sync applies another device's preferences through it, on
        // both platforms.
        AppEnvironment.prefs = prefs
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

    /// Identifies the dashboard scene so the macOS AppDelegate can reopen it
    /// by id after both icons have been hidden.
    static let dashboardWindowID = "dashboard"
    /// The macOS update window (`UpdateWindow`).
    static let updateWindowID = "update"
    /// The macOS tour window (`TourWindow`).
    static let tourWindowID = "tour"
}
