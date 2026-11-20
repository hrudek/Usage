import XCTest
@testable import UsageKit

/// The length a periodic window advances a missing reset by.
final class PeriodicResetTests: XCTestCase {
    func testAMonthlyWindowAdvancesAMissingResetByItsOwnLength() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-3600)
        let month: TimeInterval = 30 * 86400
        let previous = UsageSnapshot(providerID: "codex", windows: [
            UsageWindow(kind: .weekly, usedPct: 50, resetsAt: old, duration: month),
        ])
        let fresh = UsageSnapshot(providerID: "codex", windows: [
            UsageWindow(kind: .weekly, usedPct: 0, resetsAt: nil, duration: month),
        ])

        let filled = fresh.fillingMissingResets(from: previous, now: now)

        XCTAssertEqual(filled.weeklyWindow?.resetsAt, old.addingTimeInterval(month))
    }
}
