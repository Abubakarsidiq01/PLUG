import Foundation

/// The state matrix from manual.docx 12, written as a type. A case missing from a switch
/// is a build failure rather than a blank screen in production, which is the entire point
/// of spelling the states out instead of using a pair of booleans.
enum AuthenticationState: Equatable {
    case signedOut
    case working(SignInStep)
    case awaitingCode(challengeID: String, expiresAt: Date, attemptsRemaining: Int)
    case codeRejected(challengeID: String, reason: CodeRejection)
    case signedIn(Session)
    case consentRequired(Session)
    case failed(message: String, canRetry: Bool)
    case offline(retryPreserved: Bool)
    case rateLimited(retryAfterSeconds: Int)
    case unavailable(message: String)
    case accountLinkConflict(message: String)
    case notificationsDenied

    enum SignInStep: Equatable {
        case apple
        case guest
        case sendingCode
        case checkingCode
        case restoring
    }

    /// The server's stable tokens, not the app's guesses. `invalid` and `expired` arrive as
    /// `details[0].code` on a validation_failed, which is what the contract froze.
    enum CodeRejection: String, Equatable {
        case invalid
        case expired
    }
}
