package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
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
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(ClassificationAdmissionTest.Configuration.class)
class ClassificationAdmissionTest {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired CountingProvider provider;
    @Autowired JdbcTemplate jdbc;
    @Autowired PlatformTransactionManager transactions;
    private final java.util.List<String> users = new java.util.ArrayList<>();

    @org.junit.jupiter.api.AfterEach void removeOnlyThisTestsRecords() {
        provider.probe = () -> { };
        new TransactionTemplate(transactions).executeWithoutResult(ignored -> {
            for (String user : users) {
                jdbc.update("DELETE FROM asks WHERE user_id=?", user);
                jdbc.update("DELETE FROM request_idempotency WHERE user_id=?", user);
                jdbc.update("DELETE FROM requests WHERE user_id=?", user);
                jdbc.update("DELETE FROM users WHERE id=?", user);
            }
        });
    }

    @TestConfiguration static class Configuration {
        @Bean @Primary CountingProvider countingProvider() { return new CountingProvider(); }
    }
    static class CountingProvider implements IntentAdapter.Provider {
        final AtomicInteger calls = new AtomicInteger();
        volatile Runnable probe = () -> { };
        @Override public String extract(String text, Instant now, ZoneId zone, Duration deadline) {
            calls.incrementAndGet();
            probe.run();
            return null;
        }
    }

    @Test void replayConflictAndRateLimitNeverInvokeTheModel() throws Exception {
        for (String path : new String[] {"/v1/asks", "/v1/requests"}) {
            var guest = guest();
            String token = guest.path("access_token").asText();
            String key = UUID.randomUUID().toString();
            int before = provider.calls.get();
            String first = send(path, token, key, "Barber under $35", 201);
            assertThat(send(path, token, key, "Barber under $35", 201)).isEqualTo(first);
            send(path, token, key, "Braids under $35", 409);
            assertThat(provider.calls.get() - before).isEqualTo(1);
            for (int i = 0; i < 9; i++) send(path, token, UUID.randomUUID().toString(), "Barber under $35", 201);
            send(path, token, UUID.randomUUID().toString(), "Barber under $35", 429);
            // Retrying an accepted mutation still works after the creation budget is used.
            assertThat(send(path, token, key, "Barber under $35", 201)).isEqualTo(first);
            assertThat(provider.calls.get() - before).isEqualTo(10);
        }
    }

    @Test void classificationDoesNotHoldTheAccountLock() throws Exception {
        for (String path : new String[] {"/v1/asks", "/v1/requests"}) {
            var guest = guest();
            var acquired = new AtomicInteger();
            provider.probe = () -> new TransactionTemplate(transactions).executeWithoutResult(ignored -> {
                jdbc.queryForObject("SELECT id FROM users WHERE id=? FOR UPDATE NOWAIT", String.class,
                        guest.at("/account/user_id").asText());
                acquired.incrementAndGet();
            });
            try {
                send(path, guest.path("access_token").asText(), UUID.randomUUID().toString(), "Barber under $35", 201);
                assertThat(acquired.get()).isEqualTo(1);
            } finally { provider.probe = () -> { }; }
        }
    }

    private com.fasterxml.jackson.databind.JsonNode guest() throws Exception {
        var result = mapper.readTree(mvc.perform(post("/v1/auth/guest")
                .with(request -> { request.setRemoteAddr(UUID.randomUUID().toString()); return request; })
                .contentType(MediaType.APPLICATION_JSON).content("{\"consent_version\":\"2026-09-01\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString());
        users.add(result.at("/account/user_id").asText());
        return result;
    }
    private String send(String path, String token, String key, String text, int expected) throws Exception {
        var body = mapper.createObjectNode().put("text", text).put("time_zone", "America/Chicago");
        body.putObject("location").put("latitude", 32.528).put("longitude", -92.714).put("precision", "coarse");
        return mvc.perform(post(path).header("Authorization", "Bearer " + token).header("Idempotency-Key", key)
                .with(request -> { request.setRemoteAddr(UUID.randomUUID().toString()); return request; })
                .contentType(MediaType.APPLICATION_JSON).content(body.toString()))
                .andExpect(status().is(expected)).andReturn().getResponse().getContentAsString();
    }
}
