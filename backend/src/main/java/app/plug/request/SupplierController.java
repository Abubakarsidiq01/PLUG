package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.identity.CallerAddress;
import app.plug.request.ProviderPayloads.AvailabilityWindow;
import app.plug.security.PlugPrincipal;
import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.databind.JsonNode;
import jakarta.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.regex.Pattern;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/// Contract 0.7.7 supplierOptIn, listSuppliers, createSupplier, getSupplier, updateSupplierProfile,
/// decideSupplierVerification and listOptOuts (P3.S2). With supplier_messaging off there is no
/// handler, so every route is 404. Admin routes: reads for any active staff member, writes for an
/// owner, each limited per staff member before the role check. Bodies are validated by hand from a
/// redacting wrapper: unknown fields are refused and nothing a body holds reaches a log.
@RestController
@ConditionalOnProperty(prefix = "plug.supplier-messaging", name = "enabled", havingValue = "true")
public class SupplierController {
    static final String PHONE = "\\+1[2-9][0-9]{2}[2-9][0-9]{6}";
    /// Control and invisible format characters, bidi overrides included (§25.3); a name goes into a text.
    private static final Pattern HIDDEN = Pattern.compile("[\\p{Cc}\\p{Cf}]");
    /// A business name is texted to the number the form names, so it may not carry a link, a domain,
    /// an email or a number: "://", "www.", word.tld, "@" or five or more digits in a row.
    private static final Pattern CONTACT_IN_NAME = Pattern.compile("(?i)://|www\\.|\\b[a-z0-9-]+\\.[a-z]{2,}\\b|@|\\d{5,}");
    /// Staff reasons are kept in the audit trail; a phone number does not belong there.
    private static final Pattern NUMBER_IN_REASON = Pattern.compile("\\+?\\d{7,}");
    private static final String CLOCK = "([01][0-9]|2[0-3]):[0-5][0-9]";
    private final SupplierService suppliers;
    public SupplierController(SupplierService suppliers) { this.suppliers = suppliers; }

    @PostMapping("/v1/suppliers/opt-in")
    ResponseEntity<SupplierPayloads.Receipt> optIn(HttpServletRequest request,
            @RequestHeader(value = "Idempotency-Key", required = false) String key, @RequestBody(required = false) RedactedBody optIn) {
        JsonNode body = object(optIn, "business_name", "phone", "consent_version", "consent");
        requireKey(key);
        String name = businessName(body);
        String phone = phone(body);
        JsonNode version = body.get("consent_version");
        if (version == null || !version.isTextual() || !version.asText().equals(SupplierService.CONSENT_VERSION)) {
            throw ApiException.validation("consent_version", "unsupported_version", "Reload the form to see the current SMS terms.");
        }
        JsonNode consent = body.get("consent");
        if (consent == null || !consent.isBoolean() || !consent.booleanValue()) {
            throw ApiException.validation("consent", "consent_required", "Tick the box to agree to receive texts.");
        }
        suppliers.optIn(CallerAddress.prefixOf(request), key, new SupplierPayloads.OptIn(name, phone, version.asText()));
        return ResponseEntity.status(HttpStatus.ACCEPTED).cacheControl(CacheControl.noStore()).body(SupplierPayloads.Receipt.SENT_IF_ELIGIBLE);
    }

    @GetMapping("/v1/admin/suppliers")
    ResponseEntity<AdminInspection.Page<SupplierPayloads.Supplier>> list(@AuthenticationPrincipal PlugPrincipal caller,
            @RequestParam(required = false) String cursor, @RequestParam(required = false) String limit,
            @RequestParam(required = false) String verification) {
        suppliers.requireStaff(caller, "supplier-read", 30, false);
        return noStore(HttpStatus.OK, suppliers.list(caller, cursor, AdminInspection.limit(limit), verification));
    }

    @PostMapping("/v1/admin/suppliers")
    ResponseEntity<SupplierPayloads.Supplier> create(@AuthenticationPrincipal PlugPrincipal caller,
            @RequestHeader(value = "Idempotency-Key", required = false) String key, @RequestBody(required = false) RedactedBody create) {
        suppliers.requireStaff(caller, "supplier-write", 10, true);
        JsonNode body = object(create, "business_name", "phone", "reason");
        requireKey(key);
        var input = new SupplierPayloads.Create(businessName(body), phone(body), reason(body));
        return noStore(HttpStatus.CREATED, suppliers.create(caller, key, input));
    }

    @GetMapping("/v1/admin/suppliers/{supplierId}")
    ResponseEntity<SupplierPayloads.Supplier> get(@AuthenticationPrincipal PlugPrincipal caller, @PathVariable String supplierId) {
        suppliers.requireStaff(caller, "supplier-read", 30, false);
        return noStore(HttpStatus.OK, suppliers.get(caller, supplierId));
    }

    @PostMapping("/v1/admin/suppliers/{supplierId}")
    ResponseEntity<SupplierPayloads.Supplier> update(@AuthenticationPrincipal PlugPrincipal caller, @PathVariable String supplierId,
            @RequestBody(required = false) RedactedBody update) {
        suppliers.requireStaff(caller, "supplier-write", 10, true);
        JsonNode body = object(update, "business_name", "skill_tags", "place", "service_radius_m", "hours", "time_zone",
                "licence_ref", "contact_name");
        String name = businessName(body);
        JsonNode tags = body.get("skill_tags");
        if (tags == null || !tags.isArray() || tags.isEmpty() || tags.size() > 10) {
            throw ApiException.validation("skill_tags", "invalid", "Choose one to ten listed skills.");
        }
        List<String> skills = new ArrayList<>();
        for (JsonNode tag : tags) {
            if (!tag.isTextual()) throw ApiException.validation("skill_tags", "invalid", "Choose one to ten listed skills.");
            if (skills.contains(tag.asText())) throw ApiException.validation("skill_tags", "invalid", "List each skill once.");
            skills.add(tag.asText());
        }
        JsonNode place = object(body.get("place"), "place", "address", "location");
        String address = text(place, "address", 1, 200);
        JsonNode location = object(place.get("location"), "location", "latitude", "longitude", "precision");
        double latitude = number(location, "latitude", 90);
        double longitude = number(location, "longitude", 180);
        JsonNode precision = location.get("precision");
        if (precision == null || !precision.isTextual() || !List.of("coarse", "fine").contains(precision.asText())) {
            throw ApiException.validation("precision", "invalid", "Choose coarse or fine.");
        }
        JsonNode radius = body.get("service_radius_m");
        if (radius == null || !radius.isIntegralNumber() || !radius.canConvertToInt() || radius.intValue() < 500 || radius.intValue() > 50000) {
            throw ApiException.validation("service_radius_m", "invalid", "Choose a service radius from 500 to 50000 metres.");
        }
        JsonNode hours = body.get("hours");
        if (hours == null || !hours.isArray() || hours.isEmpty() || hours.size() > 6) {
            throw ApiException.validation("hours", "invalid", "Give one to six opening windows.");
        }
        List<AvailabilityWindow> windows = new ArrayList<>();
        for (JsonNode window : hours) {
            object(window, "hours", "days", "from", "to");
            String days = window.path("days").asText(""), from = window.path("from").asText(""), to = window.path("to").asText("");
            if (!window.path("days").isTextual() || !List.of("weekdays", "weekends", "every_day").contains(days)
                    || !window.path("from").isTextual() || !from.matches(CLOCK)
                    || !window.path("to").isTextual() || !to.matches(CLOCK + "|24:00")
                    || ProviderService.minutes(to) <= ProviderService.minutes(from)) {
                throw ApiException.validation("hours", "invalid", "Each window needs days and must end after it starts.");
            }
            windows.add(new AvailabilityWindow(days, from, to));
        }
        String zone = text(body, "time_zone", 1, 64);
        if (!zone.matches("[A-Za-z0-9_+/-]+")) throw ApiException.validation("time_zone", "invalid", "Use an IANA time zone.");
        String licence = body.has("licence_ref") ? text(body, "licence_ref", 3, 64) : null;
        if (licence != null && !licence.matches("[A-Za-z0-9 ./-]+")) {
            throw ApiException.validation("licence_ref", "invalid", "Use letters, digits, spaces and . / - only.");
        }
        String contact = body.has("contact_name") ? text(body, "contact_name", 1, 80) : null;
        var profile = new SupplierPayloads.Profile(name, skills, address,
                new RequestPayloads.Location(latitude, longitude, precision.asText()), radius.intValue(), windows, zone, licence, contact);
        return noStore(HttpStatus.OK, suppliers.update(caller, supplierId, profile));
    }

    @PostMapping("/v1/admin/suppliers/{supplierId}/verification")
    ResponseEntity<SupplierPayloads.Supplier> decide(@AuthenticationPrincipal PlugPrincipal caller, @PathVariable String supplierId,
            @RequestBody(required = false) RedactedBody decision) {
        suppliers.requireStaff(caller, "supplier-write", 10, true);
        JsonNode body = object(decision, "status", "reason");
        JsonNode status = body.get("status");
        if (status == null || !status.isTextual() || !List.of("verified", "rejected", "suspended").contains(status.asText())) {
            throw ApiException.validation("status", "invalid", "Choose verified, rejected or suspended.");
        }
        String reason = reason(body);
        return noStore(HttpStatus.OK, suppliers.decide(caller, supplierId, status.asText(), reason));
    }

    @GetMapping("/v1/admin/opt-outs")
    ResponseEntity<AdminInspection.Page<SupplierPayloads.OptOut>> optOuts(@AuthenticationPrincipal PlugPrincipal caller,
            @RequestParam(required = false) String cursor, @RequestParam(required = false) String limit) {
        suppliers.requireStaff(caller, "supplier-read", 30, false);
        return noStore(HttpStatus.OK, suppliers.optOuts(caller, cursor, AdminInspection.limit(limit)));
    }

    // ---- validation ----------------------------------------------------------------------

    private static <T> ResponseEntity<T> noStore(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }

    private static void requireKey(String key) {
        if (key == null || !key.matches("[A-Za-z0-9_-]{16,128}")) {
            throw ApiException.validation("Idempotency-Key", "invalid", "Provide a valid idempotency key.");
        }
    }

    private static JsonNode object(RedactedBody body, String... fields) {
        return object(body == null ? null : body.json, "body", fields);
    }

    /// An object holding only the named fields; anything else is refused by name.
    private static JsonNode object(JsonNode node, String name, String... fields) {
        if (node == null || !node.isObject()) throw ApiException.validation(name, "invalid", "Send a JSON object.");
        var allowed = new HashSet<>(List.of(fields));
        node.fieldNames().forEachRemaining(field -> {
            if (!allowed.contains(field)) throw ApiException.validation(field, "invalid", "That field is not accepted here.");
        });
        return node;
    }

    private static String text(JsonNode body, String field, int min, int max) {
        JsonNode value = body.get(field);
        if (value == null || value.isNull()) throw ApiException.validation(field, "required", "This field is required.");
        String text = value.isTextual() ? value.asText().strip() : "";
        int length = text.codePointCount(0, text.length());
        if (length < min || length > max || HIDDEN.matcher(text).find()) {
            throw ApiException.validation(field, "invalid", "Use " + min + " to " + max + " characters.");
        }
        return text;
    }

    private static String businessName(JsonNode body) {
        String name = text(body, "business_name", 2, 120);
        if (CONTACT_IN_NAME.matcher(name).find()) {
            throw ApiException.validation("business_name", "invalid", "Use the business name only, without links or numbers.");
        }
        return name;
    }

    private static String reason(JsonNode body) {
        String reason = text(body, "reason", 3, 300);
        if (NUMBER_IN_REASON.matcher(reason).find()) {
            throw ApiException.validation("reason", "invalid", "Leave phone numbers out of the reason.");
        }
        return reason;
    }

    private static String phone(JsonNode body) {
        JsonNode value = body.get("phone");
        if (value == null || !value.isTextual() || !value.asText().matches(PHONE)) {
            throw ApiException.validation("phone", "invalid", "Enter a US mobile number.");
        }
        return value.asText();
    }

    private static double number(JsonNode body, String field, double bound) {
        JsonNode value = body.get(field);
        if (value == null || !value.isNumber() || Math.abs(value.doubleValue()) > bound) {
            throw ApiException.validation(field, "invalid", "Send a valid coordinate.");
        }
        return value.doubleValue();
    }

    /// Spring MVC logs a decoded body through toString at DEBUG level; a phone, a contact name, a
    /// licence or a reason must not reach the log (the ReservationController.RedactedBody pattern).
    static final class RedactedBody {
        final JsonNode json;
        @JsonCreator(mode = JsonCreator.Mode.DELEGATING) RedactedBody(JsonNode json) { this.json = json; }
        @Override public String toString() { return "SupplierBody[redacted]"; }
    }
}
