import XCTest
@testable import Plug

/// Every state the sign-in screens can be in, driven from the responses that produce it.
/// The screens switch exhaustively over these cases, so a state proved here is a state the
/// person can actually reach.
@MainActor
final class AuthenticationModelTests: XCTestCase {
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

    func testPhoneFormattingAndMissingCountryCode() {
        XCTAssertEqual(AuthenticationModel.normalizedPhone("+1 (312) 555-0123"), "+13125550123")
        XCTAssertEqual(AuthenticationModel.normalizedPhone("+234 803 123 4567"), "+2348031234567")
        XCTAssertNil(AuthenticationModel.normalizedPhone("08031234567"))
        XCTAssertNil(AuthenticationModel.normalizedPhone("+123abc45678"))
        XCTAssertNil(AuthenticationModel.normalizedPhone("+0123456789"))
    }

    func testInvalidPhoneDoesNotCallTheServer() async {
        TestTransport.handler = { _ in XCTFail("Invalid number must not reach the server"); throw URLError(.badURL) }
        let model = makeModel()
        await model.sendCode(to: "08031234567")
        guard case .failed(let message, _) = model.state else { return XCTFail("Expected phone guidance") }
        XCTAssertTrue(message.contains("country code"))
    }

    func testGuestSignInReachesTheSignedInState() async throws {
        respond(with: try TestSessions.encoded(TestSessions.make(accessExpiresIn: 900,
                                                                 refreshExpiresIn: 86_400)), status: 201)
        let model = makeModel()
        await model.continueAsGuest()
        guard case .signedIn(let session) = model.state else {
            return XCTFail("Expected a signed-in state, got \(model.state)")
        }
        XCTAssertEqual(session.account.type, .guest)
        XCTAssertFalse(credentials.isEmpty, "The session must be stored so it survives a relaunch.")
    }

    func testAWrongCodeIsReportedAsWrongAndAnExpiredOneAsExpired() async throws {
        respond(with: Data(#"""
            {"error":{"code":"validation_failed","message":"That code is not correct.","request_id":"req_1",
             "details":[{"field":"code","code":"invalid"}]}}
            """#.utf8), status: 400)
        let model = makeModel()
        await model.verifyCode("000000", challengeID: "cha_1")
        XCTAssertEqual(model.state, .codeRejected(challengeID: "cha_1", reason: .invalid))

        respond(with: Data(#"""
            {"error":{"code":"validation_failed","message":"That code has expired.","request_id":"req_2",
             "details":[{"field":"code","code":"expired"}]}}
            """#.utf8), status: 400)
        await model.verifyCode("000000", challengeID: "cha_1")
        XCTAssertEqual(model.state, .codeRejected(challengeID: "cha_1", reason: .expired))
    }

    func testRunningOutOfAttemptsBecomesTheRateLimitedState() async throws {
        respond(with: Data(#"""
            {"error":{"code":"rate_limited","message":"Too many attempts. Try again shortly.",
             "request_id":"req_3","retry_after_seconds":900}}
            """#.utf8), status: 429)
        let model = makeModel()
        await model.verifyCode("000000", challengeID: "cha_1")
        XCTAssertEqual(model.state, .rateLimited(retryAfterSeconds: 900))
    }

    func testAnAccountLinkConflictIsItsOwnStateWithTheServersWording() async throws {
        respond(with: Data(#"""
            {"error":{"code":"conflict","message":"That sign-in is already connected to another PLUG account.",
             "request_id":"req_4"}}
            """#.utf8), status: 409)
        let model = makeModel()
        await model.signInWithApple(identityToken: "token", rawNonce: "nonce-value-0000000000000000")
        XCTAssertEqual(model.state,
                       .accountLinkConflict(message: "That sign-in is already connected to another PLUG account."))
    }

    func testNoCodeChannelBecomesTheUnavailableStateRatherThanAFailure() async throws {
        respond(with: Data(#"""
            {"error":{"code":"dependency_unavailable","message":"We cannot send codes right now.",
             "request_id":"req_5","retry_after_seconds":60}}
            """#.utf8), status: 503)
        let model = makeModel()
        await model.sendCode(to: "+15555550100")
        XCTAssertEqual(model.state, .unavailable(message: "We cannot send codes right now."))
    }

    func testBeingOfflineIsItsOwnStateAndSaysNothingWasLost() async {
        TestTransport.handler = { _ in throw URLError(.notConnectedToInternet) }
        let model = makeModel()
        await model.sendCode(to: "+15555550100")
        XCTAssertEqual(model.state, .offline(retryPreserved: true))
    }

    func testConsentBehindTheCurrentVersionAsksBeforeShowingTheProduct() async throws {
        let session = TestSessions.make(accessExpiresIn: 900, refreshExpiresIn: 86_400,
                                        acceptedVersion: "2020-01-01")
        respond(with: try TestSessions.encoded(session), status: 201)
        let model = makeModel()
        await model.continueAsGuest()
        guard case .consentRequired = model.state else {
            return XCTFail("Expected the consent state, got \(model.state)")
        }
    }

    func testADeniedNotificationPermissionDoesNotBlockSignIn() async throws {
        let model = makeModel()
        model.notificationPermissionDenied()
        XCTAssertEqual(model.state, .notificationsDenied)

        // The manual path is still open: the same sign-in choices are offered from here.
        respond(with: try TestSessions.encoded(TestSessions.make(accessExpiresIn: 900,
                                                                 refreshExpiresIn: 86_400)), status: 201)
        await model.continueAsGuest()
        guard case .signedIn = model.state else {
            return XCTFail("A declined notification must not stop sign-in, got \(model.state)")
        }
    }

    func testSigningOutReturnsToTheSignedOutState() async throws {
        respond(with: try TestSessions.encoded(TestSessions.make(accessExpiresIn: 900,
                                                                 refreshExpiresIn: 86_400)), status: 201)
        let model = makeModel()
        await model.continueAsGuest()
        respond(with: Data(), status: 204)
        await model.signOut()
        XCTAssertEqual(model.state, .signedOut)
        XCTAssertTrue(credentials.isEmpty)
    }

    func testExistingAccountSignupOffersSignInAndDoesNotSaveASession() async {
        respond(with: Data(#"{"error":{"code":"conflict","message":"Sign in instead.","details":[{"field":"intent","code":"account_exists","message":"Sign in instead."}]}}"#.utf8), status: 409)
        let model = makeModel()
        await model.signInWithGoogle(identityToken: "synthetic", nonce: "synthetic-nonce-for-test", creatingAccount: true)
        XCTAssertEqual(model.state, .accountExists)
        XCTAssertTrue(credentials.isEmpty)
    }

    func testGoogleRequestsCarryTheSelectedIntent() async throws {
        for creating in [true, false] {
            TestTransport.handler = { request in
                let data: Data
                if let body = request.httpBody { data = body }
                else {
                    let stream = try XCTUnwrap(request.httpBodyStream)
                    stream.open()
                    defer { stream.close() }
                    var bytes = Data()
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        bytes.append(buffer, count: count)
                    }
                    data = bytes
                }
                let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
                XCTAssertEqual(payload["intent"], creating ? "sign_up" : "sign_in")
                let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 201,
                    httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
                return (response, try TestSessions.encoded(TestSessions.make(accessExpiresIn: 900,
                    refreshExpiresIn: 86_400, accountType: .google)))
            }
            let model = makeModel()
            await model.signInWithGoogle(identityToken: "synthetic", nonce: "synthetic-nonce-for-test", creatingAccount: creating)
            guard case .signedIn = model.state else { return XCTFail("Expected verified session") }
        }
    }

    func testUnknownAccountSignInOffersSignup() async {
        respond(with: Data(#"{"error":{"code":"conflict","message":"Create an account.","details":[{"field":"intent","code":"account_not_found","message":"Create an account."}]}}"#.utf8), status: 409)
        let model = makeModel()
        await model.signInWithGoogle(identityToken: "synthetic", nonce: "synthetic-nonce-for-test")
        XCTAssertEqual(model.state, .accountNotFound)
        XCTAssertTrue(credentials.isEmpty)
    }

    private func makeModel() -> AuthenticationModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestTransport.self]
        let client = APIClient(environment: .local, session: URLSession(configuration: configuration))
        return AuthenticationModel(client: client,
                                   sessions: SessionStore(client: client, credentials: credentials))
    }

    func testRestorePreservesCredentialsThroughAServerOutageAndRetry() async throws {
        let session = TestSessions.make(accessExpiresIn: 900, refreshExpiresIn: 86_400)
        try credentials.save(TestSessions.encoded(session), account: SessionStore.account)
        let model = makeModel()
        respond(with: Data(#"{"error":{"code":"dependency_unavailable","message":"Try again."}}"#.utf8), status: 503)
        await model.restore()
        XCTAssertFalse(credentials.isEmpty)
        respond(with: try TestSessions.encoded(session), status: 200)
        await model.retry()
        XCTAssertEqual(model.state, .signedIn(session))
    }

    func testGuestUpgradeRefreshesExpiredAccessAndKeepsTheGuestIdentity() async throws {
        let guest = TestSessions.make(accessExpiresIn: -60, refreshExpiresIn: 86_400)
        try credentials.save(TestSessions.encoded(guest), account: SessionStore.account)
        let rotated = TestSessions.make(accessToken: "pat_rotated", refreshToken: "prt_rotated",
                                        accessExpiresIn: 900, refreshExpiresIn: 86_400)
        let member = TestSessions.make(accessExpiresIn: 900, refreshExpiresIn: 86_400, accountType: .phone)
        let calls = Counter()
        TestTransport.handler = { request in
            calls.increment()
            let body: Data
            let status: Int
            if request.url?.path == "/v1/auth/refresh" {
                body = try TestSessions.encoded(rotated)
                status = 200
            } else {
                XCTAssertEqual(request.url?.path, "/v1/auth/phone/verify")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer pat_rotated")
                body = try TestSessions.encoded(member)
                status = 201
            }
            return (try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])), body)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestTransport.self]
        let client = APIClient(environment: .local, session: URLSession(configuration: configuration))
        let store = SessionStore(client: client, credentials: credentials)
        _ = await store.restore()
        let model = AuthenticationModel(client: client, sessions: store)
        await model.verifyCode("123456", challengeID: "cha_test", creatingAccount: true)
        XCTAssertEqual(calls.value, 2)
        XCTAssertEqual(model.state, .signedIn(member))
    }

    func testContinuingAsGuestDuringUpgradeKeepsTheExistingAccount() async throws {
        let session = TestSessions.make(accessExpiresIn: 900, refreshExpiresIn: 86_400)
        respond(with: try TestSessions.encoded(session), status: 201)
        let model = makeModel()
        await model.continueAsGuest()
        model.startOver()
        TestTransport.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/me", "Do not create a second guest during upgrade.")
            return (try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])),
                try TestSessions.encoded(session))
        }
        await model.continueAsGuest()
        XCTAssertEqual(model.state, .signedIn(session))
    }

    func testAcceptedConsentIsPersistedForTheNextLaunch() async throws {
        let session = TestSessions.make(accessExpiresIn: 900, refreshExpiresIn: 86_400,
                                        acceptedVersion: "2020-01-01")
        respond(with: try TestSessions.encoded(session), status: 201)
        let model = makeModel()
        await model.continueAsGuest()
        let accepted = Consent(currentVersion: PlugConsent.version,
                               acceptedVersion: PlugConsent.version, acceptedAt: session.consent.acceptedAt)
        respond(with: try PlugJSON.encoder.encode(accepted), status: 200)
        await model.acceptConsent()
        let data = try XCTUnwrap(credentials.read(account: SessionStore.account))
        let saved = try PlugJSON.decoder.decode(Session.self, from: data)
        XCTAssertEqual(saved.consent, accepted)
        XCTAssertEqual(model.state, .signedIn(saved))
    }

    func testExpiredTunnelShowsServerErrorInsteadOfClaimingUserIsOffline() async {
        TestTransport.handler = { _ in throw URLError(.cannotFindHost) }
        let model = makeModel()
        await model.signInWithGoogle(identityToken: "synthetic", nonce: "synthetic-nonce-for-test")
        guard case .failed(let message, let canRetry) = model.state else { return XCTFail("Expected server guidance") }
        XCTAssertTrue(message.contains("server address"))
        XCTAssertTrue(canRetry)
    }

    private func respond(with body: Data, status: Int) {
        TestTransport.handler = { request in
            let headers = status == 204
                ? ["X-Request-Id": "req_test"]
                : ["Content-Type": "application/json", "X-Request-Id": "req_test"]
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status,
                httpVersion: nil, headerFields: headers))
            return (response, body)
        }
    }
}
