package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.UUID;
import java.util.concurrent.Executors;
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

@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(RequestV2Test.TimeConfiguration.class)
class RequestV2Test {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    @Autowired RequestService service;
    @Autowired org.springframework.transaction.PlatformTransactionManager transactions;
    private final java.util.List<String> users = new java.util.ArrayList<>();

    /// The worker takes the 20 least recently updated active requests a pass. Requests left by
    /// one test here could fill that batch in a later one and leave its request untouched, which
    /// failed seededFlowPersistsHonestProgressOffersAndReplay intermittently.
    @org.junit.jupiter.api.AfterEach void removeOnlyThisTestsRecords() {
        new org.springframework.transaction.support.TransactionTemplate(transactions).executeWithoutResult(ignored -> {
            for (String user : users) {
                jdbc.update("DELETE FROM asks WHERE user_id=?", user);
                jdbc.update("DELETE FROM request_idempotency WHERE user_id=?", user);
                jdbc.update("DELETE FROM requests WHERE user_id=?", user);
            }
            for (String user : users) jdbc.update("DELETE FROM users WHERE id=?", user);
        });
    }
    static final String BODY = """
            {"text":"Barber under $35 in 30 minutes","location":{"latitude":32.528,"longitude":-92.714,"precision":"coarse"}}
            """;
    @TestConfiguration static class TimeConfiguration {
        @Bean @Primary RequestClock fixedRequestClock() {
            return new RequestClock(Clock.fixed(Instant.parse("2026-10-01T20:00:00Z"), ZoneOffset.UTC));
        }
    }
    JsonNode guest() throws Exception {
        JsonNode session = json(mvc.perform(post("/v1/auth/guest").with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .contentType(MediaType.APPLICATION_JSON).content("{\"consent_version\":\"2026-09-01\"}"))
                .andExpect(status().isCreated()));
        users.add(session.at("/account/user_id").asText());
        return session;
    }
    ResultActions create(JsonNode guest, String body, String key) throws Exception {
        return mvc.perform(post("/v1/requests").with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .header("Authorization", "Bearer " + guest.get("access_token").asText())
                .header("Idempotency-Key", "phase2-test-key-" + key).contentType(MediaType.APPLICATION_JSON).content(body));
    }
    JsonNode json(ResultActions result) throws Exception {
        JsonNode body = mapper.readTree(result.andReturn().getResponse().getContentAsString());
        String schema = body.has("error") ? "Error" : body.has("offers") ? "OfferList"
                : body.has("request_id") ? "RequestResource" : "Session";
        app.plug.foundation.ContractSchemas.validate(schema, body);
        return body;
    }
    ResultActions read(JsonNode guest, String path) throws Exception {
        return mvc.perform(get(path).header("Authorization", "Bearer " + guest.get("access_token").asText()));
    }
    ResultActions mutate(JsonNode guest, String path, String body, String key) throws Exception {
        return mvc.perform(post(path).header("Authorization", "Bearer " + guest.get("access_token").asText())
                .header("Idempotency-Key", "phase2-test-key-" + key).contentType(MediaType.APPLICATION_JSON).content(body));
    }
    @Test void seededFlowPersistsHonestProgressOffersAndReplay() throws Exception {
        var owner = guest();
        var created = json(create(owner, BODY, "first").andExpect(status().isCreated()));
        assertThat(created.path("status").asText()).isEqualTo("submitted");
        String id = created.path("request_id").asText();
        assertThat(created.at("/progress/contacted").asInt()).isZero();
        service.workOnce();
        var routed = json(read(owner, "/v1/requests/" + id).andExpect(status().isOk()));
        assertThat(routed.path("status").asText()).isEqualTo("routed");
        assertThat(routed.at("/progress/contacted").asInt()).isEqualTo(2);
        for (int n = 0; n < 4; n++) service.workOnce();
        var ranked = json(read(owner, "/v1/requests/" + id).andExpect(status().isOk()));
        assertThat(ranked.path("status").asText()).isEqualTo("ranked");
        assertThat(ranked.at("/progress/offers_ready").asInt()).isEqualTo(2);
        var offers = json(read(owner, "/v1/requests/" + id + "/offers").andExpect(status().isOk()));
        assertThat(offers.path("offers").size()).isEqualTo(2);
        for (var offer : offers.path("offers")) {
            assertThat(offer.path("source").asText()).isEqualTo("seed");
            assertThat(offer.path("truth_label").asText()).isEqualTo("estimated");
            assertThat(offer.path("price_cents").asInt()).isBetween(500,3500);
        }
        assertThat(json(create(owner, BODY, "first").andExpect(status().isCreated()))).isEqualTo(created);
        create(owner, BODY.replace("$35", "$40"), "first").andExpect(status().isConflict());
        read(guest(), "/v1/requests/" + id).andExpect(status().isNotFound());
    }
    @Test void oneQuestionCancelAndEveryOwnershipBoundary() throws Exception {
        var owner = guest(); var other = guest();
        var draft = json(create(owner, BODY.replace("Barber under $35 in 30 minutes", "Something nearby"), "draft")
                .andExpect(status().isCreated()));
        String path = "/v1/requests/" + draft.path("request_id").asText();
        String answer = "{\"clarification_id\":\"" + draft.at("/clarification/clarification_id").asText() + "\",\"value\":\"barber\"}";
        read(other, path + "/offers").andExpect(status().isNotFound());
        mutate(other,path + "/cancel", "", "c").andExpect(status().isNotFound());
        mutate(other,path + "/clarifications",answer,"a").andExpect(status().isNotFound());
        mutate(owner,path + "/clarifications",answer.replace("barber", "astronaut"),"bad").andExpect(status().isBadRequest());
        var submitted = json(mutate(owner,path + "/clarifications",answer,"answer").andExpect(status().isOk()));
        assertThat(submitted.path("status").asText()).isEqualTo("submitted");
        assertThat(submitted.has("clarification")).isFalse();
        assertThat(json(mutate(owner,path + "/clarifications",answer,"answer").andExpect(status().isOk()))).isEqualTo(submitted);
        mutate(owner,path + "/clarifications",answer,"different").andExpect(status().isConflict());
        var canceled = json(mutate(owner,path + "/cancel","","c").andExpect(status().isOk()));
        service.workOnce();
        assertThat(json(mutate(owner,path + "/cancel","","c").andExpect(status().isOk()))).isEqualTo(canceled);
        assertThat(json(read(owner,path + "/offers").andExpect(status().isOk())).path("offers")).isEmpty();
    }
    @Test void restrictedAuditedWithoutRequestAndOpenServiceEndsHonestly() throws Exception {
        var owner = guest();
        int before = jdbc.queryForObject("SELECT count(*) FROM requests", Integer.class);
        create(owner,BODY.replace("Barber under $35 in 30 minutes", "Sell me stolen credit card numbers"),"bad")
                .andExpect(status().isUnprocessableEntity());
        assertThat(jdbc.queryForObject("SELECT count(*) FROM requests", Integer.class)).isEqualTo(before);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM audit_events WHERE action='request.restricted'", Integer.class)).isPositive();
        // ADR-009: any lawful service is accepted; with no participating supplier it ends no_coverage.
        var plumber = json(create(owner,BODY.replace("Barber under $35 in 30 minutes", "Find a plumber"),"open")
                .andExpect(status().isCreated()));
        assertThat(plumber.at("/constraints/category").asText()).isEqualTo("plumbing_minor");
        assertThat(plumber.at("/constraints/service_name").asText()).isEqualTo("Minor plumbing");
        assertThat(plumber.at("/constraints/skill_tags/0").asText()).isEqualTo("plumbing_minor");
        for (int i = 0; i < 3; i++) service.workOnce();
        var ended = json(read(owner, "/v1/requests/" + plumber.path("request_id").asText()));
        assertThat(ended.path("status").asText()).isEqualTo("expired");
        assertThat(ended.path("no_result_reason").asText()).isEqualTo("no_coverage");
        assertThat(json(read(owner, "/v1/requests/" + plumber.path("request_id").asText() + "/offers")).path("offers")).isEmpty();
        mvc.perform(post("/v1/requests").contentType(MediaType.APPLICATION_JSON).content(BODY)).andExpect(status().isUnauthorized());
    }
    @Test void concurrentCreatesAndWorkerCancelShareLocks() throws Exception {
        var owner = guest();
        try (var pool = Executors.newFixedThreadPool(4)) {
            var first = pool.submit(() -> json(create(owner,BODY,"same").andExpect(status().isCreated())));
            var second = pool.submit(() -> json(create(owner,BODY,"same").andExpect(status().isCreated())));
            var created = first.get();
            assertThat(second.get()).isEqualTo(created);
            String path = "/v1/requests/" + created.path("request_id").asText();
            var worker = pool.submit(() -> { for (int i=0;i<5;i++) service.workOnce(); });
            var cancel = pool.submit(() -> json(mutate(owner,path + "/cancel","","c").andExpect(status().isOk())));
            worker.get(); cancel.get();
            assertThat(json(read(owner,path).andExpect(status().isOk())).path("status").asText()).isEqualTo("canceled");
        }
    }
    @Test void noCoverageNoBudgetMatchAndDraftExpiryAreHonest() throws Exception {
        var owner = guest();
        var far = json(create(owner,BODY.replace("32.528", "0.0"),"far").andExpect(status().isCreated()));
        var cheap = json(create(owner,BODY.replace("$35", "$5"),"cheap").andExpect(status().isCreated()));
        var draft = json(create(owner,BODY.replace("Barber under $35 in 30 minutes", "Something"),"expire").andExpect(status().isCreated()));
        jdbc.update("UPDATE requests SET created_at=created_at-interval '2 hour',expires_at=expires_at-interval '1 hour' WHERE id=?",draft.path("request_id").asText());
        for(int i=0;i<5;i++) service.workOnce();
        assertThat(json(read(owner,"/v1/requests/"+far.path("request_id").asText())).path("no_result_reason").asText()).isEqualTo("no_coverage");
        assertThat(json(read(owner,"/v1/requests/"+cheap.path("request_id").asText())).path("no_result_reason").asText()).isEqualTo("no_offers");
        var expired = json(read(owner,"/v1/requests/"+draft.path("request_id").asText()));
        assertThat(expired.path("no_result_reason").asText()).isEqualTo("clarification_unanswered");
        assertThat(expired.at("/constraints/category").isNull()).isTrue();
    }
    @Test void labelledDatasetRunsAgainstRealController() throws Exception {
        for (String line : java.nio.file.Files.readAllLines(java.nio.file.Path.of("../fixtures/intents/p2.jsonl"))) {
            var entry = mapper.readTree(line);
            var expected = entry.path("expected");
            var response = create(guest(),entry.path("input").toString(),entry.path("id").asText());
            int expectedStatus = expected.path("outcome").asText().equals("rejected") ? expected.path("status").asInt() : 201;
            assertThat(response.andReturn().getResponse().getStatus()).as(entry.path("id").asText()
                    + " " + response.andReturn().getResponse().getContentAsString()).isEqualTo(expectedStatus);
            if (expectedStatus == 201) {
                var result = json(response);
                assertThat(result.path("status").asText()).isEqualTo(expected.path("outcome").asText());
                for (String field : ListHolder.CONSTRAINT_FIELDS) if (expected.has(field)) {
                    assertThat(result.path("constraints").path(field)).as(entry.path("id").asText()+field).isEqualTo(expected.path(field));
                }
            }
        }
    }
    @Test void strictWireTypesHeadersCodepointsConsentAndExpiry() throws Exception {
        var owner=guest();
        for(String extension:new String[]{"\"needed_by\":1790886600", "\"category\":null", "\"budget_cents\":3500.5,\"currency\":\"USD\"",
                "\"budget_cents\":\"3500\",\"currency\":\"USD\"", "\"category\":42"}) {
            create(owner,BODY.strip().replaceFirst("\\{", "{"+extension+","),"invalid-"+UUID.randomUUID()).andExpect(status().isBadRequest());
        }
        mvc.perform(post("/v1/requests").header("Authorization","Bearer "+owner.path("access_token").asText())
                .contentType(MediaType.APPLICATION_JSON).content(BODY)).andExpect(status().isBadRequest());
        String unicode="Barber "+"😀".repeat(493);
        var valid=json(create(owner,BODY.replace("Barber under $35 in 30 minutes",unicode),"unicode").andExpect(status().isCreated()));
        create(owner,BODY.replace("Barber under $35 in 30 minutes",unicode+"😀"),"too-long").andExpect(status().isBadRequest());
        String id=valid.path("request_id").asText();
        for(int n=0;n<5;n++) service.workOnce();
        jdbc.update("UPDATE request_offers SET available_at=?,expires_at=?,observed_at=? WHERE request_id=?",
                java.sql.Timestamp.from(Instant.parse("2026-10-01T18:00:00Z")),
                java.sql.Timestamp.from(Instant.parse("2026-10-01T19:00:00Z")),
                java.sql.Timestamp.from(Instant.parse("2026-10-01T17:00:00Z")),id);
        var expired=json(read(owner,"/v1/requests/"+id));
        assertThat(expired.path("status").asText()).isEqualTo("expired");
        assertThat(json(read(owner,"/v1/requests/"+id+"/offers")).path("offers")).isEmpty();
        mutate(owner,"/v1/requests/"+id+"/cancel","","expired").andExpect(status().isConflict());
        String user=jdbc.queryForObject("SELECT user_id FROM requests WHERE id=?",String.class,id);
        jdbc.update("DELETE FROM consents WHERE user_id=?",user);
        var denied=json(create(owner,BODY,"consent").andExpect(status().isForbidden()));
        assertThat(denied.at("/error/details/0/code").asText()).isEqualTo("consent_required");
        assertThat(denied.at("/error/details/0/field").asText()).isEqualTo("consent");
    }
    private static class ListHolder { static final String[] CONSTRAINT_FIELDS = {"category","budget_cents","needed_by"}; }
}
