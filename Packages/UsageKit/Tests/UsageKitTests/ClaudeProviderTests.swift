import XCTest
@testable import UsageKit

final class ClaudeProviderTests: XCTestCase {
    func testFetchUsageSuccess() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        let source = StubCredentialSource(credentials: .valid)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.providerID, "claude")
        XCTAssertEqual(snapshot.planName, "pro")
        XCTAssertEqual(snapshot.windows.count, 2)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("claude-code/"), true)
    }

    func testExpiredTokenIsRefreshedBeforeFetch() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (200, Self.refreshBody),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        let source = StubCredentialSource(credentials: .expired)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        _ = try await provider.fetchUsage()

        let usageRequest = try XCTUnwrap(
            transport.requests.first { $0.url == ClaudeProvider.usageEndpoint }
        )
        XCTAssertEqual(usageRequest.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
        XCTAssertEqual(source.saved.last?.accessToken, "new-token")
        // Rotated refresh token persisted alongside the new access token.
        XCTAssertEqual(source.saved.last?.refreshToken, "new-refresh")
    }

    func test401TriggersOneRefreshAndRetry() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (200, Self.refreshBody),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (401, "{}"),
            (200, Self.usageBody),
        ])
        let source = StubCredentialSource(credentials: .valid)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.windows.count, 2)
        let usageRequests = transport.requests.filter { $0.url == ClaudeProvider.usageEndpoint }
        XCTAssertEqual(usageRequests.count, 2)
        XCTAssertEqual(usageRequests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
    }

    func testAPairRotatedSinceTheLoadIsUsedWithoutSpendingTheOldToken() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (400, "{}"),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        // Another refresh of the same login finished while this fetch was
        // in flight: the store now holds a different, still-valid pair.
        let source = StubCredentialSource(credentials: .expired)
        source.rotatesTo = .rotatedElsewhere
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.windows.count, 2)
        let usageRequest = try XCTUnwrap(transport.requests.first { $0.url == ClaudeProvider.usageEndpoint })
        XCTAssertEqual(usageRequest.value(forHTTPHeaderField: "Authorization"), "Bearer rotated-token")
        // The spent refresh token is never sent again.
        XCTAssertFalse(transport.requests.contains { $0.url == ClaudeOAuthClient.tokenEndpoint })
        XCTAssertTrue(source.saved.isEmpty)
    }

    func testRejectedRefreshWithUnchangedCredentialsThrowsNotAuthenticated() async {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (400, "{}"),
        ])
        let source = StubCredentialSource(credentials: .expired)
        var provider = ClaudeProvider(credentialSource: source, transport: transport)
        provider.rejectionRecheckDelay = .zero

        await assertThrows(UsageError.notAuthenticated) {
            _ = try await provider.fetchUsage()
        }
        XCTAssertTrue(transport.requests.allSatisfy { $0.url == ClaudeOAuthClient.tokenEndpoint })
    }

    /// The winner of a rotation race may save its new pair a moment after
    /// the loser's rejection; the loser's second look finds it.
    func testRejectedRefreshWaitsForARotationStillBeingSaved() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (400, "{}"),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        let source = StubCredentialSource(credentials: .expired)
        // Still the rejected pair right after the rejection (the fetch's
        // own load, the look before refreshing, then the first re-read);
        // the winner's after that.
        source.rotatesTo = .rotatedElsewhere
        source.rotatesAfterLoad = 3
        var provider = ClaudeProvider(credentialSource: source, transport: transport)
        provider.rejectionRecheckDelay = .zero

        _ = try await provider.fetchUsage()

        let usageRequest = try XCTUnwrap(transport.requests.first { $0.url == ClaudeProvider.usageEndpoint })
        XCTAssertEqual(usageRequest.value(forHTTPHeaderField: "Authorization"), "Bearer rotated-token")
        XCTAssertTrue(source.saved.isEmpty)
    }

    /// Only a 400 or a 401 says the login is dead; a firewall's 403 says
    /// nothing about it and keeps its body for the UI.
    func testOtherTokenEndpointErrorsAreNotARejectedLogin() async {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (403, "blocked"),
        ])
        let source = StubCredentialSource(credentials: .expired)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        await assertThrows(UsageError.httpError(statusCode: 403, body: "blocked")) {
            _ = try await provider.fetchUsage()
        }
    }

    /// Anthropic spends the refresh token as soon as it accepts it, so a
    /// sweep cancelled mid-refresh must still store the new pair.
    func testCancelledFetchStillSavesTheRotatedPair() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (200, #"{"access_token": "new-token", "refresh_token": "new-refresh", "expires_in": 3600}"#),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.delays[ClaudeOAuthClient.tokenEndpoint] = .milliseconds(200)
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        transport.onSend = { request in
            if request.url == ClaudeOAuthClient.tokenEndpoint { startedContinuation.yield() }
        }
        let source = StubCredentialSource(credentials: .expired)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let fetch = Task { try await provider.fetchUsage() }
        for await _ in started { break }
        fetch.cancel()
        _ = try? await fetch.value

        XCTAssertEqual(source.saved.first?.refreshToken, "new-refresh")
    }

    func testThrottledRefreshThrowsRateLimitedNotNotAuthenticated() async {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (429, "", ["Retry-After": "30"]),
        ])
        let source = StubCredentialSource(credentials: .expired)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        await assertThrows(UsageError.rateLimited(retryAfter: 30, body: nil)) {
            _ = try await provider.fetchUsage()
        }
    }

    /// The app's sweep and its background task may fetch one expired
    /// login at the same moment: one refresh goes out, the other waits
    /// for it and uses its pair.
    func testConcurrentFetchesOfAnExpiredLoginRefreshOnce() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (200, Self.refreshBody),
            (400, #"{"error": "invalid_grant"}"#),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.delays[ClaudeOAuthClient.tokenEndpoint] = .milliseconds(100)
        let source = StubCredentialSource(credentials: .expired)
        let refresher = TokenRefresher()
        let first = ClaudeProvider(credentialSource: source, transport: transport, refresher: refresher)
        let second = ClaudeProvider(credentialSource: source, transport: transport, refresher: refresher)

        async let a = first.fetchUsage()
        async let b = second.fetchUsage()
        _ = try await (a, b)

        XCTAssertEqual(transport.requests.filter { $0.url == ClaudeOAuthClient.tokenEndpoint }.count, 1)
        let usage = transport.requests.filter { $0.url == ClaudeProvider.usageEndpoint }
        XCTAssertEqual(usage.count, 2)
        XCTAssertTrue(usage.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer new-token" })
        XCTAssertEqual(source.saved.map(\.refreshToken), ["new-refresh"])
    }

    func testAnExpiredLoginIsRenewedUnderTheLock() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (200, Self.refreshBody),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        let source = StubCredentialSource(credentials: .expired)
        let refresher = TokenRefresher(lock: RefreshLock(directory: temporaryDirectory()))
        let provider = ClaudeProvider(credentialSource: source, transport: transport, refresher: refresher)

        _ = try await provider.fetchUsage()

        let usage = transport.requests.filter { $0.url == ClaudeProvider.usageEndpoint }
        XCTAssertEqual(usage.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer new-token"])
        XCTAssertEqual(source.saved.map(\.refreshToken), ["new-refresh"])
    }

    func testTwoProcessesRefreshAnExpiredLoginOnce() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (200, Self.refreshBody),
            (400, #"{"error": "invalid_grant"}"#),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.delays[ClaudeOAuthClient.tokenEndpoint] = .milliseconds(100)
        let source = StubCredentialSource(credentials: .expired)
        let directory = temporaryDirectory()
        let app = ClaudeProvider(
            credentialSource: source, transport: transport,
            refresher: TokenRefresher(lock: RefreshLock(directory: directory))
        )
        let widget = ClaudeProvider(
            credentialSource: source, transport: transport,
            refresher: TokenRefresher(lock: RefreshLock(directory: directory))
        )

        async let a = app.fetchUsage()
        async let b = widget.fetchUsage()
        _ = try await (a, b)

        XCTAssertEqual(transport.requests.filter { $0.url == ClaudeOAuthClient.tokenEndpoint }.count, 1)
        let usage = transport.requests.filter { $0.url == ClaudeProvider.usageEndpoint }
        XCTAssertEqual(usage.count, 2)
        XCTAssertTrue(usage.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer new-token" })
        XCTAssertEqual(source.saved.map(\.refreshToken), ["new-refresh"])
    }

    /// The old refresh token is spent once the endpoint answers, so a
    /// store that refuses the new pair must not lose it: the next fetch
    /// uses it, and it is saved once the store accepts it.
    func testARotatedPairTheStoreRefusesIsKeptAndSavedLater() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (200, Self.refreshBody),
            (400, #"{"error": "invalid_grant"}"#),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        let source = StubCredentialSource(credentials: .expired)
        source.failsSavesAfter = 0
        let refresher = TokenRefresher(saveAttempts: 3, saveRetryDelay: .zero)
        let provider = ClaudeProvider(credentialSource: source, transport: transport, refresher: refresher)

        _ = try await provider.fetchUsage()
        XCTAssertEqual(source.saveAttempts, 3, "retried before giving up")
        XCTAssertTrue(source.saved.isEmpty)

        _ = try await provider.fetchUsage()
        XCTAssertEqual(transport.requests.filter { $0.url == ClaudeOAuthClient.tokenEndpoint }.count, 1)
        let usage = transport.requests.filter { $0.url == ClaudeProvider.usageEndpoint }
        XCTAssertEqual(usage.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")

        source.failsSavesAfter = nil
        _ = try await provider.fetchUsage()
        XCTAssertEqual(source.saved.last?.refreshToken, "new-refresh")
        XCTAssertEqual(transport.requests.filter { $0.url == ClaudeOAuthClient.tokenEndpoint }.count, 1)
    }

    func test429ThrowsRateLimitedWithRetryAfter() async {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (429, "{}", ["Retry-After": "30"]),
        ])
        let source = StubCredentialSource(credentials: .valid)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        await assertThrows(UsageError.rateLimited(retryAfter: 30, body: nil)) {
            _ = try await provider.fetchUsage()
        }
    }

    func testEmptyWindowsThrowsInvalidResponse() async {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, "{}"),
        ])
        let source = StubCredentialSource(credentials: .valid)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        do {
            _ = try await provider.fetchUsage()
            XCTFail("expected invalidResponse")
        } catch let error as UsageError {
            guard case .invalidResponse = error else {
                return XCTFail("expected invalidResponse, got \(error)")
            }
        } catch {
            XCTFail("expected UsageError, got \(error)")
        }
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func assertThrows(
        _ expected: UsageError,
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as UsageError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected UsageError, got \(error)", file: file, line: line)
        }
    }

    func testMissingSubscriptionResolvedFromProfileAndPersisted() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.route(url: ClaudeProvider.profileEndpoint, responses: [
            (200, #"{"account": {"has_claude_pro": false, "has_claude_max": true}}"#),
        ])
        let source = StubCredentialSource(credentials: .withoutSubscription)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.planName, "max")
        // Persisted so the next fetch skips the profile call.
        XCTAssertEqual(source.saved.last?.subscriptionType, "max")
    }

    /// Max 20x became Ultra (2026-10-30) while the profile kept saying
    /// `has_claude_max`: the tier is what tells them apart, as measured on
    /// 2026-11-03 on a Max (5x) and an Ultra account.
    func testMaxTierNamesTheRenamedPlans() throws {
        func plan(_ tier: String?) throws -> String? {
            let organization = tier.map { #", "organization": {"rate_limit_tier": "\#($0)"}"# } ?? ""
            let body = #"{"account": {"has_claude_pro": false, "has_claude_max": true}\#(organization)}"#
            return try JSONDecoder().decode(ClaudeProfileResponse.self, from: Data(body.utf8)).subscriptionType
        }
        XCTAssertEqual(try plan("default_claude_max_20x"), "ultra")
        XCTAssertEqual(try plan("default_claude_max_5x"), "max")
        XCTAssertEqual(try plan("default_claude_ultra"), "ultra")
        XCTAssertEqual(try plan(nil), "max")
    }

    /// A Team seat carries a Max-like tier but neither plan flag: no pill,
    /// as before (measured on a `claude_team` organization).
    func testTeamTierWithoutPlanFlagsHasNoPlan() throws {
        let body = #"{"account": {"has_claude_pro": false, "has_claude_max": false}, "organization": {"rate_limit_tier": "default_claude_max_5x"}}"#
        XCTAssertNil(try JSONDecoder().decode(ClaudeProfileResponse.self, from: Data(body.utf8)).subscriptionType)
    }

    /// The plan write-back must persist only `subscriptionType`, over
    /// whatever tokens are stored *now* — never over the ones this fetch
    /// loaded. Saving the stale pair would put an already-consumed refresh
    /// token back on top of a freshly rotated one, and Anthropic rejects a
    /// consumed refresh token for good.
    func testProfileWriteBackKeepsTokensRotatedMeanwhile() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.route(url: ClaudeProvider.profileEndpoint, responses: [
            (200, #"{"account": {"has_claude_pro": false, "has_claude_max": true}}"#),
        ])
        let source = StubCredentialSource(credentials: .withoutSubscription)
        // Another process (the iOS widget's own fetch) rotates the stored
        // token while this fetch is in flight.
        source.rotatesTo = ClaudeCredentials(
            accessToken: "rotated-token",
            refreshToken: "rotated-refresh",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        _ = try await provider.fetchUsage()

        let saved = try XCTUnwrap(source.saved.last)
        XCTAssertEqual(saved.subscriptionType, "max")
        XCTAssertEqual(saved.accessToken, "rotated-token")
        XCTAssertEqual(saved.refreshToken, "rotated-refresh")
    }

    /// A re-read that fails leaves nothing safe to write the plan over:
    /// the pair this fetch loaded may have been rotated since.
    func testProfileWriteBackSkippedWhenTheStoreCantBeRead() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.route(url: ClaudeProvider.profileEndpoint, responses: [
            (200, #"{"account": {"has_claude_pro": false, "has_claude_max": true}}"#),
        ])
        let source = StubCredentialSource(credentials: .withoutSubscription)
        source.failsLoadsAfter = 1
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.planName, "max")
        XCTAssertTrue(source.saved.isEmpty)
    }

    func testRecentlyCheckedSubscriptionSkipsProfileCall() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        let source = StubCredentialSource(credentials: .valid)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.planName, "pro")
        XCTAssertFalse(transport.requests.contains { $0.url == ClaudeProvider.profileEndpoint })
    }

    /// The upgrade case: a plan cached at login stays cached forever unless
    /// something re-checks it, and the usage response never reports one — so
    /// a Pro → Max move would keep showing "Pro" everywhere the pill renders.
    func testStalePlanIsReverifiedAndPersisted() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.route(url: ClaudeProvider.profileEndpoint, responses: [
            (200, #"{"account": {"has_claude_pro": false, "has_claude_max": true}}"#),
        ])
        let source = StubCredentialSource(credentials: .stalePlan)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.planName, "max")
        XCTAssertEqual(source.saved.last?.subscriptionType, "max")
        let checkedAt = try XCTUnwrap(source.saved.last?.planCheckedAt)
        XCTAssertEqual(checkedAt.timeIntervalSinceNow, 0, accuracy: 5)
    }

    func testUnreachableProfileKeepsLastKnownPlan() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.route(url: ClaudeProvider.profileEndpoint, responses: [
            (500, "boom"),
        ])
        let source = StubCredentialSource(credentials: .stalePlan)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.planName, "pro")
        XCTAssertTrue(source.saved.isEmpty)
    }

    private static let usageBody = """
    {
      "limits": [
        {"kind": "session", "percent": 24, "resets_at": "2026-07-17T05:59:59.620269+00:00"},
        {"kind": "weekly_all", "percent": 14, "resets_at": "2026-07-19T23:59:59.620295+00:00"}
      ]
    }
    """

    private static let refreshBody = """
    {"access_token": "new-token", "refresh_token": "new-refresh", "expires_in": 28800}
    """
}

// MARK: - Stubs

private extension ClaudeCredentials {
    static let valid = ClaudeCredentials(
        accessToken: "valid-token",
        refreshToken: "refresh-token",
        expiresAt: Date(timeIntervalSinceNow: 3600),
        subscriptionType: "pro",
        planCheckedAt: Date()
    )

    static let expired = ClaudeCredentials(
        accessToken: "old-token",
        refreshToken: "refresh-token",
        expiresAt: Date(timeIntervalSinceNow: -60),
        subscriptionType: "pro",
        planCheckedAt: Date()
    )

    /// What the shared store holds after another process refreshed the
    /// same login: a different pair, still valid.
    static let rotatedElsewhere = ClaudeCredentials(
        accessToken: "rotated-token",
        refreshToken: "rotated-refresh",
        expiresAt: Date(timeIntervalSinceNow: 3600),
        subscriptionType: "pro",
        planCheckedAt: Date()
    )

    /// A plan cached longer ago than `planRecheckInterval` — or, with
    /// `planCheckedAt` nil, one cached by a build that never re-checked at
    /// all. Both are what an account that changed plan looks like.
    static let stalePlan = ClaudeCredentials(
        accessToken: "valid-token",
        refreshToken: "refresh-token",
        expiresAt: Date(timeIntervalSinceNow: 3600),
        subscriptionType: "pro",
        planCheckedAt: Date(timeIntervalSinceNow: -ClaudeProvider.planRecheckInterval - 60)
    )

    /// An in-app OAuth connection made before the exchange captured the
    /// subscription — the case the profile fallback exists for.
    static let withoutSubscription = ClaudeCredentials(
        accessToken: "valid-token",
        refreshToken: "refresh-token",
        expiresAt: Date(timeIntervalSinceNow: 3600)
    )
}

private final class StubCredentialSource: ClaudeCredentialSource, @unchecked Sendable {
    let refreshKey = UUID().uuidString
    /// Saves past this many throw, like a Keychain that refuses the write.
    var failsSavesAfter: Int?
    private(set) var saveAttempts = 0
    private(set) var saved: [ClaudeCredentials] = []
    private var credentials: ClaudeCredentials
    /// Replaces the stored credentials right after the first `load()`
    /// (or the `rotatesAfterLoad`th), standing in for another process
    /// rotating the token mid-fetch.
    var rotatesTo: ClaudeCredentials?
    var rotatesAfterLoad = 1
    /// Every `load()` past this many throws, like a Keychain that can't be
    /// read at that moment.
    var failsLoadsAfter: Int?
    private var loads = 0

    init(credentials: ClaudeCredentials) {
        self.credentials = credentials
    }

    /// Two fetches may load and save at once (the concurrency tests).
    private let lock = NSLock()

    func load() async throws -> ClaudeCredentials {
        try lock.withLock {
            loads += 1
            if let failsLoadsAfter, loads > failsLoadsAfter {
                throw UsageError.credentialsNotFound("stub")
            }
            defer {
                if loads == rotatesAfterLoad, let rotated = rotatesTo {
                    credentials = rotated
                }
            }
            return credentials
        }
    }

    func save(_ credentials: ClaudeCredentials) async throws {
        try lock.withLock {
            saveAttempts += 1
            if let failsSavesAfter, saveAttempts > failsSavesAfter {
                throw UsageError.invalidResponse("stub save")
            }
            saved.append(credentials)
            self.credentials = credentials
        }
    }

    func clear() throws {}
}

private final class StubTransport: HTTPTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private var routes: [URL: [(status: Int, body: String, headers: [String: String])]] = [:]
    /// How long a request to the URL takes; a cancelled caller's request
    /// throws, the way URLSession's does.
    var delays: [URL: Duration] = [:]
    var onSend: (@Sendable (URLRequest) -> Void)?

    func route(url: URL, responses: [(Int, String)]) {
        routes[url] = responses.map { ($0.0, $0.1, [:]) }
    }

    func route(url: URL, responses: [(Int, String, [String: String])]) {
        routes[url] = responses
    }

    /// Two fetches may send at once (the concurrency tests).
    private let lock = NSLock()

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let delay = lock.withLock {
            requests.append(request)
            return request.url.flatMap { delays[$0] }
        }
        onSend?(request)
        if let delay {
            try await Task.sleep(for: delay)
        }
        let next = try lock.withLock {
            guard let url = request.url, let queue = routes[url], !queue.isEmpty else {
                throw UsageError.invalidResponse("no stubbed response for \(request.url?.absoluteString ?? "nil")")
            }
            // Consume responses in order; the last one repeats.
            if queue.count > 1 {
                routes[url] = Array(queue.dropFirst())
            }
            return queue[0]
        }
        guard let url = request.url else { throw UsageError.invalidResponse("no url") }
        let response = HTTPURLResponse(
            url: url,
            statusCode: next.status,
            httpVersion: nil,
            headerFields: next.headers
        )!
        return (Data(next.body.utf8), response)
    }
}
