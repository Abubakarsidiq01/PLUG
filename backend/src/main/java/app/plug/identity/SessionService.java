package app.plug.identity;

import app.plug.foundation.ApiException;
import app.plug.identity.IdentityRecords.SessionRow;
import app.plug.security.PlugPrincipal;
import app.plug.security.SessionAuthenticator;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.transaction.annotation.Transactional;

// Issuing, resolving, rotating and revoking sessions. This is also the security module's
// SessionAuthenticator, which is the only thing the rest of the service knows about it.
//
// Access tokens are opaque and short-lived, and every request resolves one against this
// table. That costs an indexed read per call and buys the property the phase is judged on:
// logout, a lost device or a replayed refresh token stops working at that moment, not
// whenever an expiry catches up with it (manual.docx 25.2).
public class SessionService implements SessionAuthenticator {
    private static final Logger log = LoggerFactory.getLogger(SessionService.class);
    private static final int SESSION_LIST_LIMIT = 50;

    private final SessionRepository sessions;
    private final IdentityRepository identities;
    private final AuditLog audit;
    private final IdentitySettings settings;
    private final Clock clock;

    SessionService(SessionRepository sessions, IdentityRepository identities, AuditLog audit,
            IdentitySettings settings, Clock clock) {
        this.sessions = sessions;
        this.identities = identities;
        this.audit = audit;
        this.settings = settings;
        this.clock = clock;
    }

    // The readable tokens exist here and in the response. They are never logged, never put
    // in the MDC, and never stored anywhere but the caller's Keychain.
    record IssuedSession(String sessionId, String userId, String accessToken, Instant accessExpiresAt,
            String refreshToken, Instant refreshExpiresAt) {
        @Override
        public String toString() {
            return "IssuedSession[redacted]";
        }
    }

    @Transactional
    IssuedSession issue(String userId, AccountType type, boolean multiFactorVerified) {
        return issue(userId, type, Secrets.identifier("chn_"), multiFactorVerified);
    }

    private IssuedSession issue(String userId, AccountType type, String chainId, boolean multiFactorVerified) {
        Instant now = clock.instant();
        Instant accessExpiresAt = now.plus(settings.accessTokenTtl());
        Instant refreshExpiresAt = now.plus(settings.refreshTtlFor(type));
        String accessToken = Secrets.token("pat_");
        String refreshToken = Secrets.token("prt_");
        String sessionId = sessions.insert(userId, chainId, Secrets.hashToken(accessToken),
                Secrets.hashToken(refreshToken), accessExpiresAt, refreshExpiresAt, multiFactorVerified);
        return new IssuedSession(sessionId, userId, accessToken, accessExpiresAt, refreshToken, refreshExpiresAt);
    }

    @Override
    @Transactional
    public Optional<PlugPrincipal> authenticate(String accessToken) {
        // A value that cannot be one of ours is rejected without a database read. The check
        // is on shape only: it must not depend on whether the token exists, or the timing
        // difference would answer the question the 401 is refusing to answer.
        if (!accessToken.startsWith("pat_")) {
            return Optional.empty();
        }
        Optional<SessionRow> row = sessions.findLiveByAccessTokenHash(Secrets.hashToken(accessToken));
        row.ifPresent(session -> sessions.touch(session.id()));
        return row.map(session -> new PlugPrincipal(session.userId(), session.id(),
                session.accountType().scopes(), session.multiFactorVerified()));
    }

    // Rotation, and the replay check that gives rotation its point. A refresh token is
    // spent the moment it is used; seeing a spent one again means the material is in two
    // places, so the whole chain goes rather than just the token that was presented.
    @Transactional
    IssuedSession rotate(String refreshToken) {
        if (!refreshToken.startsWith("prt_")) {
            throw signInAgain();
        }
        SessionRow current = sessions.findByRefreshTokenHash(Secrets.hashToken(refreshToken))
                .orElseThrow(this::signInAgain);
        if (current.revokedAt() != null) {
            if ("rotated".equals(current.revokedReason())) {
                int revoked = sessions.revokeChain(current.chainId(), "replay_detected");
                audit.record(current.userId(), current.accountType().storage(), "session.replay_detected",
                        "session", current.id(), "revoked_sessions=" + revoked);
                log.warn("refresh_replay_detected user={} revoked_sessions={}",
                        PlugPrincipal.hashForLogging(current.userId()), revoked);
            }
            throw signInAgain();
        }
        if (!current.refreshExpiresAt().isAfter(clock.instant())) {
            throw signInAgain();
        }
        // Losing this race means another caller spent the same token first. Two holders of
        // one refresh token is the definition of a leak, so it is treated as one.
        if (!sessions.revoke(current.id(), "rotated")) {
            sessions.revokeChain(current.chainId(), "replay_detected");
            audit.record(current.userId(), current.accountType().storage(), "session.replay_detected",
                    "session", current.id(), "concurrent_rotation");
            throw signInAgain();
        }
        IssuedSession rotated = issue(current.userId(), current.accountType(), current.chainId(),
                current.multiFactorVerified());
        audit.record(current.userId(), current.accountType().storage(), "session.rotated",
                "session", rotated.sessionId(), null);
        return rotated;
    }

    @Transactional
    void revokeCurrent(PlugPrincipal principal, String reason) {
        // A repeated logout is still a success. A client retrying after a dropped
        // connection must not be told that finishing the job it already finished failed.
        sessions.revoke(principal.sessionId(), reason);
        audit.record(principal.userId(), accountRole(principal), "session.revoked",
                "session", principal.sessionId(), reason);
    }

    // Used on an account-security change, such as a guest upgrading to a real identity, and
    // on account deletion. Everything that could still be open somewhere else stops working.
    @Transactional
    void revokeAllForUser(String userId, AccountType type, String reason) {
        int revoked = sessions.revokeAllForUser(userId, reason);
        audit.record(userId, type.storage(), "session.revoked_all", "user", userId,
                reason + " revoked_sessions=" + revoked);
    }

    @Transactional
    void revokeOwned(PlugPrincipal principal, String sessionId) {
        sessions.findOwned(sessionId, principal.userId()).orElseThrow(SessionService::noSuchSession);
        sessions.revoke(sessionId, "revoked_by_user");
        audit.record(principal.userId(), accountRole(principal), "session.revoked", "session", sessionId,
                "revoked_by_user");
    }

    @Transactional(readOnly = true)
    SessionRow requireOwned(PlugPrincipal principal, String sessionId) {
        return sessions.findOwned(sessionId, principal.userId()).orElseThrow(SessionService::noSuchSession);
    }

    @Transactional(readOnly = true)
    List<SessionRow> listOwned(PlugPrincipal principal) {
        return sessions.findLiveForUser(principal.userId(), SESSION_LIST_LIMIT);
    }

    private String accountRole(PlugPrincipal principal) {
        return identities.findUser(principal.userId())
                .map(user -> user.type().storage()).orElse(AuditLog.ACTOR_ANONYMOUS);
    }

    // Unknown, expired, revoked and replayed all produce the same response. Telling them
    // apart is exactly the information an attacker wants from a refresh endpoint.
    private ApiException signInAgain() {
        return ApiException.unauthenticated("Your session has ended. Sign in again.");
    }

    // A session that belongs to someone else is a 404, not a 403: a 403 would confirm that
    // the identifier names a real session (manual.docx 19.4).
    private static ApiException noSuchSession() {
        return ApiException.notFound("No such session.");
    }
}
