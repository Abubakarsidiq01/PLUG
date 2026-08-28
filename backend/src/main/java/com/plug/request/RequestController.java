package com.plug.request;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/v1/requests")
public class RequestController {
    @PostMapping
    ResponseEntity<RequestResponse> create(
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @Valid @RequestBody RequestCreate request) {
        return ResponseEntity.status(HttpStatus.ACCEPTED).body(new RequestResponse(
                "req_" + UUID.randomUUID(), RequestStatus.RECEIVED, NextAction.PROCESSING));
    }

    public record RequestCreate(@NotBlank String query, @NotNull @Valid Location location) {}
    public record Location(
            @NotNull @DecimalMin("-90") @DecimalMax("90") Double latitude,
            @NotNull @DecimalMin("-180") @DecimalMax("180") Double longitude) {}
    public record RequestResponse(String requestId, RequestStatus status, NextAction nextAction) {}
    public enum RequestStatus { RECEIVED }
    public enum NextAction { PROCESSING }
}
