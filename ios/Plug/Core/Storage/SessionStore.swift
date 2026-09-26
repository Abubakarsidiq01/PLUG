import Foundation

/// Holds the current session, keeps it in the Keychain so it survives a relaunch, and is
/// the only place that decides when to refresh.
///
/// The order on sign-out is the order from manual.docx 20.2, and it starts with the server:
/// revoke, then clear the Keychain, then clear memory. Clearing only the Keychain leaves a
/// working session on the server, which is the bug that makes "I logged out" untrue.
actor SessionStore {
    static let account = "session"

    private let credentials: CredentialStore
    private let client: APIClient
    private let now: () -> Date
    private var session: Session?
    private var refreshInFlight: Task<Session, Error>?

    init(client: APIClient, credentials: CredentialStore = KeychainStore(), now: @escaping () -> Date = Date.init) {
        self.client = client
        self.credentials = credentials
        self.now = now
    }

    /// Called once at launch. A stored session whose refresh window has closed is removed
    /// rather than shown as a signed-in state the first request would then contradict.
    func restore() -> Session? {
        session = nil
        guard let data = try? credentials.read(account: Self.account),
              let stored = try? PlugJSON.decoder.decode(Session.self, from: data) else { return nil }
        guard stored.canRefresh(at: now()) else {
            try? credentials.delete(account: Self.account)
            return nil
        }
        session = stored
        return stored
    }

    func current() -> Session? { session }

    func adopt(_ new: Session) throws {
        try credentials.save(try PlugJSON.encoder.encode(new), account: Self.account)
        session = new
    }

    /// The token to put on the next request. Refreshing is deduplicated: two screens waking
    /// at once would otherwise both spend the refresh token, and the second one to arrive
    /// would look exactly like a replay and revoke the chain.
    func validAccessToken() async throws -> String {
        guard let current = session else { throw APIError.signedOut() }
        if current.isAccessTokenUsable(at: now()) { return current.accessToken }
        if let refreshInFlight { return try await refreshInFlight.value.accessToken }
        let task = Task { try await refresh(current) }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        return try await task.value.accessToken
    }

    private func refresh(_ current: Session) async throws -> Session {
        do {
            let rotated: Session = try await client.send(
                try Endpoint.post("v1/auth/refresh", body: RefreshRequest(refreshToken: current.refreshToken)),
                as: Session.self)
            try Task.checkCancellation()
            guard session?.refreshToken == current.refreshToken else { throw APIError.signedOut() }
            try adopt(rotated)
            return rotated
        } catch let error as APIError where error.code == "unauthenticated" {
            // The server ended the session: expired, revoked, or a replay it detected. The
            // device agrees with the server rather than holding a credential it cannot use.
            if session?.refreshToken == current.refreshToken { await forget() }
            throw error
        }
    }

    func signOut() async {
        if let accessToken = try? await validAccessToken() {
            // A failure here is not a reason to keep the tokens on the device. The server
            // is told first; if the network drops, the local copy still goes.
            try? await client.sendExpectingNoContent(Endpoint.post("v1/auth/logout", accessToken: accessToken))
        }
        await forget()
    }

    func forget() async {
        session = nil
        refreshInFlight?.cancel()
        refreshInFlight = nil
        try? credentials.delete(account: Self.account)
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String
    }

}

extension APIError {
    static func signedOut() -> APIError {
        APIError(status: 401, body: Data(), requestID: nil)
    }
}
