import Foundation

/// The session envelope from the contract. `Codable` because the whole value is what gets
/// written to the Keychain: storing the tokens without the account they belong to would
/// mean asking the server who the caller is before the first screen could be drawn.
struct Session: Codable, Equatable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
    let account: Account
    let consent: Consent

    /// Treated as expired slightly early so a request is not sent with a token that will
    /// have expired by the time it arrives.
    func isAccessTokenUsable(at now: Date) -> Bool {
        accessTokenExpiresAt.addingTimeInterval(-30) > now
    }

    func canRefresh(at now: Date) -> Bool {
        refreshTokenExpiresAt > now
    }
}

struct Account: Codable, Equatable {
    let userId: String
    let type: AccountType
    let scopes: [String]

    enum AccountType: String, Codable {
        case guest
        case phone
        case apple
    }

    var isGuest: Bool { type == .guest }
}

struct Consent: Codable, Equatable {
    let currentVersion: String
    let acceptedVersion: String?
    let acceptedAt: Date?

    /// True when the published terms have moved ahead of what this person agreed to. The
    /// server decides what the current version is; the app only compares the two.
    var needsAcceptance: Bool {
        acceptedVersion != currentVersion
    }
}

struct PhoneChallenge: Decodable, Equatable {
    let challengeId: String
    let expiresAt: Date
    let attemptsRemaining: Int
}

struct Me: Decodable, Equatable {
    let account: Account
    let consent: Consent
}
