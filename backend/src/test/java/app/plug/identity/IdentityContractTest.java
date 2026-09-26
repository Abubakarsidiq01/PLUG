package app.plug.identity;

import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ContractSchemas;
import org.junit.jupiter.api.Test;

// What the server actually answers, checked against contracts/openapi.yaml rather than
// against what the code was meant to do. A field renamed in a payload record and not in
// the contract is exactly the drift this catches, and it is the kind that is invisible
// until the other lane's client breaks.
class IdentityContractTest extends IdentityTestSupport {

    @Test
    void everySignInRouteAnswersTheShapeTheContractPromises() throws Exception {
        ContractSchemas.validate("Session", body(post("/v1/auth/guest", """
                {"consent_version":"%s"}""".formatted(CONSENT)).andExpect(status().isCreated())));

        var challenge = body(post("/v1/auth/phone/start", """
                {"phone_number":"+15551270001"}""").andExpect(status().isAccepted()));
        ContractSchemas.validate("PhoneChallenge", challenge);

        var session = body(post("/v1/auth/phone/verify", """
                {"challenge_id":"%s","code":"%s","consent_version":"%s"}"""
                .formatted(challenge.get("challenge_id").asText(), codes.latest(), CONSENT))
                .andExpect(status().isCreated()));
        ContractSchemas.validate("Session", session);

        ContractSchemas.validate("Session", body(post("/v1/auth/refresh", """
                {"refresh_token":"%s"}""".formatted(refreshTokenOf(session))).andExpect(status().isOk())));
    }

    @Test
    void theAccountRoutesAnswerTheShapeTheContractPromises() throws Exception {
        var session = body(post("/v1/auth/guest", """
                {"consent_version":"%s"}""".formatted(CONSENT)).andExpect(status().isCreated()));
        String accessToken = accessTokenOf(session);

        ContractSchemas.validate("Me", body(get("/v1/me", accessToken).andExpect(status().isOk())));
        ContractSchemas.validate("Consent", body(post("/v1/me/consent", """
                {"version":"%s"}""".formatted(CONSENT), accessToken).andExpect(status().isOk())));
    }

    @Test
    void theSessionRoutesAnswerTheShapeTheContractPromises() throws Exception {
        var challenge = body(post("/v1/auth/phone/start", """
                {"phone_number":"+15551270002"}""").andExpect(status().isAccepted()));
        var session = body(post("/v1/auth/phone/verify", """
                {"challenge_id":"%s","code":"%s","consent_version":"%s"}"""
                .formatted(challenge.get("challenge_id").asText(), codes.latest(), CONSENT))
                .andExpect(status().isCreated()));
        String accessToken = accessTokenOf(session);

        var list = body(get("/v1/me/sessions", accessToken).andExpect(status().isOk()));
        ContractSchemas.validate("SessionList", list);
        String sessionId = list.get("sessions").get(0).get("session_id").asText();
        ContractSchemas.validate("SessionSummary",
                body(get("/v1/me/sessions/" + sessionId, accessToken).andExpect(status().isOk())));
    }

    @Test
    void everyRefusalUsesTheOneErrorEnvelope() throws Exception {
        // The envelope is the part both lanes depend on most, so each failure mode the
        // Phase 1 routes can produce is checked against it rather than assumed.
        ContractSchemas.validate("Error", body(post("/v1/auth/guest", """
                {"consent_version":"1999-01-01"}""").andExpect(status().isBadRequest())));
        ContractSchemas.validate("Error", body(post("/v1/auth/refresh", """
                {"refresh_token":"prt_not-a-real-token"}""").andExpect(status().isUnauthorized())));
        ContractSchemas.validate("Error", body(get("/v1/me", null).andExpect(status().isUnauthorized())));

        String guest = accessTokenOf(body(post("/v1/auth/guest", """
                {"consent_version":"%s"}""".formatted(CONSENT)).andExpect(status().isCreated())));
        ContractSchemas.validate("Error", body(get("/v1/me/sessions", guest).andExpect(status().isForbidden())));

        var challenge = body(post("/v1/auth/phone/start", """
                {"phone_number":"+15551270003"}""").andExpect(status().isAccepted()));
        ContractSchemas.validate("Error", body(post("/v1/auth/phone/verify", """
                {"challenge_id":"%s","code":"000000","consent_version":"%s"}"""
                .formatted(challenge.get("challenge_id").asText(), CONSENT))
                .andExpect(status().isBadRequest())));
    }
}
