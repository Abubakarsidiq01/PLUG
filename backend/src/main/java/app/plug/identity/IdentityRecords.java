package app.plug.identity;

import java.time.Instant;

// The rows this module reads back, named so the services never pass raw maps around. They
// carry no token and no phone number: both are stored one-way and neither is ever needed
// in readable form again.
final class IdentityRecords {
    private IdentityRecords() {}

    record UserRow(String id, AccountType type, String status, Instant createdAt) {
        boolean isActive() {
            return "active".equals(status);
        }
    }

    record SessionRow(String id, String userId, String chainId, AccountType accountType,
            Instant accessExpiresAt, Instant refreshExpiresAt, boolean multiFactorVerified,
            Instant createdAt, Instant lastUsedAt, Instant revokedAt, String revokedReason) {
        boolean isLive(Instant now) {
            return revokedAt == null && refreshExpiresAt.isAfter(now);
        }
    }

    record ConsentRow(String version, Instant acceptedAt) {}

    record ChallengeRow(String id, String phoneHash, String codeHash, int attemptsUsed,
            Instant expiresAt, Instant consumedAt) {}
}
