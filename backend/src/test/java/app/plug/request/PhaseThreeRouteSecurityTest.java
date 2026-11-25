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
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.logging.LogLevel;
import org.springframework.boot.logging.LoggingSystem;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
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

/// P3.S8 rolling security: the Phase 3 routes not yet covered by their own suites. Device
/// registration and the provider profile read have limits and a session check; the two admin provider
/// routes have a per-staff limit (30 a minute to list, 10 a minute to set standing); and a whole
/// Phase 3 scene leaves no secret, token, ask text, note, reason, coordinate, booking reference or raw
/// account id in the log, even with framework logging at DEBUG.
@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.provider-inbox.enabled=true", "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@ExtendWith(OutputCaptureExtension.class)
@Import(PhaseThreeRouteSecurityTest.TimeConfiguration.class)
class PhaseThreeRouteSecurityTest {
    static final Instant START = ReservationTest.START;
    static final ReservationTest.MutableClock CLOCK = new ReservationTest.MutableClock();
    static final String BASE = ProviderOfferTest.BASE;
    static final String NEAR = ProviderOfferTest.NEAR;
    static final String DEVICE = "{\"apns_token\":\"" + "a".repeat(64) + "\",\"environment\":\"sandbox\"}";
    // The stub intent reads "Barber under $35 in 30 minutes"; the tail is the marker the log must not hold.
    static final String ASK_TEXT = "Barber under $35 in 30 minutes zebraquartz";
    // Spring cuts a logged body at about 100 characters, so the marker sits at the start of the note.
    static final String NOTE = "Quillfern chairs open, fades and line-ups.";
    static final String SCENE_TOKEN = "5eed".repeat(16);
    static final String REASON = "Crimson ledger mismatch noted.";

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
    MockHttpServletRequestBuilder from(String address, JsonNode who, MockHttpServletRequestBuilder request) {
        request.with(r -> { r.setRemoteAddr(address); return r; });
        if (who != null) request.header("Authorization", "Bearer " + who.get("access_token").asText());
        return request;
    }
    ResultActions post(JsonNode who, String path, String body, String key) throws Exception {
        var request = from(UUID.randomUUID().toString(), who, MockMvcRequestBuilders.post(path));
        if (body != null) request.contentType(MediaType.APPLICATION_JSON).content(body);
        if (key != null) request.header("Idempotency-Key", key);
        return mvc.perform(request);
    }
    ResultActions get(JsonNode who, String path) throws Exception {
        return mvc.perform(from(UUID.randomUUID().toString(), who, MockMvcRequestBuilders.get(path)));
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
    void assertRateLimited(ResultActions result) throws Exception {
        result.andExpect(status().isTooManyRequests()).andExpect(header().exists("Retry-After"));
        assertThat(json(result, "Error").at("/error/code").asText()).isEqualTo("rate_limited");
    }
    String key() { return "route-security-" + UUID.randomUUID(); }
    String quote(String text) {
        try { return mapper.writeValueAsString(text); } catch (Exception e) { throw new RuntimeException(e); }
    }
    void provide(JsonNode who) throws Exception {
        post(who, "/v1/providers/skills", "{\"skill_tags\":[\"barber\"],\"travel_radius_m\":4828,\"base_location\":" + BASE
                + ",\"availability\":[{\"days\":\"every_day\",\"from\":\"00:00\",\"to\":\"24:00\"}],"
                + "\"time_zone\":\"America/Chicago\",\"business\":{\"name\":\"Fresh Line Studio\"}}", null).andExpect(status().isOk());
    }
    String matchId(String requestId, JsonNode provider) {
        return jdbc.queryForObject("SELECT match_id FROM request_matches WHERE request_id=? AND provider_id=?", String.class,
                requestId, userId(provider));
    }
    PlugPrincipal owner() {
        String id = "usr_staff-" + UUID.randomUUID();
        jdbc.update("INSERT INTO users(id,account_type) VALUES(?,'staff')", id);
        jdbc.update("INSERT INTO staff_accounts(user_id,email,password_hash,role) VALUES(?,?,'not-a-real-hash','owner')", id,
                id.substring(4, 24).toLowerCase() + "@example.com");
        staff.add(id);
        return new PlugPrincipal(id, "ses_staff", Set.of(PlugPrincipal.SCOPE_ADMIN), true);
    }
    ResultActions asStaff(PlugPrincipal principal, MockHttpServletRequestBuilder request) throws Exception {
        return mvc.perform(request.with(authentication(new UsernamePasswordAuthenticationToken(principal, null, List.of()))));
    }
    ResultActions standing(PlugPrincipal staffMember, String userId, String reason) throws Exception {
        return asStaff(staffMember, MockMvcRequestBuilders.post("/v1/admin/providers/" + userId + "/standing")
                .contentType(MediaType.APPLICATION_JSON).content("{\"standing\":\"suspended\",\"reason\":" + quote(reason) + "}"));
    }

    // ---- 1. device registration: per-user limit ------------------------------------------

    @Test void theEleventhDeviceRegistrationInAWindowFromOneUserIsRateLimitedWithRetryAfter() throws Exception {
        var who = guest();
        for (int n = 0; n < 10; n++) {
            // Push is not configured, so a valid call is dependency_unavailable, never rate_limited.
            assertThat(errorOf(post(who, "/v1/me/devices", DEVICE, null), 503).get("code").asText()).isEqualTo("dependency_unavailable");
        }
        assertRateLimited(post(who, "/v1/me/devices", DEVICE, null));
        // The limit is per user: another user is not held back by this one.
        errorOf(post(guest(), "/v1/me/devices", DEVICE, null), 503);
    }

    // ---- 2. provider profile read: session and IP read budget ----------------------------

    @Test void theProviderProfileReadNeedsASessionAndIsRateLimitedPastTheIpReadBudget() throws Exception {
        get(null, "/v1/providers/me").andExpect(status().isUnauthorized());
        var provider = guest();
        provide(provider);
        String address = UUID.randomUUID().toString();
        // plug.requests-per-minute is 60 and the filter counts every call from one address, signed in or not.
        for (int n = 0; n < 60; n++) {
            mvc.perform(from(address, provider, MockMvcRequestBuilders.get("/v1/providers/me"))).andExpect(status().isOk());
        }
        assertRateLimited(mvc.perform(from(address, provider, MockMvcRequestBuilders.get("/v1/providers/me"))));
    }

    // ---- 3 and 4. admin provider routes: per-staff limits --------------------------------

    @Test void theThirtyFirstAdminProviderListInAWindowFromOneStaffMemberIsRateLimitedWithRetryAfter() throws Exception {
        var staffMember = owner();
        for (int n = 0; n < 30; n++) {
            asStaff(staffMember, MockMvcRequestBuilders.get("/v1/admin/providers?limit=1")).andExpect(status().isOk());
        }
        assertRateLimited(asStaff(staffMember, MockMvcRequestBuilders.get("/v1/admin/providers?limit=1")));
        // The limit is per staff member: a second owner is not held back.
        asStaff(owner(), MockMvcRequestBuilders.get("/v1/admin/providers?limit=1")).andExpect(status().isOk());
    }

    @Test void theEleventhStandingChangeInAWindowFromOneStaffMemberIsRateLimitedWithRetryAfter() throws Exception {
        var staffMember = owner();
        String unknown = "usr_" + UUID.randomUUID();
        for (int n = 0; n < 10; n++) {
            // An unknown provider is 404; the point is that the first ten are answered, not limited.
            errorOf(standing(staffMember, unknown, "Under review."), 404);
        }
        assertRateLimited(standing(staffMember, unknown, "Under review."));
    }

    // ---- 5. a whole Phase 3 scene leaves nothing sensitive in the log --------------------

    @Test void aFullPhaseThreeSceneLeavesNoTokenAskTextNoteReasonCoordinateBookingReferenceOrAccountIdInTheLog(CapturedOutput output)
            throws Exception {
        String logger = "org.springframework.web";
        var logging = LoggingSystem.get(getClass().getClassLoader());
        var previous = logging.getLoggerConfiguration(logger).getConfiguredLevel();
        logging.setLogLevel(logger, LogLevel.DEBUG);
        try {
            var provider = guest();
            provide(provider);
            var second = guest();
            provide(second);
            var asker = guest();
            String requestId = json(post(asker, "/v1/requests", "{\"text\":" + quote(ASK_TEXT) + ",\"location\":" + NEAR + "}", key())
                    .andExpect(status().isCreated()), "RequestResource").path("request_id").asText();
            for (int n = 0; n < 3; n++) service.workOnce();
            assertThat(jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, requestId))
                    .isEqualTo("awaiting_responses");
            get(provider, "/v1/providers/me/inbox").andExpect(status().isOk());
            String offerId = json(post(provider, "/v1/requests/" + requestId + "/offers", "{\"price_cents\":3000,\"currency\":\"USD\","
                    + "\"available_at\":\"" + START.plus(Duration.ofMinutes(20)) + "\",\"note\":" + quote(NOTE) + "}", key())
                    .andExpect(status().isCreated()), "Offer").path("offer_id").asText();
            post(second, "/v1/providers/me/inbox/" + matchId(requestId, second) + "/decline", "{\"reason\":\"busy\"}", null)
                    .andExpect(status().isOk());
            service.workOnce();
            JsonNode selected = json(post(asker, "/v1/requests/" + requestId + "/select", "{\"offer_id\":\"" + offerId + "\"}", key())
                    .andExpect(status().isOk()), "RequestResource");
            String bookingRef = selected.at("/reservation/booking_ref").asText();
            assertThat(bookingRef).isNotBlank();
            post(provider, "/v1/providers/me/inbox/" + matchId(requestId, provider) + "/reservation", "{\"decision\":\"confirm\"}", null)
                    .andExpect(status().isOk());
            var admin = owner();
            asStaff(admin, MockMvcRequestBuilders.get("/v1/admin/providers")).andExpect(status().isOk());
            // At least two providers exist, so one row a page leaves a cursor; it encodes a time and an id.
            String cursor = json(asStaff(admin, MockMvcRequestBuilders.get("/v1/admin/providers?limit=1"))
                    .andExpect(status().isOk()), "AdminProviderPage").path("next_cursor").asText();
            assertThat(cursor).isNotBlank();
            standing(admin, userId(second), REASON).andExpect(status().isOk());
            // Push is not configured, so a valid registration is dependency_unavailable.
            assertThat(errorOf(post(provider, "/v1/me/devices",
                    "{\"apns_token\":\"" + SCENE_TOKEN + "\",\"environment\":\"sandbox\"}", null), 503)
                    .get("code").asText()).isEqualTo("dependency_unavailable");

            String logged = output.getAll();
            List<String> secrets = new ArrayList<>(List.of(ASK_TEXT, "zebraquartz", NOTE, "Quillfern", REASON, bookingRef,
                    "44.004", userId(asker), userId(provider), "Bearer ", SCENE_TOKEN, cursor));
            for (JsonNode session : List.of(asker, provider, second)) {
                secrets.add(session.get("access_token").asText());
                secrets.add(session.get("refresh_token").asText());
            }
            for (String secret : secrets) {
                assertThat(logged).as("a sensitive value reached the log").doesNotContain(secret);
            }
            // DispatcherServlet DEBUG prints the request path, which carries the provider id (a recorded
            // residual: path ids); only that one path occurrence is set aside, the id must appear nowhere else.
            assertThat(logged.replace("POST \"/v1/admin/providers/" + userId(second) + "/standing\"", "POST \"{path}\""))
                    .as("a sensitive value reached the log").doesNotContain(userId(second));
            // Redaction must not remove the ability to trace a request.
            assertThat(logged).contains("request_id=").doesNotContain("request_id=null");
        } finally {
            logging.setLogLevel(logger, previous);
        }
    }
}
