import XCTest
@testable import UsageKit

final class DeadlineTests: XCTestCase {
    func testWorkDoneInTimeIsReturned() async {
        let value = await withDeadline(.seconds(20)) { 1 }
        XCTAssertEqual(value, 1)
    }

    func testTheDeadlineReturnsWithoutWaitingForTheWork() async {
        let gate = Gate()
        let returned = expectation(description: "returned at the deadline")
        let call = Task {
            let value = await withDeadline(.milliseconds(50)) { () -> Int? in
                await gate.wait()
                return 1
            }
            returned.fulfill()
            return value
        }
        await fulfillment(of: [returned], timeout: 10)
        gate.open()
        let value = await call.value
        XCTAssertNil(value)
    }
}

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let waiting = lock.withLock {
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        waiting.forEach { $0.resume() }
    }
}
