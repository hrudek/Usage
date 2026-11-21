import Foundation

/// Makes the processes that share a login (the app and its widget
/// extension) take turns rotating it: an exclusive `flock` on one file per
/// login in a directory they share. The kernel drops the lock when its
/// holder exits, so an extension killed mid-refresh never leaves a login
/// locked.
///
/// iOS terminates a process suspended while it holds a file lock in a
/// shared container (exception 0xdead10cc). So the lock is only ever tried
/// without blocking, and its holder asks for background time; if that
/// time runs out, the lock is dropped at once. A refusal changes nothing:
/// the refresh runs anyway.
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
    public init(directory: URL, timeout: Duration = .seconds(8)) {
        self.init(directory: directory, timeout: timeout) { reason, block in
            ProcessInfo.processInfo.performExpiringActivity(withReason: reason, using: block)
        }
    }

    init(directory: URL, timeout: Duration, expiringActivity: @escaping ExpiringActivity) {
        self.directory = directory
        self.timeout = timeout
        self.expiringActivity = expiringActivity
    }

    /// Runs `body` while holding the lock for `key`.
    func withLock<T: Sendable>(key: String, _ body: @Sendable () async throws -> T) async throws -> T {
        let file = try LockFile(path: directory.appendingPathComponent("\(key).lock"))
        defer { file.release() }
        file.holdBackgroundTime(using: expiringActivity)
        let deadline = ContinuousClock.now + timeout
        while try !file.tryLock() {
            guard ContinuousClock.now < deadline else {
                throw UsageError.storage("another process is still refreshing \(key)")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try await body()
    }
}

/// One open lock file. Closing it releases the lock, from whichever comes
/// first: the end of the refresh or the end of its background time.
private final class LockFile: @unchecked Sendable {
    private let state = NSLock()
    private var descriptor: Int32?
    private var granted = false
    private var expired = false
    private let ended = DispatchSemaphore(value: 0)

    init(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let descriptor = open(path.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw UsageError.storage("refresh lock open failed (\(errno))")
        }
        self.descriptor = descriptor
    }

    /// The system calls the block with `false` to grant time, which lasts
    /// while that call blocks, or with `true` alone to refuse it; once
    /// granted time runs out it calls the block again with `true`, on
    /// another thread, so the two calls may arrive in either order.
    func holdBackgroundTime(using expiringActivity: RefreshLock.ExpiringActivity) {
        expiringActivity("Token refresh") { [self] expired in
            let timeRanOut = state.withLock {
                if expired { self.expired = true } else { granted = true }
                return granted && self.expired
            }
            if timeRanOut {
                release()
            } else if !expired {
                ended.wait()
            }
        }
    }

    /// Whether the lock was taken; false while another process holds it.
    func tryLock() throws -> Bool {
        try state.withLock {
            guard let descriptor else {
                throw UsageError.storage("background time ran out before the refresh lock was taken")
            }
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return true }
            let error = errno
            guard error == EWOULDBLOCK || error == EINTR else {
                throw UsageError.storage("refresh lock failed (\(error))")
            }
            return false
        }
    }

    func release() {
        let wasOpen = state.withLock {
            defer { descriptor = nil }
            guard let descriptor else { return false }
            close(descriptor)
            return true
        }
        if wasOpen { ended.signal() }
    }
}
