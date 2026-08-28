package com.plug.foundation;

import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {
    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ErrorResponse> validation(MethodArgumentNotValidException exception, HttpServletRequest request) {
        var details = exception.getBindingResult().getFieldErrors().stream()
                .map(error -> new FieldError(error.getField(), error.getDefaultMessage())).toList();
        return ResponseEntity.badRequest().body(new ErrorResponse(
                "validation_error", "The request was invalid.", "corr_" + UUID.randomUUID(),
                Instant.now(), request.getRequestURI(), details));
    }

    public record ErrorResponse(String code, String message, String correlationId, Instant timestamp, String path, List<FieldError> details) {}
    public record FieldError(String field, String message) {}
}
