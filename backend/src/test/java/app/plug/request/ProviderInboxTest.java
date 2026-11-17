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
import java.util.HashMap;
import java.util.List;
import java.util.Map;
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
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/// P3.S10: the provider inbox (contract 0.7.1 getProviderInbox, ProviderInbox, InboxItem,
/// MatchStatus), the hourly notification cap (CHANGELOG 0.7.0: a match over the cap is not made,
/// 4 per hour) and registerDevice, which is 503 until an Apple Developer team is configured.
@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.provider-inbox.enabled=true", "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(ProviderInboxTest.TimeConfiguration.class)
class ProviderInboxTest {
    static final Instant START = ReservationTest.START;
    static final ReservationTest.MutableClock CLOCK = new ReservationTest.MutableClock();
    /// Far from the seeded suppliers and every other suite's providers, so only this test's provider matches.
    static final String FAR = "{\"latitude\":45.0,\"longitude\":-100.0,\"precision\":\"coarse\"}";

    @TestConfiguration static class TimeConfiguration {
        @Bean @Primary RequestClock mutableRequestClock() { return new RequestClock(CLOCK); }
    }

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    @Autowired RequestService service;
    @Autowired MatchService matches;
    @Autowired ReservationService reservations;
    @Autowired PlatformTransactionManager transactions;
    private final List<String> users = new ArrayList<>();

    @BeforeEach void resetClock() { CLOCK.now = START; }

    @AfterEach void removeOnlyThisTestsRecords() {
        new TransactionTemplate(transactions).executeWithoutResult(ignored -> {
            for (String user : users) {
                jdbc.update("DELETE FROM request_reservations WHERE request_id IN (SELECT id FROM requests WHERE user_id=?)", user);
                jdbc.update("DELETE FROM asks WHERE user_id=?", user);
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
    ResultActions post(JsonNode who, String path, String body, boolean keyed) throws Exception {
        var request = MockMvcRequestBuilders.post(path).with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .contentType(MediaType.APPLICATION_JSON).content(body);
        if (who != null) request.header("Authorization", "Bearer " + who.get("access_token").asText());
        if (keyed) request.header("Idempotency-Key", "inbox-test-" + UUID.randomUUID());
        return mvc.perform(request);
    }
    ResultActions inbox(JsonNode who) throws Exception {
        var request = MockMvcRequestBuilders.get("/v1/providers/me/inbox").with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; });
        if (who != null) request.header("Authorization", "Bearer " + who.get("access_token").asText());
        return mvc.perform(request);
    }
    JsonNode json(ResultActions result) throws Exception {
        JsonNode body = mapper.readTree(result.andReturn().getResponse().getContentAsString());
        ContractSchemas.validate(body.has("error") ? "Error" : body.has("items") ? "ProviderInbox"
                : body.has("offers") ? "OfferList" : "RequestResource", body);
        return body;
    }
    JsonNode inboxOk(JsonNode who) throws Exception { return json(inbox(who).andExpect(status().isOk())); }
    void provide(JsonNode who, String location) throws Exception {
        post(who, "/v1/providers/skills", "{\"skill_tags\":[\"barber\"],\"travel_radius_m\":4828,\"base_location\":" + location
                + ",\"availability\":[{\"days\":\"every_day\",\"from\":\"09:00\",\"to\":\"24:00\"}],"
                + "\"time_zone\":\"America/Chicago\"}", false).andExpect(status().isOk());
    }
    String createRequest(JsonNode owner, String location) throws Exception {
        return json(post(owner, "/v1/requests", "{\"text\":\"Barber under $35 in 30 minutes\",\"location\":" + location + "}", true)
                .andExpect(status().isCreated())).path("request_id").asText();
    }
    int matchesFor(String provider) {
        return jdbc.queryForObject("SELECT count(*) FROM request_matches WHERE provider_id=?", Integer.class, provider);
    }
    int notify(String requestId) {
        Integer notified = new TransactionTemplate(transactions).execute(ignored -> matches.notify(service.read(requestId)));
        return notified;
    }
    /// A request written straight to the tables, for inbox states that need no offers.
    String seedRequest(String owner, String state, Instant updatedAt) {
        String id = "req_" + UUID.randomUUID();
        jdbc.update("INSERT INTO requests(id,user_id,text,status,created_at,updated_at,expires_at) VALUES(?,?,?,?,?,?,?)",
                id, owner, "Barber near the market at noon", state, Timestamp.from(START.minus(Duration.ofDays(9))),
                Timestamp.from(updatedAt), Timestamp.from(START.plus(Duration.ofHours(1))));
        jdbc.update("INSERT INTO request_constraints(request_id,category,service_name,skill_tags,licence_required,budget_cents,"
                + "currency,needed_by,max_distance_m,latitude,longitude,precision) VALUES(?,'barber','Haircut',ARRAY['barber'],false,"
                + "3500,'USD',NULL,4828,32.528,-92.714,'coarse')", id);
        return id;
    }
    String seedMatch(String requestId, String provider, Instant notifiedAt, int distance) {
        String matchId = "mat_" + UUID.randomUUID();
        jdbc.update("INSERT INTO request_matches(request_id,provider_id,distance_m,rank_score,notified_at,match_id) VALUES(?,?,?,?,?,?)",
                requestId, provider, distance, 50, Timestamp.from(notifiedAt), matchId);
        return matchId;
    }
    /// A request worked through the real flow until it is ranked with two seed offers.
    String rankedRequest(JsonNode owner) throws Exception {
        String id = createRequest(owner, ReservationTest.HERE);
        for (int n = 0; n < 5; n++) service.workOnce();
        return id;
    }
    List<String> offerIds(JsonNode owner, String requestId) throws Exception {
        var offers = json(mvc.perform(MockMvcRequestBuilders.get("/v1/requests/" + requestId + "/offers")
                .with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .header("Authorization", "Bearer " + owner.get("access_token").asText())).andExpect(status().isOk())).get("offers");
        assertThat(offers.size()).isEqualTo(2);
        return List.of(offers.get(0).path("offer_id").asText(), offers.get(1).path("offer_id").asText());
    }
    void select(JsonNode owner, String requestId, String offerId) throws Exception {
        post(owner, "/v1/requests/" + requestId + "/select", "{\"offer_id\":\"" + offerId + "\"}", true).andExpect(status().isOk());
    }

    // ---- 1. hourly notification cap ------------------------------------------------------

    @Test void manySimultaneousAsksNotifyOneProviderAtMostFourTimesAnHourAndAgainTheNextHour() throws Exception {
        assertThat(MatchService.NOTIFICATIONS_PER_HOUR).isEqualTo(4);
        var provider = guest();
        provide(provider, FAR);
        var asker = guest();
        List<String> ids = new ArrayList<>();
        for (int n = 0; n < 6; n++) ids.add(createRequest(asker, FAR));
        var pool = Executors.newFixedThreadPool(ids.size());
        var start = new CountDownLatch(1);
        try {
            List<Future<Integer>> runs = new ArrayList<>();
            for (String id : ids) {
                runs.add(pool.submit(() -> {
                    start.await();
                    return notify(id);
                }));
            }
            start.countDown();
            for (var run : runs) run.get();
        } finally {
            pool.shutdownNow();
        }
        assertThat(matchesFor(userId(provider))).isEqualTo(4);
        // The fifth and sixth asks did not match them, and asking again in the same hour does not either.
        String sameHour = createRequest(asker, FAR);
        CLOCK.now = START.plus(Duration.ofMinutes(59));
        assertThat(notify(sameHour)).isZero();
        // Once the first notifications are an hour old, the provider can be matched again.
        CLOCK.now = START.plus(Duration.ofMinutes(61));
        String nextHour = createRequest(asker, FAR);
        assertThat(notify(nextHour)).isEqualTo(1);
        assertThat(matchesFor(userId(provider))).isEqualTo(5);
        assertThat(inboxOk(provider).path("notifications_per_hour").asInt()).isEqualTo(4);
    }

    // ---- 2. a refused or restricted ask is never matched ---------------------------------

    @Test void aRefusedOrRestrictedAskCreatesNoMatchRowAndNoInboxItem() throws Exception {
        var provider = guest();
        provide(provider, FAR);
        var asker = guest();
        post(asker, "/v1/asks", "{\"text\":\"Barber who will sell me weed\",\"location\":" + FAR + "}", true)
                .andExpect(status().isUnprocessableEntity());
        post(asker, "/v1/requests", "{\"text\":\"Barber who will sell me weed\",\"location\":" + FAR + "}", true)
                .andExpect(status().isUnprocessableEntity());
        post(asker, "/v1/requests", "{\"text\":\"Barber to track my ex girlfriend's phone\",\"location\":" + FAR + "}", true)
                .andExpect(status().isUnprocessableEntity());
        for (int n = 0; n < 3; n++) service.workOnce();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM requests WHERE user_id=?", Integer.class, userId(asker))).isZero();
        assertThat(matchesFor(userId(provider))).isZero();
        assertThat(inboxOk(provider).get("items").size()).isZero();
    }

    // ---- 3. the inbox: statuses, order, window, limit ------------------------------------

    @Test void theInboxShowsOpenItemsFirstThenTheLastSevenDaysWithEveryStatusAndNothingAboutTheAsker() throws Exception {
        var offeredOwner = guest();
        var selectedOwner = guest();
        var confirmedOwner = guest();
        var notChosenOwner = guest();
        String offered = rankedRequest(offeredOwner);
        String selected = rankedRequest(selectedOwner);
        String confirmed = rankedRequest(confirmedOwner);
        String notChosen = rankedRequest(notChosenOwner);
        // The provider signs up after matching ran, so every match below is placed by the test.
        var provider = guest();
        String me = userId(provider);
        provide(provider, ReservationTest.HERE);
        var asker = guest();
        String owner = userId(asker);
        Map<String, String> expected = new HashMap<>();
        String offeredOffer = offerIds(offeredOwner, offered).get(0);
        jdbc.update("UPDATE request_offers SET provider_id=? WHERE id=?", me, offeredOffer);
        expected.put(seedMatch(offered, me, START, 149), "offered");
        List<String> selectedOffers = offerIds(selectedOwner, selected);
        jdbc.update("UPDATE request_offers SET provider_id=? WHERE id=?", me, selectedOffers.get(0));
        expected.put(seedMatch(selected, me, START, 900), "selected");
        select(selectedOwner, selected, selectedOffers.get(0));
        List<String> confirmedOffers = offerIds(confirmedOwner, confirmed);
        jdbc.update("UPDATE request_offers SET provider_id=? WHERE id=?", me, confirmedOffers.get(0));
        String confirmedMatch = seedMatch(confirmed, me, START, 900);
        expected.put(confirmedMatch, "confirmed");
        select(confirmedOwner, confirmed, confirmedOffers.get(0));
        reservations.decide(me, confirmedMatch, "confirm");
        List<String> notChosenOffers = offerIds(notChosenOwner, notChosen);
        jdbc.update("UPDATE request_offers SET provider_id=? WHERE id=?", me, notChosenOffers.get(0));
        expected.put(seedMatch(notChosen, me, START, 900), "not_chosen");
        select(notChosenOwner, notChosen, notChosenOffers.get(1));
        String open = seedMatch(seedRequest(owner, "awaiting_responses", START), me, START.minus(Duration.ofMinutes(1)), 900);
        expected.put(open, "open");
        // Canceled two minutes in, before the five-minute reply window ended: closed, not silence.
        expected.put(seedMatch(seedRequest(owner, "canceled", START.minus(Duration.ofMinutes(1))), me,
                START.minus(Duration.ofMinutes(3)), 900), "closed");
        expected.put(seedMatch(seedRequest(owner, "ranked", START), me, START.minus(Duration.ofMinutes(10)), 900), "expired");
        // The request expired long after the window: the provider's silence is still expired.
        expected.put(seedMatch(seedRequest(owner, "expired", START), me, START.minus(Duration.ofHours(2)), 900), "expired");
        String old = seedMatch(seedRequest(owner, "expired", START.minus(Duration.ofDays(8))), me, START.minus(Duration.ofDays(8)), 900);

        JsonNode body = inboxOk(provider);
        assertThat(body.path("notifications_per_hour").asInt()).isEqualTo(4);
        JsonNode items = body.get("items");
        Map<String, String> seen = new HashMap<>();
        for (JsonNode item : items) seen.put(item.path("match_id").asText(), item.path("status").asText());
        assertThat(seen).isEqualTo(expected).doesNotContainKey(old);
        // Open first even though newer items exist, then newest first.
        assertThat(items.get(0).path("match_id").asText()).isEqualTo(open);
        for (int n = 2; n < items.size(); n++) {
            assertThat(Instant.parse(items.get(n).path("notified_at").asText()))
                    .isBeforeOrEqualTo(Instant.parse(items.get(n - 1).path("notified_at").asText()));
        }
        for (JsonNode item : items) {
            assertThat(Instant.parse(item.path("respond_by").asText()))
                    .isEqualTo(Instant.parse(item.path("notified_at").asText()).plus(Duration.ofMinutes(5)));
            String status = item.path("status").asText();
            assertThat(item.has("offer")).isEqualTo(List.of("offered", "selected", "confirmed", "not_chosen").contains(status));
            assertThat(item.has("reservation")).isEqualTo(List.of("selected", "confirmed").contains(status));
            if (item.path("request_id").asText().equals(offered)) assertThat(item.path("distance_m").asInt()).isEqualTo(100);
        }
        // Nothing about the asker: not their words, their account or where they are.
        String raw = body.toString();
        for (String asked : List.of(owner, userId(offeredOwner), userId(selectedOwner), "Barber under", "near the market", "32.528")) {
            assertThat(raw).doesNotContain(asked);
        }
    }

    @Test void theInboxHoldsAtMostFiftyItemsAndNeverAnotherProvidersMatches() throws Exception {
        var provider = guest();
        provide(provider, FAR);
        var other = guest();
        provide(other, FAR);
        String owner = userId(guest());
        for (int n = 0; n < 55; n++) {
            seedMatch(seedRequest(owner, "expired", START), userId(provider), START.minus(Duration.ofMinutes(10 + n)), 900);
        }
        String theirs = seedMatch(seedRequest(owner, "awaiting_responses", START), userId(other), START, 900);
        JsonNode items = inboxOk(provider).get("items");
        assertThat(items.size()).isEqualTo(50);
        assertThat(Instant.parse(items.get(0).path("notified_at").asText())).isEqualTo(START.minus(Duration.ofMinutes(10)));
        for (JsonNode item : items) assertThat(item.path("match_id").asText()).isNotEqualTo(theirs);
        JsonNode otherItems = inboxOk(other).get("items");
        assertThat(otherItems.size()).isEqualTo(1);
        assertThat(otherItems.get(0).path("match_id").asText()).isEqualTo(theirs);
    }

    // ---- 4. inbox authorization and limits -----------------------------------------------

    @Test void theInboxNeedsASessionAndAProviderProfile() throws Exception {
        assertThat(json(inbox(null).andExpect(status().isUnauthorized())).at("/error/code").asText()).isEqualTo("unauthenticated");
        assertThat(json(inbox(guest()).andExpect(status().isNotFound())).at("/error/code").asText()).isEqualTo("not_found");
    }

    @Test void theInboxIsRateLimitedPerCallerWithRetryAfter() throws Exception {
        var provider = guest();
        provide(provider, FAR);
        for (int n = 0; n < 30; n++) inbox(provider).andExpect(status().isOk());
        var limited = inbox(provider).andExpect(status().isTooManyRequests()).andExpect(header().exists("Retry-After"));
        assertThat(json(limited).at("/error/code").asText()).isEqualTo("rate_limited");
    }

    // ---- 5. device registration ----------------------------------------------------------

    static final String TOKEN = "a".repeat(64);

    @Test void deviceRegistrationValidatesThenSaysPushIsUnavailable() throws Exception {
        var who = guest();
        for (String bad : List.of("{}", "{\"apns_token\":\"" + "a".repeat(63) + "\",\"environment\":\"sandbox\"}",
                "{\"apns_token\":\"" + "a".repeat(201) + "\",\"environment\":\"sandbox\"}",
                "{\"apns_token\":\"" + "A".repeat(64) + "\",\"environment\":\"sandbox\"}",
                "{\"apns_token\":\"" + TOKEN + "\",\"environment\":\"staging\"}",
                "{\"apns_token\":\"" + TOKEN + "\"}",
                "{\"apns_token\":\"" + TOKEN + "\",\"environment\":\"sandbox\",\"user_id\":\"x\"}", "[]")) {
            assertThat(json(post(who, "/v1/me/devices", bad, false).andExpect(status().isBadRequest())).at("/error/code").asText())
                    .isEqualTo("validation_failed");
        }
        post(null, "/v1/me/devices", "{\"apns_token\":\"" + TOKEN + "\",\"environment\":\"sandbox\"}", false)
                .andExpect(status().isUnauthorized());
        for (String environment : List.of("sandbox", "production")) {
            var unavailable = post(who, "/v1/me/devices", "{\"apns_token\":\"" + TOKEN + "\",\"environment\":\"" + environment + "\"}", false)
                    .andExpect(status().isServiceUnavailable());
            assertThat(json(unavailable).at("/error/code").asText()).isEqualTo("dependency_unavailable");
        }
    }
}
