import XCTest
import UsageKit
@testable import AIMeter

/// iOS 18's control reads like the Lock Screen gauge: the glance window,
/// its short title and the percentage as Settings displays it.
final class ControlFigureTests: XCTestCase {

    func testNoSnapshotYet() {
        let figure = ControlFigure(accountID: "a", name: "Work", snapshot: nil, prefs: Preferences.load(from: ScratchDefaults().defaults))
        XCTAssertEqual(figure.figure, "--")
        XCTAssertEqual(figure.fraction, 0)
    }
}
