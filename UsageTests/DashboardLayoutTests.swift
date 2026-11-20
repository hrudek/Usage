import XCTest
@testable import Usage

final class DashboardLayoutTests: XCTestCase {
    private let innerLandscape = CGSize(width: 951, height: 669)
    private let innerPortrait = CGSize(width: 669, height: 951)

    func testARegularWidthWiderThanTallPutsTheDetailBesideTheCards() {
        let layout = DashboardLayout(isRegularWidth: true, size: innerLandscape, activeFold: nil, hasAccounts: true)
        XCTAssertEqual(layout, .sideBySide)
        XCTAssertTrue(layout.selectsAccounts)
    }

    func testARegularWidthTallerThanWideKeepsTheStack() {
        let layout = DashboardLayout(isRegularWidth: true, size: innerPortrait, activeFold: nil, hasAccounts: true)
        XCTAssertEqual(layout, .stack)
        XCTAssertFalse(layout.selectsAccounts)
    }

    func testACompactWidthKeepsTheStackWhateverTheShape() {
        let phoneOnItsSide = CGSize(width: 852, height: 393)
        XCTAssertEqual(DashboardLayout(isRegularWidth: false, size: phoneOnItsSide, activeFold: nil, hasAccounts: true), .stack)
        XCTAssertEqual(DashboardLayout(isRegularWidth: false, size: CGSize(width: 466, height: 678), activeFold: nil, hasAccounts: true), .stack)
    }

    func testNoAccountKeepsTheStackSoTheConnectPromptFillsTheScreen() {
        let fold = CGRect(x: 460, y: 0, width: 31, height: 669)
        XCTAssertEqual(DashboardLayout(isRegularWidth: true, size: innerLandscape, activeFold: nil, hasAccounts: false), .stack)
        XCTAssertEqual(DashboardLayout(isRegularWidth: true, size: innerLandscape, activeFold: fold, hasAccounts: false), .stack)
    }

    func testAFoldRunningDownTheDisplayPutsTheDetailBesideTheCards() {
        let fold = CGRect(x: 460, y: 0, width: 31, height: 669)
        XCTAssertEqual(DashboardLayout(isRegularWidth: true, size: innerLandscape, activeFold: fold, hasAccounts: true), .sideBySide)
    }

    func testAFoldAcrossTheDisplayPutsTheDetailBelowIt() {
        let fold = CGRect(x: 0, y: 460, width: 669, height: 31)
        let layout = DashboardLayout(isRegularWidth: true, size: innerPortrait, activeFold: fold, hasAccounts: true)
        XCTAssertEqual(layout, .aboveAndBelow(top: 460, gap: 31))
        XCTAssertTrue(layout.selectsAccounts)
    }

    func testAFoldAcrossTheDisplayWinsOverACompactWidth() {
        let fold = CGRect(x: 0, y: 460, width: 669, height: 31)
        XCTAssertEqual(
            DashboardLayout(isRegularWidth: false, size: innerPortrait, activeFold: fold, hasAccounts: true),
            .aboveAndBelow(top: 460, gap: 31)
        )
    }

    func testAFoldAtTheContainersEdgeLeavesNoPaneAndKeepsTheStack() {
        let fold = CGRect(x: 0, y: -10, width: 669, height: 31)
        XCTAssertEqual(DashboardLayout(isRegularWidth: true, size: innerPortrait, activeFold: fold, hasAccounts: true), .stack)
    }

    func testTheDetailShowsTheSelectedAccountWhileItIsConnected() {
        XCTAssertEqual(DashboardLayout.shownAccount(selected: "b", in: ["a", "b"]), "b")
    }

    func testTheDetailFallsBackToTheFirstAccount() {
        XCTAssertEqual(DashboardLayout.shownAccount(selected: nil, in: ["a", "b"]), "a")
        XCTAssertEqual(DashboardLayout.shownAccount(selected: "gone", in: ["a", "b"]), "a")
        XCTAssertNil(DashboardLayout.shownAccount(selected: "gone", in: []))
    }
}
