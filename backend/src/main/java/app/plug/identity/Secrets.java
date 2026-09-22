package app.plug.identity;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.UUID;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

// Everything in the identity module that has to be unguessable, or compared without
// leaking how close a wrong answer was, goes through here.
//
// Two different one-way functions, for two different reasons:
//   token()/hashToken()  — the value already has 256 bits of entropy, so a plain digest
//                          is enough and a lookup stays a single indexed read.
//   hashSubject()        — a phone number or a six-digit code lives in a space small
//                          enough to enumerate on a laptop, so those are keyed with a
//                          server-held pepper. A stolen database alone reveals neither.
final class Secrets {
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Base64.Encoder ENCODER = Base64.getUrlEncoder().withoutPadding();

    private final byte[] pepper;

    Secrets(String pepper) {
        this.pepper = pepper.getBytes(StandardCharsets.UTF_8);
    }

    static String identifier(String prefix) {
        return prefix + UUID.randomUUID();
    }

    // 256 bits from the system generator. The prefix is there so a value found in a
    // support conversation or a crash report can be recognised and revoked.
    static String token(String prefix) {
        byte[] material = new byte[32];
        RANDOM.nextBytes(material);
        return prefix + ENCODER.encodeToString(material);
    }

    static String hashToken(String token) {
        return ENCODER.encodeToString(digest(token.getBytes(StandardCharsets.UTF_8)));
    }

    String hashSubject(String value) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(pepper, "HmacSHA256"));
            return ENCODER.encodeToString(mac.doFinal(value.getBytes(StandardCharsets.UTF_8)));
        } catch (java.security.GeneralSecurityException exception) {
            throw new IllegalStateException("HmacSHA256 is required and is part of the platform.");
        }
    }

    // A code the person can read back from a message. Generated from the same source as a
    // token: a predictable code is a code an attacker does not have to guess.
    static String numericCode(int digits) {
        var code = new StringBuilder(digits);
        for (int position = 0; position < digits; position++) {
            code.append(RANDOM.nextInt(10));
        }
        return code.toString();
    }

    // A wrong answer must cost exactly as much time as a right one. String.equals stops at
    // the first differing character, which tells an attacker how much of a guess was right.
    static boolean matches(String expectedHash, String candidateHash) {
        return MessageDigest.isEqual(expectedHash.getBytes(StandardCharsets.UTF_8),
                candidateHash.getBytes(StandardCharsets.UTF_8));
    }

    private static byte[] digest(byte[] value) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(value);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is required and is part of the platform.");
        }
    }
}
