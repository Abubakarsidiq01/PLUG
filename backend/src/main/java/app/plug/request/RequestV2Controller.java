package app.plug.request;

import app.plug.security.PlugPrincipal;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
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

@RestController
@RequestMapping("/v1/requests")
@ConditionalOnProperty(prefix = "plug.requests-v2", name = "enabled", havingValue = "true")
public class RequestV2Controller {
    private final RequestService service;
    public RequestV2Controller(RequestService service) { this.service = service; }
    private static void validateKey(String key) {
        if (key == null || !key.matches("[A-Za-z0-9_-]{16,128}")) {
            throw app.plug.foundation.ApiException.validation("Idempotency-Key", "invalid", "Provide a valid idempotency key.");
        }
    }
    @PostMapping
    ResponseEntity<RequestPayloads.Resource> create(@AuthenticationPrincipal PlugPrincipal caller,
            @RequestHeader(value = "Idempotency-Key", required = false) String key, @Valid @RequestBody RequestPayloads.Create body) {
        validateKey(key);
        return ResponseEntity.status(201).body(service.create(caller, key, body));
    }
    @GetMapping("/{id}")
    RequestPayloads.Resource get(@AuthenticationPrincipal PlugPrincipal caller, @PathVariable String id) {
        return service.get(caller, id);
    }
    @PostMapping("/{id}/clarifications")
    RequestPayloads.Resource clarify(@AuthenticationPrincipal PlugPrincipal caller, @PathVariable String id,
            @RequestHeader(value = "Idempotency-Key", required = false) String key, @Valid @RequestBody RequestPayloads.Answer answer) {
        validateKey(key);
        return service.clarify(caller, id, key, answer);
    }
    @PostMapping("/{id}/cancel")
    RequestPayloads.Resource cancel(@AuthenticationPrincipal PlugPrincipal caller, @PathVariable String id) {
        return service.cancel(caller, id);
    }
    @GetMapping("/{id}/offers")
    RequestPayloads.Offers offers(@AuthenticationPrincipal PlugPrincipal caller, @PathVariable String id) {
        return service.offers(caller, id);
    }
}
