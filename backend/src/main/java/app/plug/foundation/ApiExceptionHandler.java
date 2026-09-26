package app.plug.foundation;

import jakarta.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.Errors;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.HandlerMethodValidationException;

@RestControllerAdvice
public class ApiExceptionHandler {
    // Spring routes every @Valid violation on this controller through here, including
    // cascaded @RequestBody field errors (exposed as an Errors result per parameter) and
    // simple header/query constraint violations (exposed as MessageSourceResolvable).
    @ExceptionHandler(HandlerMethodValidationException.class)
    ResponseEntity<ErrorEnvelope> invalid(HandlerMethodValidationException exception, HttpServletRequest request) {
        List<FieldError> details = new ArrayList<>();
        for (var result : exception.getParameterValidationResults()) {
            if (result instanceof Errors errors) {
                errors.getFieldErrors().forEach(fieldError ->
                        details.add(new FieldError(fieldError.getField(), constraintCode(fieldError.getCode()), fieldError.getDefaultMessage())));
            } else {
                String field = result.getMethodParameter().getParameterName();
                result.getResolvableErrors().forEach(resolvable ->
                        details.add(new FieldError(field, constraintCode(firstCode(resolvable.getCodes())), resolvable.getDefaultMessage())));
            }
        }
        return ResponseEntity.badRequest().body(new ErrorEnvelope(new ErrorBody("validation_failed",
                "The request was invalid.", String.valueOf(request.getAttribute(CorrelationFilter.REQUEST_ATTRIBUTE)),
                details, null)));
    }

    // Failures the caller is allowed to see. Declared before the catch-all below so a
    // deliberate 401, 404 or 429 is never flattened into internal_error. A 401 carries the
    // WWW-Authenticate header the HTTP specification requires, matching what the security
    // filter chain already sends for an anonymous request.
    @ExceptionHandler(ApiException.class)
    ResponseEntity<ErrorEnvelope> expected(ApiException exception, HttpServletRequest request) {
        var response = ResponseEntity.status(exception.status());
        if (exception.status() == 401) {
            response = response.header("WWW-Authenticate", "Bearer");
        }
        if (exception.retryAfterSeconds() != null) {
            response = response.header("Retry-After", String.valueOf(exception.retryAfterSeconds()));
        }
        return response.body(new ErrorEnvelope(new ErrorBody(exception.code(), exception.getMessage(),
                String.valueOf(request.getAttribute(CorrelationFilter.REQUEST_ATTRIBUTE)),
                exception.details(), exception.retryAfterSeconds())));
    }

    @ExceptionHandler(org.springframework.web.HttpMediaTypeNotSupportedException.class)
    ResponseEntity<ErrorEnvelope> contentType(HttpServletRequest request) {
        return build(request, 415, "validation_failed", "Send a JSON request body.");
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorEnvelope> unexpected(Exception exception, HttpServletRequest request) {
        org.slf4j.LoggerFactory.getLogger(ApiExceptionHandler.class).error(
                "request_failed request_id={} exception_type={}",
                request.getAttribute(CorrelationFilter.REQUEST_ATTRIBUTE), exception.getClass().getSimpleName());
        return build(request, 500, "internal_error", "The request could not be completed.");
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    ResponseEntity<ErrorEnvelope> malformed(HttpServletRequest request) {
        return build(request, 400, "validation_failed", "The JSON request body could not be read.");
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ErrorEnvelope> validation(MethodArgumentNotValidException exception, HttpServletRequest request) {
        var details = exception.getBindingResult().getFieldErrors().stream()
                .map(error -> new FieldError(error.getField(), constraintCode(error.getCode()), error.getDefaultMessage()))
                .toList();
        return ResponseEntity.badRequest().body(new ErrorEnvelope(new ErrorBody(
                "validation_failed", "The request was invalid.",
                String.valueOf(request.getAttribute(CorrelationFilter.REQUEST_ATTRIBUTE)), details, null)));
    }

    private ResponseEntity<ErrorEnvelope> build(HttpServletRequest request, int status, String code, String message) {
        return ResponseEntity.status(status).body(new ErrorEnvelope(new ErrorBody(code, message,
                String.valueOf(request.getAttribute(CorrelationFilter.REQUEST_ATTRIBUTE)), List.of(), null)));
    }

    // Spring's constraint code is the bare annotation name (NotBlank, Size, ...); the
    // contract wants a stable snake_case token a client can branch on.
    private String constraintCode(String constraint) {
        return constraint == null ? "invalid" : constraint.toLowerCase(Locale.ROOT);
    }

    private String firstCode(String[] codes) {
        // Spring starts with e.g. Size.requestController#create.idempotencyKey.
        // The constraint is the first segment; the final segment is a parameter name.
        return codes == null || codes.length == 0 ? null : codes[0].split("\\.", 2)[0];
    }

    public record ErrorEnvelope(ErrorBody error) {}
    public record ErrorBody(String code, String message, String requestId, List<FieldError> details, Integer retryAfterSeconds) {}
    public record FieldError(String field, String code, String message) {}
}
