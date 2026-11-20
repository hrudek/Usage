import SwiftUI
import WidgetKit
import UsageKit

struct ContentView: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.scenePhase) private var scenePhase
    /// The Dashboard's navigation, held here so the "Open Account" intent
    /// can open an account's detail in it.
    @State private var path = NavigationPath()
    var body: some View {
        dashboard
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundRefresh.scheduleNext()
            }
            if phase == .active {
                // Always re-render widgets from the foreground, even when
                // the fetch below fails or is throttled — otherwise a
                // freshly updated app can leave placed widgets showing
                // WidgetKit's archived render of the previous version.
                WidgetReload.all()
                Task {
                    // The user may have flipped the permission in Settings.
                    await model.refreshNotificationAuthorization()
                    // Coming back to the foreground: fetch fresh usage
                    // (throttled) so app and widgets update right away.
                    await model.refreshAllIfStale()
                }
            }
        }
        .task {
            await model.refreshAll()
        }
    }

    private var dashboard: some View {
        NavigationStack(path: $path) {
            // The Dashboard draws its own header, and hides the navigation
            // bar itself but on iPhone Duo's side bar (`DashboardSideBar`).
            DashboardView()
        }
        // An account disconnected (from its own settings page or
        // Settings): back to the Dashboard, since the detail and the
        // settings page in the stack have nothing left to show.
        .onChange(of: model.accounts.map(\.account.accountID)) { old, new in
            if !Set(old).isSubset(of: Set(new)), !path.isEmpty {
                path = NavigationPath()
            }
        }
        // The "Open Account" intent (Shortcuts, Siri).
        .onChange(of: model.accountToOpen) { _, accountID in
            guard let accountID else { return }
            model.accountToOpen = nil
            path = NavigationPath()
            path.append(accountID)
        }
    }
}

#Preview {
    ContentView()
        .environment(UsageModel())
        .environment(PreferencesModel())
}
