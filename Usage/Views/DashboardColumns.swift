import SwiftUI

/// The split view keeps its column boundary off the iPhone Duo's fold by
/// itself.
struct DashboardSplitView: View {
    let accountID: String
    let sidebarWidth: CGFloat

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            DashboardView()
                .navigationSplitViewColumnWidth(
                    min: min(320, sidebarWidth), ideal: sidebarWidth, max: sidebarWidth
                )
                .toolbar(removing: .sidebarToggle)
        } detail: {
            AccountDetailStack(accountID: accountID, carriesActions: true)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct DashboardPanes: View {
    let accountID: String
    let top: CGFloat
    let gap: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                DashboardView()
            }
            .frame(height: top)
            Color.clear
                .frame(height: gap)
            AccountDetailStack(accountID: accountID, carriesActions: false)
        }
    }
}

private struct AccountDetailStack: View {
    let accountID: String
    let carriesActions: Bool

    @Environment(UsageModel.self) private var model
    @Environment(DashboardActions.self) private var actions
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            detail
                .navigationDestination(for: AccountSettingsRoute.self) { route in
                    AccountSettingsPage(accountID: route.accountID, dismissesOnDisconnect: false)
                }
        }
        .onChange(of: accountID) {
            path = NavigationPath()
        }
    }

    @ViewBuilder
    private var detail: some View {
        let page = ProviderDetailView(accountID: accountID).id(accountID)
        if carriesActions {
            @Bindable var actions = actions
            page
                .modifier(DashboardSideBar(
                    isVertical: $actions.detailBarHoldsActions,
                    isRefreshing: model.isRefreshing,
                    settings: { actions.openSettings(inColumns: sizeClass == .regular) },
                    refresh: { actions.refresh(model) },
                    addAccount: { actions.addAccount() }
                ))
                .onDisappear { actions.detailBarHoldsActions = false }
        } else {
            page
        }
    }
}
