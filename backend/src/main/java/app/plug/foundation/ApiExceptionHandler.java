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
        return codes == null || codes.length == 0 ? null : codes[0].replaceAll(".*\\.", "");
    }

    public record ErrorEnvelope(ErrorBody error) {}
    public record ErrorBody(String code, String message, String requestId, List<FieldError> details, Integer retryAfterSeconds) {}
    public record FieldError(String field, String code, String message) {}
}
