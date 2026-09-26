import OSLog
import XCTest
@testable import Plug

/// Drives the real client against a real running backend, over a real socket, with nothing
/// stubbed. Skipped unless `PLUG_INTEGRATION_API_URL` is set, so an ordinary test run and
/// CI are unaffected.
///
/// It exists for the one thing the mocked tests cannot show: that a request leaving the app
/// and a line in the backend's log are the same request. The correlation id printed here is
/// the value to search for on the server side, and it is the mechanic the connected
/// checkpoint in manual.docx §7 step 5 depends on.
///
///     PLUG_INTEGRATION_API_URL=http://127.0.0.1:8081 \
///       xcodebuild test -project ios/Plug.xcodeproj -scheme Plug -only-testing:PlugTests/LiveBackendTests ...
@MainActor
final class LiveBackendTests: XCTestCase {
    /// Defaults to the address `docs/phases/P1-ONE.md` tells you to run the backend on, so
    /// the checkpoint needs no extra plumbing. Override with PLUG_INTEGRATION_API_URL when
    /// pointing at staging.
    private static let defaultURL = "http://127.0.0.1:8080"

    private var environment: AppEnvironment!

    /// The precondition is "a backend is reachable", so that is what is checked, rather than
    /// a flag that says one ought to be. CI has nothing listening and skips; a developer who
    /// started the backend gets the test without having to remember to ask for it.
    override func setUp() async throws {
        try await super.setUp()
        let configured = ProcessInfo.processInfo.environment["PLUG_INTEGRATION_API_URL"] ?? ""
        let value = configured.isEmpty ? Self.defaultURL : configured
        guard let url = URL(string: value), url.host != nil else {
            throw XCTSkip("PLUG_INTEGRATION_API_URL is not a usable address: \(value)")
        }
        guard await Self.isReachable(url) else {
            throw XCTSkip("No backend is answering at \(value). Start one to run this test.")
        }
        environment = AppEnvironment(baseURL: url, webBaseURL: nil)
    }

    private static func isReachable(_ baseURL: URL) async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "health"))
        request.timeoutInterval = 2
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        guard let (_, response) = try? await URLSession(configuration: configuration).data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    func testTheWholeSignInFlowAgainstARealServer() async throws {
        let credentials = InMemoryCredentialStore()
        let client = APIClient(environment: environment)
        let sessions = SessionStore(client: client, credentials: credentials)
        let model = AuthenticationModel(client: client, sessions: sessions)

        await model.continueAsGuest()
        guard case .signedIn(let session) = model.state else {
            return XCTFail("Live guest sign-in did not reach the signed-in state: \(model.state)")
        }
        XCTAssertEqual(session.account.type, .guest)
        XCTAssertTrue(session.account.userId.hasPrefix("usr_"))
        XCTAssertFalse(credentials.isEmpty, "A real session must be written to storage.")

        // The session survives being rebuilt from storage, which is what a relaunch is.
        let afterRelaunch = SessionStore(client: client, credentials: credentials)
        let restored = await afterRelaunch.restore()
        XCTAssertEqual(restored?.account.userId, session.account.userId)

        let me: Me = try await client.send(
            Endpoint.get("v1/me", accessToken: try await afterRelaunch.validAccessToken()), as: Me.self)
        XCTAssertEqual(me.account.userId, session.account.userId)

        // The guest limit, enforced by the real server rather than by the client.
        do {
            _ = try await client.send(
                Endpoint.get("v1/me/sessions", accessToken: session.accessToken), as: SessionList.self)
            XCTFail("A guest must not be able to list sessions.")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "forbidden")
            logCorrelation("guest_denied_sessions", error.requestID)
        }

        // Logout, then prove the server agrees the session is over.
        await afterRelaunch.signOut()
        XCTAssertTrue(credentials.isEmpty)
        do {
            _ = try await client.send(Endpoint.get("v1/me", accessToken: session.accessToken), as: Me.self)
            XCTFail("The access token must stop working the moment logout returns.")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "unauthenticated")
            logCorrelation("revoked_after_logout", error.requestID)
        }
    }

    /// Printed as well as logged: the point is to have a value to grep for in the backend's
    /// own log, and the test output is where whoever runs the checkpoint will look for it.
    private func logCorrelation(_ label: String, _ requestID: String?) {
        guard let requestID else { return }
        Logger(subsystem: "app.plug", category: "Integration")
            .info("checkpoint \(label, privacy: .public) request_id=\(requestID, privacy: .public)")
        print("CORRELATION \(label) request_id=\(requestID)")
    }

    private struct SessionList: Decodable {
        let sessions: [SessionSummary]
        struct SessionSummary: Decodable { let sessionId: String }
    }
}
