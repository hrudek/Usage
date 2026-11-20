import XCTest
@testable import UsageKit

final class AccountRegistryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "AccountRegistryStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func account(_ accountID: String, displayName: String = "Claude") -> ConnectedAccount {
        ConnectedAccount(
            accountID: accountID,
            providerID: "claude",
            displayName: displayName,
            connectedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func testEmptyRegistryReturnsNoAccounts() {
        let store = AccountRegistryStore(userDefaults: defaults)
        XCTAssertEqual(store.accounts(), [])
        XCTAssertNil(store.account(for: "claude"))
    }

    func testAddAppendsInOrder() {
        let store = AccountRegistryStore(userDefaults: defaults)
        XCTAssertTrue(store.add(account("claude", displayName: "Personal")))
        XCTAssertTrue(store.add(account("work-uuid", displayName: "Work")))

        XCTAssertEqual(store.accounts().map(\.accountID), ["claude", "work-uuid"])
        XCTAssertEqual(store.account(for: "work-uuid")?.displayName, "Work")
    }

    func testAddingDuplicateAccountIDIsANoOp() {
        let store = AccountRegistryStore(userDefaults: defaults)
        XCTAssertTrue(store.add(account("claude", displayName: "First")))
        XCTAssertFalse(store.add(account("claude", displayName: "Second")))

        XCTAssertEqual(store.accounts().count, 1)
        XCTAssertEqual(store.account(for: "claude")?.displayName, "First")
    }

    func testRenameUpdatesDisplayNameOnly() {
        let store = AccountRegistryStore(userDefaults: defaults)
        store.add(account("claude", displayName: "Claude"))

        store.rename("claude", to: "Personal")

        let renamed = store.account(for: "claude")
        XCTAssertEqual(renamed?.displayName, "Personal")
        XCTAssertEqual(renamed?.accountID, "claude")
    }

    func testRenameMissingAccountIsANoOp() {
        let store = AccountRegistryStore(userDefaults: defaults)
        store.rename("claude", to: "Personal")
        XCTAssertEqual(store.accounts(), [])
    }

    func testRemoveDropsOnlyThatAccount() {
        let store = AccountRegistryStore(userDefaults: defaults)
        store.add(account("claude"))
        store.add(account("work-uuid", displayName: "Work"))

        store.remove("claude")

        XCTAssertEqual(store.accounts().map(\.accountID), ["work-uuid"])
    }

    func testReplaceAllOverwritesTheWholeList() {
        let store = AccountRegistryStore(userDefaults: defaults)
        store.add(account("claude"))

        store.replaceAll([account("a", displayName: "A"), account("b", displayName: "B")])

        XCTAssertEqual(store.accounts().map(\.accountID), ["a", "b"])
    }

    func testReplaceAllPersistsANewOrder() {
        let store = AccountRegistryStore(userDefaults: defaults)
        store.add(account("claude"))
        store.add(account("work-uuid", displayName: "Work"))

        // What a dashboard drag-reorder writes: same accounts, new order.
        store.replaceAll(store.accounts().reversed())

        XCTAssertEqual(store.accounts().map(\.accountID), ["work-uuid", "claude"])
        XCTAssertEqual(store.account(for: "work-uuid")?.displayName, "Work")
    }

    // MARK: Icons

    func testIconRoundTripsAndClears() {
        let store = AccountRegistryStore(userDefaults: defaults)
        store.add(account("a"))
        XCTAssertNil(store.account(for: "a")?.icon, "an account starts on the default mark")

        store.setIcon(.symbol("bolt.fill"), for: "a")
        XCTAssertEqual(store.account(for: "a")?.icon, .symbol("bolt.fill"))

        store.setIcon(.mark(.claudeCode), for: "a")
        XCTAssertEqual(store.account(for: "a")?.icon, .mark(.claudeCode))

        store.setIcon(nil, for: "a")
        XCTAssertNil(store.account(for: "a")?.icon)
    }

    func testRegistryWrittenBeforeIconsDecodesWithoutOne() throws {
        // The exact JSON a 1.5 build wrote: no `icon` key at all.
        let legacy = """
        [{"accountID":"a","providerID":"claude","displayName":"Work","credentialStrategy":"managed","connectedAt":"2027-01-15T00:00:00Z"}]
        """
        defaults.set(Data(legacy.utf8), forKey: "usage.accounts")
        let store = AccountRegistryStore(userDefaults: defaults)
        let decoded = store.accounts()
        XCTAssertEqual(decoded.map(\.displayName), ["Work"])
        XCTAssertNil(decoded.first?.icon)
    }

    func testIconEncodesAsKindAndValue() throws {
        let data = try JSONEncoder().encode(AccountIcon.mark(.claude))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json, ["kind": "mark", "value": "claude"])
        XCTAssertEqual(try JSONDecoder().decode(AccountIcon.self, from: data), .mark(.claude))
    }

    func testStoredMarksDecodeUnchangedAlongsideOpenAI() throws {
        let stored: [(String, AccountIcon)] = [
            (#"{"kind":"mark","value":"claude"}"#, .mark(.claude)),
            (#"{"kind":"mark","value":"claudeCode"}"#, .mark(.claudeCode)),
            (#"{"kind":"symbol","value":"bolt.fill"}"#, .symbol("bolt.fill")),
            (#"{"kind":"mark","value":"openAI"}"#, .mark(.openAI)),
        ]
        for (json, icon) in stored {
            XCTAssertEqual(try JSONDecoder().decode(AccountIcon.self, from: Data(json.utf8)), icon)
            let encoded = try JSONEncoder().encode(icon)
            XCTAssertEqual(try JSONDecoder().decode(AccountIcon.self, from: encoded), icon)
        }
    }
}
