import Foundation
import UsageKit

/// The providers this build knows how to talk to, by `providerID` — the
/// one place the app and the widget extension resolve a provider family
/// to a display name or to a working `UsageProvider` + credential store.
/// Adding a provider is one case in each function here plus its folder
/// under `Packages/UsageKit/.../Providers/`; nothing in the views keys on
/// a provider name (they render whatever windows a snapshot carries).
///
/// `nonisolated` for the same reason as `AppConfig`: plain constants and
/// pure functions, read from default arguments and from widget timeline
/// code that runs off the main actor.
nonisolated enum ProviderCatalog {
    /// The provider of `placeholderAccount`, and what an unknown family is
    /// treated as.
    static let defaultProviderID = ClaudeProvider.providerID

    /// Every family this build can connect, in the order the Connect
    /// sheet's picker lists them.
    static let providerIDs = [ClaudeProvider.providerID, CodexProvider.providerID]

    /// The families Settings and Privacy & data talk about: those the
    /// connected accounts belong to, in the picker's order, so someone
    /// without a family's account reads nothing about it. With nothing connected, every family, since then the text is what
    /// someone reads before choosing one.
    static func familiesToDescribe(connected providerIDs: [String]) -> [String] {
        let connected = Self.providerIDs.filter(providerIDs.contains)
        return connected.isEmpty ? Self.providerIDs : connected
    }

    /// Plain-text name shown for accounts of this family — nominative use
    /// only, never a logo (see "Design system" in the repo-root CLAUDE.md).
    static func displayName(for providerID: String) -> String {
        switch providerID {
        case ClaudeProvider.providerID: ClaudeProvider.providerDisplayName
        case CodexProvider.providerID: CodexProvider.providerDisplayName
        default: providerID.capitalized
        }
    }

    /// The glyph beside a family's name in the Connect sheet's picker: an
    /// SF Symbol, never a logo. Accounts themselves start on the default
    /// mark whatever their family (`ProviderMark`).
    static func symbolName(for providerID: String) -> String {
        switch providerID {
        case ClaudeProvider.providerID: "sparkle"
        case CodexProvider.providerID: "terminal"
        default: ProviderMark.defaultSymbol
        }
    }

    /// What a widget shows while no account is connected: its previews,
    /// and the pickers' one option. Never stored and never fetched.
    static let placeholderAccount = ConnectedAccount(
        accountID: "placeholder",
        providerID: defaultProviderID,
        displayName: displayName(for: defaultProviderID)
    )

    /// Where every provider of this process rotates its login. The lock
    /// lives in the App Group container, so the app and the widget
    /// extension never spend the same refresh token.
    static let refresher = TokenRefresher(lock: RefreshLock(appGroupID: AppConfig.appGroupID))

    /// A working provider for one connected account, plus the credential
    /// store to clear on disconnect. Keyed by `account.providerID`; the
    /// account's own Keychain key backs it. The app and the widget
    /// extension both renew an expired login through `refresher`.
    static func makeProvider(
        for account: ConnectedAccount,
        keychain: KeychainStore,
        transport: any HTTPTransport = URLSessionTransport()
    ) -> (provider: any UsageProvider, credentials: any CredentialStore) {
        switch account.providerID {
        case ClaudeProvider.providerID:
            let key = ClaudeKeychainCredentialSource.storageKey(for: account.accountID)
            let source = ClaudeKeychainCredentialSource(store: keychain, key: key)
            let provider = ClaudeProvider(credentialSource: source, transport: transport, refresher: refresher)
            return (provider, source)
        case CodexProvider.providerID:
            let key = CodexKeychainCredentialSource.storageKey(for: account.accountID)
            let source = CodexKeychainCredentialSource(store: keychain, key: key)
            let provider = CodexProvider(credentialSource: source, transport: transport, refresher: refresher)
            return (provider, source)
        default:
            // Only this app writes the registry, so an unknown family means
            // a build older than the one that wrote it. Fail loudly in
            // development; in release, treat it as the family it almost
            // certainly is rather than crash over a meter.
            assertionFailure("unknown provider \(account.providerID)")
            let claude = ConnectedAccount(
                accountID: account.accountID, providerID: ClaudeProvider.providerID,
                displayName: account.displayName,
                connectedAt: account.connectedAt, icon: account.icon
            )
            return makeProvider(for: claude, keychain: keychain, transport: transport)
        }
    }
}
