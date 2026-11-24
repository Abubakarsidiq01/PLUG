package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.test.context.ActiveProfiles;

/// P3.S15, owner decision 2026-11-23: the best 6 at t0, 4 more at t+120s and 4 more at t+240s while
/// the request has fewer than 2 live offers (manual v4 SupplierMatcher), no new wave from t+300s,
/// at most 14 contacts per request, and every contact keeps a full 5-minute reply window.
@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.provider-inbox.enabled=true", "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(FanOutPolicyTest.TimeConfiguration.class)
class FanOutPolicyTest extends FanOutSupport {
    static final Instant START = ReservationTest.START;
    static final ReservationTest.MutableClock CLOCK = new ReservationTest.MutableClock();

    @TestConfiguration static class TimeConfiguration {
        @Bean @Primary RequestClock mutableRequestClock() { return new RequestClock(CLOCK); }
    }

    @BeforeEach void resetClock() { CLOCK.now = START; }

    /// One worker pass at t0 + seconds.
    void at(int seconds) {
        CLOCK.now = START.plusSeconds(seconds);
        service.workOnce();
    }
    /// Asked at t0 and worked to awaiting_responses: wave 1 has run.
    String routed(JsonNode asker) throws Exception {
        String id = ask(asker);
        at(0);
        at(0);
        at(0);
        return id;
    }
    void declineAll(String requestId, int seconds) {
        Timestamp at = Timestamp.from(START.plusSeconds(seconds));
        jdbc.update("UPDATE request_matches SET replied_at=?,declined_at=? WHERE request_id=? AND replied_at IS NULL", at, at, requestId);
    }
    void offer(JsonNode provider, String requestId) throws Exception {
        post(provider, "/v1/requests/" + requestId + "/offers", "{\"price_cents\":3000,\"currency\":\"USD\",\"available_at\":\""
                + START.plus(Duration.ofMinutes(20)) + "\"}").andExpect(status().isCreated());
    }

    @Test void theFirstWaveContactsOnlyTheBestSix() throws Exception {
        assertThat(MatchService.INITIAL_FANOUT).isEqualTo(6);
        var providers = providers(8);
        String id = routed(guest());
        assertThat(contacted(id)).containsExactlyElementsOf(ids(providers).subList(0, 6));
        assertThat(contactedInWave(id, 1)).hasSize(6);
        assertThat(notifiedAt(id, 1)).containsOnly(START);
        assertThat(requestStatus(id)).isEqualTo("awaiting_responses");
    }

    @Test void withoutOffersFourMoreAtTwoMinutesAndFourAtFourThenNoneAndNeverMoreThanFourteen() throws Exception {
        assertThat(MatchService.ABSOLUTE_CAP).isEqualTo(14);
        var providers = providers(18);
        String id = routed(guest());
        at(119);
        assertThat(contacted(id)).hasSize(6);
        at(120);
        assertThat(contactedInWave(id, 2)).containsExactlyElementsOf(ids(providers).subList(6, 10));
        assertThat(notifiedAt(id, 2)).containsOnly(START.plusSeconds(120));
        at(121);
        at(239);
        assertThat(contacted(id)).hasSize(10);
        at(240);
        assertThat(contactedInWave(id, 3)).containsExactlyElementsOf(ids(providers).subList(10, 14));
        assertThat(notifiedAt(id, 3)).containsOnly(START.plusSeconds(240));
        for (int seconds : new int[] {241, 299, 300, 360, 600}) at(seconds);
        assertThat(contacted(id)).containsExactlyElementsOf(ids(providers).subList(0, 14));
    }

    @Test void noNewWaveStartsAtOrAfterFiveMinutes() throws Exception {
        providers(18);
        String id = routed(guest());
        // The worker was away for both expansion slots: nothing is caught up late.
        at(300);
        at(420);
        assertThat(contacted(id)).hasSize(6);
    }

    @Test void eachContactKeepsAFullFiveMinuteReplyWindowEvenPastTheStop() throws Exception {
        providers(14);
        String id = routed(guest());
        at(120);
        at(240);
        var rows = jdbc.queryForList("SELECT provider_id,match_id,notified_at FROM request_matches WHERE request_id=?", id);
        assertThat(rows).hasSize(14);
        for (var row : rows) {
            var item = service.inboxItem((String) row.get("provider_id"), (String) row.get("match_id"));
            assertThat(item.respondBy()).isEqualTo(((Timestamp) row.get("notified_at")).toInstant().plus(Duration.ofMinutes(5)));
        }
        // A wave-three contact is still open at t+500s, after the t+300s stop, until t+540s.
        String late = contactedInWave(id, 3).getFirst();
        String matchId = jdbc.queryForObject("SELECT match_id FROM request_matches WHERE request_id=? AND provider_id=?",
                String.class, id, late);
        CLOCK.now = START.plusSeconds(500);
        var item = service.inboxItem(late, matchId);
        assertThat(item.status()).isEqualTo("open");
        assertThat(item.respondBy()).isEqualTo(START.plusSeconds(540));
    }

    @Test void twoLiveOffersStopTheExpansionAndOneDoesNot() throws Exception {
        var providers = providers(18);
        JsonNode asker = guest();
        String single = routed(asker);
        String enough = routed(asker);
        offer(providers.get(0), single);
        offer(providers.get(0), enough);
        offer(providers.get(1), enough);
        at(1);
        assertThat(requestStatus(single)).isEqualTo("ranked");
        assertThat(requestStatus(enough)).isEqualTo("ranked");
        at(120);
        at(240);
        assertThat(contacted(single)).hasSize(14);
        assertThat(contacted(enough)).containsExactlyElementsOf(ids(providers).subList(0, 6));
    }

    @Test void anHourlyCappedProviderIsSkippedAndTheNextBestIsContactedInEveryWave() throws Exception {
        var providers = providers(8);
        JsonNode asker = guest();
        String best = userId(providers.get(0));
        for (int n = 0; n < MatchService.NOTIFICATIONS_PER_HOUR; n++) {
            seedMatch(seedRequest(userId(asker), "expired", START.minus(Duration.ofMinutes(20))), best, START.minus(Duration.ofMinutes(10)));
        }
        String id = routed(asker);
        assertThat(contacted(id)).containsExactlyElementsOf(ids(providers).subList(1, 7));
        at(120);
        assertThat(contacted(id)).containsExactlyElementsOf(ids(providers).subList(1, 8)).doesNotContain(best);
    }

    @Test void suspendedAndNotAcceptingProvidersAreNeverContactedInAnyWave() throws Exception {
        var providers = providers(16);
        jdbc.update("UPDATE provider_profiles SET standing='suspended',accepting=false WHERE user_id=?", userId(providers.get(0)));
        jdbc.update("UPDATE provider_profiles SET accepting=false WHERE user_id=?", userId(providers.get(1)));
        String id = routed(guest());
        at(120);
        at(240);
        assertThat(contacted(id)).containsExactlyElementsOf(ids(providers).subList(2, 16));
    }

    @Test void everyContactOnTheRequestCountsTowardTheCombinedCeiling() throws Exception {
        // SMS outreach is not built yet (P3.S4's SMS fan-out waits for funding). Six more contact
        // rows on the request stand in for contacts already made: the next wave fills only to 14.
        var providers = providers(18);
        String id = routed(guest());
        for (int n = 12; n < 18; n++) seedMatch(id, userId(providers.get(n)), START);
        at(120);
        assertThat(contactedInWave(id, 2)).containsExactlyElementsOf(ids(providers).subList(6, 8));
        at(240);
        assertThat(contacted(id)).hasSize(14);
        assertThat(contactedInWave(id, 3)).isEmpty();
    }

    @Test void everyoneDecliningEarlyStillGetsTheLaterWavesThenAnHonestNoResult() throws Exception {
        providers(14);
        String id = routed(guest());
        declineAll(id, 60);
        at(60);
        assertThat(requestStatus(id)).isEqualTo("awaiting_responses");
        at(120);
        assertThat(contacted(id)).hasSize(10);
        declineAll(id, 150);
        at(150);
        assertThat(requestStatus(id)).isEqualTo("awaiting_responses");
        at(240);
        declineAll(id, 250);
        at(250);
        assertThat(requestStatus(id)).isEqualTo("expired");
        assertThat(jdbc.queryForObject("SELECT no_result_reason FROM requests WHERE id=?", String.class, id)).isEqualTo("no_offers");
    }

    @Test void withNoOneLeftToContactTheRequestEndsAtTheFiveMinuteStop() throws Exception {
        providers(6);
        String id = routed(guest());
        declineAll(id, 30);
        at(30);
        at(120);
        at(240);
        at(299);
        assertThat(requestStatus(id)).isEqualTo("awaiting_responses");
        at(300);
        assertThat(requestStatus(id)).isEqualTo("expired");
        assertThat(contacted(id)).hasSize(6);
    }

    @Test void aBlockedRequestNeverFansOut() throws Exception {
        providers(6);
        JsonNode asker = guest();
        String id = seedRequest(userId(asker), "blocked", START);
        for (int seconds : new int[] {0, 120, 240}) at(seconds);
        assertThat(contacted(id)).isEmpty();
        assertThat(List.of(requestStatus(id))).containsExactly("blocked");
    }
}
