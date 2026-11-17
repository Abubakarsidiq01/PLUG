package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ContractSchemas;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
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

/// P3.S11: a matched provider sends an in-app offer (contract 0.7.1 sendProviderOffer). The offer is
/// the same validated Offer the asker lists, with source portal, truth_label confirmed, no place, a
/// note, distance rounded to 100 m and expires_at = available_at + 15 minutes (owner decision
/// 2026-11-17). Only the provider's own confirm books it.
@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.provider-inbox.enabled=true", "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(ProviderOfferTest.TimeConfiguration.class)
class ProviderOfferTest {
    static final Instant START = ReservationTest.START;
    static final ReservationTest.MutableClock CLOCK = new ReservationTest.MutableClock();
    /// No seeded supplier and no other suite's provider is near, so only this test's providers match.
    static final String BASE = "{\"latitude\":44.0,\"longitude\":-101.0,\"precision\":\"coarse\"}";
    /// About 450 m north of BASE, so the distance needs rounding.
    static final String NEAR = "{\"latitude\":44.004,\"longitude\":-101.0,\"precision\":\"coarse\"}";
    static final String NOTE = "2 chairs free, fades and line-ups.";

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
        var request = MockMvcRequestBuilders.post(path).with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .contentType(MediaType.APPLICATION_JSON).content(body);
        if (who != null) request.header("Authorization", "Bearer " + who.get("access_token").asText());
        if (key != null) request.header("Idempotency-Key", key);
        return mvc.perform(request);
    }
    ResultActions get(JsonNode who, String path) throws Exception {
        return mvc.perform(MockMvcRequestBuilders.get(path).with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .header("Authorization", "Bearer " + who.get("access_token").asText()));
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
    String newKey() { return "offer-test-" + UUID.randomUUID(); }
    String body(int price, Instant available, String note) {
        return "{\"price_cents\":" + price + ",\"currency\":\"USD\",\"available_at\":\"" + available + "\""
                + (note == null ? "" : ",\"note\":" + quote(note)) + "}";
    }
    String quote(String text) throws RuntimeException {
        try { return mapper.writeValueAsString(text); } catch (Exception e) { throw new RuntimeException(e); }
    }
    String valid() { return body(3000, START.plus(Duration.ofMinutes(20)), NOTE); }
    ResultActions offer(JsonNode who, String requestId, String body, String key) throws Exception {
        return post(who, "/v1/requests/" + requestId + "/offers", body, key);
    }
    ResultActions offer(JsonNode who, String requestId, String body) throws Exception { return offer(who, requestId, body, newKey()); }
    JsonNode offerOk(JsonNode who, String requestId, String body) throws Exception {
        return json(offer(who, requestId, body).andExpect(status().isCreated()), "Offer");
    }
    void provide(JsonNode who) throws Exception {
        post(who, "/v1/providers/skills", "{\"skill_tags\":[\"barber\"],\"travel_radius_m\":4828,\"base_location\":" + BASE
                + ",\"availability\":[{\"days\":\"every_day\",\"from\":\"09:00\",\"to\":\"24:00\"}],"
                + "\"time_zone\":\"America/Chicago\"}", null).andExpect(status().isOk());
    }
    String requestStatus(String requestId) {
        return jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, requestId);
    }
    String matchId(String requestId, JsonNode provider) {
        return jdbc.queryForObject("SELECT match_id FROM request_matches WHERE request_id=? AND provider_id=?", String.class,
                requestId, userId(provider));
    }

    /// A barber request worked until its matched providers wait for replies; no seed supplier is near.
    record Scene(JsonNode asker, String requestId, JsonNode provider, JsonNode second) {}
    Scene scene(String text) throws Exception {
        var provider = guest();
        provide(provider);
        var second = guest();
        provide(second);
        var asker = guest();
        String id = json(post(asker, "/v1/requests", "{\"text\":" + quote(text) + ",\"location\":" + NEAR + "}", newKey())
                .andExpect(status().isCreated()), "RequestResource").path("request_id").asText();
        for (int n = 0; n < 3; n++) service.workOnce();
        assertThat(requestStatus(id)).isEqualTo("awaiting_responses");
        assertThat(matchId(id, provider)).startsWith("mat_");
        assertThat(matchId(id, second)).startsWith("mat_");
        return new Scene(asker, id, provider, second);
    }
    Scene scene() throws Exception { return scene("Barber under $35 in 30 minutes"); }

    // ---- 1. a valid offer ----------------------------------------------------------------

    @Test void aMatchedProvidersOfferIsAConfirmedPortalOfferWithNoPlaceRoundedDistanceAndFifteenMinutes() throws Exception {
        var s = scene();
        Instant available = START.plus(Duration.ofMinutes(20));
        JsonNode offer = offerOk(s.provider(), s.requestId(), valid());
        assertThat(offer.path("offer_id").asText()).startsWith("off_");
        assertThat(offer.path("source").asText()).isEqualTo("portal");
        assertThat(offer.path("truth_label").asText()).isEqualTo("confirmed");
        assertThat(offer.has("place")).isFalse();
        assertThat(offer.path("note").asText()).isEqualTo(NOTE);
        assertThat(offer.path("price_cents").asInt()).isEqualTo(3000);
        assertThat(offer.path("currency").asText()).isEqualTo("USD");
        assertThat(Instant.parse(offer.path("available_at").asText())).isEqualTo(available);
        assertThat(Instant.parse(offer.path("expires_at").asText())).isEqualTo(available.plus(Duration.ofMinutes(15)));
        assertThat(Instant.parse(offer.path("observed_at").asText())).isEqualTo(START);
        int exact = jdbc.queryForObject("SELECT distance_m FROM request_matches WHERE request_id=? AND provider_id=?",
                Integer.class, s.requestId(), userId(s.provider()));
        assertThat(exact % 100).isNotZero();
        assertThat(offer.path("distance_m").asInt()).isEqualTo((int) Math.round(exact / 100.0) * 100);
        assertThat(offer.path("provider_score").path("state").asText()).isEqualTo("new");
        // The provider has now replied.
        assertThat(jdbc.queryForObject("SELECT replied_at FROM request_matches WHERE request_id=? AND provider_id=?",
                java.sql.Timestamp.class, s.requestId(), userId(s.provider()))).isNotNull();
    }

    @Test void theSameKeyAndBodyReplaysTheFirstOfferAndAnotherBodyWithThatKeyIsRefused() throws Exception {
        var s = scene();
        String key = newKey();
        JsonNode first = json(offer(s.provider(), s.requestId(), valid(), key).andExpect(status().isCreated()), "Offer");
        JsonNode again = json(offer(s.provider(), s.requestId(), valid(), key).andExpect(status().isCreated()), "Offer");
        assertThat(again).isEqualTo(first);
        assertDetail(errorOf(offer(s.provider(), s.requestId(), body(2500, START.plus(Duration.ofMinutes(20)), null), key), 409),
                "Idempotency-Key", "idempotency_key_reused");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM request_offers WHERE request_id=?", Integer.class, s.requestId()))
                .isEqualTo(1);
    }

    @Test void aSecondDifferentOfferIsAlreadyOffered() throws Exception {
        var s = scene();
        offerOk(s.provider(), s.requestId(), valid());
        assertDetail(errorOf(offer(s.provider(), s.requestId(), body(2500, START.plus(Duration.ofMinutes(25)), null)), 409),
                "request_id", "already_offered");
    }

    // ---- 2. validation -------------------------------------------------------------------

    @Test void aPriceAboveTheBudgetIsOverBudget() throws Exception {
        var s = scene();
        assertDetail(errorOf(offer(s.provider(), s.requestId(), body(3600, START.plus(Duration.ofMinutes(20)), null)), 400),
                "price_cents", "over_budget");
        offerOk(s.provider(), s.requestId(), body(3500, START.plus(Duration.ofMinutes(20)), null));
    }

    @Test void aTimeInThePastOrAfterNeededByIsOutsideTheWindow() throws Exception {
        var s = scene();
        assertDetail(errorOf(offer(s.provider(), s.requestId(), body(3000, START.minus(Duration.ofMinutes(1)), null)), 400),
                "available_at", "outside_window");
        assertDetail(errorOf(offer(s.provider(), s.requestId(), body(3000, START.plus(Duration.ofMinutes(40)), null)), 400),
                "available_at", "outside_window");
    }

    @Test void aTimeMoreThanSevenDaysAheadIsOutsideTheWindowEvenWithNoNeededBy() throws Exception {
        var s = scene("Barber under $35");
        assertThat(jdbc.queryForObject("SELECT needed_by FROM request_constraints WHERE request_id=?", java.sql.Timestamp.class,
                s.requestId())).isNull();
        assertDetail(errorOf(offer(s.provider(), s.requestId(),
                body(3000, START.plus(Duration.ofDays(7)).plus(Duration.ofMinutes(1)), null)), 400), "available_at", "outside_window");
        offerOk(s.provider(), s.requestId(), body(3000, START.plus(Duration.ofDays(7)), null));
    }

    @Test void aPhoneNumberEmailOrLinkInTheNoteIsContactInNote() throws Exception {
        var s = scene();
        Instant at = START.plus(Duration.ofMinutes(20));
        for (String note : List.of("Call me on 318-555-0142", "text +1 (318) 555 0142", "me@example.com",
                "Book at https://cuts.example", "see www.cuts.example", "cutsbyjo.com")) {
            assertDetail(errorOf(offer(s.provider(), s.requestId(), body(3000, at, note)), 400), "note", "contact_in_note");
        }
        assertThat(jdbc.queryForObject("SELECT count(*) FROM request_offers WHERE request_id=?", Integer.class, s.requestId())).isZero();
    }

    @Test void aBodyThatIsNotAProviderOfferCreateOrAMissingKeyIsAValidationFailure() throws Exception {
        var s = scene();
        Instant at = START.plus(Duration.ofMinutes(20));
        errorOf(offer(s.provider(), s.requestId(), valid(), null), 400);
        errorOf(offer(s.provider(), s.requestId(), body(499, at, null)), 400);
        errorOf(offer(s.provider(), s.requestId(), body(50001, at, null)), 400);
        errorOf(offer(s.provider(), s.requestId(), "{\"price_cents\":3000,\"currency\":\"USD\"}"), 400);
        errorOf(offer(s.provider(), s.requestId(), "{\"price_cents\":3000.5,\"currency\":\"USD\",\"available_at\":\"" + at + "\"}"), 400);
        errorOf(offer(s.provider(), s.requestId(), "{\"price_cents\":3000,\"currency\":\"USD\",\"available_at\":\"soon\"}"), 400);
        errorOf(offer(s.provider(), s.requestId(), body(3000, at, "")), 400);
        errorOf(offer(s.provider(), s.requestId(), body(3000, at, "x".repeat(141))), 400);
        errorOf(offer(s.provider(), s.requestId(), body(3000, at, null).replace("}", ",\"truth_label\":\"confirmed\"}")), 400);
        assertDetail(errorOf(offer(s.provider(), s.requestId(), body(3000, at, null).replace("USD", "EUR")), 400),
                "currency", "unsupported");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM request_offers WHERE request_id=?", Integer.class, s.requestId())).isZero();
    }

    // ---- 3. who may offer ----------------------------------------------------------------

    @Test void aProviderNeverMatchedANonexistentRequestAndTheAskersOwnRequestAreNotFound() throws Exception {
        var s = scene();
        var stranger = guest();
        provide(stranger);
        errorOf(offer(stranger, s.requestId(), valid()), 404);
        errorOf(offer(s.provider(), "req_" + UUID.randomUUID(), valid()), 404);
        errorOf(offer(s.provider(), "not-a-request", valid()), 404);
        errorOf(offer(s.asker(), s.requestId(), valid()), 404);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM request_offers WHERE request_id=?", Integer.class, s.requestId())).isZero();
    }

    @Test void withoutASessionTheOfferIsUnauthenticated() throws Exception {
        var s = scene();
        offer(null, s.requestId(), valid()).andExpect(status().isUnauthorized());
    }

    @Test void theEleventhOfferAttemptInAWindowIsRateLimitedWithRetryAfter() throws Exception {
        var provider = guest();
        provide(provider);
        for (int n = 0; n < 10; n++) errorOf(offer(provider, "req_" + UUID.randomUUID(), valid()), 404);
        var result = offer(provider, "req_" + UUID.randomUUID(), valid());
        result.andExpect(status().isTooManyRequests()).andExpect(header().exists("Retry-After"));
        assertThat(json(result, "Error").at("/error/code").asText()).isEqualTo("rate_limited");
    }

    // ---- 4. a closed request or a declined match -----------------------------------------

    @Test void anOfferOnACanceledRequestIsRequestClosed() throws Exception {
        var s = scene();
        post(s.asker(), "/v1/requests/" + s.requestId() + "/cancel", "", null).andExpect(status().isOk());
        assertDetail(errorOf(offer(s.provider(), s.requestId(), valid()), 409), "request_id", "request_closed");
    }

    @Test void anOfferOnAnExpiredRequestIsRequestClosed() throws Exception {
        var s = scene();
        CLOCK.now = START.plus(Duration.ofMinutes(31));
        assertDetail(errorOf(offer(s.provider(), s.requestId(), body(3000, CLOCK.now.plus(Duration.ofMinutes(5)), null)), 409),
                "request_id", "request_closed");
        // The refused offer rolls back; the next read records the expiry.
        assertThat(json(get(s.asker(), "/v1/requests/" + s.requestId()).andExpect(status().isOk()), "RequestResource")
                .path("status").asText()).isEqualTo("expired");
    }

    @Test void anOfferAfterTheAskerSelectedAnotherIsRequestClosed() throws Exception {
        var s = scene();
        String chosen = offerOk(s.provider(), s.requestId(), valid()).path("offer_id").asText();
        service.workOnce();
        post(s.asker(), "/v1/requests/" + s.requestId() + "/select", "{\"offer_id\":\"" + chosen + "\"}", newKey())
                .andExpect(status().isOk());
        assertDetail(errorOf(offer(s.second(), s.requestId(), valid()), 409), "request_id", "request_closed");
    }

    @Test void anOfferOnADeclinedMatchIsRequestClosed() throws Exception {
        var s = scene();
        jdbc.update("UPDATE request_matches SET replied_at=? WHERE request_id=? AND provider_id=?",
                java.sql.Timestamp.from(START), s.requestId(), userId(s.provider()));
        assertDetail(errorOf(offer(s.provider(), s.requestId(), valid()), 409), "request_id", "request_closed");
    }

    // ---- 5. end to end: listed, ranked, selected, confirmed only by the provider -------

    @Test void thePortalOfferIsListedRanksTheRequestAndOnlyTheProvidersConfirmBooksIt() throws Exception {
        var s = scene();
        JsonNode sent = offerOk(s.provider(), s.requestId(), valid());
        String offerId = sent.path("offer_id").asText();
        // The provider's inbox shows their live offer.
        JsonNode inbox = json(get(s.provider(), "/v1/providers/me/inbox").andExpect(status().isOk()), "ProviderInbox");
        JsonNode item = inbox.get("items").get(0);
        assertThat(item.path("request_id").asText()).isEqualTo(s.requestId());
        assertThat(item.path("status").asText()).isEqualTo("offered");
        assertThat(item.at("/offer/offer_id").asText()).isEqualTo(offerId);
        // The next worker pass ranks the request: every seed (none) replied and an offer is live.
        service.workOnce();
        assertThat(requestStatus(s.requestId())).isEqualTo("ranked");
        JsonNode offers = json(get(s.asker(), "/v1/requests/" + s.requestId() + "/offers").andExpect(status().isOk()), "OfferList")
                .get("offers");
        assertThat(offers.size()).isEqualTo(1);
        assertThat(offers.get(0)).isEqualTo(sent);
        // A ranked request with a live portal offer is not swept as offerless.
        service.workOnce();
        assertThat(requestStatus(s.requestId())).isEqualTo("ranked");
        post(s.asker(), "/v1/requests/" + s.requestId() + "/select", "{\"offer_id\":\"" + offerId + "\"}", newKey())
                .andExpect(status().isOk());
        assertThat(requestStatus(s.requestId())).isEqualTo("user_selected");
        service.workOnce();
        assertThat(requestStatus(s.requestId())).isEqualTo("user_selected");
        JsonNode confirmed = json(post(s.provider(), "/v1/providers/me/inbox/" + matchId(s.requestId(), s.provider()) + "/reservation",
                "{\"decision\":\"confirm\"}", null).andExpect(status().isOk()), "InboxItem");
        assertThat(confirmed.path("status").asText()).isEqualTo("confirmed");
        assertThat(requestStatus(s.requestId())).isEqualTo("confirmed");
    }

    @Test void theOfferExpiresFifteenMinutesAfterItsSlotAndIsNoLongerListed() throws Exception {
        var s = scene();
        offerOk(s.provider(), s.requestId(), body(3000, START.plus(Duration.ofMinutes(5)), null));
        service.workOnce();
        assertThat(requestStatus(s.requestId())).isEqualTo("ranked");
        CLOCK.now = START.plus(Duration.ofMinutes(20));
        assertThat(json(get(s.asker(), "/v1/requests/" + s.requestId() + "/offers").andExpect(status().isOk()), "OfferList")
                .get("offers").size()).isZero();
        assertThat(requestStatus(s.requestId())).isEqualTo("expired");
    }
}
