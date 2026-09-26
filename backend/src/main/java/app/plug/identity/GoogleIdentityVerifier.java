package app.plug.identity;

import app.plug.foundation.ApiException;
import java.time.Instant;
import java.util.Set;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

final class GoogleIdentityVerifier {
    private final String clientId;
    private final JdbcTemplate jdbc;
    private final JwtDecoder decoder;

    GoogleIdentityVerifier(String clientId, JdbcTemplate jdbc) {
        this(clientId, jdbc, NimbusJwtDecoder.withJwkSetUri("https://www.googleapis.com/oauth2/v3/certs").build());
    }

    GoogleIdentityVerifier(String clientId, JdbcTemplate jdbc, JwtDecoder decoder) {
        this.clientId = clientId;
        this.jdbc = jdbc;
        this.decoder = decoder;
    }

    String verify(String identityToken, String nonce) {
        if (clientId.isBlank()) {
            throw ApiException.dependencyUnavailable("Google sign-in is not available yet. Choose another method.", 60);
        }
        Jwt token;
        try { token = decoder.decode(identityToken); }
        catch (JwtException invalid) { throw refused(); }
        String issuer = token.getClaimAsString("iss");
        String subject = token.getSubject();
        Instant expires = token.getExpiresAt();
        if (issuer == null || !Set.of("accounts.google.com", "https://accounts.google.com").contains(issuer)
                || token.getAudience() == null || !token.getAudience().contains(clientId) || subject == null || subject.isBlank()
                || expires == null || !expires.isAfter(Instant.now())
                || token.getClaimAsString("nonce") == null
                || !Secrets.matches(nonce, token.getClaimAsString("nonce"))) {
            throw refused();
        }
        // Only the verified stable subject identifies the account; email never links accounts.
        jdbc.update("DELETE FROM google_token_uses WHERE expires_at < now()");
        int claimed = jdbc.update("INSERT INTO google_token_uses (token_hash, expires_at) VALUES (?, ?)"
                + " ON CONFLICT DO NOTHING", Secrets.hashToken(identityToken), java.sql.Timestamp.from(expires));
        if (claimed != 1) { throw refused(); }
        return subject;
    }

    private static ApiException refused() {
        return ApiException.unauthenticated("That Google sign-in could not be verified. Try again.");
    }
}
