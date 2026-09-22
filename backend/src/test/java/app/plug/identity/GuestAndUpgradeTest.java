package app.plug.identity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;

// The guest path, its limits, and the upgrade that must not cost the person their work.
class GuestAndUpgradeTest extends IdentityTestSupport {

    @Test
    void guestSignInCreatesARealAccountWithTheGuestScopeOnly() throws Exception {
        var session = signInAsGuest();
        assertEquals("guest", session.get("account").get("type").asText());
        assertEquals("guest", session.get("account").get("scopes").get(0).asText());
        assertEquals(1, session.get("account").get("scopes").size());
        assertTrue(session.get("account").get("user_id").asText().startsWith("usr_"));
        assertEquals(CONSENT, session.get("consent").get("accepted_version").asText());
    }

    @Test
    void guestRefreshWindowIsShorterThanAMembers() throws Exception {
        var guest = signInAsGuest();
        var verified = phoneSignIn("+15551230001");
        assertTrue(guest.get("refresh_token_expires_at").asText()
                        .compareTo(verified.get("refresh_token_expires_at").asText()) < 0,
                "A guest credential must expire sooner than one belonging to a verified account.");
    }

    @Test
    void guestIsRefusedTheSessionManagementRoutesAndAMemberIsNot() throws Exception {
        String guest = accessTokenOf(signInAsGuest());
        get("/v1/me/sessions", guest).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error.code").value("forbidden"));
        // It can still read its own account and end its own session, which is the whole
        // capability a device-bound identity needs.
        get("/v1/me", guest).andExpect(status().isOk());
        post("/v1/auth/logout", "", guest).andExpect(status().isNoContent());

        String member = accessTokenOf(phoneSignIn("+15551230002"));
        get("/v1/me/sessions", member).andExpect(status().isOk())
                .andExpect(jsonPath("$.sessions[0].current").value(true));
    }

    @Test
    void upgradingAGuestKeepsTheUserIdAndRevokesTheGuestSession() throws Exception {
        var guest = signInAsGuest();
        String guestUserId = guest.get("account").get("user_id").asText();
        String guestAccess = accessTokenOf(guest);

        var upgraded = verifyPhoneWith("+15551230003", guestAccess);
        assertEquals(guestUserId, upgraded.get("account").get("user_id").asText(),
                "Phase 2 keys work to this id. An upgrade that changes it loses the request in progress.");
        assertEquals("phone", upgraded.get("account").get("type").asText());
        assertEquals("member", upgraded.get("account").get("scopes").get(0).asText());
        assertNotEquals(guestAccess, accessTokenOf(upgraded));

        // Upgrading changes how the account is secured, so the weaker credential stops
        // working immediately rather than lingering until it expires.
        get("/v1/me", guestAccess).andExpect(status().isUnauthorized());
        get("/v1/me", accessTokenOf(upgraded)).andExpect(status().isOk());
    }

    @Test
    void upgradingIntoAnIdentityThatAlreadyHasAnAccountIsARefusalNotAMerge() throws Exception {
        phoneSignIn("+15551230004");
        String guest = accessTokenOf(signInAsGuest());
        var challenge = body(post("/v1/auth/phone/start", """
                {"phone_number":"+15551230004"}""").andExpect(status().isAccepted()));
        post("/v1/auth/phone/verify", """
                {"challenge_id":"%s","code":"%s","consent_version":"%s"}"""
                .formatted(challenge.get("challenge_id").asText(), codes.latest(), CONSENT), guest)
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.code").value("conflict"));
    }

    @Test
    void anAlreadyVerifiedSessionCannotBeUsedToLinkASecondIdentity() throws Exception {
        String member = accessTokenOf(phoneSignIn("+15551230005"));
        var challenge = body(post("/v1/auth/phone/start", """
                {"phone_number":"+15551230006"}""").andExpect(status().isAccepted()));
        post("/v1/auth/phone/verify", """
                {"challenge_id":"%s","code":"%s","consent_version":"%s"}"""
                .formatted(challenge.get("challenge_id").asText(), codes.latest(), CONSENT), member)
                .andExpect(status().isConflict());
    }

    @Test
    void consentVersionIsPersistedAndAuditable() throws Exception {
        var guest = signInAsGuest();
        String userId = guest.get("account").get("user_id").asText();
        assertEquals(CONSENT, jdbc.queryForObject(
                "SELECT version FROM consents WHERE user_id = ?", String.class, userId));
        Integer audited = jdbc.queryForObject(
                "SELECT count(*) FROM audit_events WHERE actor_id = ? AND action = 'account.created'",
                Integer.class, userId);
        assertEquals(1, audited);
    }

    @Test
    void aConsentVersionTheServerNeverPublishedIsRefused() throws Exception {
        post("/v1/auth/guest", """
                {"consent_version":"1999-01-01"}""")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("validation_failed"))
                .andExpect(jsonPath("$.error.details[0].field").value("consent_version"));
    }

    @Test
    void auditEventsCannotBeEditedOrDeleted() throws Exception {
        signInAsGuest();
        int before = jdbc.queryForObject("SELECT count(*) FROM audit_events", Integer.class);
        jdbc.update("UPDATE audit_events SET action = 'tampered'");
        jdbc.update("DELETE FROM audit_events");
        assertEquals(before, jdbc.queryForObject("SELECT count(*) FROM audit_events", Integer.class));
        assertEquals(0, jdbc.queryForObject(
                "SELECT count(*) FROM audit_events WHERE action = 'tampered'", Integer.class));
    }

    private com.fasterxml.jackson.databind.JsonNode phoneSignIn(String number) throws Exception {
        return verifyPhoneWith(number, null);
    }

    private com.fasterxml.jackson.databind.JsonNode verifyPhoneWith(String number, String accessToken)
            throws Exception {
        var challenge = body(post("/v1/auth/phone/start", """
                {"phone_number":"%s"}""".formatted(number)).andExpect(status().isAccepted()));
        return body(post("/v1/auth/phone/verify", """
                {"challenge_id":"%s","code":"%s","consent_version":"%s"}"""
                .formatted(challenge.get("challenge_id").asText(), codes.latest(), CONSENT), accessToken)
                .andExpect(status().isCreated()));
    }
}
