import Foundation

/// The app's own copy of a Codex login, from the in-app device-code
/// sign-in, in the app's Keychain (the shared access group on iOS, so
/// the widget can fetch with it). Refreshed in place by the app and the
/// widget extension.
public struct CodexKeychainCredentialSource: CodexCredentialSource {
    /// The Keychain key for an account: every account gets its own.
    public static func storageKey(for accountID: String) -> String {
        "codex.credentials.\(accountID)"
    }

    public var refreshKey: String { key }

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

