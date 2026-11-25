package app.plug.request;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/// The only place a supplier's phone number is handled (contract SupplierOptIn.phone): a keyed
/// hash to find it, an AES-256-GCM copy to send to it, and the masked form staff see. The hash
/// uses the identity pepper with its own prefix, so it never equals the identity hash of the
/// same number. Nothing here logs, and toString never shows a key.
public final class SupplierPhones {
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Base64.Encoder ENCODER = Base64.getUrlEncoder().withoutPadding();
    private final SecretKeySpec pepper;
    private final SecretKeySpec key;

    public SupplierPhones(String pepper, String base64Key) {
        if (pepper == null || pepper.length() < 32) {
            throw new IllegalStateException("plug.identity.pepper is required for supplier messaging.");
        }
        byte[] material;
        try { material = Base64.getDecoder().decode(base64Key == null ? "" : base64Key.strip()); }
        catch (IllegalArgumentException invalid) { material = new byte[0]; }
        if (material.length != 32) {
            throw new IllegalStateException("plug.supplier-messaging.phone-key must be 32 bytes in base64.");
        }
        this.pepper = new SecretKeySpec(pepper.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
        this.key = new SecretKeySpec(material, "AES");
    }

    public String hash(String phone) { return keyed("supplier-phone:" + phone); }

    /// HMAC-SHA256 with the pepper, base64url without padding. Also keys idempotency body hashes.
    String keyed(String value) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(pepper);
            return ENCODER.encodeToString(mac.doFinal(value.getBytes(StandardCharsets.UTF_8)));
        } catch (GeneralSecurityException impossible) {
            throw new IllegalStateException("HmacSHA256 is part of the platform.");
        }
    }

    /// A random 12-byte nonce, then the ciphertext and its 128-bit tag. The aad (the row's phone_hash)
    /// binds the ciphertext to its row, so a value copied onto another supplier fails to decrypt.
    public byte[] encrypt(String phone, String aad) {
        byte[] nonce = new byte[12];
        RANDOM.nextBytes(nonce);
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(128, nonce));
            cipher.updateAAD(aad.getBytes(StandardCharsets.UTF_8));
            byte[] sealed = cipher.doFinal(phone.getBytes(StandardCharsets.UTF_8));
            return ByteBuffer.allocate(nonce.length + sealed.length).put(nonce).put(sealed).array();
        } catch (GeneralSecurityException impossible) {
            throw new IllegalStateException("AES-GCM is part of the platform.");
        }
    }

    /// For the sender (P3.S9). A tampered or foreign value fails the tag check and throws.
    public String decrypt(byte[] stored, String aad) {
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(128, stored, 0, 12));
            cipher.updateAAD(aad.getBytes(StandardCharsets.UTF_8));
            return new String(cipher.doFinal(stored, 12, stored.length - 12), StandardCharsets.UTF_8);
        } catch (GeneralSecurityException invalid) {
            throw new IllegalStateException("A stored supplier number could not be read.");
        }
    }

    public static String mask(String lastTwo) { return "+1 *** *** **" + lastTwo; }

    @Override public String toString() { return "SupplierPhones[redacted]"; }
}
