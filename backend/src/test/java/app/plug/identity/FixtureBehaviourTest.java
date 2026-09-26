package app.plug.identity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ContractSchemas;
import com.fasterxml.jackson.databind.JsonNode;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

// The fixtures are hand-written, so ContractTest alone only proves they are well formed.
// This sends the shared request examples to the real server and compares what comes back
// with the fixture for that outcome: status, error code, detail tokens and message. The
// request_id and token values differ per call and are not compared.
class FixtureBehaviourTest extends IdentityTestSupport {

    @Test
    void theGuestRequestExampleSignsInAGuest() throws Exception {
        var session = body(post("/v1/auth/guest", example("auth-guest-request.json")).andExpect(status().isCreated()));
        ContractSchemas.validate("Session", session);
        assertEquals(fixture("auth.guest/success.json").get("account").get("scopes"), session.get("account").get("scopes"));
    }

    @Test
    void theGuestConsentRefusalMatchesItsFixture() throws Exception {
        assertSameError("auth.guest/unsupported-consent.json", body(post("/v1/auth/guest", """
                {"consent_version":"1999-01-01"}""").andExpect(status().isBadRequest())));
    }

    @Test
    void thePhoneStartExampleIssuesAChallenge() throws Exception {
        ContractSchemas.validate("PhoneChallenge", body(post("/v1/auth/phone/start",
                example("auth-phone-start-request.json")).andExpect(status().isAccepted())));
        assertSameError("auth.phone.start/validation-error.json", body(post("/v1/auth/phone/start", """
                {"phone_number":"5555550123"}""").andExpect(status().isBadRequest())));
    }

    @Test
    void signUpAndSignInIntentsMatchTheirFixtures() throws Exception {
        String phone = "+15551279001";
        assertSameError("auth.phone.verify/account-not-found.json", verify(phone, "sign_in"));
        body(post("/v1/auth/phone/verify", verifyPayload(phone, "sign_up")).andExpect(status().isCreated()));
        assertSameError("auth.phone.verify/account-exists.json", verify(phone, "sign_up"));
    }

    @Test
    void wrongCodesAndSessionRefusalsMatchTheirFixtures() throws Exception {
        var challenge = body(post("/v1/auth/phone/start", """
                {"phone_number":"+15551279002"}""").andExpect(status().isAccepted()));
        assertSameError("auth.phone.verify/invalid-code.json", body(post("/v1/auth/phone/verify", """
                {"challenge_id":"%s","code":"000000","consent_version":"%s"}"""
                .formatted(challenge.get("challenge_id").asText(), CONSENT)).andExpect(status().isBadRequest())));

        assertSameError("auth.refresh/session-ended.json", body(post("/v1/auth/refresh",
                example("auth-refresh-request.json")).andExpect(status().isUnauthorized())));
        assertSameError("me.get/unauthenticated.json", body(get("/v1/me", null).andExpect(status().isUnauthorized())));
        assertSameError("me.sessions/guest-forbidden.json",
                body(get("/v1/me/sessions", accessTokenOf(signInAsGuest())).andExpect(status().isForbidden())));
    }

    private JsonNode verify(String phone, String intent) throws Exception {
        return body(post("/v1/auth/phone/verify", verifyPayload(phone, intent)).andExpect(status().isConflict()));
    }

    private String verifyPayload(String phone, String intent) throws Exception {
        var challenge = body(post("/v1/auth/phone/start", """
                {"phone_number":"%s"}""".formatted(phone)).andExpect(status().isAccepted()));
        return """
                {"challenge_id":"%s","code":"%s","consent_version":"%s","intent":"%s"}"""
                .formatted(challenge.get("challenge_id").asText(), codes.latest(), CONSENT, intent);
    }

    static void assertSameError(String fixtureName, JsonNode actual) throws Exception {
        ContractSchemas.validate("Error", actual);
        JsonNode expected = fixture(fixtureName).get("error");
        JsonNode error = actual.get("error");
        assertEquals(expected.get("code"), error.get("code"), fixtureName);
        assertEquals(expected.get("message"), error.get("message"), fixtureName);
        assertEquals(expected.get("retry_after_seconds"), error.get("retry_after_seconds"), fixtureName);
        assertEquals(expected.path("details").size(), error.path("details").size(), fixtureName);
        for (int i = 0; i < expected.path("details").size(); i++) {
            assertEquals(expected.get("details").get(i).get("field"), error.get("details").get(i).get("field"), fixtureName);
            assertEquals(expected.get("details").get(i).get("code"), error.get("details").get(i).get("code"), fixtureName);
        }
    }

    static JsonNode fixture(String name) throws Exception {
        return new com.fasterxml.jackson.databind.ObjectMapper().readTree(Path.of("../fixtures/" + name).toFile());
    }

    private static String example(String name) throws Exception {
        return Files.readString(Path.of("../contracts/examples/" + name));
    }
}
