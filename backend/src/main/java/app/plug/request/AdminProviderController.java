package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.security.PlugPrincipal;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/// Contract 0.7.0 listProviders and setProviderStanding (P3.S14), owner only. SecurityConfiguration
/// requires the admin scope and a completed second factor for all of /v1/admin; the owner role is
/// checked before anything is read or validated. Responses are never cached.
@RestController
@ConditionalOnProperty(prefix = "plug.requests-v2", name = "enabled", havingValue = "true")
public class AdminProviderController {
    private final ProviderService providers;
    public AdminProviderController(ProviderService providers) { this.providers = providers; }

    @GetMapping("/v1/admin/providers")
    ResponseEntity<AdminInspection.Page<ProviderPayloads.AdminProvider>> list(@AuthenticationPrincipal PlugPrincipal caller,
            @RequestParam(required = false) String cursor, @RequestParam(required = false) String limit) {
        providers.requireOwner(caller);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(providers.list(caller, cursor, AdminInspection.limit(limit)));
    }

    @PostMapping("/v1/admin/providers/{userId}/standing")
    ResponseEntity<ProviderPayloads.AdminProvider> standing(@AuthenticationPrincipal PlugPrincipal caller,
            @PathVariable String userId, @RequestBody(required = false) JsonNode body) {
        providers.requireOwner(caller);
        // ProviderStandingDecision: exactly standing (active or suspended) and a reason of 3 to 300 characters.
        if (body == null || !body.isObject()) throw ApiException.validation("body", "invalid", "Send a standing and a reason.");
        body.fieldNames().forEachRemaining(field -> {
            if (!List.of("standing", "reason").contains(field)) {
                throw ApiException.validation(field, "invalid", "That field is not part of a standing decision.");
            }
        });
        JsonNode standing = body.get("standing");
        if (standing == null || !standing.isTextual() || !List.of("active", "suspended").contains(standing.asText())) {
            throw ApiException.validation("standing", "invalid", "Choose active or suspended.");
        }
        JsonNode reason = body.get("reason");
        if (reason == null || reason.isNull()) throw ApiException.validation("reason", "required", "Give a reason.");
        String text = reason.isTextual() ? reason.asText().strip() : "";
        int length = text.codePointCount(0, text.length());
        if (length < 3 || length > 300) throw ApiException.validation("reason", "invalid", "Give a reason of 3 to 300 characters.");
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(providers.setStanding(caller, userId, standing.asText(), text));
    }
}
