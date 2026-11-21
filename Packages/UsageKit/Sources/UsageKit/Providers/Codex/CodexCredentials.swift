import Foundation

/// A Codex login: the ChatGPT OAuth tokens the in-app device-code
/// sign-in mints. The access token is a JWT whose `exp` claim is the
/// only expiry there is. The `id_token` (it carries the email) is
/// never kept: its one claim the app needs, the account id, is copied
/// into `accountID` when the token arrives.
public struct CodexCredentials: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    /// The ChatGPT account the usage belongs to (a workspace, or the
    /// personal account), sent as the `ChatGPT-Account-Id` header the
    /// way the CLI sends it.
    public var accountID: String?
    /// The access token's `exp` claim.
    public var expiresAt: Date?
    /// When the pair was last rotated.
    public var lastRefresh: Date?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        accountID: String? = nil,
        expiresAt: Date? = nil,
        lastRefresh: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountID = accountID
        self.expiresAt = expiresAt
        self.lastRefresh = lastRefresh
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    /// ISO 8601 with fractional seconds, as the device-code sign-in sends
    /// `expires_at`.
    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

/// The two claims read from OpenAI's tokens, and nothing else: the
/// expiry, and the account id under the `https://api.openai.com/auth`
/// namespace (the email beside it is never decoded). No signature check:
/// these are the app's own tokens, read for their dates.
struct JWTClaims {
    let expiresAt: Date?
    let accountID: String?

    init?(token: String) {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        expiresAt = claims.exp.map { Date(timeIntervalSince1970: $0) }
        accountID = claims.auth?.accountID
    }

    private struct Payload: Decodable {
        let exp: Double?
        let auth: Auth?

        enum CodingKeys: String, CodingKey {
            case exp
            case auth = "https://api.openai.com/auth"
        }
    }

    private struct Auth: Decodable {
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case accountID = "chatgpt_account_id"
        }
    }
}

extension CodexCredentials: RotatingCredentials {}

/// Where `CodexProvider` obtains credentials and persists rotated tokens.
public protocol CodexCredentialSource: CredentialStore {
    /// Names the stored login. Refreshes of one key run one at a time
    /// (`TokenRefresher`).
    var refreshKey: String { get }
    func load() async throws -> CodexCredentials
    func save(_ credentials: CodexCredentials) async throws
}
