import UsageKit

/// The account a widget falls back to when its own per-instance
/// configuration hasn't resolved yet — a known WidgetKit timing edge case
/// right after a widget is first placed, before the intent's own default
/// selection has been applied. The first connected account (registry
/// order), or the placeholder if none are connected yet. Shared by
/// `UsageWidget` and `SingleUsageWidget`'s `entry(for:)` — previously
/// duplicated identically in both. `nonisolated`: timeline providers and
/// entity queries run off the main actor, and the stores it reads are
/// `Sendable`.
nonisolated enum WidgetAccountFallback {
    static func resolve() -> (accountID: String, accountName: String) {
        if let first = AccountRegistryStore(suiteName: AppConfig.appGroupID)?.accounts().first {
            return (first.accountID, first.displayName)
        }
        let placeholder = ProviderCatalog.placeholderAccount
        return (placeholder.accountID, placeholder.displayName)
    }

    /// The account a widget configured for `accountID` shows: that one,
    /// unless it is the placeholder the pickers offered while nothing
    /// was connected and no account has that id, in which case the first
    /// connected account. A first connection on a clean install gets a
    /// UUID, so a widget placed before it would otherwise stay empty
    /// until edited.
    static func resolve(configured accountID: String?, name: String?) -> (accountID: String, accountName: String) {
        if let accountID, let name,
           accountID != ProviderCatalog.placeholderAccount.accountID
            || AccountRegistryStore(suiteName: AppConfig.appGroupID)?.account(for: accountID) != nil {
            return (accountID, name)
        }
        return resolve()
    }

    /// The account's nickname from the shared registry; "Claude" for the
    /// placeholder, and the id itself for one the registry can't
    /// place (a previously picked account since removed).
    static func name(for accountID: String) -> String {
        AccountRegistryStore(suiteName: AppConfig.appGroupID)?.account(for: accountID)?.displayName
            ?? (accountID == ProviderCatalog.placeholderAccount.accountID ? ProviderCatalog.placeholderAccount.displayName : accountID)
    }

    /// The glyph the user picked for this account, from the same registry
    /// the names come from — nil (the default mark) when unset or when the
    /// account is the placeholder.
    static func icon(for accountID: String) -> AccountIcon? {
        AccountRegistryStore(suiteName: AppConfig.appGroupID)?.account(for: accountID)?.icon
    }
}
