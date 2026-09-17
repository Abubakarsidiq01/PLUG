package app.plug.foundation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

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
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

class JwtValidationTest {
    private KeyPair key() throws Exception {
        var generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        return generator.generateKeyPair();
    }

    private String token(KeyPair key, String issuer, String audience, Instant expiry) throws Exception {
        var builder = new JWTClaimsSet.Builder().issuer(issuer).subject("test-user").audience(audience)
                .issueTime(Date.from(Instant.now().minusSeconds(600)));
        if (expiry != null) builder.expirationTime(Date.from(expiry));
        var claims = builder.build();
        var signed = new SignedJWT(new JWSHeader(JWSAlgorithm.RS256), claims);
        signed.sign(new RSASSASigner(key.getPrivate()));
        return signed.serialize();
    }

    @Test
    void signatureIssuerAudienceAndExpiryAreRequired() throws Exception {
        var key = key();
        var decoder = NimbusJwtDecoder.withPublicKey((RSAPublicKey) key.getPublic()).build();
        decoder.setJwtValidator(SecurityConfiguration.validators("https://issuer.example", "plug-api"));
        var future = Instant.now().plusSeconds(300);
        assertEquals("test-user", decoder.decode(token(key, "https://issuer.example", "plug-api", future)).getSubject());
        assertThrows(JwtException.class, () -> decoder.decode(token(key, "https://other.example", "plug-api", future)));
        assertThrows(JwtException.class, () -> decoder.decode(token(key, "https://issuer.example", "other-api", future)));
        assertThrows(JwtException.class, () -> decoder.decode(token(key, "https://issuer.example", "plug-api", Instant.now().minusSeconds(300))));
        assertThrows(JwtException.class, () -> decoder.decode(token(key(), "https://issuer.example", "plug-api", future)));
        assertThrows(JwtException.class, () -> decoder.decode(token(key, "https://issuer.example", "plug-api", null)));
    }
}
