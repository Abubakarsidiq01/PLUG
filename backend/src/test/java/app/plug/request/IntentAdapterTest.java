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
    Create input(String text) { return new Create(text,null,null,null,null,null,new Location(32.52849,-92.71441,"coarse")); }
    @Test void everyUntrustedProviderFailureFallsBackWithoutModelReasoning() throws Exception {
        List<String> invalid = List.of("invalid JSON", "null", "{}", "{\"category\":\"plumber\"}",
                "{\"category\":\"barber\",\"reasoning\":\"private model reasoning\"}",
                "{\"category\":\"barber\",\"budget_cents\":499}",
                "{\"category\":\"barber\",\"budget_cents\":3500.5}",
                "{\"category\":\"barber\",\"budget_cents\":\"3500\"}",
                "{\"category\":\"barber\",\"max_distance_m\":50001}",
                "{\"category\":\"barber\",\"max_distance_m\":-1}",
                "{\"category\":\"barber\",\"needed_by\":\"2026-10-01T19:00:00Z\"}",
                "{\"category\":\"barber\",\"needed_by\":\"2027-10-01T19:00:00Z\"}",
                "{\"category\":\"barber\",\"category\":\"beauty\"}",
                "{\"category\":\"barber\"} {}", "x".repeat(4097));
        for (String raw : invalid) {
            try (var adapter = new IntentAdapter(JSON,CLOCK,(text,timeout)->raw)) {
                var result = adapter.extract(input("Barber under $35 in 30 minutes"));
                assertThat(result.category()).as(raw).isEqualTo("barber");
                assertThat(result.budgetCents()).as(raw).isEqualTo(3500);
                assertThat(result.neededBy()).as(raw).isEqualTo(NOW.plusSeconds(1800));
                assertThat(result.maxDistanceM()).isEqualTo(10000);
            }
        }
        try (var adapter = new IntentAdapter(JSON,CLOCK,(text,timeout)->{throw new java.util.concurrent.TimeoutException();})) {
            assertThat(adapter.extract(input("Something nearby")).category()).isNull();
        }
    }
    @Test void blockingProviderHasEnforcedDeadline() {
        long started=System.nanoTime();
        try (var adapter=new IntentAdapter(JSON,CLOCK,(text,timeout)->{Thread.sleep(60000);return null;})) {
            assertThat(adapter.extract(input("Barber")).category()).isEqualTo("barber");
        }
        assertThat((System.nanoTime()-started)/1_000_000).isBetween(5000L,8500L);
    }
    @Test void explicitConstraintsWinBeforeInvalidTextualExtractionAndAmbiguityIsOneQuestion() {
        try(var adapter=new IntentAdapter(JSON,CLOCK,(text,timeout)->null)) {
            var explicit=new Create("Barber under $1 in 9999999 hours", "beauty",3500,"USD",NOW.plusSeconds(60),1000,
                    new Location(32.52849,-92.71441,"coarse"));
            var result=adapter.extract(explicit);
            assertThat(result.category()).isEqualTo("beauty");
            assertThat(result.budgetCents()).isEqualTo(3500);
            assertThat(result.neededBy()).isEqualTo(NOW.plusSeconds(60));
            assertThat(result.location()).isEqualTo(new Location(32.528,-92.714,"coarse"));
            assertThat(adapter.extract(input("Fresh cut and nails under $35")).category()).isNull();
            assertThat(adapter.extract(input("Barber")).budgetCents()).isNull();
        }
    }
    @Test void malformedExtractedConstraintsNeverSilentlyBroadenSearch() {
        try(var adapter=new IntentAdapter(JSON,CLOCK,(text,timeout)->null)) {
            for(String text:List.of("Barber under $35.999", "Barber under $-5", "Barber under $1,000", "Barber under $",
                    "Barber under $30 or $35", "Barber in 9999999 hours", "Barber in -1 minutes", "Barber in 1.5 hours",
                    "Barber in 0 minutes", "Barber in 20 minutes or in 30 minutes")) {
                assertThatThrownBy(()->adapter.extract(input(text))).as(text).isInstanceOf(ApiException.class);
            }
        }
    }
    @Test void providerFixturesExerciseFailureModes() throws Exception {
        for(String line:java.nio.file.Files.readAllLines(java.nio.file.Path.of("../fixtures/intents/p2.jsonl"))) {
            var entry=JSON.readTree(line);
            if(!entry.path("expected").path("fallback_required").asBoolean()) continue;
            String provider=entry.path("provider").asText();
            IntentAdapter.Provider failure=(text,timeout)->switch(provider) {
                case "timeout" -> throw new java.util.concurrent.TimeoutException();
                case "invalid_json" -> "{bad";
                case "unknown_field" -> "{\"category\":\"barber\",\"reason\":\"secret\"}";
                case "out_of_range_budget" -> "{\"category\":\"barber\",\"budget_cents\":999999}";
                case "unsupported_category" -> "{\"category\":\"plumber\"}";
                default -> throw new IllegalArgumentException("Unknown fixture provider");
            };
            try(var adapter=new IntentAdapter(JSON,CLOCK,failure)) {
                var result=adapter.extract(JSON.treeToValue(entry.path("input"),Create.class));
                var expected=entry.path("expected");
                assertThat(result.category()).isEqualTo(expected.path("category").isNull()?null:expected.path("category").asText());
                if(expected.has("budget_cents")) assertThat(result.budgetCents()).isEqualTo(expected.path("budget_cents").asInt());
            }
        }
    }
    @Test void repeatedRelativeTimeUsesOneInstantOnARealClock() {
        try(var adapter = new IntentAdapter(JSON,Clock.systemUTC(),(text,timeout)->null)) {
            assertThat(adapter.extract(input("Barber in 30 minutes and in 30 minutes")).neededBy()).isNotNull();
        }
    }
}
