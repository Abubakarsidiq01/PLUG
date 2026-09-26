package app.plug.identity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;

// Brute force, rate limits, expiry and the shape of each refusal.
class PhoneVerificationTest extends IdentityTestSupport {

    @Test
    void aWrongCodeIsAValidationFailureTheClientCanBranchOn() throws Exception {
        var challenge = start("+15551240001");
        post("/v1/auth/phone/verify", verifyBody(challenge, wrongCode()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("validation_failed"))
                .andExpect(jsonPath("$.error.details[0].field").value("code"))
                .andExpect(jsonPath("$.error.details[0].code").value("invalid"));
    }

    @Test
    void anExpiredChallengeIsReportedAsExpiredRatherThanWrong() throws Exception {
        var challenge = start("+15551240002");
        String challengeId = challenge.get("challenge_id").asText();
        jdbc.update("UPDATE phone_challenges SET expires_at = now() - interval '1 minute' WHERE id = ?",
                challengeId);
        post("/v1/auth/phone/verify", verifyBody(challenge, codes.latest()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.details[0].code").value("expired"));
    }

    @Test
    void anUnknownChallengeIsAnsweredExactlyLikeAnExpiredOne() throws Exception {
        // Distinguishing the two would tell a caller which identifiers are real.
        post("/v1/auth/phone/verify", """
                {"challenge_id":"cha_00000000-0000-0000-0000-000000000000","code":"123456",
                 "consent_version":"%s"}""".formatted(CONSENT))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.details[0].code").value("expired"));
    }

    @Test
    void guessingRunsOutOfAttemptsBeforeItRunsOutOfCodes() throws Exception {
        var challenge = start("+15551240003");
        // Five attempts against a six-digit code. An attacker needs a hundred thousand
        // times more than the limit allows, which is the point of having one.
        for (int attempt = 1; attempt <= 4; attempt++) {
            post("/v1/auth/phone/verify", verifyBody(challenge, wrongCode()))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error.details[0].code").value("invalid"));
        }
        post("/v1/auth/phone/verify", verifyBody(challenge, wrongCode()))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.error.code").value("rate_limited"))
                .andExpect(jsonPath("$.error.retry_after_seconds").isNumber());

        // The correct code no longer helps: the budget is spent, not the guesses.
        post("/v1/auth/phone/verify", verifyBody(challenge, codes.latest()))
                .andExpect(status().isTooManyRequests());
    }

    @Test
    void askingForCodesRepeatedlyIsRateLimitedWithoutSayingWhichLimitWasHit() throws Exception {
        for (int request = 1; request <= 5; request++) {
            post("/v1/auth/phone/start", """
                    {"phone_number":"+15551240004"}""").andExpect(status().isAccepted());
        }
        post("/v1/auth/phone/start", """
                {"phone_number":"+15551240004"}""")
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.error.code").value("rate_limited"))
                .andExpect(jsonPath("$.error.message").value("Too many attempts. Try again shortly."));
        assertTrue(jdbc.queryForObject("SELECT count(*) FROM audit_events WHERE action = 'otp.rate_limited'",
                Integer.class) >= 1, "A limit that is reached without being recorded is invisible to support.");
    }

    @Test
    void oneAcceptedCodeBuysExactlyOneSession() throws Exception {
        var challenge = start("+15551240005");
        String code = codes.latest();
        post("/v1/auth/phone/verify", verifyBody(challenge, code)).andExpect(status().isCreated());
        post("/v1/auth/phone/verify", verifyBody(challenge, code))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.details[0].code").value("expired"));
    }

    @Test
    void theCodeIsStoredOneWayAndTheNumberIsNeverStoredReadably() throws Exception {
        start("+15551240006");
        String storedCode = jdbc.queryForObject("SELECT code_hash FROM phone_challenges", String.class);
        String storedPhone = jdbc.queryForObject("SELECT phone_hash FROM phone_challenges", String.class);
        assertNotEquals(codes.latest(), storedCode);
        assertTrue(storedCode.length() > 20, "A six-digit code must not be stored as six digits.");
        assertEquals(0, jdbc.queryForObject(
                "SELECT count(*) FROM phone_challenges WHERE phone_hash LIKE '%5551240006%'", Integer.class));
        assertTrue(storedPhone.length() > 20);
    }

    @Test
    void theStartResponseIsIdenticalForAKnownAndAnUnknownNumber() throws Exception {
        var unknown = start("+15551240007");
        post("/v1/auth/phone/verify", verifyBody(unknown, codes.latest())).andExpect(status().isCreated());
        var again = body(post("/v1/auth/phone/start", """
                {"phone_number":"+15551240007"}""").andExpect(status().isAccepted()));
        assertEquals(unknown.get("attempts_remaining").asInt(), again.get("attempts_remaining").asInt());
        var unknownFields = new java.util.HashSet<String>();
        unknown.fieldNames().forEachRemaining(unknownFields::add);
        var knownFields = new java.util.HashSet<String>();
        again.fieldNames().forEachRemaining(knownFields::add);
        assertEquals(unknownFields, knownFields);
    }

    @Test
    void aMalformedNumberIsRejectedBeforeAnyLimitIsSpent() throws Exception {
        post("/v1/auth/phone/start", """
                {"phone_number":"not-a-number"}""")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("validation_failed"));
        assertEquals(0, codes.count());
    }

    private com.fasterxml.jackson.databind.JsonNode start(String number) throws Exception {
        return body(post("/v1/auth/phone/start", """
                {"phone_number":"%s"}""".formatted(number)).andExpect(status().isAccepted()));
    }

    @Test
    void consumptionRechecksExpiryAndAttemptBudgetAfterAnEarlierRead() throws Exception {
        var challenge = start("+15551240008");
        String id = challenge.get("challenge_id").asText();
        var repository = new PhoneChallengeRepository(jdbc);
        org.junit.jupiter.api.Assertions.assertTrue(repository.find(id).isPresent());
        jdbc.update("UPDATE phone_challenges SET attempts_used = 6 WHERE id = ?", id);
        org.junit.jupiter.api.Assertions.assertFalse(repository.consume(id, 5));
        jdbc.update("UPDATE phone_challenges SET attempts_used = 1, expires_at = now() - interval '1 second'"
                + " WHERE id = ?", id);
        org.junit.jupiter.api.Assertions.assertFalse(repository.consume(id, 5));
        assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM phone_challenges WHERE consumed_at IS NOT NULL",
                Integer.class));
    }

    private String wrongCode() {
        return "000000".equals(codes.latest()) ? "000001" : "000000";
    }

    @Test
    void verifiedExistingPhoneSignupOffersSigninAndSigninReturnsTheSameAccount() throws Exception {
        var first = start("+15551240011");
        var account = body(post("/v1/auth/phone/verify", intendedBody(first, codes.latest(), "sign_up"))
                .andExpect(status().isCreated()));
        var repeated = start("+15551240011");
        post("/v1/auth/phone/verify", intendedBody(repeated, codes.latest(), "sign_up"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.details[0].code").value("account_exists"));
        assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM users", Integer.class));
        assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM sessions", Integer.class));
        var signin = start("+15551240011");
        var restored = body(post("/v1/auth/phone/verify", intendedBody(signin, codes.latest(), "sign_in"))
                .andExpect(status().isCreated()));
        assertEquals(account.get("account").get("user_id"), restored.get("account").get("user_id"));
    }

    @Test
    void unknownPhoneSigninCannotCreateAnAccount() throws Exception {
        var challenge = start("+15551240012");
        post("/v1/auth/phone/verify", intendedBody(challenge, codes.latest(), "sign_in"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.details[0].code").value("account_not_found"));
        assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM users", Integer.class));
        assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM sessions", Integer.class));
    }

    @Test
    void wrongOtpCannotDiscloseAnExistingPhoneAccount() throws Exception {
        var first = start("+15551240013");
        post("/v1/auth/phone/verify", intendedBody(first, codes.latest(), "sign_up"))
                .andExpect(status().isCreated());
        var challenge = start("+15551240013");
        post("/v1/auth/phone/verify", intendedBody(challenge, wrongCode(), "sign_up"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.details[0].code").value("invalid"));
    }

    private String intendedBody(com.fasterxml.jackson.databind.JsonNode challenge, String code, String intent) {
        String body = verifyBody(challenge, code);
        return body.substring(0, body.length() - 1) + ",\"intent\":\"" + intent + "\"}";
    }

    private String verifyBody(com.fasterxml.jackson.databind.JsonNode challenge, String code) {
        return """
                {"challenge_id":"%s","code":"%s","consent_version":"%s"}"""
                .formatted(challenge.get("challenge_id").asText(), code, CONSENT);
    }
}
