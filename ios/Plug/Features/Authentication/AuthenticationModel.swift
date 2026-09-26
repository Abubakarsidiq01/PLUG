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

    var isWorking: Bool {
        if case .working = state { return true }
        return false
    }

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
            try await adopt(session.updating(account: me.account, consent: me.consent))
        } catch {
            await handleRestoreFailure(error)
        }
    }

    func continueAsGuest() async {
        if await sessions.current()?.account.isGuest == true {
            await restore()
            return
        }
        await signIn(step: .guest) {
            try await self.client.send(
                try Endpoint.post("v1/auth/guest", body: ConsentBody(consentVersion: self.consentVersion)),
                as: Session.self)
        }
    }

    /// `identityToken` and `rawNonce` come from ASAuthorizationAppleIDCredential. The app
    /// verifies nothing about the token: verification is the server's job, because a client
    /// that decides a token is valid is a client an attacker can rewrite.
    func signInWithApple(identityToken: String, rawNonce: String, creatingAccount: Bool = false) async {
        await signIn(step: .apple) {
            let guestToken = creatingAccount ? try await self.guestAccessToken() : nil
            return try await self.client.send(
                try Endpoint.post("v1/auth/apple",
                                  body: ProviderBody(identityToken: identityToken, nonce: rawNonce,
                                                  consentVersion: self.consentVersion,
                                                  intent: creatingAccount ? "sign_up" : "sign_in"),
                                  // Sent only when the caller is a guest, which is what
                                  // upgrades that account in place instead of making a
                                  // second one and losing what the guest had started.
                                  accessToken: guestToken),
                as: Session.self)
        }
    }

    func providerFailed(_ message: String) {
        state = .failed(message: message, canRetry: true)
    }

    func signInWithGoogle(identityToken: String, nonce: String, creatingAccount: Bool = false) async {
        await signIn(step: .google) {
            let guestToken = creatingAccount ? try await self.guestAccessToken() : nil
            return try await self.client.send(
                try Endpoint.post("v1/auth/google",
                                  body: ProviderBody(identityToken: identityToken, nonce: nonce,
                                                  consentVersion: self.consentVersion,
                                                  intent: creatingAccount ? "sign_up" : "sign_in"), accessToken: guestToken),
                as: Session.self)
        }
    }

    static func normalizedPhone(_ input: String) -> String? {
        let compact = input.filter { !" ()-.".contains($0) && !$0.isWhitespace }
        guard compact.range(of: "^\\+[1-9][0-9]{7,14}$", options: .regularExpression) != nil else { return nil }
        return compact
    }

    func sendCode(to phoneNumber: String) async {
        guard let phoneNumber = Self.normalizedPhone(phoneNumber) else {
            state = .failed(message: "Enter your country code and number, for example +1 312 555 0123.", canRetry: true)
            return
        }
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

    func verifyCode(_ code: String, challengeID: String, creatingAccount: Bool = false) async {
        state = .working(.checkingCode)
        do {
            let guestToken = creatingAccount ? try await guestAccessToken() : nil
            let session: Session = try await client.send(
                try Endpoint.post("v1/auth/phone/verify",
                                  body: VerifyBody(challengeId: challengeID, code: code,
                                                   consentVersion: consentVersion, intent: creatingAccount ? "sign_up" : "sign_in"),
                                  accessToken: guestToken),
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
        guard await sessions.current() != nil else {
            state = .signedOut
            return
        }
        do {
            let accessToken = try await sessions.validAccessToken()
            let consent = try await client.send(
                try Endpoint.post("v1/me/consent", body: ConsentVersionBody(version: consentVersion),
                                  accessToken: accessToken),
                as: Consent.self)
            guard let session = await sessions.current() else { throw APIError.signedOut() }
            try await adopt(session.updating(account: session.account, consent: consent))
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

    func retry() async {
        if await sessions.current() != nil { await restore() }
        else { startOver() }
    }

    private func guestAccessToken() async throws -> String? {
        guard await sessions.current()?.account.isGuest == true else { return nil }
        return try await sessions.validAccessToken()
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
        if let apiError = error as? APIError, apiError.code == "unauthenticated" {
            await sessions.forget()
            state = .signedOut
        } else {
            state = mapped(error, retryPreserved: true)
        }
    }

    /// One place where a failure becomes a state. Every branch names something the person
    /// can do next, which is what separates an error state from an apology.
    private func mapped(_ error: Error, retryPreserved: Bool) -> AuthenticationState {
        if let urlError = error as? URLError {
            if urlError.code == .cannotFindHost || urlError.code == .dnsLookupFailed {
                return .failed(message: "PLUG’s server address is unavailable. Please reconnect and try again.", canRetry: true)
            }
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
            if apiError.fieldCode == "account_exists" { return .accountExists }
            if apiError.fieldCode == "account_not_found" { return .accountNotFound }
            return .accountLinkConflict(message: apiError.message)
        case "dependency_unavailable":
            return .unavailable(message: apiError.message)
        case "unauthenticated":
            return .failed(message: apiError.message, canRetry: true)
        case "validation_failed":
            return .failed(message: "We couldn’t complete sign-in. Please try again.", canRetry: true)
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
    private struct ProviderBody: Encodable {
        let identityToken: String
        let nonce: String
        let consentVersion: String
        let intent: String
    }
    private struct VerifyBody: Encodable {
        let challengeId: String
        let code: String
        let consentVersion: String
        let intent: String
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
