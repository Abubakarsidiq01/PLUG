import XCTest
@testable import Plug

/// Relaunch, refresh and sign-out, which together are the outcome sentence for this phase:
/// the session survives a relaunch, and logging out ends it on the server.
final class SessionStoreTests: XCTestCase {
    private var credentials = InMemoryCredentialStore()

    override func setUp() {
        super.setUp()
        credentials = InMemoryCredentialStore()
        TestTransport.handler = nil
    }

    override func tearDown() {
        TestTransport.handler = nil
        super.tearDown()
    }

    func testAStoredSessionSurvivesARelaunch() async throws {
        let store = makeStore()
        let session = TestSessions.make(accessExpiresIn: 900, refreshExpiresIn: 86_400)
        try await store.adopt(session)

        // A second store is the same thing a relaunch is: nothing in memory, everything
        // read back from the Keychain.
        let afterRelaunch = makeStore()
        let restored = await afterRelaunch.restore()
        XCTAssertEqual(restored, session)
        let token = try await afterRelaunch.validAccessToken()
        XCTAssertEqual(token, session.accessToken)
    }

    func testASessionWhoseRefreshWindowClosedIsNotRestored() async throws {
        let store = makeStore()
        try await store.adopt(TestSessions.make(accessExpiresIn: -60, refreshExpiresIn: -1))
        let afterRelaunch = makeStore()
        let restored = await afterRelaunch.restore()
        XCTAssertNil(restored)
        XCTAssertTrue(credentials.isEmpty, "An unusable session must not be left on the device.")
    }

    func testAnExpiredAccessTokenIsRefreshedOnce() async throws {
        let rotated = TestSessions.make(accessToken: "pat_rotated", refreshToken: "prt_rotated",
                                        accessExpiresIn: 900, refreshExpiresIn: 86_400)
        let calls = Counter()
        TestTransport.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/auth/refresh")
            calls.increment()
            return (try Self.jsonResponse(for: request), try TestSessions.encoded(rotated))
        }
        let store = makeStore()
        try await store.adopt(TestSessions.make(accessExpiresIn: -60, refreshExpiresIn: 86_400))

        // Two callers waking at the same moment must produce one refresh. Two would spend
        // the same refresh token twice, and the second would look exactly like a replay.
        async let first = store.validAccessToken()
        async let second = store.validAccessToken()
        let tokens = try await [first, second]
        XCTAssertEqual(tokens, ["pat_rotated", "pat_rotated"])
        XCTAssertEqual(calls.value, 1)
    }

    func testARefusedRefreshClearsTheStoredSession() async throws {
        TestTransport.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 401,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            return (response, Data(#"{"error":{"code":"unauthenticated","message":"Sign in again.","request_id":"req_1"}}"#.utf8))
        }
        let store = makeStore()
        try await store.adopt(TestSessions.make(accessExpiresIn: -60, refreshExpiresIn: 86_400))
        do {
            _ = try await store.validAccessToken()
            XCTFail("A refused refresh must not return a token.")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "unauthenticated")
        }
        XCTAssertTrue(credentials.isEmpty, "The device must agree with the server that the session is over.")
    }

    func testSignOutCallsTheServerBeforeClearingTheDevice() async throws {
        let calledLogout = Counter()
        TestTransport.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/auth/logout")
            // Server-side revocation is the authoritative step. Clearing the Keychain alone
            // would leave a working session behind (manual.docx 20.2).
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer pat_test")
            calledLogout.increment()
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 204,
                httpVersion: nil, headerFields: nil))
            return (response, Data())
        }
        let store = makeStore()
        try await store.adopt(TestSessions.make(accessExpiresIn: 900, refreshExpiresIn: 86_400))
        await store.signOut()
        XCTAssertEqual(calledLogout.value, 1)
        XCTAssertTrue(credentials.isEmpty)
        let restored = await makeStore().restore()
        XCTAssertNil(restored)
    }

    func testSignOutClearsTheDeviceEvenWhenTheServerCannotBeReached() async throws {
        TestTransport.handler = { _ in throw URLError(.notConnectedToInternet) }
        let store = makeStore()
        try await store.adopt(TestSessions.make(accessExpiresIn: 900, refreshExpiresIn: 86_400))
        await store.signOut()
        XCTAssertTrue(credentials.isEmpty)
    }

    private func makeStore() -> SessionStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestTransport.self]
        let client = APIClient(environment: .local, session: URLSession(configuration: configuration))
        return SessionStore(client: client, credentials: credentials)
    }

    func testSignOutRefreshesExpiredAccessBeforeRevokingTheSession() async throws {
        let calls = Counter()
        let rotated = TestSessions.make(accessToken: "pat_rotated", refreshToken: "prt_rotated",
                                        accessExpiresIn: 900, refreshExpiresIn: 86_400)
        TestTransport.handler = { request in
            calls.increment()
            if request.url?.path == "/v1/auth/refresh" {
                return (try Self.jsonResponse(for: request), try TestSessions.encoded(rotated))
            }
            XCTAssertEqual(request.url?.path, "/v1/auth/logout")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer pat_rotated")
            return (try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 204,
                                                  httpVersion: nil, headerFields: nil)), Data())
        }
        let store = makeStore()
        try await store.adopt(TestSessions.make(accessExpiresIn: -60, refreshExpiresIn: 86_400))
        await store.signOut()
        XCTAssertEqual(calls.value, 2)
        XCTAssertTrue(credentials.isEmpty)
    }

    func testFailedCredentialWriteDoesNotReplaceTheCurrentSession() async throws {
        let store = makeStore()
        let original = TestSessions.make(accessExpiresIn: 900, refreshExpiresIn: 86_400)
        try await store.adopt(original)
        credentials.failSave = true
        do {
            try await store.adopt(TestSessions.make(accessToken: "pat_unsaved",
                                                    accessExpiresIn: 900, refreshExpiresIn: 86_400))
            XCTFail("A failed save must be reported.")
        } catch { XCTAssertEqual(error as? KeychainError, .unableToSave(-1)) }
        let current = await store.current()
        XCTAssertEqual(current, original)
    }

    func testAnInFlightRefreshCannotRestoreAForgottenSession() async throws {
        let started = expectation(description: "Refresh reached the server")
        let release = DispatchSemaphore(value: 0)
        let rotated = TestSessions.make(accessToken: "pat_rotated", refreshToken: "prt_rotated",
                                        accessExpiresIn: 900, refreshExpiresIn: 86_400)
        TestTransport.handler = { request in
            started.fulfill()
            guard release.wait(timeout: .now() + 5) == .success else { throw URLError(.timedOut) }
            return (try Self.jsonResponse(for: request), try TestSessions.encoded(rotated))
        }
        let store = makeStore()
        try await store.adopt(TestSessions.make(accessExpiresIn: -60, refreshExpiresIn: 86_400))
        let refresh = Task { try await store.validAccessToken() }
        await fulfillment(of: [started], timeout: 5)
        await store.forget()
        release.signal()
        do {
            _ = try await refresh.value
            XCTFail("A cancelled session must not return refreshed credentials.")
        } catch { /* Cancellation and signed-out responses are both safe outcomes. */ }
        let current = await store.current()
        XCTAssertNil(current)
        XCTAssertTrue(credentials.isEmpty)
    }

    func testSessionDescriptionsNeverExposeTokens() {
        let session = TestSessions.make(accessExpiresIn: 900, refreshExpiresIn: 86_400)
        XCTAssertEqual(String(describing: session), "Session[redacted]")
        XCTAssertEqual(String(reflecting: session), "Session[redacted]")
    }

    private static func jsonResponse(for request: URLRequest) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "X-Request-Id": "req_test"]))
    }
}

/// Counts calls across the concurrency boundary the URLProtocol stub sits on.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}

enum TestSessions {
    static func make(accessToken: String = "pat_test", refreshToken: String = "prt_test",
                     accessExpiresIn: TimeInterval, refreshExpiresIn: TimeInterval,
                     accountType: Account.AccountType = .guest,
                     acceptedVersion: String? = PlugConsent.version) -> Session {
        // Whole seconds, because these values make a round trip through ISO-8601 and a
        // fractional part would make an equality assertion fail for the wrong reason.
        let base = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        return Session(accessToken: accessToken,
                accessTokenExpiresAt: base.addingTimeInterval(accessExpiresIn),
                refreshToken: refreshToken,
                refreshTokenExpiresAt: base.addingTimeInterval(refreshExpiresIn),
                account: Account(userId: "usr_test", type: accountType,
                                 scopes: [accountType == .guest ? "guest" : "member"]),
                consent: Consent(currentVersion: PlugConsent.version,
                                 acceptedVersion: acceptedVersion, acceptedAt: base))
    }

    static func encoded(_ session: Session) throws -> Data {
        try PlugJSON.encoder.encode(session)
    }
}
