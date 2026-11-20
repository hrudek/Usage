import SwiftUI
import UsageKit

@MainActor @Observable
final class DashboardActions {
    var showingSettings = false
    var settingsInColumns = false
    var showingConnect = false
    var refreshRequests = 0
    var selectedAccountID: String?
    var reconnecting: ConnectedAccount?
    var renamingAccountID: String?
    var renameDraft = ""
    var iconPickerAccountID: String?
    var detailBarHoldsActions = false

    func openSettings(inColumns: Bool) {
        settingsInColumns = inColumns
        showingSettings = true
    }

    func refresh(_ model: UsageModel) {
        refreshRequests += 1
        Task { await model.refreshAll() }
    }

    func addAccount() {
        showingConnect = true
    }

    func rename(_ account: ConnectedAccount) {
        renameDraft = account.displayName
        renamingAccountID = account.accountID
    }
}

struct AccountSelection {
    let selectedID: String?
    let select: (String) -> Void
}

extension EnvironmentValues {
    @Entry var accountSelection: AccountSelection? = nil
}

struct DashboardPresentations: ViewModifier {
    let actions: DashboardActions
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        @Bindable var actions = actions
        content
            #if DEBUG
            .onAppear {
                if UserDefaults.standard.bool(forKey: "UsageShowSettings") {
                    actions.openSettings(inColumns: sizeClass == .regular)
                }
            }
            #endif
            .sheet(isPresented: presentsSettings(inColumns: false)) {
                SettingsSheet()
                    .withAppModels(model, prefs)
            }
            .fullScreenCover(isPresented: presentsSettings(inColumns: true)) {
                SettingsSplitView()
                    .withAppModels(model, prefs)
            }
            .sheet(isPresented: $actions.showingConnect) {
                ConnectAccountSheet()
                    .withAppModels(model, prefs)
            }
            .sheet(item: $actions.reconnecting) { account in
                ConnectAccountSheet(reconnecting: account)
                    .withAppModels(model, prefs)
            }
            .sheet(isPresented: isSet($actions.iconPickerAccountID)) {
                if let accountID = actions.iconPickerAccountID {
                    AccountIconPicker(accountID: accountID)
                        .withAppModels(model, prefs)
                }
            }
            .renameAccountAlert(
                for: actions.renamingAccountID ?? "",
                isPresented: isSet($actions.renamingAccountID),
                name: $actions.renameDraft
            )
    }

    private func isSet(_ accountID: Binding<String?>) -> Binding<Bool> {
        Binding {
            accountID.wrappedValue != nil
        } set: {
            if !$0 { accountID.wrappedValue = nil }
        }
    }

    private func presentsSettings(inColumns: Bool) -> Binding<Bool> {
        Binding {
            actions.showingSettings && actions.settingsInColumns == inColumns
        } set: {
            actions.showingSettings = $0
        }
    }
}
