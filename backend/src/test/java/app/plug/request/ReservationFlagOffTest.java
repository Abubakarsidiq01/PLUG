package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
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
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

/// With plug.provider-inbox.enabled=false the select route does not exist: a signed-in caller
/// gets 404 (no handler), not 403 and not a reservation.
@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.provider-inbox.enabled=false", "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(ReservationFlagOffTest.TimeConfiguration.class)
class ReservationFlagOffTest {
    @TestConfiguration static class TimeConfiguration {
        @Bean @Primary RequestClock fixedRequestClock() {
            return new RequestClock(Clock.fixed(Instant.parse("2026-10-01T20:00:00Z"), ZoneOffset.UTC));
        }
    }
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    private String user;

    @AfterEach void clean() {
        if (user == null) return;
        jdbc.update("DELETE FROM request_idempotency WHERE user_id=?", user);
        jdbc.update("DELETE FROM requests WHERE user_id=?", user);
        jdbc.update("DELETE FROM users WHERE id=?", user);
    }

    @Test void selectIsNotFoundForASignedInCallerWhenTheProviderInboxFlagIsOff() throws Exception {
        JsonNode session = mapper.readTree(mvc.perform(post("/v1/auth/guest").with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .contentType(MediaType.APPLICATION_JSON).content("{\"consent_version\":\"2026-09-01\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString());
        user = session.at("/account/user_id").asText();
        String auth = "Bearer " + session.get("access_token").asText();
        String id = mapper.readTree(mvc.perform(post("/v1/requests").header("Authorization", auth)
                .header("Idempotency-Key", "flag-off-test-" + UUID.randomUUID()).contentType(MediaType.APPLICATION_JSON)
                .content(ReservationTest.BODY)).andExpect(status().isCreated()).andReturn().getResponse().getContentAsString())
                .path("request_id").asText();
        mvc.perform(post("/v1/requests/" + id + "/select").header("Authorization", auth)
                .header("Idempotency-Key", "flag-off-test-" + UUID.randomUUID()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"offer_id\":\"off_" + UUID.randomUUID() + "\"}")).andExpect(status().isNotFound());
    }
}
