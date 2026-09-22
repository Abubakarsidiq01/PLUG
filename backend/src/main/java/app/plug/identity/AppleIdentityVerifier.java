package app.plug.identity;

import app.plug.foundation.ApiException;
import app.plug.foundation.SecurityConfiguration;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.HexFormat;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.JwtDecoder;

// Verifies the identity token Sign in with Apple hands the device. Four things are checked
// before anything in the token is believed, and none of them is optional:
//
//   signature  — against Apple's published keys, so the token was issued by Apple
//   issuer     — appleid.apple.com, so it is not a token from somewhere else entirely
//   audience   — this app's bundle identifier, so it is not a token for another app
//   expiry     — so a token found in an old log is already worthless
//
// Then two more that the four above do not cover: the nonce ties the token to this
// device's sign-in attempt, and the use record makes it single-use. A token is a bearer
// credential until it expires, and a captured one is worth replaying without both.
class AppleIdentityVerifier {
    private static final Logger log = LoggerFactory.getLogger(AppleIdentityVerifier.class);

    private final IdentitySettings settings;
    private final JdbcTemplate jdbc;
    private final java.util.function.Supplier<JwtDecoder> decoder;

    AppleIdentityVerifier(IdentitySettings settings, JdbcTemplate jdbc) {
        this(settings, jdbc, null);
    }

    // The decoder is injectable so a test can supply Apple's role with a key it controls.
    // Left null, it is built on first use rather than at startup: a service that cannot
    // start because Apple is slow to answer is a worse outage than a sign-in that fails.
    AppleIdentityVerifier(IdentitySettings settings, JdbcTemplate jdbc, JwtDecoder injected) {
        this.settings = settings;
        this.jdbc = jdbc;
        this.decoder = injected != null
                ? () -> injected
                : new java.util.function.Supplier<>() {
                    private volatile JwtDecoder built;

                    @Override
                    public JwtDecoder get() {
                        JwtDecoder current = built;
                        if (current == null) {
                            synchronized (this) {
                                current = built;
                                if (current == null) {
                                    current = build(settings);
                                    built = current;
                                }
                            }
                        }
                        return current;
                    }
                };
    }

    private static JwtDecoder build(IdentitySettings settings) {
        var built = NimbusJwtDecoder.withJwkSetUri(settings.appleJwkSetUri())
                .jwsAlgorithm(org.springframework.security.oauth2.jose.jws.SignatureAlgorithm.RS256).build();
        // The same four answers the staging resource server needs, from the same code.
        built.setJwtValidator(SecurityConfiguration.validators(settings.appleIssuer(), settings.appleClientId()));
        return built;
    }

    // The Apple subject and when the token stops being worth anything. The subject is the
    // only part kept, and it is hashed before it reaches a table.
    record AppleIdentity(String subject, Instant expiresAt) {}

    AppleIdentity verify(String identityToken, String rawNonce) {
        Jwt token;
        try {
            token = decoder.get().decode(identityToken);
        } catch (JwtException rejected) {
            // The reason is deliberately not returned and not logged with the token. Which
            // check failed is information, and the caller has no legitimate use for it.
            log.warn("apple_token_rejected reason={}", rejected.getClass().getSimpleName());
            throw refused();
        }
        String presented = token.getClaimAsString("nonce");
        if (presented == null || !Secrets.matches(presented, sha256Hex(rawNonce))) {
            log.warn("apple_token_rejected reason=nonce_mismatch");
            throw refused();
        }
        String subject = token.getSubject();
        Instant expiresAt = token.getExpiresAt();
        if (subject == null || subject.isBlank() || expiresAt == null) {
            throw refused();
        }
        claimSingleUse(identityToken, expiresAt);
        return new AppleIdentity(subject, expiresAt);
    }

    // The second presentation of a token collides on the primary key and is refused. The
    // row is kept only until the token would have expired anyway, so the table stays the
    // size of one expiry window rather than growing for ever.
    private void claimSingleUse(String identityToken, Instant expiresAt) {
        jdbc.update("DELETE FROM apple_token_uses WHERE expires_at < now()");
        try {
            jdbc.update("INSERT INTO apple_token_uses (token_hash, expires_at) VALUES (?, ?)",
                    Secrets.hashToken(identityToken), java.sql.Timestamp.from(expiresAt));
        } catch (DuplicateKeyException replayed) {
            log.warn("apple_token_rejected reason=replayed");
            throw refused();
        }
    }

    // Apple is given the SHA-256 of the nonce, in lower-case hexadecimal, and returns that
    // same value in the token. The raw nonce never leaves the device until this call.
    private static String sha256Hex(String rawNonce) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(rawNonce.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is required and is part of the platform.");
        }
    }

    private static ApiException refused() {
        return ApiException.unauthenticated("That Apple sign-in could not be verified. Try again.");
    }
}
