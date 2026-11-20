import Foundation
import WidgetKit
import UsageKit

/// Adding, repairing, and removing accounts: the parts
/// of `UsageModel` that change *which* accounts exist. See the type doc
/// in `UsageModel.swift` for how the files divide.
extension UsageModel {
    // MARK: - Account management

    /// Called by the Connect sheet after a successful sign-in of any
    /// family (`ProviderLogin`). Adds a new account with the app's own
    /// credentials.
    func completeConnection(_ login: ProviderLogin, displayName: String? = nil) async {
        let accountID = UUID().uuidString
        // The Connect sheet already refuses a taken nickname; this only
        // guarantees the registry never holds two accounts under one name.
        let requested = displayName ?? suggestedNickname(providerID: login.providerID)
        let name = isNameTaken(requested) ? suggestedNickname(providerID: login.providerID) : requested
        let account = ConnectedAccount(
            accountID: accountID, providerID: login.providerID,
            displayName: name
        )
        let service = RefreshService(account: account)
        do {
            try await service.storeConnection(login)
        } catch {
            connectionError = (error as? UsageError)?.errorDescription ?? error.localizedDescription
            return
        }
        connectionError = nil
        registry?.add(account)
        addAccount(account, service: service)
        if accounts.count == 2 {
            // The first account's queued notifications were issued with no
            // nickname prefix (a single account never needs one); now that
            // there are two, they have to say which account they're about.
            relabelPendingNotifications(except: accountID)
        }
        await refresh(accountID: accountID)
    }

    /// Replaces an existing account's credentials **in place**, keeping its
    /// `accountID` — the recovery path for a login the provider stopped
    /// accepting (`AccountUsage.needsReauthentication`). Everything keyed by
    /// that id survives untouched: stored snapshot, usage history and its
    /// pace warm-up anchor, per-account notification toggles, and the
    /// account selection of every widget already on a Home Screen. That is
    /// the whole point of not routing this through
    /// `completeConnection`, which mints a new id.
    func reconnect(accountID: String, login: ProviderLogin) async {
        guard let startIndex = index(for: accountID) else { return }
        let account = accounts[startIndex].account
        guard account.providerID == login.providerID else {
            connectionError = String(localized: "That sign-in is for another service than this account.")
            return
        }
        let service = RefreshService(account: account)
        do {
            try await service.storeConnection(login)
        } catch {
            connectionError = (error as? UsageError)?.errorDescription ?? error.localizedDescription
            return
        }
        connectionError = nil
        NotificationScheduler.clearReauthenticationAlert(
            accountID: accountID, preferences: preferences(for: accountID)
        )
        guard let i = index(for: accountID) else { return }
        services[accountID] = service
        accounts[i].lastError = nil
        accounts[i].needsReauthentication = false
        await refresh(accountID: accountID)
    }

    /// Whether the account is gone: a failed cascade leaves it connected
    /// with the error on its card, and the page that asked stays open.
    @discardableResult
    func disconnect(accountID: String) -> Bool {
        guard let service = services[accountID] else { return false }
        do {
            try service.disconnect()
            registry?.remove(accountID)
            removeAccount(accountID: accountID)
            if accounts.count == 1 {
                // Back to a single account: its queued notifications still
                // carry the nickname prefix only a multi-account install
                // needs, so re-issue them reading as they always have.
                relabelPendingNotifications()
            }
            return true
        } catch {
            if let index = index(for: accountID) {
                accounts[index].lastError = error.localizedDescription
            }
            return false
        }
    }

    /// `accounts` and `services` must always move in lockstep — a service
    /// with no matching `accounts` row (or vice versa) makes that account
    /// silently unrefreshable. These are the only two places either
    /// collection grows or shrinks by one account (`loadAccounts()` is
    /// exempt: it rebuilds both wholesale in a single pass).
    func addAccount(_ account: ConnectedAccount, service: RefreshService, snapshot: UsageSnapshot? = nil) {
        services[account.accountID] = service
        accounts.append(AccountUsage(account: account, snapshot: snapshot))
    }

    func removeAccount(accountID: String) {
        services.removeValue(forKey: accountID)
        accounts.removeAll { $0.account.accountID == accountID }
    }
}
