import Foundation

/// The app's own copy of a Claude login, from the in-app sign-in, in the
/// app's Keychain (the shared access group, so the widget can use it).
/// Refreshed in place by the app and the widget extension.
public struct ClaudeKeychainCredentialSource: ClaudeCredentialSource {
    /// The Keychain key for an account: every account gets its own.
    public static func storageKey(for accountID: String) -> String {
        "claude.credentials.\(accountID)"
    }

    public var refreshKey: String { key }

    private let store: KeychainStore
    private let key: String

    public init(store: KeychainStore, key: String) {
        self.store = store
        self.key = key
    }

    public func load() async throws -> ClaudeCredentials {
        guard let credentials = try store.value(ClaudeCredentials.self, for: key) else {
            throw UsageError.credentialsNotFound("no Claude token stored yet")
        }
        return credentials
    }

    public func save(_ credentials: ClaudeCredentials) async throws {
        try store.set(credentials, for: key)
    }

    public func clear() throws {
        try store.delete(key)
    }
}
