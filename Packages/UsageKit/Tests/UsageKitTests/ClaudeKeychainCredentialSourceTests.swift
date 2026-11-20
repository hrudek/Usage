import XCTest
@testable import UsageKit

final class ClaudeKeychainCredentialSourceTests: XCTestCase {
    func testEveryAccountResolvesToASuffixedKey() {
        XCTAssertEqual(
            ClaudeKeychainCredentialSource.storageKey(for: "work-uuid"),
            "claude.credentials.work-uuid"
        )
    }
}
