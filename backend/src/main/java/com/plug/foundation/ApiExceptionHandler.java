package com.plug.foundation;

import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.List;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {
    @ExceptionHandler(org.springframework.web.method.annotation.HandlerMethodValidationException.class)
    ResponseEntity<ErrorResponse> invalidHeader(HttpServletRequest request) {
        return ResponseEntity.badRequest().body(new ErrorResponse(
                "validation_error", "A request parameter or header was invalid.",
                (String) request.getAttribute("correlationId"), Instant.now(), request.getRequestURI(), List.of()));
    }

    @ExceptionHandler(org.springframework.web.HttpMediaTypeNotSupportedException.class)
    ResponseEntity<ErrorResponse> contentType(HttpServletRequest request) {
        return ResponseEntity.status(415).body(new ErrorResponse(
                "unsupported_media_type", "Send a JSON request body.",
                (String) request.getAttribute("correlationId"), Instant.now(), request.getRequestURI(), List.of()));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorResponse> unexpected(Exception exception, HttpServletRequest request) {
        org.slf4j.LoggerFactory.getLogger(ApiExceptionHandler.class).error(
                "request_failed correlation_id={} exception_type={}", request.getAttribute("correlationId"),
                exception.getClass().getSimpleName());
        return ResponseEntity.internalServerError().body(new ErrorResponse(
                "internal_error", "The request could not be completed.",
                (String) request.getAttribute("correlationId"), Instant.now(), request.getRequestURI(), List.of()));
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    ResponseEntity<ErrorResponse> malformed(HttpServletRequest request) {
        return ResponseEntity.badRequest().body(new ErrorResponse(
                "validation_error", "The JSON request body could not be read.",
                (String) request.getAttribute("correlationId"), Instant.now(), request.getRequestURI(), List.of()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ErrorResponse> validation(MethodArgumentNotValidException exception, HttpServletRequest request) {
        var details = exception.getBindingResult().getFieldErrors().stream()
                .map(error -> new FieldError(error.getField(), error.getDefaultMessage())).toList();
        return ResponseEntity.badRequest().body(new ErrorResponse(
                "validation_error", "The request was invalid.", (String) request.getAttribute("correlationId"),
                Instant.now(), request.getRequestURI(), details));
    }

    public record ErrorResponse(String code, String message, String correlationId, Instant timestamp, String path, List<FieldError> details) {}
    public record FieldError(String field, String message) {}
}
