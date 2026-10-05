package app.plug.identity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ApiException;
import app.plug.foundation.ContractSchemas;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

/// Staff accounts (ADR-013): invited, never added in code; email, password and an emailed
/// code; only a session that finished both steps reaches /v1/admin; owners invite and
/// disable; nothing tells an outsider who is staff.
class StaffAccountsTest extends IdentityTestSupport {
    static final String PASSWORD = "correct horse battery staple";
    static final Pattern TOKEN = Pattern.compile("(sti_[A-Za-z0-9_-]+)");
    static final Pattern CODE = Pattern.compile("code is ([0-9]{6})");

    // Sign-in limits are counted per email in memory and outlive a test, as in production,
    // so each test's owner has an address of its own.
    private static final java.util.concurrent.atomic.AtomicInteger OWNERS = new java.util.concurrent.atomic.AtomicInteger();

    @Autowired StaffAccounts staff;
    String ownerEmail;

    String inviteToken() {
        Matcher match = TOKEN.matcher(mail.latest().text());
        assertThat(match.find()).isTrue();
        return match.group(1);
    }

    void accept(String token, String password, int expected) throws Exception {
        post("/v1/staff/invites/accept", "{\"invite_token\":\"" + token + "\",\"password\":\"" + password + "\"}")
                .andExpect(status().is(expected));
    }

    JsonNode challenge(String email, String password) throws Exception {
        JsonNode body = body(post("/v1/staff/login", "{\"email\":\"" + email + "\",\"password\":\"" + password + "\"}")
                .andExpect(status().isAccepted()));
        ContractSchemas.validate("StaffLoginChallenge", body);
        return body;
    }

    JsonNode signIn(String email, String password) throws Exception {
        JsonNode started = challenge(email, password);
        Matcher code = CODE.matcher(mail.latest().text());
        assertThat(code.find()).isTrue();
        JsonNode session = body(post("/v1/staff/login/verify", "{\"challenge_id\":\"" + started.get("challenge_id").asText()
                + "\",\"code\":\"" + code.group(1) + "\"}").andExpect(status().isCreated()));
        ContractSchemas.validate("Session", session);
        return session;
    }

    String owner() throws Exception {
        ownerEmail = "owner" + OWNERS.incrementAndGet() + "@example.com";
        assertThat(staff.bootstrap(ownerEmail.toUpperCase(java.util.Locale.ROOT))).isPresent();
        accept(inviteToken(), PASSWORD, 204);
        return accessTokenOf(signIn(ownerEmail, PASSWORD));
    }

    @Test
    void theFirstOwnerIsInvitedOnceFromConfigurationAndChoosesAPassword() throws Exception {
        assertThat(staff.bootstrap("owner@example.com")).isPresent();
        assertThat(mail.latest().to()).isEqualTo("owner@example.com");
        String token = inviteToken();
        assertThat(staff.bootstrap("owner@example.com")).as("an open invitation is not resent").isEmpty();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM staff_invites WHERE token_hash LIKE 'sti_%'", Integer.class))
                .as("only the hash is stored").isZero();

        for (String weak : new String[] {"short", "aaaaaaaaaaaaaaaa", "password12345", "owner-is-my-name"}) {
            accept(token, weak, 400);
        }
        accept(token, PASSWORD, 204);
        accept(token, PASSWORD, 400);
        assertThat(staff.bootstrap("someone.else@example.com")).as("never once staff exists").isEmpty();
    }

    @Test
    void signInNeedsThePasswordAndTheEmailedCodeAndRevealsNothing() throws Exception {
        String ownerToken = owner();
        var account = body(get("/v1/me", ownerToken).andExpect(status().isOk()));
        assertThat(account.at("/account/type").asText()).isEqualTo("staff");
        assertThat(account.at("/account/scopes").toString()).isEqualTo("[\"admin\"]");
        get("/v1/admin/staff", ownerToken).andExpect(status().isOk()).andExpect(header().string("Cache-Control", "no-store"));
        // A staff session is not a customer session.
        post("/v1/me/consent", "{\"version\":\"" + CONSENT + "\"}", null).andExpect(status().isUnauthorized());
        get("/v1/me/sessions", ownerToken).andExpect(status().isForbidden());

        // Wrong password, unknown email and the right pair all answer 202 with the same shape.
        int sent = mail.count();
        JsonNode wrong = challenge(ownerEmail, "not the right password");
        JsonNode unknown = challenge("nobody@example.com", PASSWORD);
        assertThat(mail.count()).as("no code without the right password").isEqualTo(sent);
        for (JsonNode decoy : new JsonNode[] {wrong, unknown}) {
            assertThat(body(post("/v1/staff/login/verify", "{\"challenge_id\":\"" + decoy.get("challenge_id").asText()
                    + "\",\"code\":\"123456\"}").andExpect(status().isBadRequest())).at("/error/details/0/code").asText())
                    .isEqualTo("expired");
        }

        JsonNode real = challenge(ownerEmail, PASSWORD);
        String path = "{\"challenge_id\":\"" + real.get("challenge_id").asText() + "\",\"code\":\"";
        Matcher code = CODE.matcher(mail.latest().text());
        assertThat(code.find()).isTrue();
        String wrongCode = code.group(1).equals("000000") ? "111111" : "000000";
        assertThat(body(post("/v1/staff/login/verify", path + wrongCode + "\"}").andExpect(status().isBadRequest()))
                .at("/error/details/0/code").asText()).isEqualTo("invalid");
        post("/v1/staff/login/verify", path + code.group(1) + "\"}").andExpect(status().isCreated());
        post("/v1/staff/login/verify", path + code.group(1) + "\"}").andExpect(status().isBadRequest());

        // A logout ends the staff session at once.
        post("/v1/auth/logout", "", ownerToken).andExpect(status().isNoContent());
        get("/v1/admin/staff", ownerToken).andExpect(status().isUnauthorized());
    }

    @Test
    void wrongCodesRunOutAndRepeatedPasswordsAreLimited() throws Exception {
        owner();
        JsonNode started = challenge(ownerEmail, PASSWORD);
        Matcher code = CODE.matcher(mail.latest().text());
        assertThat(code.find()).isTrue();
        String wrongCode = code.group(1).equals("000000") ? "111111" : "000000";
        String path = "{\"challenge_id\":\"" + started.get("challenge_id").asText() + "\",\"code\":\"";
        for (int attempt = 1; attempt < StaffAccounts.CODE_ATTEMPTS; attempt++) {
            post("/v1/staff/login/verify", path + wrongCode + "\"}").andExpect(status().isBadRequest());
        }
        post("/v1/staff/login/verify", path + wrongCode + "\"}").andExpect(status().isTooManyRequests());
        post("/v1/staff/login/verify", path + code.group(1) + "\"}").andExpect(status().isTooManyRequests());

        for (int attempt = 0; attempt < 5; attempt++) challenge("limited@example.com", "guess number " + attempt);
        post("/v1/staff/login", "{\"email\":\"limited@example.com\",\"password\":\"x\"}").andExpect(status().isTooManyRequests());
    }

    @Test
    void ownersInviteAndDisableStaffAndStaffCannotManageStaff() throws Exception {
        String ownerToken = owner();
        String admin = "/v1/admin/staff/invites";
        JsonNode invite = body(post(admin, "{\"email\":\"Partner@Example.com\",\"role\":\"staff\"}", ownerToken)
                .andExpect(status().isCreated()));
        ContractSchemas.validate("StaffInvite", invite);
        assertThat(invite.toString()).doesNotContain("sti_");
        String first = inviteToken();
        post(admin, "{\"email\":\"partner@example.com\",\"role\":\"staff\"}", ownerToken).andExpect(status().isCreated());
        accept(first, PASSWORD, 400);
        accept(inviteToken(), "a different good passphrase", 204);
        post(admin, "{\"email\":\"partner@example.com\",\"role\":\"staff\"}", ownerToken).andExpect(status().isConflict());
        post(admin, "{\"email\":\"not-an-email\",\"role\":\"staff\"}", ownerToken).andExpect(status().isBadRequest());
        post(admin, "{\"email\":\"x@example.com\",\"role\":\"emperor\"}", ownerToken).andExpect(status().isBadRequest());

        String partnerToken = accessTokenOf(signIn("partner@example.com", "a different good passphrase"));
        JsonNode list = body(get("/v1/admin/staff", partnerToken).andExpect(status().isOk()));
        ContractSchemas.validate("StaffList", list);
        assertThat(list.get("staff").findValuesAsText("role")).containsExactly("owner", "staff");
        post(admin, "{\"email\":\"third@example.com\",\"role\":\"staff\"}", partnerToken).andExpect(status().isForbidden());
        String partnerId = list.get("staff").get(1).get("user_id").asText();
        String ownerId = list.get("staff").get(0).get("user_id").asText();
        post("/v1/admin/staff/" + ownerId + "/disable", "", partnerToken).andExpect(status().isForbidden());
        post("/v1/admin/staff/" + ownerId + "/disable", "", ownerToken).andExpect(status().isConflict());
        post("/v1/admin/staff/usr_00000000-0000-0000-0000-000000000000/disable", "", ownerToken).andExpect(status().isNotFound());

        post("/v1/admin/staff/" + partnerId + "/disable", "", ownerToken).andExpect(status().isNoContent());
        get("/v1/admin/staff", partnerToken).andExpect(status().isUnauthorized());
        int sent = mail.count();
        challenge("partner@example.com", "a different good passphrase");
        assertThat(mail.count()).as("a disabled account gets no code").isEqualTo(sent);
        assertThat(jdbc.queryForList("SELECT action FROM audit_events WHERE actor_id = ?", String.class, ownerId))
                .contains("staff.invited", "staff.disabled", "staff.signed_in");
    }

    @Test
    void customerSessionsAndUnverifiedCallersNeverReachStaffManagement() throws Exception {
        owner();
        String guest = accessTokenOf(signInAsGuest());
        get("/v1/admin/staff", guest).andExpect(status().isForbidden());
        get("/v1/admin/staff", null).andExpect(status().isUnauthorized());
        post("/v1/admin/staff/invites", "{\"email\":\"x@example.com\",\"role\":\"owner\"}", guest).andExpect(status().isForbidden());
    }

    @Test
    void passwordsAndEmailsAreCheckedBeforeAnythingIsStored() {
        assertThatThrownBy(() -> StaffAccounts.email("no-at-sign")).isInstanceOf(ApiException.class);
        assertThat(StaffAccounts.email("  Person@Example.COM ")).isEqualTo("person@example.com");
        assertThatThrownBy(() -> StaffAccounts.checkPassword("é".repeat(40), "a@example.com")).isInstanceOf(ApiException.class);
        StaffAccounts.checkPassword("a long and unusual phrase", "person@example.com");
    }
}
