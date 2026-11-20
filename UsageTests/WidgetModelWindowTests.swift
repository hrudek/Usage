import XCTest
import UsageKit
@testable import Usage

final class WidgetModelWindowTests: XCTestCase {
    private var scratch: ScratchDefaults!

    override func setUp() {
        scratch = ScratchDefaults()
    }

    override func tearDown() {
        scratch.wipe()
    }

    private let snapshot = UsageSnapshot.make(windows: [
        .make(.session, used: 10),
        .make(.weekly, used: 20),
        .make(.modelSpecific("Fable"), used: 5),
    ])

    func testShownByDefault() {
        XCTAssertTrue(WidgetModelWindowPreference(accountID: "a", defaults: scratch.defaults).isShown)
        XCTAssertEqual(snapshot.forWidgets(of: "a", defaults: scratch.defaults).windows.count, 3)
    }

    func testHiddenDropsOnlyThatAccountsModelWindow() {
        WidgetModelWindowPreference(accountID: "a", defaults: scratch.defaults).isShown = false
        let shown = snapshot.forWidgets(of: "a", defaults: scratch.defaults)
        XCTAssertEqual(shown.windows.map(\.kind), [.session, .weekly])
        XCTAssertEqual(WindowSlots(snapshot: shown, modelSlotFallback: .hidden).slots.count, 2)
        XCTAssertEqual(snapshot.forWidgets(of: "b", defaults: scratch.defaults).windows.count, 3)
    }

    func testClearRestoresTheDefault() {
        let pref = WidgetModelWindowPreference(accountID: "a", defaults: scratch.defaults)
        pref.isShown = false
        pref.clear()
        XCTAssertTrue(pref.isShown)
        XCTAssertNil(scratch.defaults.object(forKey: "widget.showsModelWindow.a"))
    }
}
