import XCTest
@testable import AIMeter
import UIKit

/// The app icon picked in Settings: Sunset is the bundle's own, every
/// other look has its alternate (iOS) or Dock image (Mac) in the bundle
/// under the name `AppIconChoice` gives it, and the Mac's preference
/// falls back to Sunset.
final class AppIconChoiceTests: XCTestCase {
    func testSunsetIsTheBundlesOwnIcon() {
        XCTAssertNil(AppIconChoice.sunset.alternateIconName)
        XCTAssertNil(AppIconChoice.sunset.dockImageName)
        XCTAssertEqual(AppIconChoice(alternateIconName: nil), .sunset)
    }

    func testEveryChoiceRoundTripsThroughItsAlternateName() {
        for choice in AppIconChoice.allCases {
            XCTAssertEqual(AppIconChoice(alternateIconName: choice.alternateIconName), choice)
        }
        XCTAssertEqual(AppIconChoice(alternateIconName: "AppIcon-Gone"), .sunset, "an icon a later build removed reads as the bundle's own")
        XCTAssertEqual(Set(AppIconChoice.allCases.compactMap(\.alternateIconName)).count, AppIconChoice.allCases.count - 1)
    }

    func testEveryPreviewIsInTheBundle() {
        for choice in AppIconChoice.allCases {
            XCTAssertNotNil(UIImage(named: choice.previewImageName), choice.rawValue)
        }
    }

    func testEveryAlternateIsDeclaredToTheSystem() throws {
        let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any], "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES")
        for choice in AppIconChoice.allCases {
            guard let name = choice.alternateIconName else { continue }
            XCTAssertNotNil(alternates[name], name)
        }
    }
}
