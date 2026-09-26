package app.plug.identity;

import app.plug.foundation.ApiException;
import app.plug.identity.IdentityRecords.ChallengeRow;
import java.time.Clock;
import java.time.Instant;
import org.springframework.transaction.annotation.Transactional;

// Phone verification: issue a code, then accept exactly one correct answer to it inside a
// short window. Three separate controls apply, because each one covers a different attack.
//
//   the rate limits    bound how often codes can be asked for at all
//   the attempt limit  bounds guesses against one challenge
//   the expiry         bounds how long a leaked code is worth anything
//
// A wrong code and an expired one are both validation_failed, distinguished by the details
// token the client branches on. Running out of attempts is rate_limited: the thing that
// stopped the caller was a limit, and saying so lets a real person understand the wait.
class PhoneVerificationService {
    private static final int CODE_DIGITS = 6;

    private final PhoneChallengeRepository challenges;
    private final OtpRateLimiter limiter;
    private final PhoneCodeSender sender;
    private final AuditLog audit;
    private final Secrets secrets;
    private final IdentitySettings settings;
    private final Clock clock;

    PhoneVerificationService(PhoneChallengeRepository challenges, OtpRateLimiter limiter, PhoneCodeSender sender,
            AuditLog audit, Secrets secrets, IdentitySettings settings, Clock clock) {
        this.challenges = challenges;
        this.limiter = limiter;
        this.sender = sender;
        this.audit = audit;
        this.secrets = secrets;
        this.settings = settings;
        this.clock = clock;
    }

    record StartedChallenge(String challengeId, Instant expiresAt, int attemptsRemaining) {}

    // The response is the same whether or not the number is already known to PLUG. An
    // endpoint that answers differently for a known number is an account-enumeration tool.
    @Transactional
    StartedChallenge start(String phoneNumber, String addressPrefix) {
        String phoneHash = secrets.hashSubject(phoneNumber);
        limiter.checkStart(phoneHash, addressPrefix);
        if (!sender.isAvailable()) {
            audit.recordAnonymous("otp.start_unavailable", addressPrefix, "no_delivery_channel");
            throw ApiException.dependencyUnavailable(
                    "We cannot send codes right now. Choose another sign-in method or continue as a guest.", 60);
        }
        String code = Secrets.numericCode(CODE_DIGITS);
        Instant expiresAt = clock.instant().plus(settings.phoneCodeTtl());
        String challengeId = challenges.create(phoneHash, secrets.hashSubject(code), expiresAt);
        sender.send(phoneNumber, code);
        audit.recordAnonymous("otp.started", addressPrefix, null);
        return new StartedChallenge(challengeId, expiresAt, settings.phoneCodeAttempts());
    }

    // Returns the hashed phone number the challenge was issued for, which is what the
    // account layer matches an identity against. The number itself is never recovered.
    @Transactional
    String verify(String challengeId, String code, String addressPrefix) {
        limiter.checkVerify(challengeId, addressPrefix);
        // An unknown challenge id is reported as an expired one. Telling a caller that a
        // challenge never existed distinguishes a guessed id from a real one.
        ChallengeRow challenge = challenges.find(challengeId).orElseThrow(PhoneVerificationService::expired);
        if (challenge.consumedAt() != null || !challenge.expiresAt().isAfter(clock.instant())) {
            throw expired();
        }
        if (challenge.attemptsUsed() >= settings.phoneCodeAttempts()) {
            throw ApiException.rateLimited(Math.toIntExact(settings.phoneCodeTtl().toSeconds()));
        }
        int used = challenges.countAttempt(challengeId);
        if (used > settings.phoneCodeAttempts()) {
            throw ApiException.rateLimited(Math.toIntExact(settings.phoneCodeTtl().toSeconds()));
        }
        // Both sides are hashes of the same length, compared in constant time. Comparing
        // the codes themselves leaks their length and their matching prefix through timing.
        if (!Secrets.matches(challenge.codeHash(), secrets.hashSubject(code))) {
            audit.recordAnonymous("otp.failed", addressPrefix, "invalid_code attempts=" + used);
            if (used >= settings.phoneCodeAttempts()) {
                throw ApiException.rateLimited(Math.toIntExact(settings.phoneCodeTtl().toSeconds()));
            }
            throw ApiException.validation("code", "invalid", "That code is not correct.");
        }
        if (!challenges.consume(challengeId, settings.phoneCodeAttempts())) {
            // Another caller already exchanged this challenge. One accepted code buys one
            // session, never two.
            throw expired();
        }
        limiter.clearChallenge(challengeId);
        audit.recordAnonymous("otp.verified", addressPrefix, null);
        return challenge.phoneHash();
    }

    private static ApiException expired() {
        return ApiException.validation("code", "expired", "That code has expired. Request a new one.");
    }
}
