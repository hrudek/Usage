import Foundation

/// Fetches a ChatGPT account's Codex limits from the endpoint the Codex
/// CLI reads for `/status`. All endpoint specifics live here and in
/// `CodexUsageResponse` so a server change touches one place; the login
/// itself is `CodexCredentials`, from the CLI's file on a Mac or the
/// in-app device-code sign-in.
public struct CodexProvider: UsageProvider {
    static let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    /// The provider *family* identifier every `ConnectedAccount.providerID`
    /// and `UsageSnapshot.providerID` of this provider carries — the one
    /// place the literal lives.
    public static let providerID = "codex"
    public static let providerDisplayName = "Codex"

    public let id = CodexProvider.providerID
    public let displayName = CodexProvider.providerDisplayName

    private let credentialSource: any CodexCredentialSource
    private let transport: any HTTPTransport
    private let userAgent: String
    private let refresher: TokenRefresher

    /// How long a rejected refresh waits before its last look at the
    /// store (see `rotate`). Tests set it to zero.
    var rejectionRecheckDelay: Duration = .milliseconds(1500)

    public init(
        credentialSource: any CodexCredentialSource,
        transport: any HTTPTransport = URLSessionTransport(),
        userAgent: String = "AIMeter",
        refresher: TokenRefresher = .shared
    ) {
        self.credentialSource = credentialSource
        self.transport = transport
        self.userAgent = userAgent
        self.refresher = refresher
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        var credentials = try await loadCredentials()

        if credentials.isExpired {
            credentials = try await refreshed(credentials)
        }

        var (data, response) = try await send(with: credentials)

        if response.statusCode == 401 {
            if credentialSource.allowsRefresh {
                credentials = try await refreshed(credentials)
                (data, response) = try await send(with: credentials)
            } else {
                credentialSource.invalidateCache()
            }
        }

        switch response.statusCode {
        case 200:
            break
        case 401:
            throw UsageError.notAuthenticated
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw UsageError.rateLimited(retryAfter: retryAfter, body: Self.errorBody(data))
        default:
            throw UsageError.httpError(statusCode: response.statusCode, body: Self.errorBody(data))
        }

        let decoded: CodexUsageResponse
        do {
            decoded = try CodexUsageResponse.decode(data)
        } catch {
            throw UsageError.invalidResponse("usage decode: \(error.localizedDescription)")
        }

        let windows = decoded.usageWindows()
        guard !windows.isEmpty else {
            throw UsageError.invalidResponse("no usage windows in response")
        }

        let accountID = decoded.accountId ?? credentials.accountID
        return UsageSnapshot(
            providerID: id,
            planName: decoded.planType,
            fetchedAt: Date(),
            windows: windows,
            spend: decoded.spendStatus(),
            accountIdentity: accountID.map { Self.identity(for: $0) }
        )
    }

    /// The cross-device identity of a login, from the ChatGPT account id.
    static func identity(for accountID: String) -> String {
        "\(providerID):\(accountID)"
    }

    /// What an HTTP error shows of the response (`UsageError.displayBody`).
    private static func errorBody(_ data: Data) -> String? {
        UsageError.displayBody(data)
    }

    private func send(with credentials: CodexCredentials) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: Self.usageEndpoint)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            // The workspace the usage is read for, the way the CLI asks.
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await transport.send(request)
    }

    /// The login to fetch with; see `ClaudeProvider.loadCredentials`.
    private func loadCredentials() async throws -> CodexCredentials {
        let source = credentialSource
        guard source.allowsRefresh else { return try await source.load() }
        return try await refresher.credentials(
            key: source.refreshKey,
            load: { try await source.load() },
            save: { try await source.save($0) }
        )
    }

    private func refreshed(_ credentials: CodexCredentials) async throws -> CodexCredentials {
        guard credentialSource.allowsRefresh else {
            // A reader that may not rotate (the widget extension) leaves
            // the refresh to the app and keeps its last snapshot.
            throw UsageError.tokenExpired
        }
        // OpenAI spends the refresh token the moment it accepts it and
        // revokes the whole family when a spent one comes back, so one
        // refresh per login at a time, in a task the caller's cancellation
        // never reaches (see `ClaudeProvider`).
        let provider = self
        return try await refresher.refresh(key: credentialSource.refreshKey) {
            try await provider.rotate(credentials)
        }
    }

    /// The same rotation rules as Claude's: a pair rotated since this
    /// fetch loaded is used as is, and a rejected refresh is checked
    /// against what the store holds now.
    private func rotate(_ credentials: CodexCredentials) async throws -> CodexCredentials {
        if let stored = try? await loadCredentials(),
           stored.refreshToken != credentials.refreshToken, !stored.isExpired {
            return stored
        }
        let client = CodexOAuthClient(transport: transport)
        do {
            let updated = try await client.refresh(credentials)
            await persist(updated, replacing: credentials)
            return updated
        } catch UsageError.notAuthenticated {
            var latest = try await loadCredentials()
            if latest.refreshToken == credentials.refreshToken {
                try await Task.sleep(for: rejectionRecheckDelay)
                latest = try await loadCredentials()
            }
            guard latest.refreshToken != credentials.refreshToken else {
                throw UsageError.notAuthenticated
            }
            if !latest.isExpired {
                return latest
            }
            let updated = try await client.refresh(latest)
            await persist(updated, replacing: latest)
            return updated
        }
    }

    private func persist(_ updated: CodexCredentials, replacing old: CodexCredentials) async {
        let source = credentialSource
        await refresher.persist(updated, replacing: old.refreshToken, key: source.refreshKey) {
            try await source.save($0)
        }
    }
}
