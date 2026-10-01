package app.plug.request;

import com.fasterxml.jackson.annotation.JsonInclude;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;

public final class RequestPayloads {
    private RequestPayloads() {}
    @com.fasterxml.jackson.databind.annotation.JsonDeserialize(using = CreateDeserializer.class)
    public record Create(@NotBlank String text,
            @Pattern(regexp = "barber|beauty") String category,
            @Min(500) @Max(50000) Integer budgetCents,
            @Pattern(regexp = "[A-Z]{3}") String currency,
            Instant neededBy,
            @Min(100) @Max(50000) Integer maxDistanceM, @NotNull @Valid Location location) {
        @com.fasterxml.jackson.annotation.JsonIgnore
        @jakarta.validation.constraints.AssertTrue(message = "Text must contain at most 500 characters.")
        public boolean isTextLengthValid() { return text == null || text.codePointCount(0, text.length()) <= 500; }
        @Override public String toString() { return "Create[redacted]"; }
    }
    public static class CreateDeserializer extends com.fasterxml.jackson.databind.JsonDeserializer<Create> {
        private record Fields(String text, String category, Integer budgetCents, String currency,
                Instant neededBy, Integer maxDistanceM, Location location) {}
        @Override public Create deserialize(com.fasterxml.jackson.core.JsonParser parser,
                com.fasterxml.jackson.databind.DeserializationContext context) throws java.io.IOException {
            com.fasterxml.jackson.databind.JsonNode tree = parser.getCodec().readTree(parser);
            if (!tree.isObject()) throw com.fasterxml.jackson.databind.JsonMappingException.from(parser, "Expected an object");
            for (String field : List.of("category", "budget_cents", "currency", "needed_by", "max_distance_m")) {
                if (tree.has(field) && tree.get(field).isNull()) {
                    throw com.fasterxml.jackson.databind.JsonMappingException.from(parser, "Explicit null is not permitted");
                }
            }
            if (tree.has("needed_by") && !tree.get("needed_by").isTextual()) {
                throw com.fasterxml.jackson.databind.JsonMappingException.from(parser, "Timestamp must be an ISO-8601 string");
            }
            Fields fields = parser.getCodec().treeToValue(tree, Fields.class);
            return new Create(fields.text(), fields.category(), fields.budgetCents(), fields.currency(),
                    fields.neededBy(), fields.maxDistanceM(), fields.location());
        }
    }
    public record Location(@NotNull @DecimalMin("-90") @DecimalMax("90") Double latitude,
            @NotNull @DecimalMin("-180") @DecimalMax("180") Double longitude,
            @NotNull @Pattern(regexp = "coarse|fine") String precision) {
        @Override public String toString() { return "Location[redacted]"; }
        public Location rounded() {
            double scale = "fine".equals(precision) ? 10000 : 1000;
            return new Location(Math.round(latitude * scale) / scale, Math.round(longitude * scale) / scale, precision);
        }
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public record Constraints(String category, Integer budgetCents, String currency, Instant neededBy,
            int maxDistanceM, Location location) {}
    public record Answer(@NotBlank @Size(max = 64) @Pattern(regexp = "cla_[A-Za-z0-9-]+") String clarificationId,
            @NotBlank @Size(max = 64) @Pattern(regexp = "[a-z0-9_]+") String value) {}
    public record Progress(int contacted, int replied, int offersReady) {}
    public record Option(String value, String label) {}
    public record Clarification(String clarificationId, String field, String question, List<Option> options) {}
    public record Resource(String requestId, String status, String nextAction, String text, Constraints constraints,
            Progress progress, Clarification clarification, String noResultReason, Integer pollAfterSeconds,
            Instant createdAt, Instant updatedAt, Instant expiresAt) {
        @Override public String toString() { return "Resource[redacted]"; }
    }
    public record Place(String placeId, String name, String address, int distanceM) {}
    public record Offer(String offerId, Place place, String serviceName, int priceCents, String currency,
            Instant availableAt, Instant expiresAt, Instant observedAt, String truthLabel, String source) {}
    public record Offers(String requestId, List<Offer> offers) {}
}
