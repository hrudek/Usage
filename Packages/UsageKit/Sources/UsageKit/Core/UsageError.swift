import Foundation

/// Typed errors surfaced by UsageKit. UI layers decide presentation.
public enum UsageError: Error, Equatable, Sendable {
    /// No stored credentials were found for the provider.
    case credentialsNotFound(String)
    /// The token is expired and cannot be refreshed from this device.
    case tokenExpired
    /// The provider rejected the credentials (HTTP 401 after any refresh attempt).
    case notAuthenticated
    /// The provider is rate-limiting us (HTTP 429). `body` is the raw
    /// response text, when there was one.
    case rateLimited(retryAfter: TimeInterval?, body: String?)
    case httpError(statusCode: Int, body: String?)
    /// The response arrived but could not be interpreted.
    case invalidResponse(String)
    case storage(String)
}

extension UsageError {
    /// Whether the only way out of this failure is signing in again.
    ///
    /// All three cases mean the stored credentials can't produce a usable
    /// token from this device: the provider rejected them outright
    /// (`notAuthenticated`, i.e. a refresh token Anthropic no longer
    /// honours — typically because the same login was refreshed elsewhere
    /// and the token rotated), they expired with no refresh token to
    /// renew them (`tokenExpired`), or they're gone entirely
    /// (`credentialsNotFound`). None of them heal by retrying, so a UI that
    /// only shows the message leaves the user stuck — surfaces offer a
    /// re-connect affordance instead. Deliberately broader than what
    /// warrants a *notification*: `RefreshService` only alerts on
    /// `notAuthenticated`, the one case that is terminal rather than
    /// possibly self-healing (see its `refresh(accountLabel:)`).
    public var requiresReauthentication: Bool {
        switch self {
        case .notAuthenticated, .tokenExpired, .credentialsNotFound:
            return true
        case .rateLimited, .httpError, .invalidResponse, .storage:
            return false
        }
    }
}

extension UsageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .credentialsNotFound(let detail):
            return String(localized: "No credentials found: \(detail)", bundle: .module)
        case .tokenExpired:
            return String(localized: "The access token has expired.", bundle: .module)
        case .notAuthenticated:
            return String(localized: "The provider rejected the credentials.", bundle: .module)
        case .rateLimited(let retryAfter, let body):
            var text = retryAfter.map {
                String(localized: "Rate limited; retry after \(Int($0)) seconds.", bundle: .module)
            } ?? String(localized: "Rate limited by the provider.", bundle: .module)
            if let body {
                text += "\n\(body)"
            }
            return text
        case .httpError(let statusCode, let body):
            if let body {
                return String(localized: "The provider returned HTTP \(statusCode): \(body)", bundle: .module)
            }
            return String(localized: "The provider returned HTTP \(statusCode).", bundle: .module)
        case .invalidResponse(let detail):
            return String(localized: "Unexpected response: \(detail)", bundle: .module)
        case .storage(let detail):
            return String(localized: "Storage error: \(detail)", bundle: .module)
        }
    }
}

public extension UsageError {
    /// What an error may show of an endpoint's response body. A JSON body
    /// gives only its `error` and `error_description` (Anthropic's error
    /// object: its `type` and `message`), since a proxy or captive portal
    /// can put anything in the rest; other text is cut to 400 characters.
    /// Nil when there is nothing to show.
    static func displayBody(_ data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var parts: [String] = []
            if let error = json["error"] as? String {
                parts.append(error)
            } else if let error = json["error"] as? [String: Any] {
                parts += [error["type"], error["message"]].compactMap { $0 as? String }
            }
            if let description = json["error_description"] as? String {
                parts.append(description)
            }
            let text = parts.joined(separator: ": ")
            return text.isEmpty ? nil : String(text.prefix(400))
        }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return String(text.prefix(400))
    }
}
