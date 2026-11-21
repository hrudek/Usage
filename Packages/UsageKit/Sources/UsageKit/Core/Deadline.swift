import Foundation

/// What `work` returns, or nil once `limit` has passed. Returns at the
/// limit without waiting: `work` is cancelled then, but what it does not
/// stop for (a token rotation and its save) still finishes afterwards.
public func withDeadline<T: Sendable>(
    _ limit: Duration,
    _ work: @escaping @Sendable () async -> T?
) async -> T? {
    await withCheckedContinuation { continuation in
        let first = FirstResult(continuation)
        let working = Task { await work() }
        let timer = Task {
            guard (try? await Task.sleep(for: limit)) != nil else { return }
            working.cancel()
            first.resume(nil)
        }
        Task {
            let value = await working.value
            first.resume(value)
            timer.cancel()
        }
    }
}

private final class FirstResult<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T?) {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: value)
    }
}
