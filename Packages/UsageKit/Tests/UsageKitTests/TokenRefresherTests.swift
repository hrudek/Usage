import XCTest
@testable import UsageKit

final class TokenRefresherTests: XCTestCase {
    func testConcurrentRefreshesOfOneKeyRunOnce() async throws {
        let refresher = TokenRefresher()
        let counter = Counter()

        let results = try await withThrowingTaskGroup(of: Pair.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await refresher.refresh(key: "claude.credentials.a") {
                        let run = await counter.next()
                        try await Task.sleep(for: .milliseconds(300))
                        return Pair(refreshToken: "new-\(run)")
                    }
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        let runs = await counter.value
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(Set(results.map(\.refreshToken)), ["new-1"])
    }

    func testDifferentLoginsDoNotWaitForEachOther() async throws {
        let refresher = TokenRefresher()
        let overlap = Overlap()
        async let a = refresher.refresh(key: "a") {
            await overlap.enter()
            try await Task.sleep(for: .milliseconds(300))
            await overlap.leave()
            return Pair(refreshToken: "a")
        }
        async let b = refresher.refresh(key: "b") {
            await overlap.enter()
            try await Task.sleep(for: .milliseconds(300))
            await overlap.leave()
            return Pair(refreshToken: "b")
        }
        let (first, second) = try await (a, b)
        let peak = await overlap.peak
        XCTAssertEqual(peak, 2, "both refreshes ran at the same time")
        XCTAssertEqual([first.refreshToken, second.refreshToken], ["a", "b"])
    }

    /// A kept pair is never saved again while its login rotates: the
    /// rotation's successor would land first and be overwritten.
    func testAKeptPairIsNotWrittenBackWhileItsLoginRotates() async throws {
        let refresher = TokenRefresher(saveAttempts: 1, saveRetryDelay: .zero)
        let store = Store(Pair(refreshToken: "old"))
        await store.refuseSaves(true)
        await refresher.persist(Pair(refreshToken: "kept"), replacing: "old", key: "a") { try await store.save($0) }
        await store.refuseSaves(false)

        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
        let rotation = Task {
            try await refresher.refresh(key: "a") {
                startedContinuation.yield()
                for await _ in release { break }
                let next = Pair(refreshToken: "newer")
                await refresher.persist(next, replacing: "kept", key: "a") { try await store.save($0) }
                return next
            }
        }
        for await _ in started { break }

        let served = try await refresher.credentials(key: "a", load: { await store.pair }, save: { try await store.save($0) })
        XCTAssertEqual(served.refreshToken, "kept")
        let during = await store.pair
        XCTAssertEqual(during.refreshToken, "old", "no write-back while the rotation runs")

        releaseContinuation.yield()
        _ = try await rotation.value
        let after = await store.pair
        XCTAssertEqual(after.refreshToken, "newer")
    }

    /// The plan write waits for a rotation under way and lands on its pair.
    func testAPlanWriteWaitsForARotationAndKeepsItsPair() async throws {
        let refresher = TokenRefresher()
        let store = Store(Pair(refreshToken: "old"))
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
        let rotation = Task {
            try await refresher.refresh(key: "a") {
                startedContinuation.yield()
                for await _ in release { break }
                let next = Pair(refreshToken: "new")
                try await store.save(next)
                return next
            }
        }
        for await _ in started { break }

        let update = Task {
            await refresher.update(key: "a", load: { await store.pair }, save: { try await store.save($0) }) {
                $0.plan = "max"
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        let attempts = await store.attempts
        XCTAssertEqual(attempts, 0, "nothing written while the rotation runs")

        releaseContinuation.yield()
        _ = try await rotation.value
        await update.value
        let after = await store.pair
        XCTAssertEqual(after.refreshToken, "new")
        XCTAssertEqual(after.plan, "max")
    }

    func testAFinishedRefreshDoesNotAnswerTheNextOne() async throws {
        let refresher = TokenRefresher()
        let counter = Counter()
        for _ in 0..<2 {
            _ = try await refresher.refresh(key: "a") {
                let run = await counter.next()
                return Pair(refreshToken: "new-\(run)")
            }
        }
        let runs = await counter.value
        XCTAssertEqual(runs, 2)
    }

    func testAFailedRefreshThrowsAndLeavesTheKeyFree() async throws {
        let refresher = TokenRefresher()
        do {
            let _: Pair = try await refresher.refresh(key: "a") { throw UsageError.notAuthenticated }
            XCTFail("expected the refresh's error")
        } catch {
            XCTAssertEqual(error as? UsageError, .notAuthenticated)
        }
        let next: Pair = try await refresher.refresh(key: "a") { Pair(refreshToken: "next") }
        XCTAssertEqual(next.refreshToken, "next")
    }

    func testAPairTheStoreRefusesIsServedUntilItIsSaved() async throws {
        let refresher = TokenRefresher(saveAttempts: 2, saveRetryDelay: .zero)
        let store = Store(Pair(refreshToken: "old"))
        await store.refuseSaves(true)

        await refresher.persist(Pair(refreshToken: "new"), replacing: "old", key: "a") { try await store.save($0) }
        let attempts = await store.attempts
        XCTAssertEqual(attempts, 2)

        let served = try await refresher.credentials(key: "a", load: { await store.pair }, save: { try await store.save($0) })
        XCTAssertEqual(served.refreshToken, "new")

        await store.refuseSaves(false)
        let saved = try await refresher.credentials(key: "a", load: { await store.pair }, save: { try await store.save($0) })
        XCTAssertEqual(saved.refreshToken, "new")
        let stored = await store.pair
        XCTAssertEqual(stored.refreshToken, "new")
    }

    /// A store that moved on (a new sign-in) wins over a pair kept in memory.
    func testAStoreThatMovedOnWinsOverTheKeptPair() async throws {
        let refresher = TokenRefresher(saveAttempts: 1, saveRetryDelay: .zero)
        let store = Store(Pair(refreshToken: "old"))
        await store.refuseSaves(true)
        await refresher.persist(Pair(refreshToken: "new"), replacing: "old", key: "a") { try await store.save($0) }

        await store.replace(with: Pair(refreshToken: "signed-in-again"))
        let served = try await refresher.credentials(key: "a", load: { await store.pair }, save: { try await store.save($0) })
        XCTAssertEqual(served.refreshToken, "signed-in-again")

        // And the kept pair is gone for good.
        await store.refuseSaves(false)
        _ = try await refresher.credentials(key: "a", load: { await store.pair }, save: { try await store.save($0) })
        let stored = await store.pair
        XCTAssertEqual(stored.refreshToken, "signed-in-again")
    }

    /// A store that can't be read right now still has the kept pair served.
    func testAnUnreadableStoreServesTheKeptPair() async throws {
        let refresher = TokenRefresher(saveAttempts: 1, saveRetryDelay: .zero)
        await refresher.persist(Pair(refreshToken: "new"), replacing: "old", key: "a") { _ in
            throw UsageError.invalidResponse("locked")
        }
        let served: Pair = try await refresher.credentials(
            key: "a",
            load: { throw UsageError.invalidResponse("locked") },
            save: { _ in throw UsageError.invalidResponse("locked") }
        )
        XCTAssertEqual(served.refreshToken, "new")
    }
}

private struct Pair: RotatingCredentials {
    var refreshToken: String?
    var plan: String?
    var isExpired: Bool { false }
}

private actor Counter {
    private(set) var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}

private actor Overlap {
    private var running = 0
    private(set) var peak = 0

    func enter() {
        running += 1
        peak = max(peak, running)
    }

    func leave() { running -= 1 }
}

private actor Store {
    private(set) var pair: Pair
    private(set) var attempts = 0
    private var refuses = false

    init(_ pair: Pair) { self.pair = pair }

    func refuseSaves(_ refuses: Bool) { self.refuses = refuses }
    func replace(with pair: Pair) { self.pair = pair }

    func save(_ pair: Pair) throws {
        attempts += 1
        if refuses { throw UsageError.invalidResponse("refused") }
        self.pair = pair
    }
}
