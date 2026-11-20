import Foundation

/// Fetches Claude Pro/Max/Ultra usage from the undocumented endpoint Claude Code
/// uses internally. All endpoint specifics live here and in
/// `ClaudeUsageResponse` so a breaking change touches one place.
public struct ClaudeProvider: UsageProvider {
    static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let profileEndpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    /// The provider *family* identifier every `ConnectedAccount.providerID`
    /// and `UsageSnapshot.providerID` of this provider carries — the one
    /// place the literal lives.
    public static let providerID = "claude"
    public static let providerDisplayName = "Claude"

    public let id = ClaudeProvider.providerID
    public let displayName = ClaudeProvider.providerDisplayName

    /// How long a resolved plan is trusted before it's re-verified against
    /// the profile endpoint. The plan is the one part of a snapshot that
    /// isn't re-derived on every fetch — the usage response carries no
    /// subscription field, so it's cached in the credentials — and a
    /// subscription changes whenever the user upgrades or downgrades. A
    /// cache with no expiry keeps showing "Pro" forever after a move to
    /// Max, so it gets one: at most four extra profile calls a day.
    static let planRecheckInterval: TimeInterval = 6 * 60 * 60

    private let credentialSource: any ClaudeCredentialSource
    private let transport: any HTTPTransport
    private let userAgent: String
    private let refresher: TokenRefresher

    /// How long a rejected refresh waits before its last look at the
    /// store (see `rotate`). Tests set it to zero.
    var rejectionRecheckDelay: Duration = .milliseconds(1500)

    /// - Parameter userAgent: sent as `User-Agent`. Must look like a Claude
    ///   Code client (`claude-code/<version>`); other agents hit an
    ///   aggressively rate-limited bucket and get persistent 429s.
    /// - Parameter refresher: where refreshes of one login wait for each
    ///   other; every provider in the app shares `.shared`.
    public init(
        credentialSource: any ClaudeCredentialSource,
        transport: any HTTPTransport = URLSessionTransport(),
        userAgent: String = "claude-code/2.1.212",
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

        if response.statusCode == 401, credentialSource.allowsRefresh {
            credentials = try await refreshed(credentials)
            (data, response) = try await send(with: credentials)
        }

        switch response.statusCode {
        case 200:
            break
        case 401:
            throw UsageError.notAuthenticated
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            throw UsageError.rateLimited(retryAfter: retryAfter, body: Self.errorBody(data))
        default:
            throw UsageError.httpError(statusCode: response.statusCode, body: Self.errorBody(data))
        }

        let decoded: ClaudeUsageResponse
        do {
            decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        } catch {
            throw UsageError.invalidResponse("usage decode: \(error.localizedDescription)")
        }

        let windows = decoded.usageWindows()
        guard !windows.isEmpty else {
            throw UsageError.invalidResponse("no usage windows in response")
        }

        let planName = await plan(for: credentials)
        return UsageSnapshot(
            providerID: id,
            planName: planName,
            fetchedAt: Date(),
            windows: windows,
            spend: decoded.spendStatus(),
            extraUsage: decoded.extraUsageStatus(),
            breakdown: decoded.usageBreakdown()
        )
    }

    /// The stored plan while it is still within `planRecheckInterval`;
    /// otherwise re-resolved from the profile endpoint and persisted, so
    /// later fetches skip the extra call until it goes stale again.
    /// Best-effort: a profile failure keeps the last plan we knew rather
    /// than blanking it.
    ///
    /// The write-back re-reads the source instead of saving the
    /// `credentials` value this fetch started with, and that matters: only
    /// `subscriptionType` and `planCheckedAt` are ours to persist here,
    /// while the token fields may have been rotated in the meantime by a
    /// concurrent fetch. The refresher runs the write once no rotation of
    /// this login does, on what the store holds then. Saving the whole
    /// stale value would put a consumed refresh token back over the fresh
    /// one, and Anthropic rejects a consumed refresh token permanently.
    private func plan(for credentials: ClaudeCredentials) async -> String? {
        if let subscription = credentials.subscriptionType,
           let checkedAt = credentials.planCheckedAt,
           Date().timeIntervalSince(checkedAt) < Self.planRecheckInterval {
            return subscription
        }
        guard let plan = try? await fetchProfile(with: credentials)?.subscriptionType else {
            // Unreachable profile, or one that reports no subscription at
            // all, which is also what a shape change would look like. Keep
            // the last plan we knew instead of dropping the pill over it.
            return credentials.subscriptionType
        }
        if credentialSource.allowsRefresh {
            let source = credentialSource
            let checkedAt = Date()
            await refresher.update(
                key: source.refreshKey,
                load: { try await source.load() },
                save: { try await source.save($0) }
            ) { latest in
                latest.subscriptionType = plan
                latest.planCheckedAt = checkedAt
            }
        }
        return plan
    }

    private func fetchProfile(with credentials: ClaudeCredentials) async throws -> ClaudeProfileResponse? {
        let (data, response) = try await transport.send(
            request(for: Self.profileEndpoint, credentials: credentials)
        )
        guard response.statusCode == 200 else { return nil }
        return try JSONDecoder().decode(ClaudeProfileResponse.self, from: data)
    }

    /// What an HTTP error shows of the response (`UsageError.displayBody`).
    private static func errorBody(_ data: Data) -> String? {
        UsageError.displayBody(data)
    }

    private func send(with credentials: ClaudeCredentials) async throws -> (Data, HTTPURLResponse) {
        try await transport.send(request(for: Self.usageEndpoint, credentials: credentials))
    }

    private func request(for url: URL, credentials: ClaudeCredentials) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// The login to fetch with. Where this source may rotate, it goes
    /// through the refresher, which still has a rotated pair the store
    /// refused to save.
    private func loadCredentials() async throws -> ClaudeCredentials {
        let source = credentialSource
        guard source.allowsRefresh else { return try await source.load() }
        return try await refresher.credentials(
            key: source.refreshKey,
            load: { try await source.load() },
            save: { try await source.save($0) }
        )
    }

    private func refreshed(_ credentials: ClaudeCredentials) async throws -> ClaudeCredentials {
        guard credentialSource.allowsRefresh else {
            // A reader that may not rotate (the widget extension) leaves
            // the refresh to the app and keeps its last snapshot.
            throw UsageError.tokenExpired
        }
        // Anthropic rotates the refresh token the moment it accepts it, so
        // two refreshes of one login must never overlap: a second caller
        // joins the one under way (`TokenRefresher`). The refresher runs
        // the exchange and the save in a task of their own, so a cancelled
        // sweep never throws away a pair Anthropic has already rotated.
        let provider = self
        return try await refresher.refresh(key: credentialSource.refreshKey) {
            try await provider.rotate(credentials)
        }
    }

    private func rotate(_ credentials: ClaudeCredentials) async throws -> ClaudeCredentials {
        // A refresh of this login that finished after `credentials` was
        // loaded already spent their refresh token. Its pair is the one to
        // use; sending the spent token again would only be rejected.
        if let stored = try? await loadCredentials(),
           stored.refreshToken != credentials.refreshToken, !stored.isExpired {
            return stored
        }
        let client = ClaudeOAuthClient(transport: transport)
        do {
            let updated = try await client.refresh(credentials)
            await persist(updated, replacing: credentials)
            return updated
        } catch UsageError.notAuthenticated {
            // A rejection doesn't only mean the login is dead: another
            // device signed in with the same pair may have rotated it. If
            // the store now holds a different pair than the one just
            // rejected, use that instead of declaring the account broken.
            // A save may still be landing, so an unchanged store gets one
            // more look a moment later. Same token then means the
            // rejection is real.
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

    /// Saves a rotated pair. The old refresh token is spent at this point,
    /// so a store that refuses the new pair is retried, and the refresher
    /// keeps the pair in memory if it still fails.
    private func persist(_ updated: ClaudeCredentials, replacing old: ClaudeCredentials) async {
        let source = credentialSource
        await refresher.persist(updated, replacing: old.refreshToken, key: source.refreshKey) {
            try await source.save($0)
        }
    }
}
