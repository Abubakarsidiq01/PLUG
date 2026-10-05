package app.plug.foundation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
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
        // The Phase 0 stub the backend still serves until requests_v2 replaces it.
        ContractSchemas.validateExample("Phase0RequestCreate", "request-create.json");
        ContractSchemas.validateExample("Phase0RequestResponse", "request-response.json");
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

    // Phase 2. One example per documented outcome (manual.docx §18.1), each checked against
    // the schema the server will answer with.
    @Test
    void phaseTwoRequestExamplesMatchTheirSchemas() throws Exception {
        ContractSchemas.validateExample("CreateRequestBody", "requests-create-barber.json");
        ContractSchemas.validateExample("CreateRequestBody", "requests-create-structured.json");
        ContractSchemas.validateExample("ClarificationAnswer", "requests-clarification-answer.json");
        for (String resource : REQUEST_RESOURCE_EXAMPLES) {
            ContractSchemas.validateExample("RequestResource", resource);
        }
        ContractSchemas.validateExample("OfferList", "requests-offers.json");
        ContractSchemas.validateExample("OfferList", "requests-offers-empty.json");
        ContractSchemas.validateExample("CreateRequestBody", "requests-create-open-service.json");
        for (String error : List.of("requests-validation-error.json",
                "requests-restricted-intent-error.json", "requests-consent-required-error.json",
                "requests-idempotency-conflict-error.json", "requests-not-awaiting-clarification-error.json",
                "requests-not-cancelable-error.json", "requests-not-found-error.json")) {
            ContractSchemas.validateExample("Error", error);
        }
    }

    // JSON Schema cannot express "present if and only if next_action is ...", so the rules the
    // contract states in prose are checked here against every request example instead.
    @Test
    void requestExamplesFollowTheNextActionRules() throws Exception {
        Map<String, String> nextActionFor = Map.of(
                "draft", "answer_clarification", "submitted", "wait_for_offers", "routed", "wait_for_offers",
                "awaiting_responses", "wait_for_offers", "ranked", "choose_offer",
                "user_selected", "await_supplier_confirmation", "confirmed", "show_result",
                "completed", "show_result", "expired", "show_no_result", "canceled", "none");
        for (String name : REQUEST_RESOURCE_EXAMPLES) {
            JsonNode body = json.readTree(Path.of("../contracts/examples/" + name).toFile());
            String nextAction = body.get("next_action").asText();
            assertEquals(nextActionFor.get(body.get("status").asText()), nextAction, name);
            assertEquals(nextAction.equals("answer_clarification"), body.has("clarification"), name);
            assertEquals(nextAction.equals("show_no_result"), body.has("no_result_reason"), name);
            assertEquals(nextAction.equals("wait_for_offers"), body.has("poll_after_seconds"), name);
            assertEquals(body.get("status").asText().equals("draft"), body.at("/constraints/category").isNull(), name);
            JsonNode progress = body.get("progress");
            assertTrue(progress.get("replied").asInt() <= progress.get("contacted").asInt(), name);
            assertTrue(progress.get("offers_ready").asInt() <= progress.get("replied").asInt(), name);
        }
    }

    @Test
    void seededOffersAreNeverLabelledAsVerified() throws Exception {
        JsonNode offers = json.readTree(Path.of("../contracts/examples/requests-offers.json").toFile()).get("offers");
        for (JsonNode offer : offers) {
            if (offer.get("source").asText().equals("seed")) {
                assertFalse(List.of("confirmed", "recent").contains(offer.get("truth_label").asText()), offer.toString());
            }
        }
    }

    private static final List<String> REQUEST_RESOURCE_EXAMPLES = List.of(
            "requests-created.json", "requests-awaiting-clarification.json", "requests-ranked.json",
            "requests-no-result.json", "requests-canceled.json");

    @Test
    void realProviderResponsesMatchTheContract() throws Exception {
        ContractSchemas.validate("HealthResponse", json.readTree(mvc.perform(get("/health")).andReturn().getResponse().getContentAsString()));
        ContractSchemas.validate("ReadinessResponse", json.readTree(mvc.perform(get("/health/ready")).andReturn().getResponse().getContentAsString()));
        String input = Files.readString(Path.of("../contracts/examples/request-create.json"));
        ContractSchemas.validate("Phase0RequestResponse", json.readTree(mvc.perform(post("/v1/requests")
                .contentType(MediaType.APPLICATION_JSON).content(input)).andReturn().getResponse().getContentAsString()));
        ContractSchemas.validate("Error", json.readTree(mvc.perform(post("/v1/requests")
                .contentType(MediaType.APPLICATION_JSON).content("{bad")).andReturn().getResponse().getContentAsString()));
    }
}
