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

    private func makeModel() -> AuthenticationModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestTransport.self]
        let client = APIClient(environment: .local, session: URLSession(configuration: configuration))
        return AuthenticationModel(client: client,
                                   sessions: SessionStore(client: client, credentials: credentials))
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
