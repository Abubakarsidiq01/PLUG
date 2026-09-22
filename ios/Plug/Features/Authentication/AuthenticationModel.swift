import Foundation
import OSLog

/// One view model for the whole sign-in flow, owning exactly one state enum.
///
/// It never stores a token itself: the tokens go straight to the SessionStore, which puts
/// them in the Keychain. What this type holds is the state a screen draws, and none of the
/// values in it are secret.
@MainActor
final class AuthenticationModel: ObservableObject {
    @Published private(set) var state: AuthenticationState = .signedOut

    private let client: APIClient
    private let sessions: SessionStore
    private let consentVersion: String
    private let log = Logger(subsystem: "app.plug", category: "Authentication")

    init(client: APIClient, sessions: SessionStore, consentVersion: String = PlugConsent.version) {
        self.client = client
        self.sessions = sessions
        self.consentVersion = consentVersion
    }

    /// Called at launch. A session restored from the Keychain is proved against the server
    /// before the app treats the person as signed in, so a session revoked on another
    /// device shows as signed out here rather than as a screen that fails on first use.
    func restore() async {
        state = .working(.restoring)
        guard await sessions.restore() != nil else {
            state = .signedOut
            return
        }
        do {
            let accessToken = try await sessions.validAccessToken()
            let me: Me = try await client.send(Endpoint.get("v1/me", accessToken: accessToken), as: Me.self)
            guard let session = await sessions.current() else {
                state = .signedOut
                return
            }
            state = me.consent.needsAcceptance ? .consentRequired(session) : .signedIn(session)
        } catch {
            await handleRestoreFailure(error)
        }
    }

    func continueAsGuest() async {
        await signIn(step: .guest) {
            try await self.client.send(
                try Endpoint.post("v1/auth/guest", body: ConsentBody(consentVersion: self.consentVersion)),
                as: Session.self)
        }
    }

    /// `identityToken` and `rawNonce` come from ASAuthorizationAppleIDCredential. The app
    /// verifies nothing about the token: verification is the server's job, because a client
    /// that decides a token is valid is a client an attacker can rewrite.
    func signInWithApple(identityToken: String, rawNonce: String) async {
        let existing = await sessions.current()
        await signIn(step: .apple) {
            try await self.client.send(
                try Endpoint.post("v1/auth/apple",
                                  body: AppleBody(identityToken: identityToken, nonce: rawNonce,
                                                  consentVersion: self.consentVersion),
                                  // Sent only when the caller is a guest, which is what
                                  // upgrades that account in place instead of making a
                                  // second one and losing what the guest had started.
                                  accessToken: existing?.account.isGuest == true ? existing?.accessToken : nil),
                as: Session.self)
        }
    }

    func sendCode(to phoneNumber: String) async {
        state = .working(.sendingCode)
        do {
            let challenge: PhoneChallenge = try await client.send(
                try Endpoint.post("v1/auth/phone/start", body: PhoneStartBody(phoneNumber: phoneNumber)),
                as: PhoneChallenge.self)
            state = .awaitingCode(challengeID: challenge.challengeId, expiresAt: challenge.expiresAt,
                                  attemptsRemaining: challenge.attemptsRemaining)
        } catch {
            state = mapped(error, retryPreserved: true)
        }
    }

    func verifyCode(_ code: String, challengeID: String) async {
        let existing = await sessions.current()
        state = .working(.checkingCode)
        do {
            let session: Session = try await client.send(
                try Endpoint.post("v1/auth/phone/verify",
                                  body: VerifyBody(challengeId: challengeID, code: code,
                                                   consentVersion: consentVersion),
                                  accessToken: existing?.account.isGuest == true ? existing?.accessToken : nil),
                as: Session.self)
            try await adopt(session)
        } catch let error as APIError where error.code == "validation_failed" {
            // The server said which problem it is. The screen says so too, rather than
            // showing one message for two situations the person can act on differently.
            let reason = AuthenticationState.CodeRejection(rawValue: error.fieldCode ?? "") ?? .invalid
            state = .codeRejected(challengeID: challengeID, reason: reason)
        } catch {
            state = mapped(error, retryPreserved: true)
        }
    }

    func acceptConsent() async {
        guard let session = await sessions.current() else {
            state = .signedOut
            return
        }
        do {
            let accessToken = try await sessions.validAccessToken()
            _ = try await client.send(
                try Endpoint.post("v1/me/consent", body: ConsentVersionBody(version: consentVersion),
                                  accessToken: accessToken),
                as: Consent.self)
            state = .signedIn(session)
        } catch {
            state = mapped(error, retryPreserved: false)
        }
    }

    func signOut() async {
        await sessions.signOut()
        state = .signedOut
    }

    /// Recorded so the person can be offered the manual path instead of a dead end. A
    /// denied notification permission never blocks sign-in.
    func notificationPermissionDenied() {
        if case .signedIn = state { return }
        state = .notificationsDenied
    }

    func startOver() {
        state = .signedOut
    }

    private func signIn(step: AuthenticationState.SignInStep,
                        _ work: @escaping () async throws -> Session) async {
        state = .working(step)
        do {
            try await adopt(try await work())
        } catch {
            state = mapped(error, retryPreserved: false)
        }
    }

    private func adopt(_ session: Session) async throws {
        try await sessions.adopt(session)
        state = session.consent.needsAcceptance ? .consentRequired(session) : .signedIn(session)
    }

    private func handleRestoreFailure(_ error: Error) async {
        if let urlError = error as? URLError, isOffline(urlError) {
            // A stored session and no network is not a signed-out person. Saying so would
            // throw away a session that is still perfectly good.
            state = .offline(retryPreserved: true)
            return
        }
        await sessions.forget()
        state = .signedOut
    }

    /// One place where a failure becomes a state. Every branch names something the person
    /// can do next, which is what separates an error state from an apology.
    private func mapped(_ error: Error, retryPreserved: Bool) -> AuthenticationState {
        if let urlError = error as? URLError {
            return isOffline(urlError)
                ? .offline(retryPreserved: retryPreserved)
                : .failed(message: "We could not reach PLUG. Please try again.", canRetry: true)
        }
        guard let apiError = error as? APIError else {
            return .failed(message: "Something went wrong. Please try again.", canRetry: true)
        }
        if let requestID = apiError.requestID {
            // The identifier, never the message and never anything from the request body.
            log.error("auth_failed code=\(apiError.code, privacy: .public) request_id=\(requestID, privacy: .public)")
        }
        switch apiError.code {
        case "rate_limited":
            return .rateLimited(retryAfterSeconds: apiError.retryAfterSeconds ?? 60)
        case "conflict":
            return .accountLinkConflict(message: apiError.message)
        case "dependency_unavailable":
            return .unavailable(message: apiError.message)
        case "unauthenticated":
            return .failed(message: apiError.message, canRetry: true)
        default:
            return .failed(message: apiError.message, canRetry: true)
        }
    }

    private func isOffline(_ error: URLError) -> Bool {
        [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
         .cannotConnectToHost, .timedOut].contains(error.code)
    }

    private struct ConsentBody: Encodable { let consentVersion: String }
    private struct ConsentVersionBody: Encodable { let version: String }
    private struct PhoneStartBody: Encodable { let phoneNumber: String }
    private struct AppleBody: Encodable {
        let identityToken: String
        let nonce: String
        let consentVersion: String
    }
    private struct VerifyBody: Encodable {
        let challengeId: String
        let code: String
        let consentVersion: String
    }
}

/// The published version of the Terms and Privacy Policy this build displays. It is sent
/// with every sign-in, and the server refuses a version it has not published — so this
/// constant and the server's `plug.identity.consent-version` move together or not at all.
///
/// The link targets are the routes Person Two builds in /web. The host is configuration
/// rather than a constant here, because no production domain has been decided yet and
/// writing a guess into the app would make it look as though one had been.
enum PlugConsent {
    static let version = "2026-09-01"

    static func termsURL(_ environment: AppEnvironment) -> URL? {
        environment.webBaseURL?.appending(path: "terms")
    }

    static func privacyURL(_ environment: AppEnvironment) -> URL? {
        environment.webBaseURL?.appending(path: "privacy")
    }
}
