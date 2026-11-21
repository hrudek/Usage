import Foundation

/// Makes the processes that share a login (the app and its widget
/// extension) take turns rotating it: an exclusive `flock` on one file per
/// login in a directory they share. The kernel drops the lock when its
/// holder exits, so an extension killed mid-refresh never leaves a login
/// locked.
public struct RefreshLock: Sendable {
    private let directory: URL
    private let timeout: Duration

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
        self.directory = directory
        self.timeout = timeout
    }

    /// Runs `body` while holding the lock for `key`.
    func withLock<T: Sendable>(key: String, _ body: @Sendable () async throws -> T) async throws -> T {
        let assertion = BackgroundAssertion(reason: "Token refresh")
        defer { assertion.end() }
        let descriptor = try lockFile(for: key)
        defer { close(descriptor) }
        try await acquire(descriptor, key: key)
        return try await body()
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

/// Keeps the process from being suspended while it holds a lock: iOS
/// terminates a process suspended while holding a file lock in a shared
/// container (exception 0xdead10cc).
private final class BackgroundAssertion: Sendable {
    private let released = DispatchSemaphore(value: 0)

    init(reason: String) {
        let released = released
        ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { expired in
            guard !expired else { return }
            released.wait()
        }
    }

    func end() {
        released.signal()
    }
}
