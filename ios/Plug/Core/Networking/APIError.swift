import Foundation

/// The error envelope from the contract, and the small set of things a screen can do about
/// it. Screens switch on `code` and on `fieldCode`; they never parse the message, and they
/// never branch on the HTTP status, because the status is not the stable part.
struct APIError: Error, Equatable {
    let code: String
    let message: String
    let fieldCode: String?
    let retryAfterSeconds: Int?
    let requestID: String?

    init(status: Int, body: Data, requestID: String?) {
        let envelope = try? PlugJSON.decoder.decode(Envelope.self, from: body)
        self.code = envelope?.error.code ?? APIError.codeForStatus(status)
        // The server's message is written to be shown. A missing one means the response was
        // not ours, so the app supplies its own rather than showing an empty screen.
        self.message = envelope?.error.message ?? "Something went wrong. Please try again."
        self.fieldCode = envelope?.error.details?.first?.code
        self.retryAfterSeconds = envelope?.error.retryAfterSeconds
        self.requestID = envelope?.error.requestId ?? requestID
    }

    private init(code: String, message: String, requestID: String?) {
        self.code = code
        self.message = message
        self.fieldCode = nil
        self.retryAfterSeconds = nil
        self.requestID = requestID
    }

    static func contractViolation(requestID: String?) -> APIError {
        APIError(code: "internal_error",
                 message: "Something went wrong. Please try again.",
                 requestID: requestID)
    }

    /// A response with no readable envelope still has to be classified. Falling back to the
    /// status keeps the screens' switch statements total instead of leaving a silent gap.
    private static func codeForStatus(_ status: Int) -> String {
        switch status {
        case 401: return "unauthenticated"
        case 403: return "forbidden"
        case 404: return "not_found"
        case 409: return "conflict"
        case 429: return "rate_limited"
        case 503: return "dependency_unavailable"
        default: return status >= 500 ? "internal_error" : "validation_failed"
        }
    }

    private struct Envelope: Decodable {
        let error: Body

        struct Body: Decodable {
            let code: String
            let message: String
            let requestId: String?
            let details: [Detail]?
            let retryAfterSeconds: Int?
        }

        struct Detail: Decodable {
            let field: String
            let code: String
        }
    }
}
