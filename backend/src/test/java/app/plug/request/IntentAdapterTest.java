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
    static IntentAdapter adapter(IntentAdapter.Provider provider) { return new IntentAdapter(JSON, CLOCK, provider); }
    Create input(String text) { return input(text, null); }
    Create input(String text, String zone) { return new Create(text,null,null,null,null,null,HERE,zone); }
    RequestPayloads.Constraints extract(IntentAdapter adapter, String text) { return adapter.extract(input(text)).constraints(); }
    IntentAdapter.Result ask(IntentAdapter adapter, String text) { return adapter.classify(text, HERE, "America/Chicago"); }

    @Test void everyUntrustedProviderFailureFallsBackWithoutModelReasoning() throws Exception {
        List<String> invalid = List.of("invalid JSON", "null", "{}", "{\"ask_type\":\"guess\"}",
                "{\"ask_type\":\"service_request\",\"skill_tags\":[],\"reasoning\":\"private model reasoning\"}",
                "{\"ask_type\":\"service_request\",\"skill_tags\":[],\"budget_cents\":499}",
                "{\"ask_type\":\"service_request\",\"skill_tags\":[],\"budget_cents\":3500.5}",
                "{\"ask_type\":\"service_request\",\"skill_tags\":[],\"max_distance_m\":50001}",
                "{\"ask_type\":\"service_request\",\"skill_tags\":[],\"needed_by\":\"2026-10-01T19:00:00Z\"}",
                "{\"ask_type\":\"service_request\",\"skill_tags\":[],\"needed_by\":\"2027-10-01T19:00:00Z\"}",
                "{\"ask_type\":\"service_request\",\"ask_type\":\"place_question\"}",
                "{\"ask_type\":\"service_request\"} {}", "x".repeat(8193));
        for (String raw : invalid) {
            try (var adapter = adapter((text,now,zone,deadline)->raw)) {
                var result = extract(adapter, "Barber under $35 in 30 minutes");
                assertThat(result.category()).as(raw).isEqualTo("barber");
                assertThat(result.skillTags()).as(raw).containsExactly("barber");
                assertThat(result.budgetCents()).as(raw).isEqualTo(3500);
                assertThat(result.neededBy()).as(raw).isEqualTo(NOW.plusSeconds(1800));
                assertThat(result.maxDistanceM()).isEqualTo(10000);
            }
        }
        try (var adapter = adapter((text,now,zone,deadline)->{throw new java.util.concurrent.TimeoutException();})) {
            var result = ask(adapter, "Something nearby");
            assertThat(result.askType()).isEqualTo(IntentAdapter.AskType.UNCLEAR);
            assertThat(result.clarificationField()).isEqualTo("ask");
            assertThat(result.clarificationOptions()).extracting(RequestPayloads.Option::value).contains("place_question", "barber");
        }
    }
    @Test void oneFieldTakesBothKindsOfAsk() {
        try (var adapter = adapter(NONE)) {
            var braids = ask(adapter, "Someone to do knotless braids, $120 max, Saturday morning");
            assertThat(braids.askType()).isEqualTo(IntentAdapter.AskType.SERVICE_REQUEST);
            assertThat(braids.constraints().skillTags()).containsExactly("braids");
            assertThat(braids.constraints().budgetCents()).isEqualTo(12000);
            var line = ask(adapter, "How long is the line at Walmart on Ben White?");
            assertThat(line.askType()).isEqualTo(IntentAdapter.AskType.PLACE_QUESTION);
            assertThat(line.placeName()).isEqualTo("Walmart on Ben White");
            assertThat(ask(adapter, "Is the DPS office busy right now?").askType()).isEqualTo(IntentAdapter.AskType.PLACE_QUESTION);
            // A status question about a business is still a place question, not a booking.
            assertThat(ask(adapter, "Is the barbershop on Main busy right now?").askType()).isEqualTo(IntentAdapter.AskType.PLACE_QUESTION);
            assertThat(ask(adapter, "Something").askType()).isEqualTo(IntentAdapter.AskType.UNCLEAR);
        }
    }
    @Test void modelMustSupplyEverySchemaFieldAndAtMostFiveTags() throws Exception {
        String valid = "{\"ask_type\":\"service_request\",\"skill_tags\":[\"nails\"],"
                + "\"place_name\":null,\"budget_cents\":null,\"needed_by\":null,\"max_distance_m\":null}";
        // A complete structured reading is accepted, proving that this is not an
        // always-fallback test. Incomplete/malformed readings must use the rules.
        try (var adapter = adapter((text, now, zone, deadline) -> valid)) {
            assertThat(extract(adapter, "Barber").category()).isEqualTo("nails");
        }
        for (String field : List.of("ask_type", "skill_tags", "place_name", "budget_cents", "needed_by", "max_distance_m")) {
            var missing = (com.fasterxml.jackson.databind.node.ObjectNode) JSON.readTree(valid);
            missing.remove(field);
            try (var adapter = adapter((text, now, zone, deadline) -> missing.toString())) {
                assertThat(extract(adapter, "Barber").category()).as("missing %s", field).isEqualTo("barber");
            }
        }
        for (String tags : List.of("null", "[\"nails\",\"nails\",\"nails\",\"nails\",\"nails\",\"nails\"]")) {
            var malformed = (com.fasterxml.jackson.databind.node.ObjectNode) JSON.readTree(valid);
            malformed.set("skill_tags", JSON.readTree(tags));
            try (var adapter = adapter((text, now, zone, deadline) -> malformed.toString())) {
                assertThat(extract(adapter, "Barber").category()).isEqualTo("barber");
            }
        }
    }
    @Test void skillTagsComeOnlyFromTheVocabulary() {
        String model = "{\"ask_type\":\"service_request\",\"skill_tags\":[\"underwater_basket_weaving\",\"laptop_repair\"],"
                + "\"place_name\":null,\"budget_cents\":99900,\"needed_by\":null,\"max_distance_m\":null}";
        try (var adapter = adapter((text,now,zone,deadline)->model)) {
            var result = ask(adapter, "My macbook screen cracked, fix it for $45");
            assertThat(result.constraints().skillTags()).as("an invented tag is dropped").containsExactly("laptop_repair");
            assertThat(result.constraints().serviceName()).isEqualTo("Laptop repair");
            assertThat(result.constraints().budgetCents()).as("the stated $45 wins over the model's number").isEqualTo(4500);
        }
        try (var adapter = adapter(NONE)) {
            var shoe = adapter.extract(input("I need to repair my shoe for 45 dollars tomorrow, who is available?", "America/Chicago"));
            assertThat(shoe.constraints().skillTags()).containsExactly("shoe_repair");
            assertThat(shoe.constraints().budgetCents()).isEqualTo(4500);
            assertThat(shoe.constraints().neededBy()).isEqualTo(Instant.parse("2026-10-03T04:59:00Z"));
            var both = extract(adapter, "Need a fresh cut and my nails done under $35");
            assertThat(both.skillTags()).containsExactly("barber", "nails");
            var licensed = extract(adapter, "Electrician to fix a breaker");
            assertThat(licensed.licenceRequired()).isTrue();
            assertThat(extract(adapter, "Leaking kitchen sink within 5 miles").maxDistanceM()).isEqualTo(8047);
            assertThat(extract(adapter, "Find a restaurant for dinner").category()).isNull();
        }
    }
    @Test void blockingProviderHasEnforcedDeadline() {
        long started=System.nanoTime();
        try (var adapter=adapter((text,now,zone,deadline)->{Thread.sleep(60000);return null;})) {
            assertThat(extract(adapter, "Barber").category()).isEqualTo("barber");
        }
        assertThat((System.nanoTime()-started)/1_000_000).isBetween(5000L,8500L);
    }
    @Test void explicitConstraintsWinAndUnknownSkillsAreRefused() {
        try (var adapter=adapter(NONE)) {
            var explicit=new Create("Barber under $1 in 9999999 hours", "nails",3500,"USD",NOW.plusSeconds(60),1000,HERE,null);
            var result=adapter.extract(explicit).constraints();
            assertThat(result.category()).isEqualTo("nails");
            assertThat(result.serviceName()).isEqualTo("Nails");
            assertThat(result.budgetCents()).isEqualTo(3500);
            assertThat(result.location()).isEqualTo(new Location(32.528,-92.714,"coarse"));
            assertThatThrownBy(()->adapter.extract(new Create("Hair", "hairdresser_deluxe",null,null,null,null,HERE,null)))
                    .isInstanceOf(ApiException.class);
            var unknown = adapter.extract(input("Something nearby under $35"));
            assertThat(unknown.clarificationField()).isEqualTo("category");
            assertThat(unknown.clarificationOptions()).hasSize(8).noneMatch(o -> o.value().equals("place_question"));
        }
    }
    @Test void malformedExtractedConstraintsNeverSilentlyBroadenSearch() {
        try(var adapter=adapter(NONE)) {
            for(String text:List.of("Barber under $35.999", "Barber under $-5", "Barber under $1,00", "Barber under $10,0000",
                    "Barber under $", "Barber under $30 or $35", "Barber in 9999999 hours", "Barber in -1 minutes",
                    "Barber in 1.5 hours", "Barber in 0 minutes", "Barber in 20 minutes or in 30 minutes",
                    "Barber under $5001", "Barber for 45 dollars or $50", "Barber in 30 minutes tomorrow", "Barber within 100 miles")) {
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
                case "unknown_field" -> "{\"ask_type\":\"service_request\",\"skill_tags\":[\"barber\"],\"reason\":\"secret\"}";
                case "out_of_range_budget" -> "{\"ask_type\":\"service_request\",\"skill_tags\":[\"barber\"],\"budget_cents\":999999}";
                case "invalid_category" -> "{\"ask_type\":\"service_request\",\"skill_tags\":[\"Plumber!\"]}";
                default -> throw new IllegalArgumentException("Unknown fixture provider");
            };
            try(var adapter=adapter(failure)) {
                var result=adapter.extract(JSON.treeToValue(entry.path("input"),Create.class)).constraints();
                var expected=entry.path("expected");
                assertThat(result.category()).isEqualTo(expected.path("category").isNull()?null:expected.path("category").asText());
                if(expected.has("budget_cents")) assertThat(result.budgetCents()).isEqualTo(expected.path("budget_cents").asInt());
            }
        }
    }
    @Test void restrictedIntentIsStricterWithoutRefusingOrdinaryJobs() {
        var policy = new RestrictedIntentPolicy();
        for (String refused : List.of("Find someone to sell me stolen credit card numbers", "Need a gun by tonight",
                "Track my ex girlfriend's phone", "Where does my coworker live", "Someone to hack her instagram",
                "Escort for tonight", "Babysitter for my kids tonight", "Diagnose my rash", "Kill my neighbour")) {
            assertThat(policy.refusal(refused)).as(refused).isPresent();
        }
        for (String allowed : List.of("Someone to clean her house", "Car diagnostic for check engine light", "Kill the weeds in my yard",
                "Poison ivy removal", "Track my package delivery", "Pick up my prescription from CVS",
                "Borrow a nail gun and hang shelves", "Bath bombs for a gift", "Apartment cleaning Saturday")) {
            assertThat(policy.refusal(allowed)).as(allowed).isEmpty();
        }
        assertThat(policy.placeRefusal("Is anyone at her house right now?")).isPresent();
        assertThat(policy.placeRefusal("How long is the line at Walmart?")).isEmpty();
    }
    @Test void repeatedRelativeTimeUsesOneInstantOnARealClock() {
        try(var adapter = new IntentAdapter(JSON,Clock.systemUTC(),NONE)) {
            assertThat(extract(adapter, "Barber in 30 minutes and in 30 minutes").neededBy()).isNotNull();
        }
    }
}
