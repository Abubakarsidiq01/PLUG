package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ContractSchemas;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
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
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/// P3.S12: a decline is a reply and costs the provider nothing; silence is what lowers a response
/// score (manual v4 §12C.2, contract 0.7.1 declineMatch). A decline records its reason and time and
/// sets replied_at; a match past respond_by with no reply is expired and counted as silence.
@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.provider-inbox.enabled=true", "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(ProviderDeclineTest.TimeConfiguration.class)
class ProviderDeclineTest {
    static final Instant START = ReservationTest.START;
    static final ReservationTest.MutableClock CLOCK = new ReservationTest.MutableClock();
    static final String BASE = ProviderOfferTest.BASE;
    static final String NEAR = ProviderOfferTest.NEAR;

    @TestConfiguration static class TimeConfiguration {
        @Bean @Primary RequestClock mutableRequestClock() { return new RequestClock(CLOCK); }
    }

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    @Autowired RequestService service;
    @Autowired PlatformTransactionManager transactions;
    private final List<String> users = new ArrayList<>();

    @BeforeEach void resetClock() { CLOCK.now = START; }

    @AfterEach void removeOnlyThisTestsRecords() {
        new TransactionTemplate(transactions).executeWithoutResult(ignored -> {
            for (String user : users) {
                jdbc.update("DELETE FROM request_reservations WHERE request_id IN (SELECT id FROM requests WHERE user_id=?)", user);
                jdbc.update("DELETE FROM request_idempotency WHERE user_id=?", user);
                jdbc.update("DELETE FROM requests WHERE user_id=?", user);
            }
            for (String user : users) jdbc.update("DELETE FROM provider_profiles WHERE user_id=?", user);
            for (String user : users) jdbc.update("DELETE FROM users WHERE id=?", user);
        });
    }

    // ---- helpers -------------------------------------------------------------------------

    JsonNode guest() throws Exception {
        JsonNode session = mapper.readTree(mvc.perform(MockMvcRequestBuilders.post("/v1/auth/guest")
                .with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .contentType(MediaType.APPLICATION_JSON).content("{\"consent_version\":\"2026-09-01\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString());
        users.add(session.at("/account/user_id").asText());
        return session;
    }
    String userId(JsonNode session) { return session.at("/account/user_id").asText(); }
    ResultActions post(JsonNode who, String path, String body, String key) throws Exception {
        var request = MockMvcRequestBuilders.post(path).with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; });
        if (body != null) request.contentType(MediaType.APPLICATION_JSON).content(body);
        if (who != null) request.header("Authorization", "Bearer " + who.get("access_token").asText());
        if (key != null) request.header("Idempotency-Key", key);
        return mvc.perform(request);
    }
    JsonNode json(ResultActions result, String schema) throws Exception {
        JsonNode body = mapper.readTree(result.andReturn().getResponse().getContentAsString());
        ContractSchemas.validate(body.has("error") ? "Error" : schema, body);
        return body;
    }
    JsonNode errorOf(ResultActions result, int status) throws Exception {
        result.andExpect(status().is(status));
        return json(result, "Error").get("error");
    }
    void assertDetail(JsonNode error, String field, String code) {
        assertThat(error.at("/details/0/field").asText()).isEqualTo(field);
        assertThat(error.at("/details/0/code").asText()).isEqualTo(code);
    }
    String quote(String text) {
        try { return mapper.writeValueAsString(text); } catch (Exception e) { throw new RuntimeException(e); }
    }
    void provide(JsonNode who) throws Exception {
        post(who, "/v1/providers/skills", "{\"skill_tags\":[\"barber\"],\"travel_radius_m\":4828,\"base_location\":" + BASE
                + ",\"availability\":[{\"days\":\"every_day\",\"from\":\"09:00\",\"to\":\"24:00\"}],"
                + "\"time_zone\":\"America/Chicago\"}", null).andExpect(status().isOk());
    }
    String matchId(String requestId, JsonNode provider) {
        return jdbc.queryForObject("SELECT match_id FROM request_matches WHERE request_id=? AND provider_id=?", String.class,
                requestId, userId(provider));
    }
    ResultActions decline(JsonNode who, String matchId, String body) throws Exception {
        return post(who, "/v1/providers/me/inbox/" + matchId + "/decline", body, null);
    }
    JsonNode declineOk(JsonNode who, String matchId, String body) throws Exception {
        return json(decline(who, matchId, body).andExpect(status().isOk()), "InboxItem");
    }
    ResultActions offer(JsonNode who, String requestId) throws Exception {
        return post(who, "/v1/requests/" + requestId + "/offers", "{\"price_cents\":3000,\"currency\":\"USD\",\"available_at\":\""
                + START.plus(Duration.ofMinutes(20)) + "\"}", "decline-test-" + UUID.randomUUID());
    }
    Map<String, String> inboxStatuses(JsonNode provider) throws Exception {
        JsonNode inbox = json(mvc.perform(MockMvcRequestBuilders.get("/v1/providers/me/inbox")
                .with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .header("Authorization", "Bearer " + provider.get("access_token").asText())).andExpect(status().isOk()), "ProviderInbox");
        Map<String, String> seen = new java.util.HashMap<>();
        for (JsonNode item : inbox.get("items")) seen.put(item.path("match_id").asText(), item.path("status").asText());
        return seen;
    }
    Map<String, Object> matchRow(String matchId) {
        return jdbc.queryForMap("SELECT replied_at,declined_at,decline_reason FROM request_matches WHERE match_id=?", matchId);
    }

    /// A barber request worked until its two matched providers wait for replies.
    record Scene(JsonNode asker, String requestId, JsonNode provider, JsonNode second) {}
    Scene scene() throws Exception {
        var provider = guest();
        provide(provider);
        var second = guest();
        provide(second);
        var asker = guest();
        String id = json(post(asker, "/v1/requests", "{\"text\":\"Barber under $35 in 30 minutes\",\"location\":" + NEAR + "}",
                "decline-test-" + UUID.randomUUID()).andExpect(status().isCreated()), "RequestResource").path("request_id").asText();
        for (int n = 0; n < 3; n++) service.workOnce();
        assertThat(jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, id)).isEqualTo("awaiting_responses");
        return new Scene(asker, id, provider, second);
    }

    // ---- 1. a decline is a reply ---------------------------------------------------------

    @Test void aDeclineIsAReplyThatRecordsItsReasonAndTimeAndShowsAsDeclined() throws Exception {
        var s = scene();
        String match = matchId(s.requestId(), s.provider());
        CLOCK.now = START.plus(Duration.ofMinutes(2));
        JsonNode item = declineOk(s.provider(), match, "{\"reason\":\"busy\"}");
        assertThat(item.path("match_id").asText()).isEqualTo(match);
        assertThat(item.path("request_id").asText()).isEqualTo(s.requestId());
        assertThat(item.path("status").asText()).isEqualTo("declined");
        assertThat(item.has("offer")).isFalse();
        var row = matchRow(match);
        assertThat(((Timestamp) row.get("declined_at")).toInstant()).isEqualTo(CLOCK.now);
        assertThat(((Timestamp) row.get("replied_at")).toInstant()).isEqualTo(CLOCK.now);
        assertThat(row.get("decline_reason")).isEqualTo("busy");
        assertThat(inboxStatuses(s.provider())).containsEntry(match, "declined");
        // The other provider is untouched and still open.
        assertThat(inboxStatuses(s.second())).containsEntry(matchId(s.requestId(), s.second()), "open");
    }

    @Test void aDeclineNeedsNoBodyOrReasonAndEveryListedReasonIsAccepted() throws Exception {
        var s = scene();
        String first = matchId(s.requestId(), s.provider());
        assertThat(declineOk(s.provider(), first, null).path("status").asText()).isEqualTo("declined");
        assertThat(matchRow(first).get("decline_reason")).isNull();
        String second = matchId(s.requestId(), s.second());
        declineOk(s.second(), second, "{}");
        assertThat(matchRow(second).get("decline_reason")).isNull();
        for (String reason : List.of("too_far", "price", "not_my_skill", "other")) {
            // Earlier providers stop accepting, so matching's fan-out reaches the new ones.
            jdbc.update("UPDATE provider_profiles SET accepting=false WHERE user_id = ANY(?)", (Object) users.toArray(String[]::new));
            var t = scene();
            String m = matchId(t.requestId(), t.provider());
            declineOk(t.provider(), m, "{\"reason\":\"" + reason + "\"}");
            assertThat(matchRow(m).get("decline_reason")).isEqualTo(reason);
        }
    }

    @Test void declineAgainReturnsTheSameItemAndKeepsTheFirstReasonAndTime() throws Exception {
        var s = scene();
        String match = matchId(s.requestId(), s.provider());
        JsonNode first = declineOk(s.provider(), match, "{\"reason\":\"price\"}");
        CLOCK.now = START.plus(Duration.ofMinutes(1));
        JsonNode again = declineOk(s.provider(), match, "{\"reason\":\"busy\"}");
        assertThat(again).isEqualTo(first);
        var row = matchRow(match);
        assertThat(((Timestamp) row.get("declined_at")).toInstant()).isEqualTo(START);
        assertThat(row.get("decline_reason")).isEqualTo("price");
    }

    // ---- 2. a decline and an offer exclude each other ------------------------------------

    @Test void aDeclineAfterOfferingIsRequestClosed() throws Exception {
        var s = scene();
        offer(s.provider(), s.requestId()).andExpect(status().isCreated());
        String match = matchId(s.requestId(), s.provider());
        assertDetail(errorOf(decline(s.provider(), match, "{\"reason\":\"busy\"}"), 409), "match_id", "request_closed");
        assertThat(matchRow(match).get("declined_at")).isNull();
        assertThat(inboxStatuses(s.provider())).containsEntry(match, "offered");
    }

    @Test void anOfferAfterDecliningIsRequestClosed() throws Exception {
        var s = scene();
        declineOk(s.provider(), matchId(s.requestId(), s.provider()), "{\"reason\":\"busy\"}");
        assertDetail(errorOf(offer(s.provider(), s.requestId()), 409), "request_id", "request_closed");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM request_offers WHERE request_id=?", Integer.class, s.requestId())).isZero();
    }

    @Test void aDeclineOnACanceledOrExpiredRequestIsRequestClosed() throws Exception {
        var s = scene();
        post(s.asker(), "/v1/requests/" + s.requestId() + "/cancel", "", null).andExpect(status().isOk());
        assertDetail(errorOf(decline(s.provider(), matchId(s.requestId(), s.provider()), null), 409), "match_id", "request_closed");
        var t = scene();
        CLOCK.now = START.plus(Duration.ofMinutes(31));
        String match = matchId(t.requestId(), t.provider());
        assertDetail(errorOf(decline(t.provider(), match, null), 409), "match_id", "request_closed");
        assertThat(matchRow(match).get("declined_at")).isNull();
    }

    // ---- 3. who may decline and what they may send ---------------------------------------

    @Test void anotherProvidersMatchAMissingOrMalformedMatchIsNotFoundAndNoSessionIsUnauthenticated() throws Exception {
        var s = scene();
        String match = matchId(s.requestId(), s.provider());
        errorOf(decline(s.second(), match, null), 404);
        errorOf(decline(s.asker(), match, null), 404);
        errorOf(decline(s.provider(), "mat_" + UUID.randomUUID(), null), 404);
        errorOf(decline(s.provider(), "not-a-match", null), 404);
        errorOf(decline(s.provider(), "mat_" + "x".repeat(70), null), 404);
        decline(null, match, null).andExpect(status().isUnauthorized());
        assertThat(matchRow(match).get("declined_at")).isNull();
    }

    @Test void aBodyThatIsNotAMatchDeclineIsAValidationFailure() throws Exception {
        var s = scene();
        String match = matchId(s.requestId(), s.provider());
        assertDetail(errorOf(decline(s.provider(), match, "{\"reason\":\"tired\"}"), 400), "reason", "invalid");
        assertDetail(errorOf(decline(s.provider(), match, "{\"reason\":\"BUSY\"}"), 400), "reason", "invalid");
        assertDetail(errorOf(decline(s.provider(), match, "{\"reason\":1}"), 400), "reason", "invalid");
        assertDetail(errorOf(decline(s.provider(), match, "{\"reason\":null}"), 400), "reason", "invalid");
        errorOf(decline(s.provider(), match, "{\"reason\":\"busy\",\"note\":\"no\"}"), 400);
        errorOf(decline(s.provider(), match, "[\"busy\"]"), 400);
        errorOf(decline(s.provider(), match, "\"busy\""), 400);
        assertThat(matchRow(match).get("declined_at")).isNull();
    }

    @Test void theThirtyFirstDeclineInAWindowIsRateLimitedWithRetryAfter() throws Exception {
        var provider = guest();
        provide(provider);
        for (int n = 0; n < 30; n++) errorOf(decline(provider, "mat_" + UUID.randomUUID(), null), 404);
        var result = decline(provider, "mat_" + UUID.randomUUID(), null);
        result.andExpect(status().isTooManyRequests()).andExpect(header().exists("Retry-After"));
        assertThat(json(result, "Error").at("/error/code").asText()).isEqualTo("rate_limited");
    }

    // ---- 4. silence, not a decline, is what counts against a provider --------------------

    @Test void silencePastRespondByIsExpiredAndCountedWhileADeclineIsAnAnswerNeverSilence() throws Exception {
        var s = scene();
        String declined = matchId(s.requestId(), s.provider());
        String silent = matchId(s.requestId(), s.second());
        declineOk(s.provider(), declined, "{\"reason\":\"too_far\"}");
        // Inside the reply window the silent provider is still open and not yet silent.
        CLOCK.now = START.plus(Duration.ofMinutes(4));
        assertThat(inboxStatuses(s.second())).containsEntry(silent, "open");
        assertThat(service.responsiveness(userId(s.second()))).isEqualTo(new RequestService.Responsiveness(0, 0));
        // respond_by passed with no reply: expired, and recorded as silence.
        CLOCK.now = START.plus(Duration.ofMinutes(5));
        assertThat(inboxStatuses(s.second())).containsEntry(silent, "expired");
        assertThat(service.responsiveness(userId(s.second()))).isEqualTo(new RequestService.Responsiveness(0, 1));
        // The decline stays a reply, never silence, however late it is read.
        assertThat(inboxStatuses(s.provider())).containsEntry(declined, "declined");
        assertThat(service.responsiveness(userId(s.provider()))).isEqualTo(new RequestService.Responsiveness(1, 0));
        // After the request itself expires (its deadline, well past respond_by) both stay as they were.
        CLOCK.now = START.plus(Duration.ofMinutes(31));
        service.workOnce();
        assertThat(jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, s.requestId())).isEqualTo("expired");
        assertThat(inboxStatuses(s.second())).containsEntry(silent, "expired");
        assertThat(inboxStatuses(s.provider())).containsEntry(declined, "declined");
        assertThat(service.responsiveness(userId(s.second()))).isEqualTo(new RequestService.Responsiveness(0, 1));
        assertThat(service.responsiveness(userId(s.provider()))).isEqualTo(new RequestService.Responsiveness(1, 0));
    }

    @Test void anOfferIsAnAnswerAndARequestCanceledInsideTheWindowIsNeitherAnswerNorSilence() throws Exception {
        var s = scene();
        offer(s.provider(), s.requestId()).andExpect(status().isCreated());
        CLOCK.now = START.plus(Duration.ofMinutes(2));
        post(s.asker(), "/v1/requests/" + s.requestId() + "/cancel", "", null).andExpect(status().isOk());
        CLOCK.now = START.plus(Duration.ofMinutes(10));
        assertThat(service.responsiveness(userId(s.provider()))).isEqualTo(new RequestService.Responsiveness(1, 0));
        assertThat(inboxStatuses(s.second())).containsEntry(matchId(s.requestId(), s.second()), "closed");
        assertThat(service.responsiveness(userId(s.second()))).isEqualTo(new RequestService.Responsiveness(0, 0));
    }

    @Test void declinesNeverLowerResponsivenessAndOnlySilenceDoes() throws Exception {
        var provider = guest();
        provide(provider);
        var second = guest();
        provide(second);
        var asker = guest();
        String me = userId(provider);
        // Three requests the provider declines and one they ignore.
        List<String> ids = new ArrayList<>();
        for (int n = 0; n < 4; n++) {
            ids.add(json(post(asker, "/v1/requests", "{\"text\":\"Barber under $35 in 30 minutes\",\"location\":" + NEAR + "}",
                    "decline-test-" + UUID.randomUUID()).andExpect(status().isCreated()), "RequestResource").path("request_id").asText());
        }
        for (int n = 0; n < 3; n++) service.workOnce();
        for (int n = 0; n < 3; n++) {
            declineOk(provider, jdbc.queryForObject("SELECT match_id FROM request_matches WHERE request_id=? AND provider_id=?",
                    String.class, ids.get(n), me), "{\"reason\":\"busy\"}");
        }
        CLOCK.now = START.plus(Duration.ofMinutes(6));
        assertThat(service.responsiveness(me)).isEqualTo(new RequestService.Responsiveness(3, 1));
    }
}
