package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import app.plug.foundation.ApiException;
import app.plug.request.RequestPayloads.Create;
import app.plug.request.RequestPayloads.Location;
import com.fasterxml.jackson.core.StreamReadFeature;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.MapperFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.fasterxml.jackson.databind.json.JsonMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.Test;

class IntentAdapterTest {
    static final Instant NOW = Instant.parse("2026-10-01T20:00:00Z");
    static final Clock CLOCK = Clock.fixed(NOW, ZoneOffset.UTC);
    static final ObjectMapper JSON = JsonMapper.builder().findAndAddModules()
            .propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
            .enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, DeserializationFeature.FAIL_ON_TRAILING_TOKENS)
            .enable(StreamReadFeature.STRICT_DUPLICATE_DETECTION)
            .disable(DeserializationFeature.ACCEPT_FLOAT_AS_INT).disable(MapperFeature.ALLOW_COERCION_OF_SCALARS).build();
    static final Location HERE = new Location(32.52849,-92.71441,"coarse");
    static final IntentAdapter.Provider NONE = (text, now, zone, deadline) -> null;
    Create input(String text) { return input(text, null); }
    Create input(String text, String zone) { return new Create(text,null,null,null,null,null,HERE,zone); }
    RequestPayloads.Constraints extract(IntentAdapter adapter, String text) { return adapter.extract(input(text)).constraints(); }

    @Test void everyUntrustedProviderFailureFallsBackWithoutModelReasoning() throws Exception {
        List<String> invalid = List.of("invalid JSON", "null", "{}", "{\"category\":\"plumber\"}",
                "{\"category\":\"barber\",\"service_name\":\"Barber\",\"reasoning\":\"private model reasoning\"}",
                "{\"category\":\"Barber Shop\",\"service_name\":\"Barber\"}",
                "{\"category\":\"barber\",\"service_name\":\"Barber\",\"budget_cents\":499}",
                "{\"category\":\"barber\",\"service_name\":\"Barber\",\"budget_cents\":3500.5}",
                "{\"category\":\"barber\",\"service_name\":\"Barber\",\"budget_cents\":\"3500\"}",
                "{\"category\":\"barber\",\"service_name\":\"Barber\",\"max_distance_m\":50001}",
                "{\"category\":\"barber\",\"service_name\":\"Barber\",\"needed_by\":\"2026-10-01T19:00:00Z\"}",
                "{\"category\":\"barber\",\"service_name\":\"Barber\",\"needed_by\":\"2027-10-01T19:00:00Z\"}",
                "{\"category\":\"barber\",\"service_name\":\"Barber\",\"search_terms\":[\"a\",\"b\",\"c\",\"d\",\"e\",\"f\"]}",
                "{\"category\":\"barber\",\"service_name\":\"<script>\"}",
                "{\"category\":\"barber\",\"category\":\"beauty\"}",
                "{\"category\":\"barber\"} {}", "x".repeat(8193));
        for (String raw : invalid) {
            try (var adapter = new IntentAdapter(JSON,CLOCK,(text,now,zone,deadline)->raw)) {
                var result = extract(adapter, "Barber under $35 in 30 minutes");
                assertThat(result.category()).as(raw).isEqualTo("barber");
                assertThat(result.serviceName()).as(raw).isEqualTo("Barber");
                assertThat(result.budgetCents()).as(raw).isEqualTo(3500);
                assertThat(result.neededBy()).as(raw).isEqualTo(NOW.plusSeconds(1800));
                assertThat(result.maxDistanceM()).isEqualTo(10000);
            }
        }
        try (var adapter = new IntentAdapter(JSON,CLOCK,(text,now,zone,deadline)->{throw new java.util.concurrent.TimeoutException();})) {
            var result = adapter.extract(input("Something nearby"));
            assertThat(result.constraints().category()).isNull();
            assertThat(result.clarificationOptions()).isEqualTo(IntentAdapter.POPULAR);
        }
    }
    @Test void anyServiceIsExtractedFromThePersonsWords() {
        try (var adapter = new IntentAdapter(JSON,CLOCK,NONE)) {
            var shoe = adapter.extract(input("I need to repair my shoe for 45 dollars tomorrow, who is available?", "America/Chicago"));
            assertThat(shoe.clarificationOptions()).isNull();
            assertThat(shoe.constraints().category()).isEqualTo("shoe_repair");
            assertThat(shoe.constraints().serviceName()).isEqualTo("Shoe repair");
            assertThat(shoe.constraints().searchTerms()).containsExactly("shoe repair", "cobbler");
            assertThat(shoe.constraints().budgetCents()).isEqualTo(4500);
            // 23:59 tomorrow in Chicago (UTC-5 in October), not tomorrow in UTC.
            assertThat(shoe.constraints().neededBy()).isEqualTo(Instant.parse("2026-10-03T04:59:00Z"));
            assertThat(extract(adapter, "Leaking kitchen sink, plumber within 5 miles").maxDistanceM()).isEqualTo(8047);
            assertThat(extract(adapter, "Locked out of my house tonight").category()).isEqualTo("locksmith");
            assertThat(extract(adapter, "Cheap pizza for lunch under $2,000").category()).isEqualTo("restaurant");
            assertThat(extract(adapter, "Movers for 1,200 dollars").budgetCents()).isEqualTo(120000);
        }
    }
    @Test void validClaudeOutputNamesTheServiceButNotTheNumbersItCanParse() {
        String model = "{\"category\":\"bike_repair\",\"service_name\":\"Bike repair\",\"search_terms\":[\"bike repair\","
                + "\"bicycle shop\"],\"budget_cents\":99900,\"needed_by\":null,\"max_distance_m\":null,\"candidates\":[]}";
        try (var adapter = new IntentAdapter(JSON,CLOCK,(text,now,zone,deadline)->model)) {
            var result = extract(adapter, "My bicycle chain snapped, fix it for $45");
            assertThat(result.category()).isEqualTo("bike_repair");
            assertThat(result.serviceName()).isEqualTo("Bike repair");
            assertThat(result.searchTerms()).containsExactly("bike repair", "bicycle shop");
            assertThat(result.budgetCents()).as("the stated $45 wins over the model's number").isEqualTo(4500);
        }
        String candidates = "{\"category\":null,\"service_name\":null,\"search_terms\":[],\"budget_cents\":null,"
                + "\"needed_by\":null,\"max_distance_m\":null,\"candidates\":[{\"value\":\"tailor\",\"label\":\"Tailor\"},"
                + "{\"value\":\"dry_cleaning\",\"label\":\"Dry cleaning\"}]}";
        try (var adapter = new IntentAdapter(JSON,CLOCK,(text,now,zone,deadline)->candidates)) {
            var result = adapter.extract(input("Something for my suit"));
            assertThat(result.constraints().category()).isNull();
            assertThat(result.clarificationOptions()).extracting(RequestPayloads.Option::value).containsExactly("tailor", "dry_cleaning");
        }
    }
    @Test void blockingProviderHasEnforcedDeadline() {
        long started=System.nanoTime();
        try (var adapter=new IntentAdapter(JSON,CLOCK,(text,now,zone,deadline)->{Thread.sleep(60000);return null;})) {
            assertThat(extract(adapter, "Barber").category()).isEqualTo("barber");
        }
        assertThat((System.nanoTime()-started)/1_000_000).isBetween(5000L,8500L);
    }
    @Test void explicitConstraintsWinBeforeInvalidTextualExtractionAndAmbiguityIsOneQuestion() {
        try(var adapter=new IntentAdapter(JSON,CLOCK,NONE)) {
            var explicit=new Create("Barber under $1 in 9999999 hours", "beauty",3500,"USD",NOW.plusSeconds(60),1000,HERE,null);
            var result=adapter.extract(explicit).constraints();
            assertThat(result.category()).isEqualTo("beauty");
            assertThat(result.serviceName()).isEqualTo("Beauty & nails");
            assertThat(result.budgetCents()).isEqualTo(3500);
            assertThat(result.neededBy()).isEqualTo(NOW.plusSeconds(60));
            assertThat(result.location()).isEqualTo(new Location(32.528,-92.714,"coarse"));
            var ambiguous = adapter.extract(input("Fresh cut and nails under $35"));
            assertThat(ambiguous.constraints().category()).isNull();
            assertThat(ambiguous.constraints().searchTerms()).isEmpty();
            assertThat(ambiguous.clarificationOptions()).extracting(RequestPayloads.Option::value).containsExactly("barber", "beauty");
            assertThat(extract(adapter, "Barber").budgetCents()).isNull();
        }
    }
    @Test void malformedExtractedConstraintsNeverSilentlyBroadenSearch() {
        try(var adapter=new IntentAdapter(JSON,CLOCK,NONE)) {
            for(String text:List.of("Barber under $35.999", "Barber under $-5", "Barber under $1,00", "Barber under $10,0000", "Barber under $",
                    "Barber under $30 or $35", "Barber in 9999999 hours", "Barber in -1 minutes", "Barber in 1.5 hours",
                    "Barber in 0 minutes", "Barber in 20 minutes or in 30 minutes", "Barber under $5001",
                    "Barber for 45 dollars or $50", "Barber in 30 minutes tomorrow", "Barber within 100 miles")) {
                assertThatThrownBy(()->adapter.extract(input(text))).as(text).isInstanceOf(ApiException.class);
            }
            assertThatThrownBy(()->adapter.extract(input("Barber tomorrow", "Mars/Olympus"))).isInstanceOf(ApiException.class);
        }
    }
    @Test void providerFixturesExerciseFailureModes() throws Exception {
        for(String line:java.nio.file.Files.readAllLines(java.nio.file.Path.of("../fixtures/intents/p2.jsonl"))) {
            var entry=JSON.readTree(line);
            if(!entry.path("expected").path("fallback_required").asBoolean()) continue;
            String provider=entry.path("provider").asText();
            IntentAdapter.Provider failure=(text,now,zone,deadline)->switch(provider) {
                case "timeout" -> throw new java.util.concurrent.TimeoutException();
                case "invalid_json" -> "{bad";
                case "unknown_field" -> "{\"category\":\"barber\",\"service_name\":\"Barber\",\"reason\":\"secret\"}";
                case "out_of_range_budget" -> "{\"category\":\"barber\",\"service_name\":\"Barber\",\"budget_cents\":999999}";
                case "invalid_category" -> "{\"category\":\"Plumber!\",\"service_name\":\"Plumber\"}";
                default -> throw new IllegalArgumentException("Unknown fixture provider");
            };
            try(var adapter=new IntentAdapter(JSON,CLOCK,failure)) {
                var result=adapter.extract(JSON.treeToValue(entry.path("input"),Create.class)).constraints();
                var expected=entry.path("expected");
                assertThat(result.category()).isEqualTo(expected.path("category").isNull()?null:expected.path("category").asText());
                if(expected.has("budget_cents")) assertThat(result.budgetCents()).isEqualTo(expected.path("budget_cents").asInt());
            }
        }
    }
    @Test void repeatedRelativeTimeUsesOneInstantOnARealClock() {
        try(var adapter = new IntentAdapter(JSON,Clock.systemUTC(),NONE)) {
            assertThat(extract(adapter, "Barber in 30 minutes and in 30 minutes").neededBy()).isNotNull();
        }
    }
}
