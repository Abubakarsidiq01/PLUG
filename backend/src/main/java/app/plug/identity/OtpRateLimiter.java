package app.plug.identity;

import app.plug.foundation.ApiException;
import app.plug.foundation.FixedWindowLimiter;
import java.time.Duration;

// Three independent limits, from manual.docx 27.2. An attacker who controls many addresses
// is still bounded by the per-number limit; one with many numbers is still bounded by the
// per-address limit; and one who has a challenge in hand is bounded per challenge. A
// single limit is not a control, it is a speed bump.
//
// The refusal is identical whichever limit was reached, and always names the same wait.
// Distinguishable refusals let a caller map the limits and then work around them.
class OtpRateLimiter {
    private static final int PER_PHONE_MAX = 5;
    private static final Duration PER_PHONE_WINDOW = Duration.ofMinutes(15);
    private static final int PER_ADDRESS_MAX = 20;
    private static final Duration PER_ADDRESS_WINDOW = Duration.ofMinutes(15);
    private static final int PER_CHALLENGE_MAX = 5;
    private static final Duration PER_CHALLENGE_WINDOW = Duration.ofMinutes(10);
    private static final int RETRY_AFTER_SECONDS = 900;

    private final FixedWindowLimiter limiter;
    private final AuditLog audit;

    OtpRateLimiter(AuditLog audit) {
        this(audit, new FixedWindowLimiter(8192));
    }

    OtpRateLimiter(AuditLog audit, FixedWindowLimiter limiter) {
        this.audit = audit;
        this.limiter = limiter;
    }

    void checkStart(String phoneHash, String addressPrefix) {
        consume("otp:start:phone:" + phoneHash, PER_PHONE_MAX, PER_PHONE_WINDOW, addressPrefix);
        consume("otp:start:address:" + addressPrefix, PER_ADDRESS_MAX, PER_ADDRESS_WINDOW, addressPrefix);
    }

    void checkVerify(String challengeId, String addressPrefix) {
        consume("otp:verify:challenge:" + challengeId, PER_CHALLENGE_MAX, PER_CHALLENGE_WINDOW, addressPrefix);
        consume("otp:verify:address:" + addressPrefix, PER_ADDRESS_MAX, PER_ADDRESS_WINDOW, addressPrefix);
    }

    // Called once a code has been accepted, so a person who mistyped twice before getting
    // it right does not carry those attempts into their next sign-in.
    void clearChallenge(String challengeId) {
        limiter.forget("otp:verify:challenge:" + challengeId);
    }

    private void consume(String key, int maximum, Duration window, String addressPrefix) {
        if (!limiter.tryConsume(key, maximum, window)) {
            // Recorded before the refusal so a burst is visible in the audit trail even
            // though the caller is told nothing beyond "too many attempts".
            audit.recordAnonymous("otp.rate_limited", addressPrefix, "limit_reached");
            throw ApiException.rateLimited(RETRY_AFTER_SECONDS);
        }
    }
}
