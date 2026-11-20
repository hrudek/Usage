import XCTest
import UsageKit
@testable import AIMeter

final class ProviderCatalogTests: XCTestCase {
    func testKnownProviderName() {
        XCTAssertEqual(ProviderCatalog.displayName(for: ClaudeProvider.providerID), ClaudeProvider.providerDisplayName)
        XCTAssertEqual(ProviderCatalog.defaultProviderID, ClaudeProvider.providerID)
    }

    func testLegacyAccountIsTheMigratedSentinel() {
        let legacy = ProviderCatalog.legacyAccount
        XCTAssertEqual(legacy.accountID, ClaudeKeychainCredentialSource.legacyAccountID)
        XCTAssertEqual(legacy.providerID, ClaudeProvider.providerID)
        XCTAssertEqual(legacy.credentialStrategy, .managed)
    }

    func testFallbackAccountKeepsItsOwnID() {
        let fallback = ProviderCatalog.fallbackAccount(for: "7F2C-work")
        XCTAssertEqual(fallback.accountID, "7F2C-work", "its own Keychain key, never another account's")
        XCTAssertEqual(fallback.providerID, ProviderCatalog.defaultProviderID)
        XCTAssertEqual(fallback.credentialStrategy, .managed)
        let legacy = ProviderCatalog.fallbackAccount(for: ClaudeKeychainCredentialSource.legacyAccountID)
        XCTAssertEqual(legacy.accountID, ProviderCatalog.legacyAccount.accountID, "the legacy id falls back to the legacy account")
        XCTAssertEqual(legacy.displayName, ProviderCatalog.legacyAccount.displayName)
    }

    func testMakeProviderBuildsTheClaudeProvider() {
        let keychain = KeychainStore(service: "aimeter.tests")
        let bundle = ProviderCatalog.makeProvider(for: .managed("x", name: "X"), keychain: keychain, allowsRefresh: true)
        XCTAssertTrue(bundle.provider is ClaudeProvider)
        XCTAssertTrue(bundle.credentials is ClaudeKeychainCredentialSource)
        XCTAssertEqual(bundle.provider.id, ClaudeProvider.providerID)
    }

    /// The widget extension builds its providers this way: they read the
    /// stored login and never rotate it.
    func testWidgetProvidersNeverRefresh() {
        let keychain = KeychainStore(service: "aimeter.tests")
        let claude = ProviderCatalog.makeProvider(for: .managed("x", name: "X"), keychain: keychain, allowsRefresh: false)
        XCTAssertEqual((claude.credentials as? ClaudeKeychainCredentialSource)?.allowsRefresh, false)

        let codexAccount = ConnectedAccount(
            accountID: "y", providerID: CodexProvider.providerID, displayName: "Y", credentialStrategy: .managed
        )
        let codex = ProviderCatalog.makeProvider(for: codexAccount, keychain: keychain, allowsRefresh: false)
        XCTAssertTrue(codex.provider is CodexProvider)
        XCTAssertEqual((codex.credentials as? CodexKeychainCredentialSource)?.allowsRefresh, false)

        let app = ProviderCatalog.makeProvider(for: codexAccount, keychain: keychain, allowsRefresh: true)
        XCTAssertEqual((app.credentials as? CodexKeychainCredentialSource)?.allowsRefresh, true)
    }


}
