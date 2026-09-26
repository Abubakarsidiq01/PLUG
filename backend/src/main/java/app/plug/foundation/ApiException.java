package app.plug.foundation;

import java.util.List;

// A failure the caller is allowed to see, carrying one of the frozen error codes from
// manual.docx 18.2. Everything that is not one of these becomes internal_error, so a
// failure mode nobody anticipated cannot leak an internal detail through its message.
// The message is written for a person to read on a screen: no identifiers, no SQL, no
// provider text, and nothing that says whether an account exists.
public class ApiException extends RuntimeException {
    private static final long serialVersionUID = 1L;

    private final int status;
    private final String code;
    private final transient List<ApiExceptionHandler.FieldError> details;
    private final Integer retryAfterSeconds;

    private ApiException(int status, String code, String message,
            List<ApiExceptionHandler.FieldError> details, Integer retryAfterSeconds) {
        super(message, null, false, false);
        this.status = status;
        this.code = code;
        this.details = details;
        this.retryAfterSeconds = retryAfterSeconds;
    }

    // A field-level problem the client branches on. The field and code tokens are part of
    // the contract; the message is the only part that may be reworded.
    public static ApiException validation(String field, String fieldCode, String message) {
        return new ApiException(400, "validation_failed", message,
                List.of(new ApiExceptionHandler.FieldError(field, fieldCode, message)), null);
    }

    public static ApiException unauthenticated(String message) {
        return new ApiException(401, "unauthenticated", message, List.of(), null);
    }

    public static ApiException forbidden(String message) {
        return new ApiException(403, "forbidden", message, List.of(), null);
    }

    // Used for a resource that exists but is not the caller's, as well as one that does not
    // exist. A 403 on the first case would confirm the identifier names something real.
    public static ApiException notFound(String message) {
        return new ApiException(404, "not_found", message, List.of(), null);
    }

    public static ApiException conflict(String message) {
        return new ApiException(409, "conflict", message, List.of(), null);
    }

    // Called only after provider/OTP ownership has been verified, never for an email lookup.
    public static ApiException authIntentConflict(String reason, String message) {
        return new ApiException(409, "conflict", message,
                List.of(new ApiExceptionHandler.FieldError("intent", reason, message)), null);
    }

    public static ApiException rateLimited(int retryAfterSeconds) {
        return new ApiException(429, "rate_limited", "Too many attempts. Try again shortly.",
                List.of(), retryAfterSeconds);
    }

    public static ApiException dependencyUnavailable(String message, int retryAfterSeconds) {
        return new ApiException(503, "dependency_unavailable", message, List.of(), retryAfterSeconds);
    }

    public int status() {
        return status;
    }

    public String code() {
        return code;
    }

    public List<ApiExceptionHandler.FieldError> details() {
        return details == null ? List.of() : details;
    }

    public Integer retryAfterSeconds() {
        return retryAfterSeconds;
    }
}
