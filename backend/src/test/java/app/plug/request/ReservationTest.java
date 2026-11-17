package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ApiException;
import app.plug.foundation.ContractSchemas;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
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
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/// P3.S6: choosing an offer opens a reservation that only the provider can confirm (manual v4
/// 19.6). Contract 0.7.0: POST /v1/requests/{id}/select, RequestResource.reservation,
/// SelectionConflict. The provider decision is tested at service level (its HTTP route waits for
/// contract 0.7.1). The clock is mutable and starts each test at the fixed instant.
@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.provider-inbox.enabled=true", "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(ReservationTest.TimeConfiguration.class)
class ReservationTest {
    static final Instant START = Instant.parse("2026-10-01T20:00:00Z");
    static final MutableClock CLOCK = new MutableClock();
    static final String BODY = "{\"text\":\"Barber under $35 in 30 minutes\","
            + "\"location\":{\"latitude\":32.528,\"longitude\":-92.714,\"precision\":\"coarse\"}}";
    static final String HERE = "{\"latitude\":32.528,\"longitude\":-92.714,\"precision\":\"coarse\"}";

    static final class MutableClock extends Clock {
        volatile Instant now = START;
        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }
    }
    @TestConfiguration static class TimeConfiguration {
        @Bean @Primary RequestClock mutableRequestClock() { return new RequestClock(CLOCK); }
    }

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    @Autowired RequestService service;
    @Autowired ReservationService reservations;
    @Autowired PlatformTransactionManager transactions;
    private final List<String> users = new ArrayList<>();

    @BeforeEach void resetClock() { CLOCK.now = START; }

    /// The worker drains 20 requests a pass; leftovers would starve later suites.
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
        JsonNode session = mapper.readTree(mvc.perform(MockMvcRequestBuilders.post("/v1/auth/guest").with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
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
    ResultActions read(JsonNode who, String path) throws Exception {
        return mvc.perform(get(path).with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .header("Authorization", "Bearer " + who.get("access_token").asText()));
    }
    JsonNode json(ResultActions result) throws Exception {
        JsonNode body = mapper.readTree(result.andReturn().getResponse().getContentAsString());
        ContractSchemas.validate(body.has("error") ? "Error" : body.has("offers") ? "OfferList" : "RequestResource", body);
        return body;
    }
    String newKey() { return "reservation-test-" + UUID.randomUUID(); }
    String offerBody(String offerId) { return "{\"offer_id\":\"" + offerId + "\"}"; }
    ResultActions select(JsonNode who, String requestId, String offerId) throws Exception {
        return post(who, "/v1/requests/" + requestId + "/select", offerBody(offerId), newKey());
    }
    ResultActions cancel(JsonNode who, String requestId) throws Exception {
        return post(who, "/v1/requests/" + requestId + "/cancel", "", null);
    }
    JsonNode resource(JsonNode who, String requestId) throws Exception {
        return json(read(who, "/v1/requests/" + requestId).andExpect(status().isOk()));
    }
    JsonNode offers(JsonNode who, String requestId) throws Exception {
        return json(read(who, "/v1/requests/" + requestId + "/offers").andExpect(status().isOk())).get("offers");
    }
    /// Creates a request through the real flow and works it until it is ranked with seed offers.
    String rankedRequest(JsonNode owner) throws Exception {
        String id = json(post(owner, "/v1/requests", BODY, newKey()).andExpect(status().isCreated())).path("request_id").asText();
        for (int n = 0; n < 5; n++) service.workOnce();
        assertThat(resource(owner, id).path("status").asText()).isEqualTo("ranked");
        assertThat(offers(owner, id).size()).isEqualTo(2);
        return id;
    }
    JsonNode errorOf(ResultActions result, int status) throws Exception {
        result.andExpect(status().is(status));
        JsonNode body = json(result);
        assertThat(body.has("error")).isTrue();
        return body.get("error");
    }
    void assertDetail(JsonNode error, String field, String code) {
        assertThat(error.at("/details/0/field").asText()).isEqualTo(field);
        assertThat(error.at("/details/0/code").asText()).isEqualTo(code);
    }
    Instant instant(JsonNode node, String pointer) { return Instant.parse(node.at(pointer).asText()); }
    Instant ts(String sql, Object... args) {
        var rows = jdbc.queryForList(sql, Timestamp.class, args);
        Timestamp value = rows.isEmpty() ? null : rows.get(0);
        return value == null ? null : value.toInstant();
    }
    String reservationStatus(String requestId) {
        return jdbc.queryForObject("SELECT status FROM request_reservations WHERE request_id=?", String.class, requestId);
    }

    /// Owner with a ranked request, a provider linked to one offer and matched to the request.
    record Scene(JsonNode owner, String requestId, JsonNode offer, JsonNode other, String provider, String matchId) {}
    Scene scene() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        var list = offers(owner, id);
        var providerSession = guest();
        String provider = userId(providerSession);
        post(providerSession, "/v1/providers/skills", "{\"skill_tags\":[\"barber\"],\"travel_radius_m\":4828,\"base_location\":" + HERE
                + ",\"availability\":[{\"days\":\"every_day\",\"from\":\"09:00\",\"to\":\"24:00\"}],"
                + "\"time_zone\":\"America/Chicago\"}", null).andExpect(status().isOk());
        String matchId = "mat_" + UUID.randomUUID();
        jdbc.update("INSERT INTO request_matches(request_id,provider_id,distance_m,rank_score,notified_at,match_id) VALUES(?,?,?,?,?,?)",
                id, provider, 100, 50, Timestamp.from(START), matchId);
        jdbc.update("UPDATE request_offers SET provider_id=? WHERE id=?", provider, list.get(0).path("offer_id").asText());
        return new Scene(owner, id, list.get(0), list.get(1), provider, matchId);
    }
    JsonNode selectOk(Scene s) throws Exception {
        return json(select(s.owner(), s.requestId(), s.offer().path("offer_id").asText()).andExpect(status().isOk()));
    }
    void assertApi(Runnable call, int status, String field, String code) {
        assertThatThrownBy(call::run).isInstanceOfSatisfying(ApiException.class, e -> {
            assertThat(e.status()).isEqualTo(status);
            if (field != null) {
                assertThat(e.details().get(0).field()).isEqualTo(field);
                assertThat(e.details().get(0).code()).isEqualTo(code);
            }
        });
    }

    // ---- 1. select happy path ------------------------------------------------------------

    @Test void selectingARankedOfferOpensAPendingReservationAwaitingTheSupplier() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        var offer = offers(owner, id).get(0);
        var selected = json(select(owner, id, offer.path("offer_id").asText()).andExpect(status().isOk()));
        assertThat(selected.path("status").asText()).isEqualTo("user_selected");
        assertThat(selected.path("next_action").asText()).isEqualTo("await_supplier_confirmation");
        assertThat(selected.path("poll_after_seconds").asInt()).isEqualTo(5);
        var reservation = selected.path("reservation");
        assertThat(reservation.path("status").asText()).isEqualTo("pending");
        assertThat(reservation.path("reservation_id").asText()).startsWith("rsv_");
        assertThat(reservation.path("offer_id").asText()).isEqualTo(offer.path("offer_id").asText());
        assertThat(reservation.path("booking_ref").asText()).matches("^[2-9A-HJ-NP-Z]{4}$");
        Instant available = instant(offer, "/available_at");
        Instant floor = START.plus(Duration.ofMinutes(10));
        Instant cap = START.plus(Duration.ofMinutes(20));
        Instant expected = available.isAfter(floor) ? (available.isBefore(cap) ? available : cap) : floor;
        assertThat(instant(reservation, "/confirm_by")).isEqualTo(expected);
        assertThat(instant(reservation, "/created_at")).isEqualTo(START);
        assertThat(reservation.has("confirmed_at")).isFalse();
        assertThat(reservation.has("ended_at")).isFalse();
        assertThat(resource(owner, id).path("reservation")).isEqualTo(reservation);
    }

    /// confirm_by = min(selected_at + 20 min, max(available_at, selected_at + 10 min)), owner rule 0.7.1.
    Instant confirmByFor(Instant availableAt) throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        String offerId = offers(owner, id).get(0).path("offer_id").asText();
        // Keep the table checks: observed_at <= available_at < expires_at.
        jdbc.update("UPDATE request_offers SET observed_at=LEAST(observed_at,?),available_at=?,expires_at=GREATEST(expires_at,?) WHERE id=?",
                Timestamp.from(availableAt), Timestamp.from(availableAt), Timestamp.from(availableAt.plus(Duration.ofHours(1))), offerId);
        return instant(json(select(owner, id, offerId).andExpect(status().isOk())), "/reservation/confirm_by");
    }
    @Test void anOfferAlreadyAvailableGetsTenMinutesNotAnInstantTimeout() throws Exception {
        Instant confirmBy = confirmByFor(START.minus(Duration.ofMinutes(5)));
        assertThat(confirmBy).isEqualTo(START.plus(Duration.ofMinutes(10)));
    }
    @Test void aSlotFifteenMinutesAwayMustBeConfirmedByTheSlot() throws Exception {
        Instant slot = START.plus(Duration.ofMinutes(15));
        assertThat(confirmByFor(slot)).isEqualTo(slot);
    }
    @Test void aSlotTwoHoursAwayIsCappedAtTwentyMinutes() throws Exception {
        assertThat(confirmByFor(START.plus(Duration.ofHours(2)))).isEqualTo(START.plus(Duration.ofMinutes(20)));
    }

    // ---- 2. idempotency and validation ---------------------------------------------------

    @Test void sameKeySameBodyReplaysTheFirstAnswerAndOtherBodyIsRefused() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        var list = offers(owner, id);
        String first = list.get(0).path("offer_id").asText();
        String key = newKey();
        String path = "/v1/requests/" + id + "/select";
        var created = json(post(owner, path, offerBody(first), key).andExpect(status().isOk()));
        assertThat(json(post(owner, path, offerBody(first), key).andExpect(status().isOk()))).isEqualTo(created);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM request_reservations WHERE request_id=?", Integer.class, id)).isEqualTo(1);
        var reused = errorOf(post(owner, path, offerBody(list.get(1).path("offer_id").asText()), key), 409);
        assertDetail(reused, "Idempotency-Key", "idempotency_key_reused");
    }

    @Test void missingIdempotencyKeyAndBadOfferIdAreValidationFailures() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        String path = "/v1/requests/" + id + "/select";
        String offer = offers(owner, id).get(0).path("offer_id").asText();
        var noKey = errorOf(post(owner, path, offerBody(offer), null), 400);
        assertDetail(noKey, "Idempotency-Key", "invalid");
        for (String bad : List.of("{\"offer_id\":\"nope\"}", "{}", "{\"offer_id\":\"off_" + "x".repeat(70) + "\"}")) {
            assertDetail(errorOf(post(owner, path, bad, newKey()), 400), "offer_id", "invalid");
        }
        assertThat(resource(owner, id).path("status").asText()).isEqualTo("ranked");
    }

    // ---- 3. selection race ---------------------------------------------------------------

    void race(boolean sameOffer) throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        var list = offers(owner, id);
        String[] offerIds = {list.get(0).path("offer_id").asText(), list.get(sameOffer ? 0 : 1).path("offer_id").asText()};
        var pool = Executors.newFixedThreadPool(2);
        var go = new CountDownLatch(1);
        List<Future<String[]>> results = new ArrayList<>();
        for (String offerId : offerIds) {
            results.add(pool.submit(() -> {
                go.await();
                var response = select(owner, id, offerId).andReturn().getResponse();
                return new String[] {String.valueOf(response.getStatus()), response.getContentAsString()};
            }));
        }
        go.countDown();
        List<String[]> done = new ArrayList<>();
        for (var future : results) done.add(future.get());
        pool.shutdown();
        assertThat(done.stream().map(r -> r[0]).sorted().toList()).containsExactly("200", "409");
        JsonNode loser = mapper.readTree(done.stream().filter(r -> r[0].equals("409")).findFirst().orElseThrow()[1]);
        ContractSchemas.validate("Error", loser);
        assertDetail(loser.get("error"), "offer_id", "already_selected");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM request_reservations WHERE request_id=?", Integer.class, id)).isEqualTo(1);
        assertThat(resource(owner, id).path("status").asText()).isEqualTo("user_selected");
    }
    @Test void twoConcurrentSelectionsOfDifferentOffersLeaveExactlyOneWinner() throws Exception { race(false); }
    @Test void twoConcurrentSelectionsOfTheSameOfferLeaveExactlyOneWinner() throws Exception { race(true); }

    @Test void selectingAgainAfterWinningWithANewKeyIsAlreadySelected() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        var list = offers(owner, id);
        select(owner, id, list.get(0).path("offer_id").asText()).andExpect(status().isOk());
        assertDetail(errorOf(select(owner, id, list.get(1).path("offer_id").asText()), 409), "offer_id", "already_selected");
    }

    // ---- 4. not selectable ---------------------------------------------------------------

    @Test void aRequestThatIsNotRankedCannotBeSelected() throws Exception {
        var owner = guest();
        String id = json(post(owner, "/v1/requests", BODY, newKey()).andExpect(status().isCreated())).path("request_id").asText();
        service.workOnce();
        service.workOnce();
        assertThat(resource(owner, id).path("status").asText()).isEqualTo("awaiting_responses");
        assertDetail(errorOf(select(owner, id, "off_" + UUID.randomUUID()), 409), "request_id", "not_selectable");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM request_reservations WHERE request_id=?", Integer.class, id)).isZero();
    }

    // ---- 5. offer expiry -----------------------------------------------------------------

    @Test void anExpiredOfferIsNeitherListedNorSelectable() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        var list = offers(owner, id);
        String dead = list.get(0).path("offer_id").asText();
        jdbc.update("UPDATE request_offers SET observed_at=?,available_at=?,expires_at=? WHERE id=?",
                Timestamp.from(START.minusSeconds(7200)), Timestamp.from(START.minusSeconds(3600)), Timestamp.from(START), dead);
        assertThat(offers(owner, id).findValuesAsText("offer_id")).doesNotContain(dead).hasSize(1);
        assertDetail(errorOf(select(owner, id, dead), 409), "offer_id", "offer_unavailable");
        assertThat(resource(owner, id).path("status").asText()).isEqualTo("ranked");
    }

    @Test void anotherRequestsOfferIsUnavailableToThisRequest() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        var other = guest();
        String foreign = offers(other, rankedRequest(other)).get(0).path("offer_id").asText();
        assertDetail(errorOf(select(owner, id, foreign), 409), "offer_id", "offer_unavailable");
    }

    // ---- 6. timeout ----------------------------------------------------------------------

    @Test void unconfirmedReservationTimesOutLazilyAndTheRequestReturnsToRankedWithTheOtherOffer() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        var list = offers(owner, id);
        var selected = json(select(owner, id, list.get(0).path("offer_id").asText()).andExpect(status().isOk()));
        Instant confirmBy = instant(selected, "/reservation/confirm_by");
        CLOCK.now = confirmBy.minusSeconds(1);
        assertThat(resource(owner, id).at("/reservation/status").asText()).isEqualTo("pending");
        CLOCK.now = confirmBy;
        var after = resource(owner, id);
        assertThat(after.path("status").asText()).isEqualTo("ranked");
        assertThat(after.at("/reservation/status").asText()).isEqualTo("timed_out");
        assertThat(instant(after, "/reservation/ended_at")).isEqualTo(confirmBy);
        assertThat(after.at("/reservation").has("confirmed_at")).isFalse();
        assertThat(after.at("/progress/offers_ready").asInt()).isEqualTo(1);
        assertThat(offers(owner, id).findValuesAsText("offer_id")).containsExactly(list.get(1).path("offer_id").asText());
        assertThat(ts("SELECT withdrawn_at FROM request_offers WHERE id=?", list.get(0).path("offer_id").asText())).isNotNull();
    }

    @Test void theWorkerTimesOutAnUnconfirmedReservationWithoutAnyoneAsking() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        var selected = json(select(owner, id, offers(owner, id).get(0).path("offer_id").asText()).andExpect(status().isOk()));
        Instant confirmBy = instant(selected, "/reservation/confirm_by");
        CLOCK.now = confirmBy.minusSeconds(1);
        service.workOnce();
        assertThat(reservationStatus(id)).isEqualTo("pending");
        CLOCK.now = confirmBy;
        service.workOnce();
        assertThat(reservationStatus(id)).isEqualTo("timed_out");
        assertThat(ts("SELECT ended_at FROM request_reservations WHERE request_id=?", id)).isEqualTo(confirmBy);
        assertThat(jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, id)).isEqualTo("ranked");
    }

    @Test void timeoutWithNoOtherLiveOfferExpiresTheRequestAsNotConfirmed() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        var list = offers(owner, id);
        var selected = json(select(owner, id, list.get(0).path("offer_id").asText()).andExpect(status().isOk()));
        jdbc.update("DELETE FROM request_offers WHERE id=?", list.get(1).path("offer_id").asText());
        CLOCK.now = instant(selected, "/reservation/confirm_by");
        var after = resource(owner, id);
        assertThat(after.path("status").asText()).isEqualTo("expired");
        assertThat(after.path("no_result_reason").asText()).isEqualTo("not_confirmed");
        assertThat(after.path("next_action").asText()).isEqualTo("show_no_result");
        assertThat(after.at("/reservation/status").asText()).isEqualTo("timed_out");
        assertThat(after.at("/progress/offers_ready").asInt()).isZero();
        assertThat(after.has("poll_after_seconds")).isFalse();
    }

    @Test void aRequestOwnExpiryDoesNotExpireAWaitingReservation() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        var selected = json(select(owner, id, offers(owner, id).get(0).path("offer_id").asText()).andExpect(status().isOk()));
        Instant confirmBy = instant(selected, "/reservation/confirm_by");
        Instant requestExpiry = instant(selected, "/expires_at");
        assertThat(confirmBy).isBeforeOrEqualTo(requestExpiry);
        jdbc.update("UPDATE requests SET expires_at=? WHERE id=?", Timestamp.from(START.plusSeconds(1)), id);
        CLOCK.now = START.plusSeconds(2);
        assertThat(resource(owner, id).path("status").asText()).isEqualTo("user_selected");
    }

    // ---- 7. confirmation only by a supplier event ----------------------------------------

    @Test void noTimerCancelOrSelectionEverConfirms() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        var selected = json(select(owner, id, offers(owner, id).get(0).path("offer_id").asText()).andExpect(status().isOk()));
        assertThat(selected.path("status").asText()).isNotEqualTo("confirmed");
        CLOCK.now = instant(selected, "/reservation/confirm_by").plusSeconds(60);
        service.workOnce();
        assertThat(jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, id)).isNotEqualTo("confirmed");
        assertThat(jdbc.queryForList("SELECT status FROM request_reservations WHERE request_id=?", String.class, id)).doesNotContain("confirmed");
        var other = guest();
        String second = rankedRequest(other);
        select(other, second, offers(other, second).get(0).path("offer_id").asText()).andExpect(status().isOk());
        assertThat(json(cancel(other, second).andExpect(status().isOk())).path("status").asText()).isEqualTo("canceled");
        assertThat(reservationStatus(second)).isEqualTo("canceled");
    }

    @Test void providerConfirmBeforeConfirmByConfirmsOnceAndRepeatIsTheSameResult() throws Exception {
        var s = scene();
        selectOk(s);
        var first = reservations.decide(s.provider(), s.matchId(), "confirm");
        assertThat(reservationStatus(s.requestId())).isEqualTo("confirmed");
        var resource = resource(s.owner(), s.requestId());
        assertThat(resource.path("status").asText()).isEqualTo("confirmed");
        assertThat(resource.path("next_action").asText()).isEqualTo("show_result");
        assertThat(resource.at("/reservation/status").asText()).isEqualTo("confirmed");
        assertThat(instant(resource, "/reservation/confirmed_at")).isEqualTo(START);
        assertThat(resource.at("/reservation").has("ended_at")).isFalse();
        assertThat(reservations.decide(s.provider(), s.matchId(), "confirm")).isEqualTo(first);
        assertApi(() -> reservations.decide(s.provider(), s.matchId(), "release"), 409, "match_id", "reservation_closed");
        assertThat(reservationStatus(s.requestId())).isEqualTo("confirmed");
    }

    @Test void providerDecisionAtOrAfterConfirmByIsClosed() throws Exception {
        var s = scene();
        Instant confirmBy = instant(selectOk(s), "/reservation/confirm_by");
        CLOCK.now = confirmBy;
        assertApi(() -> reservations.decide(s.provider(), s.matchId(), "confirm"), 409, "match_id", "reservation_closed");
        assertThat(jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, s.requestId())).isNotEqualTo("confirmed");
        assertThat(jdbc.queryForList("SELECT status FROM request_reservations WHERE request_id=?", String.class, s.requestId()))
                .doesNotContain("confirmed");
    }

    @Test void providerDecisionOnSomeoneElsesOrMalformedMatchIsNotFound() throws Exception {
        var s = scene();
        selectOk(s);
        String stranger = userId(guest());
        assertApi(() -> reservations.decide(stranger, s.matchId(), "confirm"), 404, null, null);
        assertApi(() -> reservations.decide(s.provider(), "mat_" + UUID.randomUUID(), "confirm"), 404, null, null);
        assertApi(() -> reservations.decide(s.provider(), "not-a-match", "confirm"), 404, null, null);
        assertApi(() -> reservations.decide(s.provider(), "mat_" + "x".repeat(70), "confirm"), 404, null, null);
        assertThat(reservationStatus(s.requestId())).isEqualTo("pending");
    }

    @Test void providerDecisionWithNoReservationForThatProviderIsNoReservation() throws Exception {
        var s = scene();
        assertApi(() -> reservations.decide(s.provider(), s.matchId(), "confirm"), 409, "match_id", "no_reservation");
        // The asker chose the other offer, which is not this provider's.
        select(s.owner(), s.requestId(), s.other().path("offer_id").asText()).andExpect(status().isOk());
        assertApi(() -> reservations.decide(s.provider(), s.matchId(), "confirm"), 409, "match_id", "no_reservation");
        assertThat(reservationStatus(s.requestId())).isEqualTo("pending");
    }

    // ---- 8. release ----------------------------------------------------------------------

    @Test void providerReleaseEndsTheReservationWithdrawsTheOfferAndReturnsToRanked() throws Exception {
        var s = scene();
        selectOk(s);
        CLOCK.now = START.plusSeconds(30);
        var first = reservations.decide(s.provider(), s.matchId(), "release");
        assertThat(reservations.decide(s.provider(), s.matchId(), "release")).isEqualTo(first);
        var resource = resource(s.owner(), s.requestId());
        assertThat(resource.path("status").asText()).isEqualTo("ranked");
        assertThat(resource.at("/reservation/status").asText()).isEqualTo("released");
        assertThat(instant(resource, "/reservation/ended_at")).isEqualTo(CLOCK.now);
        assertThat(resource.at("/reservation").has("confirmed_at")).isFalse();
        assertThat(resource.at("/progress/offers_ready").asInt()).isEqualTo(1);
        assertThat(offers(s.owner(), s.requestId()).findValuesAsText("offer_id"))
                .containsExactly(s.other().path("offer_id").asText());
        assertApi(() -> reservations.decide(s.provider(), s.matchId(), "confirm"), 409, "match_id", "reservation_closed");
    }

    @Test void providerReleaseWithNoOtherLiveOfferExpiresTheRequestAsNotConfirmed() throws Exception {
        var s = scene();
        selectOk(s);
        jdbc.update("DELETE FROM request_offers WHERE id=?", s.other().path("offer_id").asText());
        reservations.decide(s.provider(), s.matchId(), "release");
        var resource = resource(s.owner(), s.requestId());
        assertThat(resource.path("status").asText()).isEqualTo("expired");
        assertThat(resource.path("no_result_reason").asText()).isEqualTo("not_confirmed");
        assertThat(resource.path("next_action").asText()).isEqualTo("show_no_result");
        assertThat(reservationStatus(s.requestId())).isEqualTo("released");
    }

    // ---- 9. completion -------------------------------------------------------------------

    Instant confirmedScene(Scene s) throws Exception {
        selectOk(s);
        reservations.decide(s.provider(), s.matchId(), "confirm");
        return instant(s.offer(), "/available_at");
    }
    @Test void aConfirmedBookingCompletesThreeHoursAfterTheSlotViaTheWorker() throws Exception {
        var s = scene();
        Instant slot = confirmedScene(s);
        CLOCK.now = slot.plus(Duration.ofHours(3)).minusSeconds(1);
        service.workOnce();
        assertThat(jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, s.requestId())).isEqualTo("confirmed");
        CLOCK.now = slot.plus(Duration.ofHours(3));
        service.workOnce();
        assertThat(jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, s.requestId())).isEqualTo("completed");
    }
    @Test void aConfirmedBookingCompletesLazilyOnRead() throws Exception {
        var s = scene();
        Instant slot = confirmedScene(s);
        CLOCK.now = slot.plus(Duration.ofHours(3)).minusSeconds(1);
        assertThat(resource(s.owner(), s.requestId()).path("status").asText()).isEqualTo("confirmed");
        CLOCK.now = slot.plus(Duration.ofHours(3));
        var done = resource(s.owner(), s.requestId());
        assertThat(done.path("status").asText()).isEqualTo("completed");
        assertThat(done.path("next_action").asText()).isEqualTo("show_result");
    }
    @Test void aBookingCanceledBeforeCompletionStaysCanceled() throws Exception {
        var s = scene();
        Instant slot = confirmedScene(s);
        assertThat(json(cancel(s.owner(), s.requestId()).andExpect(status().isOk())).path("status").asText()).isEqualTo("canceled");
        CLOCK.now = slot.plus(Duration.ofHours(4));
        service.workOnce();
        assertThat(resource(s.owner(), s.requestId()).path("status").asText()).isEqualTo("canceled");
    }

    // ---- 10. cancel ----------------------------------------------------------------------

    @Test void cancelingWithAPendingReservationCancelsBoth() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        select(owner, id, offers(owner, id).get(0).path("offer_id").asText()).andExpect(status().isOk());
        CLOCK.now = START.plusSeconds(20);
        var canceled = json(cancel(owner, id).andExpect(status().isOk()));
        assertThat(canceled.path("status").asText()).isEqualTo("canceled");
        assertThat(canceled.at("/reservation/status").asText()).isEqualTo("canceled");
        assertThat(instant(canceled, "/reservation/ended_at")).isEqualTo(CLOCK.now);
        assertThat(canceled.at("/reservation").has("confirmed_at")).isFalse();
    }

    @Test void cancelingAConfirmedReservationDropsConfirmedAtAndSetsEndedAt() throws Exception {
        var s = scene();
        confirmedScene(s);
        CLOCK.now = START.plusSeconds(60);
        var canceled = json(cancel(s.owner(), s.requestId()).andExpect(status().isOk()));
        assertThat(canceled.at("/reservation/status").asText()).isEqualTo("canceled");
        assertThat(instant(canceled, "/reservation/ended_at")).isEqualTo(CLOCK.now);
        assertThat(canceled.at("/reservation").has("confirmed_at")).isFalse();
        assertThat(ts("SELECT confirmed_at FROM request_reservations WHERE request_id=?", s.requestId()))
                .as("the stored row follows the contract too").isNull();
    }

    // ---- 11. authorization and limits ----------------------------------------------------

    @Test void selectWithoutASessionIsUnauthenticated() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        post(null, "/v1/requests/" + id + "/select", offerBody(offers(owner, id).get(0).path("offer_id").asText()), newKey())
                .andExpect(status().isUnauthorized());
        assertThat(resource(owner, id).path("status").asText()).isEqualTo("ranked");
    }

    @Test void anotherUsersOrMalformedRequestIdIsNotFound() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        String offer = offers(owner, id).get(0).path("offer_id").asText();
        errorOf(select(guest(), id, offer), 404);
        errorOf(select(owner, "not-a-request", offer), 404);
        errorOf(select(owner, "req_" + UUID.randomUUID(), offer), 404);
        assertThat(resource(owner, id).path("status").asText()).isEqualTo("ranked");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM request_reservations WHERE request_id=?", Integer.class, id)).isZero();
    }

    @Test void theEleventhSelectAttemptInAWindowIsRateLimitedWithRetryAfter() throws Exception {
        var owner = guest();
        String id = rankedRequest(owner);
        for (int n = 0; n < 10; n++) {
            assertDetail(errorOf(select(owner, id, "off_" + UUID.randomUUID()), 409), "offer_id", "offer_unavailable");
        }
        var result = select(owner, id, "off_" + UUID.randomUUID());
        result.andExpect(status().isTooManyRequests()).andExpect(header().exists("Retry-After"));
        var error = json(result).get("error");
        assertThat(error.path("code").asText()).isEqualTo("rate_limited");
        assertThat(error.path("retry_after_seconds").asInt()).isPositive();
    }
}
