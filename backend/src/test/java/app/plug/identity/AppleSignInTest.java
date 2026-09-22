package app.plug.identity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.security.interfaces.RSAPublicKey;
import java.time.Instant;
import java.util.Date;
import java.util.HexFormat;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

// Apple's side of the exchange, played by a key this test controls so the verifier can be
// pushed at tokens Apple would never issue: expired ones, ones for another app, ones signed
// by somebody else, and ones presented twice.
@Import(AppleSignInTest.LocalAppleKeys.class)
class AppleSignInTest extends IdentityTestSupport {
    private static final String ISSUER = "https://appleid.apple.com";
    private static final String AUDIENCE = "app.plug.test";
    private static final KeyPair APPLE_KEY = generateKey();
    private static final KeyPair SOMEBODY_ELSE = generateKey();

    @TestConfiguration
    static class LocalAppleKeys {
        // Replaces only the key source. Every check the real verifier runs — issuer,
        // audience, expiry, nonce and the single-use record — is the code under test.
        @Bean
        @Primary
        AppleIdentityVerifier testAppleIdentityVerifier(IdentitySettings settings, JdbcTemplate jdbc) {
            var decoder = NimbusJwtDecoder.withPublicKey((RSAPublicKey) APPLE_KEY.getPublic()).build();
            decoder.setJwtValidator(
                    app.plug.foundation.SecurityConfiguration.validators(ISSUER, AUDIENCE));
            return new AppleIdentityVerifier(
                    new IdentitySettings(settings.enabled(), settings.consentVersion(), settings.pepper(),
                            settings.accessTokenTtl(), settings.refreshTokenTtl(), settings.guestRefreshTokenTtl(),
                            settings.phoneCodeTtl(), settings.phoneCodeAttempts(), AUDIENCE, ISSUER,
                            settings.appleJwkSetUri(), settings.phoneDelivery()),
                    jdbc, decoder);
        }
    }

    @Test
    void aValidTokenCreatesAnAccountAndASession() throws Exception {
        String nonce = "device-nonce-0000000001";
        var session = body(post("/v1/auth/apple", signInBody(
                token("apple-subject-1", nonce, ISSUER, AUDIENCE, APPLE_KEY, Instant.now().plusSeconds(300)), nonce))
                .andExpect(status().isCreated()));
        assertEquals("apple", session.get("account").get("type").asText());
        assertEquals("member", session.get("account").get("scopes").get(0).asText());

        // The Apple subject is stored one way. A leaked database must not hand somebody a
        // list of the Apple accounts that use PLUG.
        assertEquals(0, jdbc.queryForObject(
                "SELECT count(*) FROM identities WHERE subject_hash = 'apple-subject-1'", Integer.class));
        assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM identities WHERE provider = 'apple'",
                Integer.class));
    }

    @Test
    void thesameTokenCannotBeExchangedTwice() throws Exception {
        String nonce = "device-nonce-0000000002";
        String identityToken = token("apple-subject-2", nonce, ISSUER, AUDIENCE, APPLE_KEY,
                Instant.now().plusSeconds(300));
        post("/v1/auth/apple", signInBody(identityToken, nonce)).andExpect(status().isCreated());
        // A captured token is worth one replay unless the exchange is recorded. This is
        // that record doing its job.
        post("/v1/auth/apple", signInBody(identityToken, nonce))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error.code").value("unauthenticated"));
    }

    @Test
    void anExpiredTokenIsRefused() throws Exception {
        String nonce = "device-nonce-0000000003";
        post("/v1/auth/apple", signInBody(
                token("apple-subject-3", nonce, ISSUER, AUDIENCE, APPLE_KEY, Instant.now().minusSeconds(60)), nonce))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void aTokenForAnotherAppOrAnotherIssuerIsRefused() throws Exception {
        String nonce = "device-nonce-0000000004";
        Instant future = Instant.now().plusSeconds(300);
        post("/v1/auth/apple", signInBody(
                token("apple-subject-4", nonce, ISSUER, "some.other.app", APPLE_KEY, future), nonce))
                .andExpect(status().isUnauthorized());
        post("/v1/auth/apple", signInBody(
                token("apple-subject-4", nonce, "https://issuer.invalid", AUDIENCE, APPLE_KEY, future), nonce))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void aTokenSignedByTheWrongKeyIsRefused() throws Exception {
        String nonce = "device-nonce-0000000005";
        post("/v1/auth/apple", signInBody(
                token("apple-subject-5", nonce, ISSUER, AUDIENCE, SOMEBODY_ELSE, Instant.now().plusSeconds(300)),
                nonce)).andExpect(status().isUnauthorized());
    }

    @Test
    void aTokenWhoseNonceDoesNotMatchThisSignInAttemptIsRefused() throws Exception {
        // Without this check, any valid Apple token for this app would work, including one
        // captured from a different device's sign-in.
        String issuedFor = "device-nonce-0000000006";
        post("/v1/auth/apple", signInBody(
                token("apple-subject-6", issuedFor, ISSUER, AUDIENCE, APPLE_KEY, Instant.now().plusSeconds(300)),
                "device-nonce-0000000007")).andExpect(status().isUnauthorized());
    }

    @Test
    void appleSignInUpgradesAGuestInPlace() throws Exception {
        var guest = signInAsGuest();
        String nonce = "device-nonce-0000000008";
        var upgraded = body(post("/v1/auth/apple", signInBody(
                token("apple-subject-8", nonce, ISSUER, AUDIENCE, APPLE_KEY, Instant.now().plusSeconds(300)), nonce),
                accessTokenOf(guest)).andExpect(status().isCreated()));
        assertEquals(guest.get("account").get("user_id").asText(),
                upgraded.get("account").get("user_id").asText());
        assertEquals("apple", upgraded.get("account").get("type").asText());
    }

    @Test
    void signingInAgainReturnsToTheSameAccount() throws Exception {
        String first = "device-nonce-0000000009";
        var one = body(post("/v1/auth/apple", signInBody(
                token("apple-subject-9", first, ISSUER, AUDIENCE, APPLE_KEY, Instant.now().plusSeconds(300)), first))
                .andExpect(status().isCreated()));
        String second = "device-nonce-0000000010";
        var two = body(post("/v1/auth/apple", signInBody(
                token("apple-subject-9", second, ISSUER, AUDIENCE, APPLE_KEY, Instant.now().plusSeconds(300)), second))
                .andExpect(status().isCreated()));
        assertEquals(one.get("account").get("user_id").asText(), two.get("account").get("user_id").asText());
    }

    private String signInBody(String identityToken, String nonce) {
        return """
                {"identity_token":"%s","nonce":"%s","consent_version":"%s"}"""
                .formatted(identityToken, nonce, CONSENT);
    }

    // Apple receives the SHA-256 of the nonce and echoes that value back in the token.
    private static String token(String subject, String rawNonce, String issuer, String audience,
            KeyPair key, Instant expiry) {
        try {
            var claims = new JWTClaimsSet.Builder().issuer(issuer).subject(subject).audience(audience)
                    .issueTime(Date.from(Instant.now().minusSeconds(30)))
                    .expirationTime(Date.from(expiry))
                    .claim("nonce", HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                            .digest(rawNonce.getBytes(StandardCharsets.UTF_8))))
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
