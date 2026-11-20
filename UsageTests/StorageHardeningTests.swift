import XCTest
import UsageKit
@testable import Usage

/// What the registry keeps when its stored list is damaged or holds an
/// id twice, and what a Codex login keeps of the tokens it was given.
@MainActor
final class AccountRegistryHardeningTests: XCTestCase {
    private let scratch = ScratchDefaults()
    private var registry: AccountRegistryStore { AccountRegistryStore(userDefaults: scratch.defaults) }

    override func tearDown() async throws {
        scratch.wipe()
    }

    private func entry(_ id: String, name: String, icon: String = "null") -> String {
        """
        {"accountID": "\(id)", "providerID": "claude", "displayName": "\(name)",
         "credentialStrategy": "managed", "connectedAt": "2026-11-01T10:00:00Z", "icon": \(icon)}
        """
    }

    private func store(_ entries: [String]) {
        scratch.defaults.set(Data("[\(entries.joined(separator: ","))]".utf8), forKey: "usage.accounts")
    }

    func testAnEntryThatDoesNotDecodeDropsOnlyItself() {
        store([
            entry("acc-work", name: "Work"),
            entry("acc-odd", name: "Odd", icon: #"{"kind": "mark", "value": "someFutureMark"}"#),
            #"{"accountID": "acc-broken"}"#,
            entry("acc-home", name: "Home", icon: #"{"kind": "symbol", "value": "bolt.fill"}"#),
        ])

        XCTAssertEqual(registry.accounts().map(\.accountID), ["acc-work", "acc-home"])
        XCTAssertEqual(registry.account(for: "acc-home")?.icon, .symbol("bolt.fill"))
    }

    func testAStoredDuplicateIDKeepsItsFirstEntry() {
        store([entry("acc-work", name: "Work"), entry("acc-work", name: "Copy"), entry("acc-home", name: "Home")])

        XCTAssertEqual(registry.accounts().map(\.displayName), ["Work", "Home"])
    }

    func testReplaceAllDropsADuplicateID() {
        registry.replaceAll([
            .managed("acc-work", name: "Work"),
            .managed("acc-home", name: "Home"),
            .managed("acc-work", name: "Copy"),
        ])

        XCTAssertEqual(registry.accounts().map(\.displayName), ["Work", "Home"])
    }

    func testTheModelLoadsAStoredDuplicateOnce() {
        store([entry("acc-work", name: "Work"), entry("acc-work", name: "Copy")])

        let model = UsageModel(registry: registry, platformServices: false)

        XCTAssertEqual(model.accounts.map(\.account.displayName), ["Work"])
    }
}

final class CodexCredentialsStorageTests: XCTestCase {
    func testAnItemStoredWithAnIDTokenStillDecodesAndDropsIt() throws {
        // `JSONEncoder`'s default form, as `KeychainStore` wrote it.
        let stored = """
        {"accessToken": "at-1", "refreshToken": "rt-1", "idToken": "header.payload.signature",
         "accountID": "acct-1", "expiresAt": 800000000, "lastRefresh": 799000000}
        """
        let credentials = try JSONDecoder().decode(CodexCredentials.self, from: Data(stored.utf8))

        XCTAssertEqual(credentials.accessToken, "at-1")
        XCTAssertEqual(credentials.refreshToken, "rt-1")
        XCTAssertEqual(credentials.accountID, "acct-1")
        XCTAssertEqual(credentials.expiresAt, Date(timeIntervalSinceReferenceDate: 800_000_000))

        let encoded = try JSONEncoder().encode(credentials)
        let saved = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertNil(saved?["idToken"], "the next save leaves the id token out")
        XCTAssertEqual(saved?["accountID"] as? String, "acct-1")
    }

    func testTheSignInKeepsTheAccountIDAndNotTheIDToken() async throws {
        let idToken = Self.jwt(["https://api.openai.com/auth": ["chatgpt_account_id": "acct-from-id"]])
        let transport = StubTransport(routes: [
            "/api/accounts/deviceauth/usercode": #"{"device_auth_id": "deviceauth_1", "user_code": "ABCD-1234", "interval": "5"}"#,
            "/api/accounts/deviceauth/token": #"{"authorization_code": "code-1", "code_challenge": "ch", "code_verifier": "ver-1"}"#,
            "/oauth/token": #"{"access_token": "opaque-access", "refresh_token": "rt-9", "id_token": "\#(idToken)", "expires_in": 3600}"#,
        ])
        let auth = CodexDeviceAuth(transport: transport)

        let code = try await auth.requestCode()
        let polled = try await auth.poll(code)
        let credentials = try XCTUnwrap(polled)

        XCTAssertEqual(credentials.accountID, "acct-from-id", "copied from the id token when the access token has none")
        let encoded = try JSONEncoder().encode(credentials)
        let saved = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(saved.contains(idToken))
        XCTAssertFalse(saved.contains("idToken"))
    }

    private static func jwt(_ claims: [String: Any]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return "e30.\(payload).sig"
    }
}

/// Answers each request by its URL's path with a 200 and the given body.
private struct StubTransport: HTTPTransport {
    let routes: [String: String]

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try XCTUnwrap(request.url)
        let body = try XCTUnwrap(routes[url.path], "no route for \(url.path)")
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        return (Data(body.utf8), response)
    }
}
