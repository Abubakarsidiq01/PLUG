package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ContractSchemas;
import app.plug.security.PlugPrincipal;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
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
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/// P3.S13 trust score v1 and P3.S14 New and standing (manual v4 §12C.2, §12C.3, §19A.5; contract
/// 0.7.0 ProviderScore, ProviderScoreBreakdown, ProviderStanding, listProviders, setProviderStanding).
/// Owner rules 2026-11-17: completion is completed / confirmed bookings (asker cancels excluded, at
/// least 3), responsiveness is answered / (answered + silent) (at least 5), reliability is null,
/// standing is 100 or 0; the value is their weighted mean (25, 15, 10, 10) over the non-null ones.
@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.provider-inbox.enabled=true", "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(TrustScoreTest.TimeConfiguration.class)
class TrustScoreTest {
    static final Instant START = ReservationTest.START;
    static final ReservationTest.MutableClock CLOCK = new ReservationTest.MutableClock();
    static final String BASE = ProviderOfferTest.BASE;
    static final String NEAR = ProviderOfferTest.NEAR;
    static final String ASK = "{\"text\":\"Barber under $35 in 30 minutes\",\"location\":" + NEAR + "}";

    @TestConfiguration static class TimeConfiguration {
        @Bean @Primary RequestClock mutableRequestClock() { return new RequestClock(CLOCK); }
    }

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    @Autowired RequestService service;
    @Autowired PlatformTransactionManager transactions;
    private final List<String> users = new ArrayList<>();
    private final List<String> staff = new ArrayList<>();

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
            for (String user : staff) jdbc.update("DELETE FROM users WHERE id=?", user);
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
    MockHttpServletRequestBuilder signed(JsonNode who, MockHttpServletRequestBuilder request) {
        request.with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; });
        if (who != null) request.header("Authorization", "Bearer " + who.get("access_token").asText());
        return request;
    }
    ResultActions post(JsonNode who, String path, String body, String key) throws Exception {
        var request = signed(who, MockMvcRequestBuilders.post(path));
        if (body != null) request.contentType(MediaType.APPLICATION_JSON).content(body);
        if (key != null) request.header("Idempotency-Key", key);
        return mvc.perform(request);
    }
    ResultActions get(JsonNode who, String path) throws Exception { return mvc.perform(signed(who, MockMvcRequestBuilders.get(path))); }
    JsonNode json(ResultActions result, String schema) throws Exception {
        JsonNode body = mapper.readTree(result.andReturn().getResponse().getContentAsString());
        ContractSchemas.validate(body.has("error") ? "Error" : schema, body);
        return body;
    }
    JsonNode errorOf(ResultActions result, int status) throws Exception {
        result.andExpect(status().is(status));
        return json(result, "Error").get("error");
    }
    String key() { return "trust-test-" + UUID.randomUUID(); }
    void provide(JsonNode who) throws Exception {
        post(who, "/v1/providers/skills", "{\"skill_tags\":[\"barber\"],\"travel_radius_m\":4828,\"base_location\":" + BASE
                + ",\"availability\":[{\"days\":\"every_day\",\"from\":\"00:00\",\"to\":\"24:00\"}],"
                + "\"time_zone\":\"America/Chicago\",\"business\":{\"name\":\"Fresh Line Studio\"}}", null).andExpect(status().isOk());
    }
    String requestStatus(String id) { return jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, id); }
    String matchId(String requestId, JsonNode provider) {
        var ids = jdbc.queryForList("SELECT match_id FROM request_matches WHERE request_id=? AND provider_id=?", String.class,
                requestId, userId(provider));
        return ids.isEmpty() ? null : ids.getFirst();
    }
    record Ask(JsonNode asker, String id) {}
    /// A fresh asker's barber request, worked until its matched providers wait for replies.
    Ask ask() throws Exception {
        var asker = guest();
        String id = json(post(asker, "/v1/requests", ASK, key()).andExpect(status().isCreated()), "RequestResource")
                .path("request_id").asText();
        for (int n = 0; n < 3; n++) service.workOnce();
        assertThat(requestStatus(id)).isEqualTo("awaiting_responses");
        return new Ask(asker, id);
    }
    ResultActions sendOffer(JsonNode provider, String requestId) throws Exception {
        return post(provider, "/v1/requests/" + requestId + "/offers", "{\"price_cents\":3000,\"currency\":\"USD\",\"available_at\":\""
                + CLOCK.now.plus(Duration.ofMinutes(20)) + "\"}", key());
    }
    String offerOk(JsonNode provider, String requestId) throws Exception {
        return json(sendOffer(provider, requestId).andExpect(status().isCreated()), "Offer").path("offer_id").asText();
    }
    ResultActions answer(JsonNode provider, String matchId, String decision) throws Exception {
        return post(provider, "/v1/providers/me/inbox/" + matchId + "/reservation", "{\"decision\":\"" + decision + "\"}", null);
    }
    /// Offer, choose, confirm: a confirmed booking, not yet completed.
    Ask confirmedBooking(JsonNode provider) throws Exception {
        Ask a = ask();
        String offer = offerOk(provider, a.id());
        service.workOnce();
        assertThat(requestStatus(a.id())).isEqualTo("ranked");
        post(a.asker(), "/v1/requests/" + a.id() + "/select", "{\"offer_id\":\"" + offer + "\"}", key()).andExpect(status().isOk());
        answer(provider, matchId(a.id(), provider), "confirm").andExpect(status().isOk());
        assertThat(requestStatus(a.id())).isEqualTo("confirmed");
        return a;
    }
    /// A booking worked through to completed: three hours after its slot, the worker completes it.
    void completeJob(JsonNode provider) throws Exception {
        Ask a = confirmedBooking(provider);
        CLOCK.now = CLOCK.now.plus(Duration.ofMinutes(20)).plus(Duration.ofHours(3));
        service.workOnce();
        assertThat(requestStatus(a.id())).isEqualTo("completed");
        // Past the hourly notification cap before the next request.
        CLOCK.now = CLOCK.now.plus(Duration.ofMinutes(61));
    }
    /// A match the provider never answers, past respond_by, seen by the worker.
    void silentMatch(JsonNode provider) throws Exception {
        Ask a = ask();
        assertThat(matchId(a.id(), provider)).isNotNull();
        CLOCK.now = CLOCK.now.plus(Duration.ofMinutes(6));
        service.workOnce();
        CLOCK.now = CLOCK.now.plus(Duration.ofMinutes(61));
    }
    JsonNode me(JsonNode provider) throws Exception {
        return json(get(provider, "/v1/providers/me").andExpect(status().isOk()), "ProviderProfile");
    }
    void assertComponent(JsonNode breakdown, String name, Integer value, int basis) {
        JsonNode component = breakdown.get(name);
        assertThat(component.has("value")).as(name + " always carries value").isTrue();
        if (value == null) assertThat(component.get("value").isNull()).as(name).isTrue();
        else assertThat(component.get("value").asInt()).as(name).isEqualTo(value);
        assertThat(component.get("basis").asInt()).as(name + " basis").isEqualTo(basis);
    }
    List<String> causes(JsonNode provider) {
        return jdbc.queryForList("SELECT cause FROM score_history WHERE provider_id=? ORDER BY id", String.class, userId(provider));
    }
    Integer storedTrust(JsonNode provider) {
        return jdbc.queryForObject("SELECT trust_score FROM provider_scores WHERE user_id=?", Integer.class, userId(provider));
    }

    // Staff: a users row of type staff and its staff account, as an invitation would leave them.
    PlugPrincipal staffMember(String role, boolean secondFactor) {
        String id = "usr_staff-" + UUID.randomUUID();
        jdbc.update("INSERT INTO users(id,account_type) VALUES(?,'staff')", id);
        jdbc.update("INSERT INTO staff_accounts(user_id,email,password_hash,role) VALUES(?,?,'not-a-real-hash',?)", id,
                id.substring(4, 24).toLowerCase() + "@example.com", role);
        staff.add(id);
        return new PlugPrincipal(id, "ses_staff", Set.of(PlugPrincipal.SCOPE_ADMIN), secondFactor);
    }
    ResultActions asStaff(PlugPrincipal principal, MockHttpServletRequestBuilder request) throws Exception {
        return mvc.perform(request.with(authentication(new UsernamePasswordAuthenticationToken(principal, null, List.of()))));
    }
    ResultActions standing(PlugPrincipal owner, String userId, String body) throws Exception {
        return asStaff(owner, MockMvcRequestBuilders.post("/v1/admin/providers/" + userId + "/standing")
                .contentType(MediaType.APPLICATION_JSON).content(body));
    }
    JsonNode suspend(PlugPrincipal owner, JsonNode provider, String to) throws Exception {
        return json(standing(owner, userId(provider), "{\"standing\":\"" + to + "\",\"reason\":\"Asked a customer to pay outside PLUG.\"}")
                .andExpect(status().isOk()).andExpect(header().string("Cache-Control", "no-store")), "AdminProvider");
    }

    // ---- 1. New is a state, never a zero; scored from the third completed job ------------

    @Test void underThreeCompletedJobsIsNewWithNoValueAndTheThirdScoresTheWeightedValue() throws Exception {
        var provider = guest();
        provide(provider);
        JsonNode fresh = me(provider);
        // Reads are stable: the same profile twice, whatever the clock says in between.
        CLOCK.now = CLOCK.now.plusSeconds(30);
        assertThat(me(provider)).isEqualTo(fresh);
        assertThat(fresh.at("/score_breakdown/updated_at").asText()).isEqualTo(fresh.path("created_at").asText());
        assertThat(fresh.path("standing").asText()).isEqualTo("active");
        assertThat(fresh.path("score").path("state").asText()).isEqualTo("new");
        assertThat(fresh.path("score").has("value")).isFalse();
        JsonNode breakdown = fresh.path("score_breakdown");
        assertThat(breakdown.path("version").asText()).isEqualTo("v1");
        assertComponent(breakdown, "completion", null, 0);
        assertComponent(breakdown, "reliability", null, 0);
        assertComponent(breakdown, "responsiveness", null, 0);
        assertComponent(breakdown, "standing", 100, 0);
        assertThat(breakdown.has("customer_rating") && breakdown.get("customer_rating").isNull()).isTrue();

        completeJob(provider);
        completeJob(provider);
        JsonNode two = me(provider);
        assertThat(two.path("score").path("state").asText()).isEqualTo("new");
        assertThat(two.path("score").path("completed_jobs").asInt()).isEqualTo(2);
        assertThat(two.path("score").has("value")).isFalse();
        assertComponent(two.path("score_breakdown"), "completion", null, 2);
        assertComponent(two.path("score_breakdown"), "responsiveness", null, 2);
        assertThat(storedTrust(provider)).as("New is stored as no value, never 0").isNull();

        completeJob(provider);
        JsonNode three = me(provider);
        assertThat(three.path("score").path("state").asText()).isEqualTo("scored");
        assertThat(three.path("score").path("completed_jobs").asInt()).isEqualTo(3);
        // completion 100 (25) and standing 100 (10); responsiveness has 3 of the 5 matches it needs.
        assertThat(three.path("score").path("value").asInt()).isEqualTo(100);
        assertComponent(three.path("score_breakdown"), "completion", 100, 3);
        assertComponent(three.path("score_breakdown"), "reliability", null, 0);
        assertComponent(three.path("score_breakdown"), "responsiveness", null, 3);
        assertThat(storedTrust(provider)).isEqualTo(100);

        // Two silent matches: 3 answered of 5 is 60, so (25*100 + 10*60 + 10*100) / 45 = 91.
        silentMatch(provider);
        silentMatch(provider);
        JsonNode scored = me(provider);
        assertComponent(scored.path("score_breakdown"), "responsiveness", 60, 5);
        assertThat(scored.path("score").path("value").asInt()).isEqualTo(91);
        assertThat(storedTrust(provider)).isEqualTo(91);
        assertThat(jdbc.queryForObject("SELECT response_rate FROM provider_scores WHERE user_id=?", Double.class, userId(provider)))
                .isEqualTo(0.6);
        assertThat(causes(provider)).contains("offer_sent", "reservation_confirmed", "job_completed", "silence_detected")
                .doesNotContain("standing_changed");
        // Every row records the change it made and why.
        assertThat(jdbc.queryForObject("SELECT new_value FROM score_history WHERE provider_id=? ORDER BY id DESC LIMIT 1",
                Integer.class, userId(provider))).isEqualTo(91);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM score_history WHERE provider_id=? AND components->'responsiveness'->>'value'='60'",
                Integer.class, userId(provider))).isEqualTo(1);
    }

    @Test void offersCarryTheProvidersScoreNewThenScored() throws Exception {
        var provider = guest();
        provide(provider);
        Ask first = ask();
        offerOk(provider, first.id());
        service.workOnce();
        JsonNode listed = json(get(first.asker(), "/v1/requests/" + first.id() + "/offers").andExpect(status().isOk()), "OfferList");
        JsonNode newScore = listed.at("/offers/0/provider_score");
        assertThat(newScore.path("state").asText()).isEqualTo("new");
        assertThat(newScore.has("value")).isFalse();
        CLOCK.now = CLOCK.now.plus(Duration.ofMinutes(61));
        for (int n = 0; n < 3; n++) completeJob(provider);
        Ask later = ask();
        JsonNode offer = json(sendOffer(provider, later.id()).andExpect(status().isCreated()), "Offer");
        // 3 completed of 3 confirmed; 5 offers of 5 matches answered: 100 everywhere.
        assertThat(offer.path("provider_score").path("state").asText()).isEqualTo("scored");
        assertThat(offer.path("provider_score").path("value").asInt()).isEqualTo(100);
        assertThat(offer.path("provider_score").path("completed_jobs").asInt()).isEqualTo(3);
    }

    // ---- 2. completion: asker cancellations are not the provider's failure ---------------

    @Test void anAskerCancellingAConfirmedBookingDoesNotLowerCompletion() throws Exception {
        var provider = guest();
        provide(provider);
        for (int n = 0; n < 3; n++) completeJob(provider);
        Ask booked = confirmedBooking(provider);
        // Owner rule: the open booking counts once confirmed, so 3 completed of 4 confirmed is 75.
        assertComponent(me(provider).path("score_breakdown"), "completion", 75, 4);
        post(booked.asker(), "/v1/requests/" + booked.id() + "/cancel", "", null).andExpect(status().isOk());
        JsonNode after = me(provider);
        assertComponent(after.path("score_breakdown"), "completion", 100, 3);
        assertThat(after.path("score").path("value").asInt()).isEqualTo(100);
        assertThat(causes(provider)).contains("reservation_canceled");
    }

    @Test void aReleaseOrTimeoutBeforeConfirmingIsNotABooking() throws Exception {
        var provider = guest();
        provide(provider);
        Ask released = ask();
        String offer = offerOk(provider, released.id());
        service.workOnce();
        post(released.asker(), "/v1/requests/" + released.id() + "/select", "{\"offer_id\":\"" + offer + "\"}", key())
                .andExpect(status().isOk());
        answer(provider, matchId(released.id(), provider), "release").andExpect(status().isOk());
        CLOCK.now = CLOCK.now.plus(Duration.ofMinutes(61));
        Ask timedOut = ask();
        String second = offerOk(provider, timedOut.id());
        service.workOnce();
        post(timedOut.asker(), "/v1/requests/" + timedOut.id() + "/select", "{\"offer_id\":\"" + second + "\"}", key())
                .andExpect(status().isOk());
        CLOCK.now = CLOCK.now.plus(Duration.ofMinutes(21));
        service.workOnce();
        assertComponent(me(provider).path("score_breakdown"), "completion", null, 0);
        // Recomputed on both, but nothing moved, so only the two offers are in the log.
        assertThat(causes(provider)).containsExactly("offer_sent", "offer_sent");
    }

    // ---- 3. responsiveness: a decline is an answer, silence is not ------------------------

    @Test void declinesNeverLowerResponsivenessAndSilenceDoes() throws Exception {
        var provider = guest();
        provide(provider);
        for (int n = 0; n < 5; n++) {
            Ask a = ask();
            post(provider, "/v1/providers/me/inbox/" + matchId(a.id(), provider) + "/decline", "{\"reason\":\"busy\"}", null)
                    .andExpect(status().isOk());
            CLOCK.now = CLOCK.now.plus(Duration.ofMinutes(16));
        }
        assertComponent(me(provider).path("score_breakdown"), "responsiveness", 100, 5);
        assertThat(causes(provider)).contains("match_declined");
        // An open match inside respond_by is neither answered nor silent.
        Ask open = ask();
        assertComponent(me(provider).path("score_breakdown"), "responsiveness", 100, 5);
        CLOCK.now = CLOCK.now.plus(Duration.ofMinutes(6));
        service.workOnce();
        assertThat(matchId(open.id(), provider)).isNotNull();
        // 5 answered of 6 is 83.
        assertComponent(me(provider).path("score_breakdown"), "responsiveness", 83, 6);
        assertThat(jdbc.queryForObject("SELECT response_rate FROM provider_scores WHERE user_id=?", Double.class, userId(provider)))
                .isEqualTo(0.833);
        assertThat(causes(provider)).endsWith("silence_detected");
        // The provider is still New (no completed jobs), so the public score has no value.
        assertThat(me(provider).path("score").has("value")).isFalse();
        assertThat(storedTrust(provider)).isNull();
    }

    // ---- 4. standing: suspend and reinstate ----------------------------------------------

    @Test void suspendingStopsMatchingRefusesActionsWithdrawsOffersReleasesReservationsAndReinstatingRestores() throws Exception {
        var owner = staffMember("owner", true);
        var provider = guest();
        provide(provider);
        // A live offer, a pending reservation and an open match.
        Ask offered = ask();
        String liveOffer = offerOk(provider, offered.id());
        Ask chosen = ask();
        String chosenOffer = offerOk(provider, chosen.id());
        service.workOnce();
        post(chosen.asker(), "/v1/requests/" + chosen.id() + "/select", "{\"offer_id\":\"" + chosenOffer + "\"}", key())
                .andExpect(status().isOk());
        Ask open = ask();
        String openMatch = matchId(open.id(), provider);

        JsonNode suspended = suspend(owner, provider, "suspended");
        assertThat(suspended.path("user_id").asText()).isEqualTo(userId(provider));
        assertThat(suspended.path("standing").asText()).isEqualTo("suspended");
        assertThat(suspended.path("display_name").asText()).isEqualTo("Fresh Line Studio");
        assertComponent(suspended.path("score_breakdown"), "standing", 0, 0);
        assertThat(me(provider).path("standing").asText()).isEqualTo("suspended");

        // Live offers withdrawn; the pending reservation released, so that request has no offer left.
        assertThat(jdbc.queryForObject("SELECT withdrawn_at IS NOT NULL FROM request_offers WHERE id=?", Boolean.class, liveOffer)).isTrue();
        assertThat(jdbc.queryForObject("SELECT status FROM request_reservations WHERE request_id=?", String.class, chosen.id()))
                .isEqualTo("released");
        assertThat(requestStatus(chosen.id())).isEqualTo("expired");
        assertThat(json(get(offered.asker(), "/v1/requests/" + offered.id() + "/offers").andExpect(status().isOk()), "OfferList")
                .get("offers").size()).isZero();

        // Offer, decline and reservation answer are 403.
        assertThat(errorOf(sendOffer(provider, open.id()), 403).path("code").asText()).isEqualTo("forbidden");
        errorOf(post(provider, "/v1/providers/me/inbox/" + openMatch + "/decline", null, null), 403);
        errorOf(answer(provider, matchId(chosen.id(), provider), "confirm"), 403);
        assertThat(jdbc.queryForObject("SELECT declined_at IS NULL FROM request_matches WHERE match_id=?", Boolean.class, openMatch)).isTrue();

        // Never matched while suspended.
        CLOCK.now = CLOCK.now.plus(Duration.ofMinutes(61));
        var other = guest();
        provide(other);
        Ask unseen = ask();
        assertThat(matchId(unseen.id(), provider)).isNull();
        assertThat(matchId(unseen.id(), other)).isNotNull();

        // The change is audited with its reason and logged against the score.
        assertThat(jdbc.queryForObject("SELECT count(*) FROM audit_events WHERE actor_id=? AND action='provider.standing_changed'"
                + " AND resource_id=? AND reason LIKE 'suspended:%'", Integer.class, owner.userId(), userId(provider))).isEqualTo(1);
        // The open match then went silent while suspended, which the worker logged too.
        assertThat(causes(provider)).containsExactly("offer_sent", "offer_sent", "standing_changed", "silence_detected");
        assertThat(jdbc.queryForObject("SELECT components->'standing'->>'value' FROM score_history WHERE provider_id=?"
                + " AND cause='standing_changed'", String.class, userId(provider))).isEqualTo("0");

        // Reinstated: standing 100 again, matched again, may offer again.
        JsonNode active = suspend(owner, provider, "active");
        assertThat(active.path("standing").asText()).isEqualTo("active");
        assertComponent(active.path("score_breakdown"), "standing", 100, 0);
        assertThat(causes(provider)).endsWith("silence_detected", "standing_changed");
        CLOCK.now = CLOCK.now.plus(Duration.ofMinutes(61));
        Ask back = ask();
        assertThat(matchId(back.id(), provider)).isNotNull();
        offerOk(provider, back.id());
    }

    @Test void standingBasisCountsDaysSinceTheProfileOrTheLastChange() throws Exception {
        var owner = staffMember("owner", true);
        var provider = guest();
        provide(provider);
        CLOCK.now = START.plus(Duration.ofDays(12)).plus(Duration.ofHours(1));
        assertComponent(me(provider).path("score_breakdown"), "standing", 100, 12);
        suspend(owner, provider, "suspended");
        CLOCK.now = CLOCK.now.plus(Duration.ofDays(2));
        assertComponent(me(provider).path("score_breakdown"), "standing", 0, 2);
    }

    // ---- 5. the admin routes: owner only, validated, audited -----------------------------

    @Test void theProviderAdminRoutesAreOwnerOnly() throws Exception {
        var provider = guest();
        provide(provider);
        String path = "/v1/admin/providers/" + userId(provider) + "/standing";
        String body = "{\"standing\":\"suspended\",\"reason\":\"Under review.\"}";
        mvc.perform(MockMvcRequestBuilders.get("/v1/admin/providers")).andExpect(status().isUnauthorized());
        mvc.perform(MockMvcRequestBuilders.post(path).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isUnauthorized());
        get(provider, "/v1/admin/providers").andExpect(status().isForbidden());
        post(provider, path, body, null).andExpect(status().isForbidden());
        for (PlugPrincipal refused : List.of(staffMember("owner", false), staffMember("staff", true),
                new PlugPrincipal("usr_admin-" + UUID.randomUUID(), "ses_x", Set.of(PlugPrincipal.SCOPE_ADMIN), true))) {
            errorOf(asStaff(refused, MockMvcRequestBuilders.get("/v1/admin/providers")), 403);
            errorOf(standing(refused, userId(provider), body), 403);
        }
        assertThat(me(provider).path("standing").asText()).isEqualTo("active");
    }

    @Test void standingValidatesItsBodyAndAnUnknownProviderIsNotFound() throws Exception {
        var owner = staffMember("owner", true);
        var provider = guest();
        provide(provider);
        String id = userId(provider);
        assertThat(errorOf(standing(owner, id, "{\"standing\":\"suspended\"}"), 400).at("/details/0/code").asText()).isEqualTo("required");
        for (String bad : List.of("{\"standing\":\"suspended\",\"reason\":\"no\"}",
                "{\"standing\":\"suspended\",\"reason\":\"" + "x".repeat(301) + "\"}",
                "{\"standing\":\"suspended\",\"reason\":3}",
                "{\"standing\":\"banned\",\"reason\":\"Under review.\"}",
                "{\"reason\":\"Under review.\"}",
                "{\"standing\":\"suspended\",\"reason\":\"Under review.\",\"note\":\"x\"}",
                "[\"suspended\"]")) {
            errorOf(standing(owner, id, bad), 400);
        }
        errorOf(standing(owner, "usr_" + UUID.randomUUID(), "{\"standing\":\"suspended\",\"reason\":\"Under review.\"}"), 404);
        errorOf(standing(owner, "not-a-user", "{\"standing\":\"suspended\",\"reason\":\"Under review.\"}"), 404);
        assertThat(me(provider).path("standing").asText()).isEqualTo("active");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM audit_events WHERE actor_id=? AND action='provider.standing_changed'",
                Integer.class, owner.userId())).isZero();
    }

    @Test void theOwnerListsProvidersInPagesAndEveryReadIsAudited() throws Exception {
        var owner = staffMember("owner", true);
        var first = guest();
        provide(first);
        CLOCK.now = START.plus(Duration.ofMinutes(1));
        var second = guest();
        provide(second);
        JsonNode page = json(asStaff(owner, MockMvcRequestBuilders.get("/v1/admin/providers?limit=1")).andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store")), "AdminProviderPage");
        assertThat(page.path("items").size()).isEqualTo(1);
        String cursor = page.path("next_cursor").asText();
        assertThat(cursor).isNotBlank();
        JsonNode next = json(asStaff(owner, MockMvcRequestBuilders.get("/v1/admin/providers?limit=1&cursor=" + cursor))
                .andExpect(status().isOk()), "AdminProviderPage");
        assertThat(next.path("items").get(0).path("user_id").asText()).isNotEqualTo(page.path("items").get(0).path("user_id").asText());
        JsonNode all = json(asStaff(owner, MockMvcRequestBuilders.get("/v1/admin/providers?limit=100")).andExpect(status().isOk()),
                "AdminProviderPage");
        assertThat(all.path("items").findValuesAsText("user_id")).contains(userId(first), userId(second));
        for (String query : List.of("?limit=0", "?limit=101", "?limit=abc", "?cursor=not-a-cursor")) {
            errorOf(asStaff(owner, MockMvcRequestBuilders.get("/v1/admin/providers" + query)), 400);
        }
        assertThat(jdbc.queryForObject("SELECT count(*) FROM audit_events WHERE actor_id=? AND action='admin.read' AND resource='providers'",
                Integer.class, owner.userId())).isGreaterThanOrEqualTo(3);
    }
}
