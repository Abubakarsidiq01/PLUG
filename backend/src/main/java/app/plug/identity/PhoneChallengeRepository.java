package app.plug.identity;

import app.plug.identity.IdentityRecords.ChallengeRow;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.Optional;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

// One-time code challenges. The attempt count is a column rather than a field in memory,
// so the attempt limit survives a restart and cannot be reset by making the service fail.
class PhoneChallengeRepository {
    private static final RowMapper<ChallengeRow> CHALLENGE = (ResultSet row, int index) -> new ChallengeRow(
            row.getString("id"), row.getString("phone_hash"), row.getString("code_hash"),
            row.getInt("attempts_used"), row.getTimestamp("expires_at").toInstant(),
            Optional.ofNullable(row.getTimestamp("consumed_at")).map(Timestamp::toInstant).orElse(null));

    private final JdbcTemplate jdbc;

    PhoneChallengeRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    String create(String phoneHash, String codeHash, Instant expiresAt) {
        // Expired challenges are cleared on the way past rather than by a separate job, so
        // the table stays the size of one expiry window.
        jdbc.update("DELETE FROM phone_challenges WHERE expires_at < now() - interval '1 hour'");
        String id = Secrets.identifier("cha_");
        jdbc.update("INSERT INTO phone_challenges (id, phone_hash, code_hash, expires_at) VALUES (?, ?, ?, ?)",
                id, phoneHash, codeHash, Timestamp.from(expiresAt));
        return id;
    }

    Optional<ChallengeRow> find(String challengeId) {
        return jdbc.query("SELECT id, phone_hash, code_hash, attempts_used, expires_at, consumed_at"
                        + " FROM phone_challenges WHERE id = ?", CHALLENGE, challengeId).stream().findFirst();
    }

    // Returns the attempt count after the increment. Counting in the database rather than
    // in the service means two attempts arriving at once are both counted, and doing it in
    // its own transaction means a wrong code still spends an attempt: a refusal rolls the
    // caller's transaction back, and an attempt limit that unwinds with it is not a limit.
    @org.springframework.transaction.annotation.Transactional(
            propagation = org.springframework.transaction.annotation.Propagation.REQUIRES_NEW)
    int countAttempt(String challengeId) {
        Integer used = jdbc.queryForObject("UPDATE phone_challenges SET attempts_used = attempts_used + 1"
                + " WHERE id = ? RETURNING attempts_used", Integer.class, challengeId);
        return used == null ? Integer.MAX_VALUE : used;
    }

    // Returns false when the challenge was already consumed, which is what stops one
    // accepted code from being exchanged for two sessions.
    boolean consume(String challengeId, int maximumAttempts) {
        return jdbc.update("UPDATE phone_challenges SET consumed_at = now()"
                + " WHERE id = ? AND consumed_at IS NULL AND expires_at > clock_timestamp()"
                + " AND attempts_used <= ?", challengeId, maximumAttempts) == 1;
    }
}
