package app.plug.foundation;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class ContractTest {
    @Autowired MockMvc mvc;
    private final ObjectMapper json = new ObjectMapper();

    @Test
    void sharedExamplesMatchTheirSchemas() throws Exception {
        ContractSchemas.validateExample("HealthResponse", "health-response.json");
        ContractSchemas.validateExample("ReadinessResponse", "readiness-response.json");
        ContractSchemas.validateExample("RequestCreate", "request-create.json");
        ContractSchemas.validateExample("RequestResponse", "request-response.json");
        ContractSchemas.validateExample("Error", "validation-error.json");
        ContractSchemas.validateExample("Error", "authorization-error.json");
        ContractSchemas.validateExample("Error", "transient-error.json");
        ContractSchemas.validateExample("Error", "rate-limited.json");
        // Phase 1. Every example the two lanes build against is checked against the same
        // schema the server answers with, so a hand-written example cannot drift.
        ContractSchemas.validateExample("Session", "session.json");
        ContractSchemas.validateExample("PhoneChallenge", "phone-challenge.json");
        ContractSchemas.validateExample("Me", "me.json");
        ContractSchemas.validateExample("SessionSummary", "session-summary.json");
        ContractSchemas.validateExample("Error", "invalid-code-error.json");
        ContractSchemas.validateExample("Error", "expired-code-error.json");
        ContractSchemas.validateExample("Error", "account-link-conflict-error.json");
    }

    @Test
    void realProviderResponsesMatchTheContract() throws Exception {
        ContractSchemas.validate("HealthResponse", json.readTree(mvc.perform(get("/health")).andReturn().getResponse().getContentAsString()));
        ContractSchemas.validate("ReadinessResponse", json.readTree(mvc.perform(get("/health/ready")).andReturn().getResponse().getContentAsString()));
        String input = Files.readString(Path.of("../contracts/examples/request-create.json"));
        ContractSchemas.validate("RequestResponse", json.readTree(mvc.perform(post("/v1/requests")
                .contentType(MediaType.APPLICATION_JSON).content(input)).andReturn().getResponse().getContentAsString()));
        ContractSchemas.validate("Error", json.readTree(mvc.perform(post("/v1/requests")
                .contentType(MediaType.APPLICATION_JSON).content("{bad")).andReturn().getResponse().getContentAsString()));
    }
}
