import Foundation

/// Credentials whose refresh token names the pair they belong to.
public protocol RotatingCredentials: Sendable {
    var refreshToken: String? { get }
    var isExpired: Bool { get }
}

/// Keeps a login's token refreshes in order within one process.
///
/// Both providers rotate the refresh token on every use, and OpenAI
/// revokes the whole token family when a spent one comes back. So a
/// login is refreshed once at a time: a caller that needs a refresh while
/// one runs for the same key joins it instead of sending the same token
/// again. Only the app refreshes; the widget extension builds its
/// providers with `allowsRefresh == false`.
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
    private var writes: [String: Task<Bool, Never>] = [:]
    private var unsaved: [String: Unsaved] = [:]
    private let saveAttempts: Int
    private let saveRetryDelay: Duration

    public init(saveAttempts: Int = 3, saveRetryDelay: Duration = .milliseconds(250)) {
        self.saveAttempts = max(1, saveAttempts)
        self.saveRetryDelay = saveRetryDelay
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
        let task = Task<any Sendable, any Error> { try await rotation() }
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
        // A rotation under way saves this pair's successor, and a write
        // under way may be saving this very pair: neither needs another.
        guard inFlight[key] == nil, writes[key] == nil else { return newer }
        if await exclusiveWrite(key, { (try? await save(newer)) != nil }) {
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
        while true {
            if let running = inFlight[key] {
                _ = try? await running.value
                clear(running, of: key)
            } else if !(await waitForWrite(of: key)) {
                break
            }
        }
        _ = await exclusiveWrite(key) {
            guard var latest = try? await load() else { return false }
            change(&latest)
            return (try? await save(latest)) != nil
        }
    }

    /// Runs `write` as the key's one write and returns whether it saved;
    /// the caller checked that none is running. A rotation asked for
    /// meanwhile waits for it.
    private func exclusiveWrite(_ key: String, _ write: @escaping @Sendable () async -> Bool) async -> Bool {
        let task = Task<Bool, Never> { await write() }
        writes[key] = task
        let saved = await task.value
        if writes[key] == task { writes[key] = nil }
        return saved
    }

    /// Waits for the key's running write, if any, and says whether there
    /// was one.
    private func waitForWrite(of key: String) async -> Bool {
        guard let write = writes[key] else { return false }
        _ = await write.value
        if writes[key] == write { writes[key] = nil }
        return true
    }

    /// Frees the key once `task` is done. Whoever sees it finish first
    /// clears it, so a waiter never spins on a finished task; a newer
    /// task in the slot stays.
    private func clear(_ task: Task<any Sendable, any Error>, of key: String) {
        if inFlight[key] == task { inFlight[key] = nil }
    }

    private static func typed<C>(_ value: any Sendable) throws -> C {
        guard let typed = value as? C else {
            throw UsageError.invalidResponse("a refresh of another credential type ran under the same key")
        }
        return typed
    }
}
