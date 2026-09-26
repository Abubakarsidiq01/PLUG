package app.plug.identity;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

// Every number that decides how long a credential lives, in one place, checked before the
// service accepts a request. Section 27.2 of the manual is blunt about why: changing token
// expiry after this phase ripples through every screen that can be open when a session
// ends, so the lifetimes are decided here and written into the contract.
//
// An invalid value stops the process rather than being corrected to something safe-looking.
// A service that starts with a missing pepper or an hour-long access token is worse than a
// service that does not start, because only one of the two gets noticed.
@ConfigurationProperties(prefix = "plug.identity")
public record IdentitySettings(
        boolean enabled,
        String consentVersion,
        String pepper,
        Duration accessTokenTtl,
        Duration refreshTokenTtl,
        Duration guestRefreshTokenTtl,
        Duration phoneCodeTtl,
        int phoneCodeAttempts,
        String appleClientId,
        String appleIssuer,
        String appleJwkSetUri,
        PhoneDelivery phoneDelivery) {

    // Delivery is explicit: no sender, local file for tests, or configured Twilio SMS.
    public enum PhoneDelivery { NONE, DEVELOPMENT, TWILIO }

    public IdentitySettings {
        // Nothing is required while the module is off. The profile that enables it is also
        // the profile that supplies these values, so demanding them here would stop a local
        // backend that never intends to serve an auth route.
        if (enabled) {
            require(consentVersion != null && consentVersion.matches("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"),
                    "plug.identity.consent-version must be the publication date of the terms, as YYYY-MM-DD.");
            // The pepper is what stops a leaked database from being brute-forced back into
            // phone numbers and six-digit codes, both of which live in spaces small enough
            // to enumerate. Starting without one stores them as good as in the clear.
            require(pepper != null && pepper.length() >= 32,
                    "plug.identity.pepper must be at least 32 characters and must come from secret storage.");
            require(isPositive(accessTokenTtl) && accessTokenTtl.toMinutes() <= 60,
                    "plug.identity.access-token-ttl must be positive and no longer than an hour.");
            require(isPositive(refreshTokenTtl) && isPositive(guestRefreshTokenTtl),
                    "plug.identity refresh lifetimes must be positive.");
            require(refreshTokenTtl.compareTo(accessTokenTtl) >= 0
                            && guestRefreshTokenTtl.compareTo(accessTokenTtl) >= 0,
                    "A refresh token that outlives nothing is not a refresh token.");
            require(isPositive(phoneCodeTtl) && phoneCodeTtl.toMinutes() <= 15,
                    "plug.identity.phone-code-ttl must be positive and no longer than fifteen minutes.");
            require(phoneCodeAttempts >= 1 && phoneCodeAttempts <= 10,
                    "plug.identity.phone-code-attempts must be between one and ten.");
            require(appleClientId != null && !appleClientId.isBlank(),
                    "plug.identity.apple-client-id must be the app's bundle identifier.");
            require(appleIssuer != null && appleIssuer.startsWith("https://"),
                    "plug.identity.apple-issuer must be an https issuer.");
            require(appleJwkSetUri != null && appleJwkSetUri.startsWith("https://"),
                    "plug.identity.apple-jwk-set-uri must be an https key set.");
            require(phoneDelivery != null,
                    "plug.identity.phone-delivery must be none, development or twilio.");
        }
    }

    // A guest's refresh window is shorter. It represents a device rather than a person who
    // proved anything, so it is worth less to keep alive and worth more to expire.
    public Duration refreshTtlFor(AccountType type) {
        return type == AccountType.GUEST ? guestRefreshTokenTtl : refreshTokenTtl;
    }

    private static boolean isPositive(Duration value) {
        return value != null && !value.isNegative() && !value.isZero();
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalArgumentException(message);
        }
    }
}
