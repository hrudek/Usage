import SwiftUI
import UsageKit

@MainActor @Observable
final class AccountPresenter {
    var reconnecting: ConnectedAccount?
    var iconPickerAccountID: String?
    var renamingAccountID: String?
    var renameDraft = ""
    var disconnectingAccountID: String?
    @ObservationIgnored private var onDisconnect: (() -> Void)?

    func rename(_ account: ConnectedAccount) {
        renameDraft = account.displayName
        renamingAccountID = account.accountID
    }

    func confirmDisconnect(_ accountID: String, onDone: (() -> Void)?) {
        onDisconnect = onDone
        disconnectingAccountID = accountID
    }

    fileprivate func disconnected() {
        onDisconnect?()
        onDisconnect = nil
    }
}

struct AccountPresentations: ViewModifier {
    @State private var presenter = AccountPresenter()
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    func body(content: Content) -> some View {
        @Bindable var presenter = presenter
        content
            .environment(presenter)
            .sheet(item: $presenter.reconnecting) { account in
                ConnectAccountSheet(reconnecting: account)
                    .withAppModels(model, prefs)
            }
            .sheet(isPresented: isSet($presenter.iconPickerAccountID)) {
                if let accountID = presenter.iconPickerAccountID {
                    AccountIconPicker(accountID: accountID)
                        .withAppModels(model, prefs)
                }
            }
            .renameAccountAlert(
                for: presenter.renamingAccountID ?? "",
                isPresented: isSet($presenter.renamingAccountID),
                name: $presenter.renameDraft
            )
            .disconnectConfirmation(
                accountID: presenter.disconnectingAccountID ?? "",
                isPresented: isSet($presenter.disconnectingAccountID)
            ) {
                presenter.disconnected()
            }
    }

    private func isSet(_ accountID: Binding<String?>) -> Binding<Bool> {
        Binding {
            accountID.wrappedValue != nil
        } set: {
            if !$0 { accountID.wrappedValue = nil }
        }
    }
}

extension View {
    func presentsAccountSheets() -> some View {
        modifier(AccountPresentations())
    }
}
