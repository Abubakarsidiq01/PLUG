package app.plug.identity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPublicKey;
import java.time.Instant;
import java.util.Date;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

// Google's side of the exchange, played by a key this test controls so the verifier can be
// pushed at tokens Google would never issue: expired ones, ones for another app, ones signed
// by somebody else, and ones presented twice.
@Import(GoogleSignInTest.LocalGoogleKeys.class)
class GoogleSignInTest extends IdentityTestSupport {
    private static final String ISSUER = "https://accounts.google.com";
    private static final String AUDIENCE = "app.plug.test";
    private static final KeyPair GOOGLE_KEY = generateKey();
    private static final KeyPair SOMEBODY_ELSE = generateKey();

    @TestConfiguration
    static class LocalGoogleKeys {
        // Replaces only the key source. Every check the real verifier runs — issuer,
        // audience, expiry, nonce and the single-use record — is the code under test.
        @Bean
        @Primary
        GoogleIdentityVerifier testGoogleIdentityVerifier(IdentitySettings settings, JdbcTemplate jdbc) {
            var decoder = NimbusJwtDecoder.withPublicKey((RSAPublicKey) GOOGLE_KEY.getPublic()).build();
            return new GoogleIdentityVerifier(AUDIENCE, jdbc, decoder);
        }
    }

    @Test
    void aValidTokenCreatesAnAccountAndASession() throws Exception {
        String nonce = "device-nonce-0000000001";
        String realSizedToken = token("google-subject-1", nonce, ISSUER, AUDIENCE, GOOGLE_KEY,
                Instant.now().plusSeconds(300));
        assertTrue(realSizedToken.length() > 1000, "Real Google tokens exceed the old JSON parser limit");
        var session = body(post("/v1/auth/google", signInBody(realSizedToken, nonce))
                .andExpect(status().isCreated()));
        assertEquals("google", session.get("account").get("type").asText());
        assertEquals("member", session.get("account").get("scopes").get(0).asText());

        // The Google subject is stored one way. A leaked database must not hand somebody a
        // list of the Google accounts that use PLUG.
        assertEquals(0, jdbc.queryForObject(
                "SELECT count(*) FROM identities WHERE subject_hash = 'google-subject-1'", Integer.class));
        assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM identities WHERE provider = 'google'",
                Integer.class));
    }

    @Test
    void thesameTokenCannotBeExchangedTwice() throws Exception {
        String nonce = "device-nonce-0000000002";
        String identityToken = token("google-subject-2", nonce, ISSUER, AUDIENCE, GOOGLE_KEY,
                Instant.now().plusSeconds(300));
        post("/v1/auth/google", signInBody(identityToken, nonce)).andExpect(status().isCreated());
        // A captured token is worth one replay unless the exchange is recorded. This is
        // that record doing its job.
        post("/v1/auth/google", signInBody(identityToken, nonce))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error.code").value("unauthenticated"));
    }

    @Test
    void anExpiredTokenIsRefused() throws Exception {
        String nonce = "device-nonce-0000000003";
        post("/v1/auth/google", signInBody(
                token("google-subject-3", nonce, ISSUER, AUDIENCE, GOOGLE_KEY, Instant.now().minusSeconds(60)), nonce))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void aTokenInsideTheDecodersClockSkewWindowIsStillExpired() throws Exception {
        String nonce = "device-nonce-recent-expiry";
        post("/v1/auth/google", signInBody(
                token("google-recent-expiry", nonce, ISSUER, AUDIENCE, GOOGLE_KEY,
                        Instant.now().minusSeconds(1)), nonce)).andExpect(status().isUnauthorized());
        assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM users", Integer.class));
    }

    @Test
    void aTokenForAnotherAppOrAnotherIssuerIsRefused() throws Exception {
        String nonce = "device-nonce-0000000004";
        Instant future = Instant.now().plusSeconds(300);
        post("/v1/auth/google", signInBody(
                token("google-subject-4", nonce, ISSUER, "some.other.app", GOOGLE_KEY, future), nonce))
                .andExpect(status().isUnauthorized());
        post("/v1/auth/google", signInBody(
                token("google-subject-4", nonce, "https://issuer.invalid", AUDIENCE, GOOGLE_KEY, future), nonce))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void aTokenSignedByTheWrongKeyIsRefused() throws Exception {
        String nonce = "device-nonce-0000000005";
        post("/v1/auth/google", signInBody(
                token("google-subject-5", nonce, ISSUER, AUDIENCE, SOMEBODY_ELSE, Instant.now().plusSeconds(300)),
                nonce)).andExpect(status().isUnauthorized());
    }

    @Test
    void aTokenWhoseNonceDoesNotMatchThisSignInAttemptIsRefused() throws Exception {
        // Without this check, any valid Google token for this app would work, including one
        // captured from a different device's sign-in.
        String issuedFor = "device-nonce-0000000006";
        post("/v1/auth/google", signInBody(
                token("google-subject-6", issuedFor, ISSUER, AUDIENCE, GOOGLE_KEY, Instant.now().plusSeconds(300)),
                "device-nonce-0000000007")).andExpect(status().isUnauthorized());
    }

    @Test
    void googleSignInUpgradesAGuestInPlace() throws Exception {
        var guest = signInAsGuest();
        String nonce = "device-nonce-0000000008";
        var upgraded = body(post("/v1/auth/google", signInBody(
                token("google-subject-8", nonce, ISSUER, AUDIENCE, GOOGLE_KEY, Instant.now().plusSeconds(300)), nonce),
                accessTokenOf(guest)).andExpect(status().isCreated()));
        assertEquals(guest.get("account").get("user_id").asText(),
                upgraded.get("account").get("user_id").asText());
        assertEquals("google", upgraded.get("account").get("type").asText());
    }

    @Test
    void signingInAgainReturnsToTheSameAccount() throws Exception {
        String first = "device-nonce-0000000009";
        var one = body(post("/v1/auth/google", signInBody(
                token("google-subject-9", first, ISSUER, AUDIENCE, GOOGLE_KEY, Instant.now().plusSeconds(300)), first))
                .andExpect(status().isCreated()));
        String second = "device-nonce-0000000010";
        var two = body(post("/v1/auth/google", signInBody(
                token("google-subject-9", second, ISSUER, AUDIENCE, GOOGLE_KEY, Instant.now().plusSeconds(300)), second))
                .andExpect(status().isCreated()));
        assertEquals(one.get("account").get("user_id").asText(), two.get("account").get("user_id").asText());
    }

    @Test
    void signupRefusesAnExistingAccountWithoutIssuingAnotherSession() throws Exception {
        String subject = "existing-google-account";
        post("/v1/auth/google", intendedBody(subject, "signup-first-nonce-0001", "sign_up"))
                .andExpect(status().isCreated());
        post("/v1/auth/google", intendedBody(subject, "signup-again-nonce-0002", "sign_up"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.details[0].code").value("account_exists"));
        assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM users", Integer.class));
        assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM sessions", Integer.class));
    }

    @Test
    void explicitSignInReturnsTheRegisteredAccount() throws Exception {
        String subject = "registered-google-account";
        var created = body(post("/v1/auth/google", intendedBody(subject, "create-nonce-00000001", "sign_up"))
                .andExpect(status().isCreated()));
        var signedIn = body(post("/v1/auth/google", intendedBody(subject, "signin-nonce-00000002", "sign_in"))
                .andExpect(status().isCreated()));
        assertEquals(created.get("account").get("user_id"), signedIn.get("account").get("user_id"));
        assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM users", Integer.class));
    }

    @Test
    void explicitSignInDoesNotSilentlyCreateAnAccount() throws Exception {
        post("/v1/auth/google", intendedBody("unknown-google-account", "unknown-nonce-0000001", "sign_in"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.details[0].code").value("account_not_found"));
        assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM users", Integer.class));
        assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM sessions", Integer.class));
    }

    @Test
    void anUnverifiedTokenCannotDiscoverAccountExistence() throws Exception {
        post("/v1/auth/google", intendedBody("private-google-account", "private-nonce-0000001", "sign_up"))
                .andExpect(status().isCreated());
        String nonce = "invalid-nonce-0000002";
        String invalid = signInBody(token("private-google-account", nonce, ISSUER, AUDIENCE,
                SOMEBODY_ELSE, Instant.now().plusSeconds(300)), nonce);
        post("/v1/auth/google", invalid.substring(0, invalid.length() - 1) + ",\"intent\":\"sign_up\"}")
                .andExpect(status().isUnauthorized());
    }

    private String intendedBody(String subject, String nonce, String intent) {
        String request = signInBody(token(subject, nonce, ISSUER, AUDIENCE, GOOGLE_KEY,
                Instant.now().plusSeconds(300)), nonce);
        return request.substring(0, request.length() - 1) + ",\"intent\":\"" + intent + "\"}";
    }

    private String signInBody(String identityToken, String nonce) {
        return """
                {"identity_token":"%s","nonce":"%s","consent_version":"%s"}"""
                .formatted(identityToken, nonce, CONSENT);
    }

    // Google echoes the SDK nonce in the signed token.
    private static String token(String subject, String rawNonce, String issuer, String audience,
            KeyPair key, Instant expiry) {
        try {
            var claims = new JWTClaimsSet.Builder().issuer(issuer).subject(subject).audience(audience)
                    .issueTime(Date.from(Instant.now().minusSeconds(30)))
                    .expirationTime(Date.from(expiry))
                    .claim("nonce", rawNonce)
                    .claim("name", "Example Person")
                    .claim("email", "person@example.invalid")
                    .claim("picture", "https://example.invalid/avatar/" + "a".repeat(360))
                    .build();
            var signed = new SignedJWT(new JWSHeader(JWSAlgorithm.RS256), claims);
            signed.sign(new RSASSASigner(key.getPrivate()));
            return signed.serialize();
        } catch (Exception exception) {
            throw new IllegalStateException(exception);
        }
    }

    private static KeyPair generateKey() {
        try {
            var generator = KeyPairGenerator.getInstance("RSA");
            generator.initialize(2048);
            return generator.generateKeyPair();
        } catch (Exception exception) {
            throw new IllegalStateException(exception);
        }
    }
}
