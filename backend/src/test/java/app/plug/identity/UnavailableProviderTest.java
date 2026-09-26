package app.plug.identity;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

// The default configuration: no SMS channel and no Google client. Both routes must say so
// with 503 dependency_unavailable and a recovery path, exactly as the fixtures describe,
// rather than pretending a code was sent or failing as an internal error.
@Tag("database")
@SpringBootTest(properties = {
        "plug.environment=local",
        "plug.identity.pepper=identity-test-pepper-value-not-used-anywhere-real",
        "plug.identity.consent-version=2026-09-01",
        "plug.identity.phone-delivery=none",
        "plug.identity.google-client-id="})
@ActiveProfiles("db")
@AutoConfigureMockMvc
class UnavailableProviderTest {
    @Autowired MockMvc mvc;
    private final ObjectMapper json = new ObjectMapper();

    @Test
    void phoneStartWithoutADeliveryChannelMatchesItsFixture() throws Exception {
        var response = mvc.perform(post("/v1/auth/phone/start").with(request -> {
                    request.setRemoteAddr("10.250.0.1");
                    return request;
                })
                .contentType(MediaType.APPLICATION_JSON).content(example("auth-phone-start-request.json")))
                .andExpect(status().isServiceUnavailable())
                .andExpect(header().string("Retry-After", "60"))
                .andReturn().getResponse().getContentAsString();
        FixtureBehaviourTest.assertSameError("auth.phone.start/unavailable.json", json.readTree(response));
    }

    @Test
    void googleWithoutAClientIdMatchesItsFixture() throws Exception {
        var response = mvc.perform(post("/v1/auth/google").with(request -> {
                    request.setRemoteAddr("10.250.0.2");
                    return request;
                })
                .contentType(MediaType.APPLICATION_JSON).content(example("auth-google-request.json")))
                .andExpect(status().isServiceUnavailable())
                .andReturn().getResponse().getContentAsString();
        FixtureBehaviourTest.assertSameError("auth.google/unavailable.json", json.readTree(response));
    }

    private static String example(String name) throws Exception {
        return Files.readString(Path.of("../contracts/examples/" + name));
    }
}
