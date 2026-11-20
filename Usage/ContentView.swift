import SwiftUI
import WidgetKit
import UsageKit

struct ContentView: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The Dashboard's navigation, held here so the "Open Account" intent
    /// can open an account's detail in it.
    @State private var path = NavigationPath()
    @State private var shownLayout = DashboardLayout.stack
    @State private var selectedAccountID: String?
    @State private var actions = DashboardActions()

    var body: some View {
        GeometryReader { proxy in
            let layout = DashboardLayout(
                isRegularWidth: sizeClass == .regular,
                size: proxy.size,
                activeFold: Self.activeFold(in: proxy),
                hasAccounts: !model.accounts.isEmpty
            )
            dashboard(layout, in: proxy.size)
                .onAppear { shownLayout = layout }
                .onChange(of: layout) { _, layout in shownLayout = layout }
        }
        .environment(actions)
        .modifier(DashboardPresentations(actions: actions))
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
            selectedAccountID = accountID
            path = NavigationPath()
            if !shownLayout.selectsAccounts {
                path.append(accountID)
            }
        }
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

    private static func activeFold(in proxy: GeometryProxy) -> CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        return proxy.reservedRegions(kind: .division).first?.frame
    }

    @ViewBuilder
    private func dashboard(_ layout: DashboardLayout, in size: CGSize) -> some View {
        let accountIDs = model.accounts.map(\.account.accountID)
        if layout.selectsAccounts,
           let shown = DashboardLayout.shownAccount(selected: selectedAccountID, in: accountIDs) {
            Group {
                if case .aboveAndBelow(let top, let gap) = layout {
                    DashboardPanes(accountID: shown, top: top, gap: gap)
                } else {
                    DashboardSplitView(accountID: shown, sidebarWidth: DashboardLayout.sidebarWidth(in: size))
                }
            }
            .environment(\.accountSelection, AccountSelection(selectedID: shown) { selectedAccountID = $0 })
        } else {
            stack
        }
    }

    private var stack: some View {
        NavigationStack(path: $path) {
            // The Dashboard draws its own header, and hides the navigation
            // bar itself but on iPhone Duo's side bar (`DashboardSideBar`).
            DashboardView()
        }
    }
}

#Preview {
    ContentView()
        .environment(UsageModel())
        .environment(PreferencesModel())
}
