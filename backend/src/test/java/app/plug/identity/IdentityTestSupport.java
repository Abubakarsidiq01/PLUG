package app.plug.identity;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
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
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;

// Shared setup for the identity tests. These need a real database, so they carry the
// "database" tag and run in the databaseTest task alongside the Phase 0 migration checks.
//
// The pepper here is a test value. It is written into the properties rather than read from
// the environment so that a developer running one test does not have to be told a secret,
// and so that nothing can accidentally run against the value staging uses.
@Tag("database")
@SpringBootTest(properties = {
        "plug.environment=local",
        "plug.identity.pepper=identity-test-pepper-value-not-used-anywhere-real",
        "plug.identity.consent-version=2026-09-01"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(IdentityTestSupport.RecordingDelivery.class)
abstract class IdentityTestSupport {
    static final String CONSENT = "2026-09-01";

    // The per-address limits are counted in memory and outlive a single test, because in
    // production they are meant to. Each test therefore calls from its own network, which
    // is also closer to the truth than every request in the suite sharing one address.
    private static final java.util.concurrent.atomic.AtomicInteger NETWORKS =
            new java.util.concurrent.atomic.AtomicInteger();

    @Autowired MockMvc mvc;
    @Autowired JdbcTemplate jdbc;
    @Autowired RecordingPhoneCodeSender codes;

    final ObjectMapper json = new ObjectMapper();
    private String callerAddress;

    // Every test starts from an empty identity schema. Leaving rows behind would make one
    // test's outcome depend on which tests ran before it, and a rate-limit test is exactly
    // the kind that then fails for the wrong reason.
    @BeforeEach
    void resetIdentityTables() {
        int network = NETWORKS.incrementAndGet();
        callerAddress = "10." + (network / 250) + "." + (network % 250) + ".7";
        jdbc.execute("TRUNCATE sessions, identities, consents, phone_challenges, apple_token_uses,"
                + " audit_events, users RESTART IDENTITY CASCADE");
        codes.clear();
    }

    // Stands in for the messaging provider Phase 3 will connect, so the verification path
    // can be exercised end to end without inventing an SMS integration a phase early.
    static final class RecordingPhoneCodeSender implements PhoneCodeSender {
        private final List<String> sent = new ArrayList<>();

        @Override
        public void send(String phoneNumber, String code) {
            sent.add(code);
        }

        @Override
        public boolean isAvailable() {
            return true;
        }

        String latest() {
            return sent.get(sent.size() - 1);
        }

        int count() {
            return sent.size();
        }

        void clear() {
            sent.clear();
        }
    }

    @TestConfiguration
    static class RecordingDelivery {
        @Bean
        @Primary
        RecordingPhoneCodeSender recordingPhoneCodeSender() {
            return new RecordingPhoneCodeSender();
        }
    }

    JsonNode signInAsGuest() throws Exception {
        return body(post("/v1/auth/guest", """
                {"consent_version":"%s"}""".formatted(CONSENT)).andExpect(
                        org.springframework.test.web.servlet.result.MockMvcResultMatchers.status().isCreated()));
    }

    ResultActions post(String path, String payload) throws Exception {
        return mvc.perform(fromThisTestsNetwork(MockMvcRequestBuilders.post(path))
                .contentType(MediaType.APPLICATION_JSON).content(payload));
    }

    ResultActions post(String path, String payload, String accessToken) throws Exception {
        return mvc.perform(authorize(MockMvcRequestBuilders.post(path), accessToken)
                .contentType(MediaType.APPLICATION_JSON).content(payload));
    }

    ResultActions get(String path, String accessToken) throws Exception {
        return mvc.perform(authorize(MockMvcRequestBuilders.get(path), accessToken));
    }

    ResultActions delete(String path, String accessToken) throws Exception {
        return mvc.perform(authorize(MockMvcRequestBuilders.delete(path), accessToken));
    }

    private MockHttpServletRequestBuilder authorize(MockHttpServletRequestBuilder builder, String accessToken) {
        var request = fromThisTestsNetwork(builder);
        return accessToken == null ? request : request.header("Authorization", "Bearer " + accessToken);
    }

    private MockHttpServletRequestBuilder fromThisTestsNetwork(MockHttpServletRequestBuilder builder) {
        return builder.with(request -> {
            request.setRemoteAddr(callerAddress);
            return request;
        });
    }

    JsonNode body(ResultActions actions) throws Exception {
        return json.readTree(actions.andReturn().getResponse().getContentAsString());
    }

    String accessTokenOf(JsonNode session) {
        return session.get("access_token").asText();
    }

    String refreshTokenOf(JsonNode session) {
        return session.get("refresh_token").asText();
    }
}
