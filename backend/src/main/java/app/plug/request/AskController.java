package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.request.RequestPayloads.Answer;
import app.plug.request.RequestPayloads.AskBody;
import app.plug.request.RequestPayloads.AskResult;
import app.plug.security.PlugPrincipal;
import jakarta.validation.Valid;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/// The single ask entry point (manual v4 §12A, contract 0.5.0).
@RestController
@RequestMapping("/v1/asks")
@ConditionalOnProperty(prefix = "plug.requests-v2", name = "enabled", havingValue = "true")
public class AskController {
    private final AskService asks;
    public AskController(AskService asks) { this.asks = asks; }

    private static void validateKey(String key) {
        if (key == null || !key.matches("[A-Za-z0-9_-]{16,128}")) {
            throw ApiException.validation("Idempotency-Key", "invalid", "Provide a valid idempotency key.");
        }
    }
    @PostMapping
    ResponseEntity<AskResult> create(@AuthenticationPrincipal PlugPrincipal caller,
            @RequestHeader(value = "Idempotency-Key", required = false) String key, @Valid @RequestBody AskBody body) {
        validateKey(key);
        return ResponseEntity.status(201).body(asks.create(caller, key, body));
    }
    @GetMapping("/{id}")
    AskResult get(@AuthenticationPrincipal PlugPrincipal caller, @PathVariable String id) {
        return asks.get(caller, id);
    }
    @PostMapping("/{id}/clarifications")
    AskResult clarify(@AuthenticationPrincipal PlugPrincipal caller, @PathVariable String id,
            @RequestHeader(value = "Idempotency-Key", required = false) String key, @Valid @RequestBody Answer answer) {
        validateKey(key);
        return asks.clarify(caller, id, key, answer);
    }
}
