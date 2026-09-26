package app.plug.identity;

import app.plug.identity.IdentityRecords.SessionRow;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

// Sessions, stored so that revoking one is a write rather than a wait. Tokens reach this
// class already hashed; the readable values exist only in the response that leaves the
// service and in the Keychain on the device.
class SessionRepository {
    private static final String COLUMNS = "s.id, s.user_id, s.chain_id, u.account_type, s.access_expires_at,"
            + " s.refresh_expires_at, s.mfa_verified, s.created_at, s.last_used_at, s.revoked_at, s.revoked_reason";

    private static final RowMapper<SessionRow> SESSION = (ResultSet row, int index) -> new SessionRow(
            row.getString("id"), row.getString("user_id"), row.getString("chain_id"),
            AccountType.fromStorage(row.getString("account_type")),
            row.getTimestamp("access_expires_at").toInstant(),
            row.getTimestamp("refresh_expires_at").toInstant(),
            row.getBoolean("mfa_verified"),
            row.getTimestamp("created_at").toInstant(),
            row.getTimestamp("last_used_at").toInstant(),
            Optional.ofNullable(row.getTimestamp("revoked_at")).map(Timestamp::toInstant).orElse(null),
            row.getString("revoked_reason"));

    private final JdbcTemplate jdbc;

    SessionRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    String insert(String userId, String chainId, String accessTokenHash, String refreshTokenHash,
            Instant accessExpiresAt, Instant refreshExpiresAt, boolean multiFactorVerified) {
        String id = Secrets.identifier("ses_");
        jdbc.update("INSERT INTO sessions (id, user_id, chain_id, access_token_hash, refresh_token_hash,"
                        + " access_expires_at, refresh_expires_at, mfa_verified)"
                        + " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                id, userId, chainId, accessTokenHash, refreshTokenHash,
                Timestamp.from(accessExpiresAt), Timestamp.from(refreshExpiresAt), multiFactorVerified);
        return id;
    }

    // The authentication read. Revocation and expiry are part of the predicate rather than
    // checked afterwards, so there is no window in which a revoked session still resolves.
    Optional<SessionRow> findLiveByAccessTokenHash(String accessTokenHash) {
        return jdbc.query("SELECT " + COLUMNS + " FROM sessions s JOIN users u ON u.id = s.user_id"
                        + " WHERE s.access_token_hash = ? AND s.revoked_at IS NULL"
                        + " AND s.access_expires_at > now() AND u.status = 'active'",
                SESSION, accessTokenHash).stream().findFirst();
    }

    // Deliberately finds revoked rows too. A refresh token that was already rotated has to
    // be recognised as a replay, and a row this query skipped would look like a typo.
    Optional<SessionRow> findByRefreshTokenHash(String refreshTokenHash) {
        return jdbc.query("SELECT " + COLUMNS + " FROM sessions s JOIN users u ON u.id = s.user_id"
                        + " WHERE s.refresh_token_hash = ?", SESSION, refreshTokenHash).stream().findFirst();
    }

    Optional<SessionRow> findOwned(String sessionId, String userId) {
        return jdbc.query("SELECT " + COLUMNS + " FROM sessions s JOIN users u ON u.id = s.user_id"
                        + " WHERE s.id = ? AND s.user_id = ? AND s.revoked_at IS NULL",
                SESSION, sessionId, userId).stream().findFirst();
    }

    List<SessionRow> findLiveForUser(String userId, int limit) {
        return jdbc.query("SELECT " + COLUMNS + " FROM sessions s JOIN users u ON u.id = s.user_id"
                        + " WHERE s.user_id = ? AND s.revoked_at IS NULL AND s.refresh_expires_at > now()"
                        + " ORDER BY s.created_at DESC LIMIT ?", SESSION, userId, limit);
    }

    // Returns false when the row was already revoked. Refresh uses that answer: losing the
    // race to revoke means another caller spent this token first, and the only safe reading
    // of two callers holding one refresh token is that it leaked.
    boolean revoke(String sessionId, String reason) {
        return jdbc.update("UPDATE sessions SET revoked_at = now(), revoked_reason = ?"
                + " WHERE id = ? AND revoked_at IS NULL", reason, sessionId) == 1;
    }

    // Its own transaction: this is called on the replay path, immediately before the
    // caller throws. Revocation that rolls back with the refusal leaves the leaked chain
    // working, which is the whole thing rotation exists to prevent.
    @org.springframework.transaction.annotation.Transactional(
            propagation = org.springframework.transaction.annotation.Propagation.REQUIRES_NEW)
    int revokeChain(String chainId, String reason) {
        return jdbc.update("UPDATE sessions SET revoked_at = now(), revoked_reason = ?"
                + " WHERE chain_id = ? AND revoked_at IS NULL", reason, chainId);
    }

    int revokeAllForUser(String userId, String reason) {
        return jdbc.update("UPDATE sessions SET revoked_at = now(), revoked_reason = ?"
                + " WHERE user_id = ? AND revoked_at IS NULL", reason, userId);
    }

    void touch(String sessionId) {
        jdbc.update("UPDATE sessions SET last_used_at = now() WHERE id = ?", sessionId);
    }
}
