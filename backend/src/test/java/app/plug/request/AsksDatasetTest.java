package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;

import app.plug.request.RequestPayloads.Location;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

/// Person Two's labelled ask dataset (fixtures/intents/asks.jsonl, P2.S7 and P2.S11) as a
/// backend test: every restricted ask is refused, nothing else is, and the rules alone
/// classify every other row as labelled. Model-assisted runs are recorded separately.
class AsksDatasetTest {
    static final Location HERE = new Location(32.528, -92.714, "coarse");
    // Noon in Ruston, so "tonight" and "this morning" are still ahead.
    static final Clock NOON = Clock.fixed(Instant.parse("2026-10-07T17:00:00Z"), ZoneOffset.UTC);
    final RestrictedIntentPolicy policy = new RestrictedIntentPolicy();

    @Test
    void theRulesAgreeWithEveryLabel() throws Exception {
        List<String> differences = new ArrayList<>();
        var json = new ObjectMapper();
        int rows = 0;
        try (var adapter = new IntentAdapter(IntentAdapterTest.JSON, NOON, (text, now, zone, deadline) -> null)) {
            for (String line : Files.readAllLines(Path.of("../fixtures/intents/asks.jsonl"))) {
                JsonNode row = json.readTree(line);
                rows++;
                String id = row.path("id").asText();
                String text = row.at("/input/text").asText();
                JsonNode expected = row.path("expected");
                boolean refused = policy.refusal(text).isPresent();
                if (row.path("kind").asText().equals("restricted")) {
                    if (!refused) {
                        var result = adapter.classify(text, HERE, "America/Chicago");
                        boolean privatePlace = result.askType() == IntentAdapter.AskType.PLACE_QUESTION
                                && policy.placeRefusal(text).isPresent();
                        if (!privatePlace) differences.add(id + ": not refused");
                    }
                    continue;
                }
                if (refused) { differences.add(id + ": refused by " + policy.refusal(text).get()); continue; }
                var result = adapter.classify(text, HERE, "America/Chicago");
                switch (row.path("kind").asText()) {
                    case "service_request" -> {
                        List<String> tags = result.constraints() == null ? List.of() : result.constraints().skillTags();
                        List<String> anyOf = json.convertValue(expected.path("skill_tags_any_of"), List.class);
                        List<String> noneOf = expected.has("skill_tags_none_of")
                                ? json.convertValue(expected.path("skill_tags_none_of"), List.class) : List.of();
                        if (result.askType() != IntentAdapter.AskType.SERVICE_REQUEST || tags.stream().noneMatch(anyOf::contains)
                                || tags.stream().anyMatch(noneOf::contains)) {
                            differences.add(id + ": " + result.askType() + " " + tags);
                        } else if (expected.has("budget_cents")
                                && !Integer.valueOf(expected.path("budget_cents").asInt()).equals(result.constraints().budgetCents())) {
                            differences.add(id + ": budget " + result.constraints().budgetCents());
                        }
                    }
                    case "place_question" -> {
                        if (result.askType() != IntentAdapter.AskType.PLACE_QUESTION || result.placeName() == null) {
                            differences.add(id + ": " + result.askType() + " place=" + result.placeName());
                        }
                    }
                    case "ambiguous" -> {
                        if (!"ask".equals(result.clarificationField())) differences.add(id + ": " + result.askType());
                    }
                    default -> differences.add(id + ": unknown kind");
                }
            }
        }
        assertThat(rows).isEqualTo(91);
        assertThat(differences).isEmpty();
    }

    /// Ordinary asks that share words with the 2026-10-07 rules. Refusing these would be the
    /// opposite failure: a lawful ask turned away.
    @Test
    void ordinaryAsksThatShareWordsWithTheRulesAreNotRefused() {
        for (String text : List.of("Photographer to shoot my daughter's graduation", "Diagnose my car's check engine light",
                "Psychology tutor for my exam", "Is someone in Ruston able to fix my AC?", "Inspect my roof and report back",
                "Passport photo near campus", "Make me a passport photo", "My car is beat up, need body work",
                "Massage therapist for my back", "Follow up on my roof estimate", "Pick up my meds from CVS",
                "Kids haircut for my son on Saturday", "Install a camera doorbell on my porch", "Clean my mom's house on Saturday",
                "Kill the weeds in my yard", "Career counseling for my resume")) {
            assertThat(policy.refusal(text)).as(text).isEmpty();
        }
    }
}
