import Foundation

/// Makes the processes that share a login (the app and its widget
/// extension) take turns rotating it: an exclusive `flock` on one file per
/// login in a directory they share. The kernel drops the lock when its
/// holder exits, so an extension killed mid-refresh never leaves a login
/// locked.
///
/// iOS terminates a process suspended while it holds a file lock in a
/// shared container (exception 0xdead10cc), so the lock is only taken
/// under background time the system granted. When that time runs out the
/// work under the lock is cancelled and the lock dropped before the
/// process is suspended; when the system grants none, nothing is locked
/// or refreshed.
public struct RefreshLock: Sendable {
    /// `ProcessInfo.performExpiringActivity(withReason:using:)`.
    typealias ExpiringActivity = @Sendable (String, @escaping @Sendable (Bool) -> Void) -> Void

    private let directory: URL
    private let timeout: Duration
    private let expiringActivity: ExpiringActivity

    /// The App Group container's `refresh-locks/` folder; nil when the
    /// container can't be resolved.
    public init?(appGroupID: String) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        self.init(directory: container.appendingPathComponent("refresh-locks", isDirectory: true))
    }

    /// - Parameter timeout: how long to wait for another process's
    ///   refresh before giving up with `UsageError.storage`.
    public init(directory: URL, timeout: Duration = .seconds(20)) {
        self.init(directory: directory, timeout: timeout) { reason, block in
            ProcessInfo.processInfo.performExpiringActivity(withReason: reason, using: block)
        }
    }

    init(directory: URL, timeout: Duration, expiringActivity: @escaping ExpiringActivity) {
        self.directory = directory
        self.timeout = timeout
        self.expiringActivity = expiringActivity
    }

    /// Runs `body` while holding the lock for `key`. Throws
    /// `UsageError.storage` without running it when the system grants no
    /// background time, and `CancellationError` when that time ran out.
    func withLock<T: Sendable>(key: String, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        let activity = BackgroundActivity()
        guard await activity.begin(reason: "Token refresh", using: expiringActivity) else {
            throw UsageError.storage("no background time to refresh \(key)")
        }
        let work = Task {
            let descriptor = try lockFile(for: key)
            defer { close(descriptor) }
            try await acquire(descriptor, key: key)
            return try await body()
        }
        activity.onExpiration { work.cancel() }
        defer { activity.end() }
        return try await work.value
    }

    private func lockFile(for key: String) throws -> Int32 {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("\(key).lock").path
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw UsageError.storage("refresh lock open failed (\(errno))")
        }
        return descriptor
    }

    private func acquire(_ descriptor: Int32, key: String) async throws {
        let deadline = ContinuousClock.now + timeout
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let error = errno
            guard error == EWOULDBLOCK || error == EINTR else {
                throw UsageError.storage("refresh lock failed (\(error))")
            }
            guard ContinuousClock.now < deadline else {
                throw UsageError.storage("another process is still refreshing \(key)")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// Background time for one locked refresh. The system calls the activity
/// block with `false` to grant time (the time lasts while that call
/// blocks) or with `true` to refuse it, and calls it again with `true`
/// when granted time runs out; the process is suspended once that call
/// returns.
private final class BackgroundActivity: @unchecked Sendable {
    /// How long expiry waits for the cancelled work to drop the lock.
    private static let expiryGrace: DispatchTimeInterval = .seconds(2)

    private let state = NSLock()
    private var answer: CheckedContinuation<Bool, Never>?
    private var granted = false
    private var expired = false
    private var cancelWork: (@Sendable () -> Void)?
    private let ended = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    /// Whether the system granted background time.
    func begin(reason: String, using expiringActivity: RefreshLock.ExpiringActivity) async -> Bool {
        await withCheckedContinuation { continuation in
            state.withLock { answer = continuation }
            expiringActivity(reason) { [self] expired in
                if expired {
                    expire()
                } else {
                    resolve(true)
                    released.wait()
                }
            }
        }
    }

    /// Cancels the work when the time runs out, at once if it already has.
    func onExpiration(_ cancel: @escaping @Sendable () -> Void) {
        let expiredAlready = state.withLock {
            cancelWork = cancel
            return expired
        }
        if expiredAlready { cancel() }
    }

    func end() {
        ended.signal()
        released.signal()
    }

    private func resolve(_ granted: Bool) {
        let continuation = state.withLock {
            self.granted = granted
            defer { answer = nil }
            return answer
        }
        continuation?.resume(returning: granted)
    }

    /// A refusal before any grant, or granted time running out: then the
    /// work is cancelled and the call holds the suspension until the lock
    /// is dropped.
    private func expire() {
        let (wasGranted, cancel) = state.withLock {
            expired = true
            return (granted, cancelWork)
        }
        guard wasGranted else { return resolve(false) }
        cancel?()
        _ = ended.wait(timeout: .now() + Self.expiryGrace)
    }
}
