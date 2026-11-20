import Foundation

/// The app's own copy of a Codex login, from the in-app device-code
/// sign-in, in the app's Keychain (the shared access group on iOS, so
/// the widget can fetch with it). Refreshed in place.
public struct CodexKeychainCredentialSource: CodexCredentialSource {
    /// The Keychain key for an account: every Codex account gets its own
    /// suffixed key (there is no legacy single-account install of this
    /// provider to keep a bare key for).
    public static func storageKey(for accountID: String) -> String {
        "codex.credentials.\(accountID)"
    }

    public var allowsRefresh: Bool { true }

    private let store: KeychainStore
    private let key: String

    public init(store: KeychainStore, key: String) {
        self.store = store
        self.key = key
    }

    public func load() async throws -> CodexCredentials {
        guard let credentials = try store.value(CodexCredentials.self, for: key) else {
            throw UsageError.credentialsNotFound("no Codex token stored yet")
        }
        return credentials
    }

    public func save(_ credentials: CodexCredentials) async throws {
        try store.set(credentials, for: key)
    }

    public func clear() throws {
        try store.delete(key)
    }
}

