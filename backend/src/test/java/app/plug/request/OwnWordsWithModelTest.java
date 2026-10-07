package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ContractSchemas;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/// Requests in the person's own words with a model reading the ask (ADR-011, 2026-10-07
/// amendment), against real PostGIS. The model is scripted per sentence so the server's own
/// handling of its answer is what is tested: the label, a model refusal, a label the policy
/// refuses, and a label that names a licensed listed skill.
@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(OwnWordsWithModelTest.ScriptedModel.class)
class OwnWordsWithModelTest {
    static final String HERE = "{\"latitude\":32.528,\"longitude\":-92.714,\"precision\":\"coarse\"}";
    static final String READING = "{\"ask_type\":\"service_request\",\"skill_tags\":[],\"place_name\":null,"
            + "\"budget_cents\":null,\"needed_by\":null,\"max_distance_m\":null,\"service_label\":%s,\"restricted\":%s}";
    static final Map<String, String> ANSWERS = Map.of(
            "Can someone bring my grandfather's harp back to life", READING.formatted("\"restring harp\"", "false"),
            "Teach my roommate a lesson he will not forget", READING.formatted("null", "true"),
            "Someone discreet for a small job in a bedroom", READING.formatted("\"hidden camera install\"", "false"),
            "Brighten up my kitchen ceiling", READING.formatted("\"install track lighting\"", "false"));

    @TestConfiguration static class ScriptedModel {
        @Bean @org.springframework.context.annotation.Primary IntentAdapter.Provider scriptedProvider() {
            return (text, now, zone, deadline) -> ANSWERS.get(text);
        }
    }

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    @Autowired RequestService service;
    @Autowired PlatformTransactionManager transactions;
    private final List<String> users = new ArrayList<>();

    @AfterEach void removeOnlyThisTestsRecords() {
        new TransactionTemplate(transactions).executeWithoutResult(ignored -> {
            for (String user : users) {
                jdbc.update("DELETE FROM asks WHERE user_id=?", user);
                jdbc.update("DELETE FROM request_idempotency WHERE user_id=?", user);
                jdbc.update("DELETE FROM requests WHERE user_id=?", user);
            }
            for (String user : users) jdbc.update("DELETE FROM provider_profiles WHERE user_id=?", user);
            for (String user : users) jdbc.update("DELETE FROM users WHERE id=?", user);
        });
    }

    JsonNode guest() throws Exception {
        JsonNode session = mapper.readTree(mvc.perform(post("/v1/auth/guest").with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .contentType(MediaType.APPLICATION_JSON).content("{\"consent_version\":\"2026-09-01\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString());
        users.add(session.at("/account/user_id").asText());
        return session;
    }
    ResultActions send(JsonNode who, String path, String body) throws Exception {
        return mvc.perform(post(path).with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .header("Authorization", "Bearer " + who.get("access_token").asText())
                .header("Idempotency-Key", "own-words-" + UUID.randomUUID())
                .contentType(MediaType.APPLICATION_JSON).content(body));
    }
    ResultActions ask(JsonNode who, String text) throws Exception {
        return send(who, "/v1/asks", "{\"text\":\"" + text + "\",\"location\":" + HERE + ",\"time_zone\":\"America/Chicago\"}");
    }
    JsonNode body(ResultActions result, String schema) throws Exception {
        JsonNode body = mapper.readTree(result.andReturn().getResponse().getContentAsString());
        ContractSchemas.validate(body.has("error") ? "Error" : schema, body);
        return body;
    }
    int asksOf(JsonNode who) {
        return jdbc.queryForObject("SELECT count(*) FROM asks WHERE user_id=?", Integer.class, who.at("/account/user_id").asText());
    }

    @Test void aServiceTheModelNamesIsRequestedInThoseWordsAndReachesProvidersWhoSayTheSame() throws Exception {
        var restringer = guest();
        send(restringer, "/v1/providers/skills", "{\"skill_tags\":[],\"custom_skills\":[\"harp restringing\"],"
                + "\"travel_radius_m\":8000,\"base_location\":" + HERE + ",\"availability\":[{\"days\":\"every_day\","
                + "\"from\":\"00:00\",\"to\":\"24:00\"}],\"time_zone\":\"America/Chicago\"}").andExpect(status().isOk());
        var asker = guest();
        var request = body(ask(asker, "Can someone bring my grandfather's harp back to life").andExpect(status().isCreated()),
                "AskResult").path("request");
        assertThat(request.at("/constraints/service_name").asText()).isEqualTo("Restring harp");
        assertThat(request.at("/constraints/category").asText()).startsWith("custom_");
        service.workOnce();
        assertThat(jdbc.queryForList("SELECT provider_id FROM request_matches WHERE request_id=?", String.class,
                request.path("request_id").asText())).contains(restringer.at("/account/user_id").asText());
    }

    @Test void whatTheModelJudgesHarmfulIsRefusedAndCreatesNothing() throws Exception {
        var person = guest();
        for (String text : List.of("Teach my roommate a lesson he will not forget", "Someone discreet for a small job in a bedroom")) {
            assertThat(body(ask(person, text).andExpect(status().isUnprocessableEntity()), "Error").at("/error/code").asText())
                    .isEqualTo("restricted_intent");
        }
        assertThat(asksOf(person)).isZero();
        assertThat(jdbc.queryForList("SELECT reason FROM audit_events WHERE actor_id=? AND action='request.restricted'",
                String.class, person.at("/account/user_id").asText()))
                .containsExactlyInAnyOrder("restricted_intent:model_flagged", "restricted_intent:stalking_tracking");
    }

    @Test void aLabelThatNamesAListedSkillKeepsItsLicenceRule() throws Exception {
        var request = body(ask(guest(), "Brighten up my kitchen ceiling").andExpect(status().isCreated()), "AskResult").path("request");
        assertThat(request.at("/constraints/category").asText()).isEqualTo("electrical");
        assertThat(request.at("/constraints/licence_required").asBoolean()).isTrue();
    }
}
