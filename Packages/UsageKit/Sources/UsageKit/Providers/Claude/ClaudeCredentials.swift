import Foundation

/// A Claude login from the in-app OAuth sign-in, as the app keeps it in
/// the Keychain.
public struct ClaudeCredentials: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
    public var scopes: [String]
    /// e.g. "pro", "max", "ultra".
    public var subscriptionType: String?
    /// When `subscriptionType` was last confirmed against the profile
    /// endpoint. Nil means "never confirmed, or confirmed before this field
    /// existed" — which reads as due for a check, so an install upgrading
    /// from a build that cached the plan forever re-verifies on its next
    /// fetch. A subscription can change at any time (Pro → Max) and nothing
    /// in the usage response reports it, so the cached value needs an
    /// expiry date of its own; see `ClaudeProvider.planRecheckInterval`.
    public var planCheckedAt: Date?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        scopes: [String] = [],
        subscriptionType: String? = nil,
        planCheckedAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.subscriptionType = subscriptionType
        self.planCheckedAt = planCheckedAt
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

extension ClaudeCredentials: RotatingCredentials {}

/// Where `ClaudeProvider` obtains credentials and persists rotated tokens.
public protocol ClaudeCredentialSource: CredentialStore {
    /// Names the stored login. Refreshes of one key run one at a time
    /// (`TokenRefresher`).
    var refreshKey: String { get }
    func load() async throws -> ClaudeCredentials
    func save(_ credentials: ClaudeCredentials) async throws
}
