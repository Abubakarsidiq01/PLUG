package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.security.PlugPrincipal;
import com.fasterxml.jackson.databind.JsonNode;
import java.text.Normalizer;
import java.util.List;
import java.util.regex.Pattern;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

/// Contract 0.7.0 selectOffer, getProviderInbox and registerDevice, and 0.7.1 answerReservation and sendProviderOffer. With
/// the provider inbox off there is no handler, so every route here is 404.
@RestController
@ConditionalOnExpression("${plug.requests-v2.enabled:false} and ${plug.provider-inbox.enabled:false}")
public class ReservationController {
    /// RFC 3339 date-time with seconds and an explicit offset (contract format date-time).
    private static final Pattern RFC3339 = Pattern.compile(
            "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,9})?(?:Z|[+-]\\d{2}:\\d{2})");
    /// Control and invisible format characters, bidi overrides and zero-width ones included (§25.3).
    private static final Pattern HIDDEN = Pattern.compile("[\\p{Cc}\\p{Cf}]");
    // Spaced forms only for TLDs that are not everyday words after a full stop ("me. Us", "Co-owner").
    private static final String TLDS = "com|net|org|io|dev|ai|gg|shop|ee|app|ly|info|biz|xyz|link|site";
    /// Contact details in an NFKC-normalized note: seven or more digits whatever separates them, an
    /// email (also "jo at gmail dot com"), a link, any word.tld, or a spaced or spelled ".com". A regex
    /// cannot catch every spelled-out number ("five one two ..."); moderation is the backstop.
    static final Pattern CONTACT = Pattern.compile("(?:\\p{Nd}[^\\p{L}\\p{Nd}]{0,3}){6,}\\p{Nd}"
            + "|[^\\s@]+@[^\\s@]+\\.[^\\s@]+"
            + "|(?i:[\\p{L}\\p{Nd}._-]+\\s*[(\\[]?\\s*\\bat\\b\\s*[)\\]]?\\s*[\\p{L}\\p{Nd}-]+\\s*[(\\[]?\\s*\\bdot\\b)"
            + "|(?i:https?://|www\\.)"
            + "|(?i:[\\p{L}\\p{Nd}-]+\\.\\p{L}{2,})"
            + "|(?i:[\\p{L}\\p{Nd}-]+\\s*(?:\\.|\\bdot\\b)\\s*(?:" + TLDS + ")\\b)");
    private final ReservationService service;
    public ReservationController(ReservationService service) { this.service = service; }
    @PostMapping("/v1/requests/{id}/select")
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
    @PostMapping("/v1/requests/{id}/offers")
    ResponseEntity<RequestPayloads.Offer> sendOffer(@AuthenticationPrincipal PlugPrincipal caller, @PathVariable String id,
            @RequestHeader(value = "Idempotency-Key", required = false) String key,
            @RequestBody(required = false) JsonNode body) {
        if (key == null || !key.matches("[A-Za-z0-9_-]{16,128}")) {
            throw ApiException.validation("Idempotency-Key", "invalid", "Provide a valid idempotency key.");
        }
        // ProviderOfferCreate: price_cents, currency, available_at and an optional note, nothing else.
        if (body == null || !body.isObject()) throw ApiException.validation("body", "invalid", "Send an offer.");
        body.fieldNames().forEachRemaining(field -> {
            if (!List.of("price_cents", "currency", "available_at", "note").contains(field)) {
                throw ApiException.validation(field, "invalid", "That field is not part of an offer.");
            }
        });
        JsonNode price = body.get("price_cents");
        if (price == null || !price.isIntegralNumber() || !price.canConvertToInt() || price.intValue() < 500 || price.intValue() > 50000) {
            throw ApiException.validation("price_cents", "invalid", "Enter a price from $5 to $500.");
        }
        JsonNode currency = body.get("currency");
        if (currency == null || !currency.isTextual() || !currency.asText().matches("[A-Z]{3}")) {
            throw ApiException.validation("currency", "invalid", "Enter a currency code.");
        }
        if (!currency.asText().equals("USD")) throw ApiException.validation("currency", "unsupported", "Only USD is supported.");
        JsonNode available = body.get("available_at");
        java.time.Instant at = null;
        if (available != null && available.isTextual() && RFC3339.matcher(available.asText()).matches()) {
            try { at = java.time.OffsetDateTime.parse(available.asText()).toInstant(); }
            catch (java.time.format.DateTimeParseException invalid) { at = null; }
        }
        if (at == null) throw ApiException.validation("available_at", "invalid", "Enter the time you can start.");
        JsonNode note = body.get("note");
        // Normalized first, so look-alike digits and dots cannot slip past the contact check.
        String text = note == null || !note.isTextual() ? null : Normalizer.normalize(note.asText(), Normalizer.Form.NFKC);
        if (note != null && (text == null || text.isEmpty() || text.codePointCount(0, text.length()) > 140
                || HIDDEN.matcher(text).find())) {
            throw ApiException.validation("note", "invalid", "Keep the note to 140 characters of plain text.");
        }
        if (text != null && CONTACT.matcher(text).find()) {
            throw ApiException.validation("note", "contact_in_note", "Leave out phone numbers, emails and links.");
        }
        return ResponseEntity.status(201).body(service.sendOffer(caller, id, key,
                new RequestPayloads.OfferCreate(price.intValue(), currency.asText(), at, text)));
    }
    @GetMapping("/v1/providers/me/inbox")
    RequestPayloads.ProviderInbox inbox(@AuthenticationPrincipal PlugPrincipal caller) {
        return service.inbox(caller);
    }
    @PostMapping("/v1/me/devices")
    void registerDevice(@AuthenticationPrincipal PlugPrincipal caller, @RequestBody(required = false) JsonNode body) {
        // DeviceRegistration: exactly apns_token (lowercase hex, 64 to 200) and environment.
        JsonNode token = body == null || !body.isObject() || body.size() != 2 ? null : body.get("apns_token");
        if (token == null || !token.isTextual() || !token.asText().matches("[0-9a-f]{64,200}")) {
            throw ApiException.validation("apns_token", "invalid", "Send the device token from Apple.");
        }
        JsonNode environment = body.get("environment");
        if (environment == null || !environment.isTextual() || !List.of("sandbox", "production").contains(environment.asText())) {
            throw ApiException.validation("environment", "invalid", "Choose sandbox or production.");
        }
        service.registerDevice(caller);
    }
    @PostMapping("/v1/providers/me/inbox/{matchId}/reservation")
    RequestPayloads.InboxItem answer(@AuthenticationPrincipal PlugPrincipal caller, @PathVariable String matchId,
            @RequestBody(required = false) JsonNode body) {
        // ReservationDecision: exactly one field, decision, confirm or release.
        JsonNode decision = body == null || !body.isObject() || body.size() != 1 ? null : body.get("decision");
        if (decision == null || !decision.isTextual() || !List.of("confirm", "release").contains(decision.asText())) {
            throw ApiException.validation("decision", "invalid", "Choose confirm or release.");
        }
        return service.answer(caller, matchId, decision.asText());
    }
}
