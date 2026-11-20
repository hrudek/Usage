import XCTest
import UsageKit
@testable import Usage

/// Which window leads an account card (`AccountCardLayout`): the app's
/// Dashboard card, the small widget and each account of the all-accounts
/// widget all draw from this one rule.
final class AccountCardLayoutTests: XCTestCase {
    func testTheSessionLeadsEvenWhenAnotherWindowIsMoreUsed() {
        let snapshot = UsageSnapshot.make(windows: [
            .make(.session, used: 42, resetsIn: 3600),
            .make(.weekly, used: 61, resetsIn: 86400),
            .make(.modelSpecific("Top model"), used: 18, resetsIn: 86400),
        ])
        let layout = AccountCardLayout(snapshot: snapshot, modelSlotFallback: .auto)
        XCTAssertEqual(layout.hero.kind, .session)
        XCTAssertEqual(layout.heroIndex, 0)
        XCTAssertEqual(layout.others.map(\.kind), [.weekly, .modelSpecific("Top model")])
    }

    func testTheSessionLeadsOverAFlaggedWindow() {
        let snapshot = UsageSnapshot.make(windows: [
            .make(.session, used: 10, resetsIn: 3600),
            UsageWindow(kind: .weekly, usedPct: 40, resetsAt: Date().addingTimeInterval(86400), severity: .exceeded),
        ])
        let layout = AccountCardLayout(snapshot: snapshot, modelSlotFallback: .hidden)
        XCTAssertEqual(layout.hero.kind, .session)
        XCTAssertEqual(layout.others.first?.window?.level, .danger)
    }

    func testWithoutASessionTheMostUsedWindowLeads() {
        let snapshot = UsageSnapshot.make(windows: [
            .make(.weekly, used: 20, resetsIn: 86400),
            .make(.modelSpecific("Top model"), used: 70, resetsIn: 86400),
        ])
        let layout = AccountCardLayout(snapshot: snapshot, modelSlotFallback: .auto)
        XCTAssertEqual(layout.hero.kind, .modelSpecific("Top model"))
        XCTAssertEqual(layout.others.map(\.kind), [.weekly])
    }

    func testBeforeTheFirstFetchThePlaceholderSessionLeads() {
        let layout = AccountCardLayout(snapshot: nil, modelSlotFallback: .auto)
        XCTAssertEqual(layout.hero.kind, .session)
        XCTAssertNil(layout.hero.window)
        XCTAssertEqual(layout.others.map(\.kind), [.weekly])
    }
}
