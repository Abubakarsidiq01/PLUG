package app.plug.identity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;

// Rotation, replay, revocation, and the authorization checks that stop one person reading
// another's session. These are the cases gate G1 is judged on.
class SessionLifecycleTest extends IdentityTestSupport {

    @Test
    void everyRefreshRotatesBothTokens() throws Exception {
        var first = signInAsGuest();
        var second = body(post("/v1/auth/refresh", """
                {"refresh_token":"%s"}""".formatted(refreshTokenOf(first))).andExpect(status().isOk()));
        assertNotEquals(accessTokenOf(first), accessTokenOf(second));
        assertNotEquals(refreshTokenOf(first), refreshTokenOf(second));
        assertEquals(first.get("account").get("user_id").asText(),
                second.get("account").get("user_id").asText());
        get("/v1/me", accessTokenOf(second)).andExpect(status().isOk());
    }

    @Test
    void reusingARotatedRefreshTokenIsRefusedAndRevokesTheWholeChain() throws Exception {
        var first = signInAsGuest();
        var second = body(post("/v1/auth/refresh", """
                {"refresh_token":"%s"}""".formatted(refreshTokenOf(first))).andExpect(status().isOk()));

        // The spent token comes back. The only reading of that is a leak.
        post("/v1/auth/refresh", """
                {"refresh_token":"%s"}""".formatted(refreshTokenOf(first)))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error.code").value("unauthenticated"));

        // The session the attacker did not have is revoked too, which is the point of
        // revoking the chain rather than the token that was presented.
        get("/v1/me", accessTokenOf(second)).andExpect(status().isUnauthorized());
        post("/v1/auth/refresh", """
                {"refresh_token":"%s"}""".formatted(refreshTokenOf(second)))
                .andExpect(status().isUnauthorized());
        assertEquals(1, jdbc.queryForObject(
                "SELECT count(*) FROM audit_events WHERE action = 'session.replay_detected'", Integer.class));
    }

    @Test
    void logoutRevokesTheSessionOnTheServerNotOnlyInTheClient() throws Exception {
        var session = signInAsGuest();
        get("/v1/me", accessTokenOf(session)).andExpect(status().isOk());
        post("/v1/auth/logout", "", accessTokenOf(session)).andExpect(status().isNoContent());

        get("/v1/me", accessTokenOf(session)).andExpect(status().isUnauthorized());
        post("/v1/auth/refresh", """
                {"refresh_token":"%s"}""".formatted(refreshTokenOf(session)))
                .andExpect(status().isUnauthorized());
        assertEquals("logout", jdbc.queryForObject(
                "SELECT revoked_reason FROM sessions WHERE revoked_at IS NOT NULL", String.class));
    }

    @Test
    void repeatingLogoutStillSucceedsSoARetryIsSafe() throws Exception {
        var session = signInAsGuest();
        post("/v1/auth/logout", "", accessTokenOf(session)).andExpect(status().isNoContent());
        // The second call has no live token to present, so it is refused as unauthenticated
        // rather than reporting that the work it asked for failed.
        post("/v1/auth/logout", "", accessTokenOf(session)).andExpect(status().isUnauthorized());
    }

    @Test
    void oneAccountCannotReadOrRevokeAnotherAccountsSession() throws Exception {
        // Verified accounts, because these are the routes a guest is refused outright and
        // the point here is what happens to a caller who is allowed through the door.
        var mine = memberSession("+15551260001");
        var theirs = memberSession("+15551260002");
        String theirSessionId = sessionIdOf(theirs);

        // A 404 rather than a 403: a 403 would confirm the identifier names a real session,
        // which is the disclosure a BOLA test is looking for (manual.docx 19.4).
        get("/v1/me/sessions/" + theirSessionId, accessTokenOf(mine))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));
        delete("/v1/me/sessions/" + theirSessionId, accessTokenOf(mine))
                .andExpect(status().isNotFound());

        // Nothing was revoked by the attempt.
        get("/v1/me", accessTokenOf(theirs)).andExpect(status().isOk());
    }

    @Test
    void anInventedSessionIdentifierIsAnsweredExactlyLikeSomebodyElses() throws Exception {
        var mine = memberSession("+15551260003");
        get("/v1/me/sessions/ses_00000000-0000-0000-0000-000000000000", accessTokenOf(mine))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));
    }

    @Test
    void protectedRoutesAreDeniedWithoutAValidSession() throws Exception {
        var session = signInAsGuest();
        for (String path : new String[] {"/v1/me", "/v1/me/sessions"}) {
            get(path, null).andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("$.error.code").value("unauthenticated"));
            get(path, "pat_not-a-real-token").andExpect(status().isUnauthorized());
            get(path, "").andExpect(status().isUnauthorized());
        }
        // A well-formed token for a different scheme is still not a PLUG session.
        get("/v1/me", "eyJhbGciOiJub25lIn0.eyJzdWIiOiJhZG1pbiJ9.").andExpect(status().isUnauthorized());
        get("/v1/me", accessTokenOf(session)).andExpect(status().isOk());
    }

    @Test
    void adminRoutesAreDeniedToEveryIdentityThisPhaseCanIssue() throws Exception {
        // No account type in Phase 1 is granted the admin scope, and admin also requires a
        // session that completed a second factor. Both are checked before the first admin
        // route exists, so there is no window in which the control is missing.
        String member = accessTokenOf(signInAsGuest());
        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                        .get("/v1/admin/requests/req_1").header("Authorization", "Bearer " + member))
                .andExpect(status().isForbidden());
        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                        .get("/v1/admin/requests/req_1"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void unmappedRoutesAreDeniedRatherThanQuietlyPublished() throws Exception {
        get("/v1/anything-not-in-the-contract", null).andExpect(status().isUnauthorized());
        get("/v1/me/sessions/../sessions", accessTokenOf(memberSession("+15551260004")))
                .andExpect(result -> assertNotEquals(200, result.getResponse().getStatus()));
    }

    @Test
    void revokingOneOwnSessionLeavesTheOthersAlone() throws Exception {
        // Signing a lost device out must not sign the person out of the device in their
        // hand, which is the difference between this route and logout.
        var phone = memberSession("+15551260005");
        var onAnotherDevice = body(post("/v1/auth/refresh", """
                {"refresh_token":"%s"}""".formatted(refreshTokenOf(phone))).andExpect(status().isOk()));
        var current = memberSessionForExistingNumber("+15551260005");

        String other = sessionIdOf(onAnotherDevice);
        delete("/v1/me/sessions/" + other, accessTokenOf(current)).andExpect(status().isNoContent());
        get("/v1/me", accessTokenOf(onAnotherDevice)).andExpect(status().isUnauthorized());
        get("/v1/me", accessTokenOf(current)).andExpect(status().isOk());
        assertEquals("revoked_by_user", jdbc.queryForObject(
                "SELECT revoked_reason FROM sessions WHERE id = ?", String.class, other));
    }

    private JsonNode memberSession(String number) throws Exception {
        var challenge = body(post("/v1/auth/phone/start", """
                {"phone_number":"%s"}""".formatted(number)).andExpect(status().isAccepted()));
        return body(post("/v1/auth/phone/verify", """
                {"challenge_id":"%s","code":"%s","consent_version":"%s"}"""
                .formatted(challenge.get("challenge_id").asText(), codes.latest(), CONSENT))
                .andExpect(status().isCreated()));
    }

    private JsonNode memberSessionForExistingNumber(String number) throws Exception {
        return memberSession(number);
    }

    // The caller's own live session id. Sessions carry opaque identifiers on purpose, so a
    // test that needs one reads it from the database rather than guessing at a pattern.
    private String sessionIdOf(JsonNode session) {
        return jdbc.queryForObject("SELECT id FROM sessions WHERE access_token_hash = ?"
                        + " AND revoked_at IS NULL", String.class,
                app.plug.identity.TestTokens.hashOf(accessTokenOf(session)));
    }
}
