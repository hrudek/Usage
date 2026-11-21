import Foundation

/// Makes the processes that share a login (the app and its widget
/// extension) take turns rotating it: an exclusive `flock` on one file per
/// login in a directory they share. The kernel drops the lock when its
/// holder exits, so an extension killed mid-refresh never leaves a login
/// locked.
///
/// iOS terminates a process suspended while it holds a file lock in a
/// shared container (exception 0xdead10cc), so the lock is only ever tried
/// without blocking and its holder asks for background time. The refresh
/// runs whether or not that time is granted, and keeps the lock until it
/// is over: if iOS kills the holder, the kernel frees the lock.
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

    func withLock<T: Sendable>(key: String, _ body: @Sendable () async throws -> T) async throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("\(key).lock").path
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw UsageError.storage("refresh lock open failed (\(errno))")
        }
        defer { close(descriptor) }
        let finished = DispatchSemaphore(value: 0)
        defer { finished.signal() }
        expiringActivity("Token refresh") { expired in
            if !expired { finished.wait() }
        }
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
        return try await body()
    }
}
