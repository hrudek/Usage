import XCTest
import UsageKit
@testable import Usage

final class ProviderCatalogTests: XCTestCase {
    func testKnownProviderName() {
        XCTAssertEqual(ProviderCatalog.displayName(for: ClaudeProvider.providerID), ClaudeProvider.providerDisplayName)
        XCTAssertEqual(ProviderCatalog.defaultProviderID, ClaudeProvider.providerID)
    }

    func testMakeProviderBuildsTheClaudeProvider() {
        let keychain = KeychainStore(service: "usage.tests")
        let bundle = ProviderCatalog.makeProvider(for: .managed("x", name: "X"), keychain: keychain)
        XCTAssertTrue(bundle.provider is ClaudeProvider)
        XCTAssertTrue(bundle.credentials is ClaudeKeychainCredentialSource)
        XCTAssertEqual(bundle.provider.id, ClaudeProvider.providerID)
    }

    func testMakeProviderBuildsTheCodexProvider() {
        let keychain = KeychainStore(service: "usage.tests")
        let account = ConnectedAccount(accountID: "y", providerID: CodexProvider.providerID, displayName: "Y")
        let bundle = ProviderCatalog.makeProvider(for: account, keychain: keychain)
        XCTAssertTrue(bundle.provider is CodexProvider)
        XCTAssertTrue(bundle.credentials is CodexKeychainCredentialSource)
    }
}
