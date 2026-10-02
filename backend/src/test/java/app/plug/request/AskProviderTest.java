package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ContractSchemas;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.UUID;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

/// Manual v4 Phase 2 against real PostGIS: one field for both kinds of ask, skills from the
/// vocabulary only, provider capability on the same account, and matching that respects each
/// provider's own radius, availability and licence.
@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(AskProviderTest.TimeConfiguration.class)
class AskProviderTest {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    @Autowired RequestService service;

    // Thursday 2026-10-01 15:00 in Chicago.
    @TestConfiguration static class TimeConfiguration {
        @Bean @Primary RequestClock fixedRequestClock() {
            return new RequestClock(Clock.fixed(Instant.parse("2026-10-01T20:00:00Z"), ZoneOffset.UTC));
        }
    }
    static final String HERE = "{\"latitude\":32.528,\"longitude\":-92.714,\"precision\":\"coarse\"}";

    JsonNode guest() throws Exception {
        return body(mvc.perform(post("/v1/auth/guest").with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .contentType(MediaType.APPLICATION_JSON).content("{\"consent_version\":\"2026-09-01\"}"))
                .andExpect(status().isCreated()), "Session");
    }
    ResultActions send(JsonNode who, String path, String body, boolean keyed) throws Exception {
        var request = post(path).with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .header("Authorization", "Bearer " + who.get("access_token").asText())
                .contentType(MediaType.APPLICATION_JSON).content(body);
        if (keyed) request.header("Idempotency-Key", "ask-provider-test-" + UUID.randomUUID());
        return mvc.perform(request);
    }
    ResultActions read(JsonNode who, String path) throws Exception {
        return mvc.perform(get(path).header("Authorization", "Bearer " + who.get("access_token").asText()));
    }
    JsonNode body(ResultActions result, String schema) throws Exception {
        JsonNode body = mapper.readTree(result.andReturn().getResponse().getContentAsString());
        ContractSchemas.validate(body.has("error") ? "Error" : schema, body);
        return body;
    }
    JsonNode ask(JsonNode who, String text) throws Exception {
        return body(send(who, "/v1/asks", "{\"text\":\"" + text + "\",\"location\":" + HERE
                + ",\"time_zone\":\"America/Chicago\"}", true).andExpect(status().isCreated()), "AskResult");
    }
    JsonNode provide(JsonNode who, String skills, int radius, String location, String days, String licence) throws Exception {
        String body = "{\"skill_tags\":" + skills + ",\"travel_radius_m\":" + radius + ",\"base_location\":" + location
                + ",\"availability\":[{\"days\":\"" + days + "\",\"from\":\"09:00\",\"to\":\"24:00\"}],"
                + "\"time_zone\":\"America/Chicago\"" + (licence == null ? "" : ",\"licence_ref\":\"" + licence + "\"") + "}";
        return body(send(who, "/v1/providers/skills", body, false).andExpect(status().isOk()), "ProviderProfile");
    }

    @Test void oneFieldTakesBothKindsOfAskAndTheServerDecides() throws Exception {
        var person = guest();
        var service = ask(person, "Someone to do knotless braids, $120 max");
        assertThat(service.path("ask_type").asText()).isEqualTo("service_request");
        assertThat(service.at("/request/constraints/skill_tags/0").asText()).isEqualTo("braids");
        assertThat(service.at("/request/constraints/budget_cents").asInt()).isEqualTo(12000);

        var place = ask(person, "How long is the line at Walmart on Ben White?");
        assertThat(place.path("ask_type").asText()).isEqualTo("place_question");
        assertThat(place.at("/place_question/place_name").asText()).isEqualTo("Walmart on Ben White");
        // Phase 4 builds the people-nearby pipeline. Until then: an honest Unknown, real zeros.
        assertThat(place.at("/place_question/status").asText()).isEqualTo("unknown");
        assertThat(place.at("/place_question/progress/notified").asInt()).isZero();
        assertThat(place.at("/place_question/web_answer").isNull()).isTrue();

        var unclear = ask(person, "Something");
        assertThat(unclear.path("ask_type").isNull()).isTrue();
        assertThat(unclear.at("/clarification/field").asText()).isEqualTo("ask");
        String path = "/v1/asks/" + unclear.path("ask_id").asText();
        String answer = "{\"clarification_id\":\"" + unclear.at("/clarification/clarification_id").asText() + "\",\"value\":\"";
        send(person, path + "/clarifications", answer + "astronaut\"}", true).andExpect(status().isBadRequest());
        var resolved = body(send(person, path + "/clarifications", answer + "place_question\"}", true)
                .andExpect(status().isOk()), "AskResult");
        assertThat(resolved.path("ask_type").asText()).isEqualTo("place_question");
        send(person, path + "/clarifications", answer + "barber\"}", true).andExpect(status().isConflict());
        assertThat(body(read(person, path).andExpect(status().isOk()), "AskResult").path("ask_type").asText())
                .isEqualTo("place_question");
        read(guest(), path).andExpect(status().isNotFound());
    }

    @Test void privatePlacesAndRestrictedAsksAreRefusedAndAudited() throws Exception {
        var person = guest();
        int asks = jdbc.queryForObject("SELECT count(*) FROM asks", Integer.class);
        send(person, "/v1/asks", "{\"text\":\"Is anyone at her house right now?\",\"location\":" + HERE + "}", true)
                .andExpect(status().isUnprocessableEntity());
        send(person, "/v1/asks", "{\"text\":\"Track my ex girlfriend's phone\",\"location\":" + HERE + "}", true)
                .andExpect(status().isUnprocessableEntity());
        // Classified as a place question, then refused because the place is a private residence.
        send(person, "/v1/asks", "{\"text\":\"How busy is it at her apartment right now?\",\"location\":" + HERE + "}", true)
                .andExpect(status().isUnprocessableEntity());
        assertThat(jdbc.queryForObject("SELECT count(*) FROM asks", Integer.class)).isEqualTo(asks);
        assertThat(jdbc.queryForList("SELECT reason FROM audit_events WHERE actor_id=? AND action='request.restricted'",
                String.class, person.at("/account/user_id").asText()))
                .contains("restricted_intent:private_place", "restricted_intent:stalking_tracking");
    }

    @Test void anyUserAddsSkillsToTheSameAccount() throws Exception {
        var person = guest();
        String userId = person.at("/account/user_id").asText();
        read(person, "/v1/providers/me").andExpect(status().isNotFound());
        var proposal = body(send(person, "/v1/providers/skills/propose",
                "{\"description\":\"I do knotless braids and wig installs, also crochet locs\"}", false)
                .andExpect(status().isOk()), "SkillProposal");
        assertThat(proposal.path("skills").findValuesAsText("tag")).containsExactly("braids", "wig_install");
        assertThat(proposal.path("unmatched").toString()).contains("crochet locs");
        int users = jdbc.queryForObject("SELECT count(*) FROM users", Integer.class);
        var profile = provide(person, "[\"braids\",\"wig_install\"]", 4828, HERE, "every_day", null);
        assertThat(profile.path("user_id").asText()).as("no second account").isEqualTo(userId);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM users", Integer.class)).isEqualTo(users);
        assertThat(profile.at("/score/state").asText()).as("New, never a zero").isEqualTo("new");
        assertThat(profile.has("licence_ref")).isFalse();
        send(person, "/v1/providers/skills", "{\"skill_tags\":[\"wizardry\"],\"travel_radius_m\":4828,\"base_location\":" + HERE
                + ",\"availability\":[{\"days\":\"weekdays\",\"from\":\"09:00\",\"to\":\"17:00\"}],\"time_zone\":\"America/Chicago\"}", false)
                .andExpect(status().isBadRequest());
        var licenceMissing = body(send(person, "/v1/providers/skills", "{\"skill_tags\":[\"electrical\"],\"travel_radius_m\":4828,"
                + "\"base_location\":" + HERE + ",\"availability\":[{\"days\":\"weekdays\",\"from\":\"09:00\",\"to\":\"17:00\"}],"
                + "\"time_zone\":\"America/Chicago\"}", false).andExpect(status().isBadRequest()), "Error");
        assertThat(licenceMissing.at("/error/details/0/code").asText()).isEqualTo("licence_required");
        send(person, "/v1/providers/skills/propose", "{\"description\":\"I sell stolen phones\"}", false)
                .andExpect(status().isUnprocessableEntity());
    }

    @Test void matchingRespectsEachProvidersOwnRadiusAvailabilityAndLicence() throws Exception {
        String near = "{\"latitude\":32.531,\"longitude\":-92.711,\"precision\":\"coarse\"}";       // about 450 m away
        String farAway = "{\"latitude\":32.575,\"longitude\":-92.714,\"precision\":\"coarse\"}";    // about 5.2 km away
        var available = guest();
        provide(available, "[\"laptop_repair\"]", 4828, near, "every_day", null);
        var shortRadius = guest();
        provide(shortRadius, "[\"laptop_repair\"]", 1609, farAway, "every_day", null);   // 1 mi, 5 km away: never sent
        var weekendsOnly = guest();
        provide(weekendsOnly, "[\"laptop_repair\"]", 8000, near, "weekends", null);      // Thursday: not available
        var otherSkill = guest();
        provide(otherSkill, "[\"braids\"]", 8000, near, "every_day", null);

        var asker = guest();
        provide(asker, "[\"laptop_repair\"]", 8000, near, "every_day", null);            // never matched to themselves
        var request = ask(asker, "My laptop screen is cracked, laptop repair today").path("request");
        service.workOnce();
        var matched = jdbc.queryForList("SELECT provider_id FROM request_matches WHERE request_id=?", String.class,
                request.path("request_id").asText());
        assertThat(matched).contains(available.at("/account/user_id").asText()).doesNotContain(
                shortRadius.at("/account/user_id").asText(), weekendsOnly.at("/account/user_id").asText(),
                otherSkill.at("/account/user_id").asText(), asker.at("/account/user_id").asText());
        var progress = body(read(asker, "/v1/requests/" + request.path("request_id").asText()), "RequestResource").path("progress");
        assertThat(progress.path("contacted").asInt()).as("real providers count as contacted").isEqualTo(matched.size());
        assertThat(progress.path("replied").asInt()).isZero();

        var licensed = guest();
        provide(licensed, "[\"electrical\"]", 8000, near, "every_day", "LA-EL-12345");
        var unlicensedAsk = guest();
        var electrical = ask(unlicensedAsk, "Electrician to fix a breaker today").path("request");
        assertThat(electrical.at("/constraints/licence_required").asBoolean()).isTrue();
        service.workOnce();
        assertThat(jdbc.queryForList("SELECT provider_id FROM request_matches WHERE request_id=?", String.class,
                electrical.path("request_id").asText())).contains(licensed.at("/account/user_id").asText())
                .doesNotContain(available.at("/account/user_id").asText());
    }
}
