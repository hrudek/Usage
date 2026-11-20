import XCTest
import UsageKit
@testable import AIMeter

/// The second provider family: how the slots read a snapshot that has
/// no session, and the titles a window's own length gives it.
final class ProviderCatalogMultiProviderTests: XCTestCase {
    private let keychain = KeychainStore(service: "aimeter.tests")




}

final class WindowSlotsMultiProviderTests: XCTestCase {
    private let now = Date()
    private let month: TimeInterval = 30 * 86400

    private func codexFree() -> UsageSnapshot {
        UsageSnapshot(providerID: "codex", planName: "free", windows: [
            UsageWindow(kind: .weekly, usedPct: 12, resetsAt: now.addingTimeInterval(20 * 86400), duration: month),
        ])
    }


    func testAMonthAloneIsOneSlotNotAnEmptySessionBesideIt() {
        let slots = WindowSlots(snapshot: codexFree(), modelSlotFallback: .auto).slots
        XCTAssertEqual(slots.map(\.kind), [.weekly])
        XCTAssertEqual(slots.first?.window?.duration, month)
        XCTAssertEqual(WindowSlots(snapshot: codexFree(), modelSlotFallback: .credits).slots.map(\.kind), [.weekly, .credits], "the third-slot fallback still applies")
    }


}

final class WindowTitleTests: XCTestCase {
    func testTitlesFollowTheWindowsLength() {
        XCTAssertEqual(UsageWindow.Kind.session.title(duration: nil), "5-hour session")
        XCTAssertEqual(UsageWindow.Kind.session.title(duration: 5 * 3600), "5-hour session")
        XCTAssertEqual(UsageWindow.Kind.session.title(duration: 3 * 3600), "3-hour session")
        XCTAssertEqual(UsageWindow.Kind.weekly.title(duration: nil), "Weekly")
        XCTAssertEqual(UsageWindow.Kind.weekly.title(duration: 7 * 86400), "Weekly")
        XCTAssertEqual(UsageWindow.Kind.weekly.title(duration: 30 * 86400), "Monthly")
        XCTAssertEqual(UsageWindow.Kind.weekly.title(duration: 31 * 86400), "Monthly")
        XCTAssertEqual(UsageWindow.Kind.weekly.title(duration: 14 * 86400), "14-day window")
        XCTAssertEqual(UsageWindow.Kind.modelSpecific("Spark").title(duration: 7 * 86400), "Weekly · Spark")
        XCTAssertEqual(UsageWindow.Kind.modelSpecific("Spark").title(duration: 30 * 86400), "Monthly · Spark")
        XCTAssertEqual(UsageWindow.Kind.credits.title(duration: nil), "Credits")
    }

    func testShortTitlesAndTheWindowsOwn() {
        XCTAssertEqual(UsageWindow.Kind.weekly.shortTitle(duration: nil), "Week")
        XCTAssertEqual(UsageWindow.Kind.weekly.shortTitle(duration: 30 * 86400), "Month")
        XCTAssertEqual(UsageWindow.Kind.weekly.shortTitle(duration: 14 * 86400), "14d")
        let month = UsageWindow(kind: .weekly, usedPct: 1, duration: 30 * 86400)
        XCTAssertEqual(month.title, "Monthly")
        XCTAssertEqual(month.shortTitle, "Month")
        let snapshot = UsageSnapshot(providerID: "codex", windows: [month])
        XCTAssertEqual(snapshot.title(for: .weekly), "Monthly")
        XCTAssertEqual(snapshot.title(for: .session), "5-hour session", "the kind's own when the account has no such window")
    }

}
