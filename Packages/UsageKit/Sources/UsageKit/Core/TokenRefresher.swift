import Foundation

/// Credentials whose refresh token names the pair they belong to.
public protocol RotatingCredentials: Sendable {
    var refreshToken: String? { get }
    var isExpired: Bool { get }
}

/// Keeps a login's token refreshes in order.
///
/// Both providers rotate the refresh token on every use, and OpenAI
/// revokes the whole token family when a spent one comes back. So a
/// login is refreshed once at a time: a caller that needs a refresh while
/// one runs for the same key joins it instead of sending the same token
/// again. With a `RefreshLock`, rotations and writes of a login also take
/// turns with other processes (the app and its widget extension), and a
/// rotation that waited finds the other process's pair in the store.
///
/// It also keeps a rotated pair the store refused to save: the old
/// refresh token is spent by then, so that pair is the only login left.
/// Every other write to a login (saving that kept pair again, the plan
/// write-back) runs while no rotation of it does, so it can never put a
/// spent pair back over a newer one.
public actor TokenRefresher {
    public static let shared = TokenRefresher()

    private struct Unsaved {
        let credentials: any Sendable
        /// The refresh token of the stored pair this one replaced. While
        /// the store still holds that pair, this one is newer.
        let replacing: String?
    }

    private var inFlight: [String: Task<any Sendable, any Error>] = [:]
    /// Writes other than a rotation's own save, one per key at a time.
    private var writes: [String: Task<Void, any Error>] = [:]
    private var unsaved: [String: Unsaved] = [:]
    private let saveAttempts: Int
    private let saveRetryDelay: Duration
    private let lock: RefreshLock?

    /// - Parameter lock: shared with the other processes that rotate the
    ///   same logins; nil keeps the turns within this process.
    public init(
        saveAttempts: Int = 3,
        saveRetryDelay: Duration = .milliseconds(250),
        lock: RefreshLock? = nil
    ) {
        self.saveAttempts = max(1, saveAttempts)
        self.saveRetryDelay = saveRetryDelay
        self.lock = lock
    }

    /// Runs `rotation` for `key`, or waits for the one already running for
    /// it and returns its result. The rotation runs in a task of its own,
    /// so a cancelled caller never abandons a refresh the server already
    /// accepted.
    public func refresh<C: Sendable>(
        key: String,
        _ rotation: @escaping @Sendable () async throws -> C
    ) async throws -> C {
        while true {
            if let running = inFlight[key] {
                defer { clear(running, of: key) }
                let value = try await running.value
                return try Self.typed(value)
            }
            guard await waitForWrite(of: key) else { break }
        }
        let lock = lock
        let task = Task<any Sendable, any Error> { try await Self.holding(lock, key, rotation) }
        inFlight[key] = task
        defer { clear(task, of: key) }
        let value = try await task.value
        return try Self.typed(value)
    }

    /// Saves a freshly rotated pair, trying again when the store refuses
    /// it. If every attempt fails, the pair stays in memory and
    /// `credentials(key:load:save:)` serves it until a save succeeds.
    public func persist<C: RotatingCredentials>(
        _ credentials: C,
        replacing old: String?,
        key: String,
        save: @Sendable (C) async throws -> Void
    ) async {
        for attempt in 1...saveAttempts {
            do {
                try await save(credentials)
                unsaved[key] = nil
                return
            } catch {
                if attempt < saveAttempts { try? await Task.sleep(for: saveRetryDelay) }
            }
        }
        // A pair rotated from an unsaved one still replaces what the store
        // holds, which is the pair before both.
        let replacing = unsaved[key].map(\.replacing) ?? old
        unsaved[key] = Unsaved(credentials: credentials, replacing: replacing)
    }

    /// The login to use for `key`: what the store holds, unless a rotated
    /// pair could not be saved and the store still holds the pair it
    /// replaced. Then that pair is saved again and returned.
    public func credentials<C: RotatingCredentials>(
        key: String,
        load: @Sendable () async throws -> C,
        save: @escaping @Sendable (C) async throws -> Void
    ) async throws -> C {
        guard let pending = unsaved[key], let newer = pending.credentials as? C else {
            return try await load()
        }
        let stored: C
        do {
            stored = try await load()
        } catch {
            if let usageError = error as? UsageError, case .credentialsNotFound = usageError {
                // The login was removed; so is the pair that replaced it.
                unsaved[key] = nil
                throw error
            }
            return newer
        }
        guard stored.refreshToken == pending.replacing else {
            // The store moved on (a later save, a new sign-in): it wins.
            unsaved[key] = nil
            return stored
        }
        guard let current = unsaved[key]?.credentials as? C,
              current.refreshToken == newer.refreshToken else {
            // The kept pair was rotated during the load, so it is spent:
            // start over from what is current now.
            return try await credentials(key: key, load: load, save: save)
        }
        // A rotation under way saves this pair's successor, and a write
        // under way may be saving this very pair: neither needs another.
        guard inFlight[key] == nil, writes[key] == nil else { return newer }
        if (try? await exclusiveWrite(key) { try await save(newer) }) != nil {
            unsaved[key] = nil
        }
        return newer
    }

    /// Changes fields of the stored login that a rotation leaves alone
    /// (the plan), on what the store holds once no rotation of it runs.
    /// Skipped when the store can't be read.
    public func update<C: RotatingCredentials>(
        key: String,
        load: @escaping @Sendable () async throws -> C,
        save: @escaping @Sendable (C) async throws -> Void,
        _ change: @escaping @Sendable (inout C) -> Void
    ) async {
        await waitForTurn(of: key)
        try? await exclusiveWrite(key) {
            var latest = try await load()
            change(&latest)
            try await save(latest)
        }
    }

    /// Stores a new sign-in for `key` once no rotation or write of it
    /// runs, so a rotation can't put the replaced login back over it.
    public func save(key: String, _ write: @escaping @Sendable () async throws -> Void) async throws {
        await waitForTurn(of: key)
        try await exclusiveWrite(key, write)
    }

    private func waitForTurn(of key: String) async {
        while true {
            if let running = inFlight[key] {
                _ = try? await running.value
                clear(running, of: key)
            } else if !(await waitForWrite(of: key)) {
                break
            }
        }
    }

    /// Runs `write` as the key's one write; the caller checked that none
    /// is running. A rotation asked for meanwhile waits for it.
    private func exclusiveWrite(_ key: String, _ write: @escaping @Sendable () async throws -> Void) async throws {
        let lock = lock
        let task = Task<Void, any Error> { try await Self.holding(lock, key, write) }
        writes[key] = task
        defer { if writes[key] == task { writes[key] = nil } }
        try await task.value
    }

    /// Waits for the key's running write, if any, and says whether there
    /// was one.
    private func waitForWrite(of key: String) async -> Bool {
        guard let write = writes[key] else { return false }
        _ = await write.result
        if writes[key] == write { writes[key] = nil }
        return true
    }

    /// Frees the key once `task` is done. Whoever sees it finish first
    /// clears it, so a waiter never spins on a finished task; a newer
    /// task in the slot stays.
    private func clear(_ task: Task<any Sendable, any Error>, of key: String) {
        if inFlight[key] == task { inFlight[key] = nil }
    }

    private static func holding<T: Sendable>(
        _ lock: RefreshLock?,
        _ key: String,
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        guard let lock else { return try await body() }
        return try await lock.withLock(key: key, body)
    }

    private static func typed<C>(_ value: any Sendable) throws -> C {
        guard let typed = value as? C else {
            throw UsageError.invalidResponse("a refresh of another credential type ran under the same key")
        }
        return typed
    }
}
