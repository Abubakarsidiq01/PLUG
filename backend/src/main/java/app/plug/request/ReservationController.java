package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.security.PlugPrincipal;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/// Contract 0.7.0 selectOffer. With the provider inbox off there is no handler, so the route is 404.
@RestController
@RequestMapping("/v1/requests")
@ConditionalOnExpression("${plug.requests-v2.enabled:false} and ${plug.provider-inbox.enabled:false}")
public class ReservationController {
    private final ReservationService service;
    public ReservationController(ReservationService service) { this.service = service; }
    @PostMapping("/{id}/select")
    RequestPayloads.Resource select(@AuthenticationPrincipal PlugPrincipal caller, @PathVariable String id,
            @RequestHeader(value = "Idempotency-Key", required = false) String key,
            @RequestBody(required = false) JsonNode body) {
        if (key == null || !key.matches("[A-Za-z0-9_-]{16,128}")) {
            throw ApiException.validation("Idempotency-Key", "invalid", "Provide a valid idempotency key.");
        }
        // OfferSelection: exactly one field, offer_id, matching the contract pattern.
        JsonNode offer = body == null || !body.isObject() || body.size() != 1 ? null : body.get("offer_id");
        if (offer == null || !offer.isTextual() || offer.asText().length() > 64 || !offer.asText().matches("off_[A-Za-z0-9-]+")) {
            throw ApiException.validation("offer_id", "invalid", "Choose one of the offers.");
        }
        return service.select(caller, id, key, new RequestPayloads.Selection(offer.asText()));
    }
}
