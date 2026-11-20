import XCTest
@testable import UsageKit

/// Opt-in integration test against the real endpoint with the local Claude
/// Code login. Never runs in CI: requires AIMETER_LIVE_TEST=1.
///
///     AIMETER_LIVE_TEST=1 swift test --filter LiveClaudeProviderTests
final class LiveClaudeProviderTests: XCTestCase {
    func testFetchUsageAgainstRealAccount() async throws {
        throw XCTSkip("live test is macOS-only")
    }
}
