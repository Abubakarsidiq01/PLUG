package app.plug.identity;

import app.plug.identity.IdentityRecords.ConsentRow;
import app.plug.identity.IdentityRecords.UserRow;
import java.sql.ResultSet;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

// Users, the identities attached to them, and what they consented to. Every statement is
// parameterised: no value from a caller is ever assembled into SQL text, so there is no
// path from a request body to the query planner (manual.docx 25.3).
class IdentityRepository {
    private static final RowMapper<UserRow> USER = (ResultSet row, int index) -> new UserRow(
            row.getString("id"), AccountType.fromStorage(row.getString("account_type")),
            row.getString("status"), row.getTimestamp("created_at").toInstant());

    private final JdbcTemplate jdbc;

    IdentityRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    UserRow createUser(AccountType type) {
        String id = Secrets.identifier("usr_");
        jdbc.update("INSERT INTO users (id, account_type) VALUES (?, ?)", id, type.storage());
        return findUser(id).orElseThrow();
    }

    Optional<UserRow> findUser(String userId) {
        return jdbc.query("SELECT id, account_type, status, created_at FROM users WHERE id = ?", USER, userId)
                .stream().findFirst();
    }

    // The account a proven identity belongs to, if any. Only a live account counts: a
    // deleted one must not be resurrected by signing in with the same Apple ID.
    Optional<UserRow> findUserByIdentity(String provider, String subjectHash) {
        return jdbc.query("SELECT u.id, u.account_type, u.status, u.created_at FROM users u"
                        + " JOIN identities i ON i.user_id = u.id"
                        + " WHERE i.provider = ? AND i.subject_hash = ? AND u.status = 'active'",
                USER, provider, subjectHash).stream().findFirst();
    }

    // Returns false when the subject already belongs to a different account. The unique
    // constraint decides, not a prior read, because two upgrades can arrive at once and
    // only one of them may win.
    boolean attachIdentity(String userId, String provider, String subjectHash) {
        try {
            jdbc.update("INSERT INTO identities (id, user_id, provider, subject_hash) VALUES (?, ?, ?, ?)",
                    Secrets.identifier("idn_"), userId, provider, subjectHash);
            return true;
        } catch (DuplicateKeyException alreadyAttached) {
            return false;
        }
    }

    void promoteAccountType(String userId, AccountType type) {
        jdbc.update("UPDATE users SET account_type = ?, updated_at = now() WHERE id = ?", type.storage(), userId);
    }

    void markDeleted(String userId) {
        jdbc.update("UPDATE users SET status = 'deleted', deleted_at = now(), updated_at = now()"
                + " WHERE id = ? AND status = 'active'", userId);
    }

    // Recording the same version twice is not an error: a client that retries after a
    // dropped connection should see the acceptance it already made, not a failure.
    void recordConsent(String userId, String version, String requestId) {
        jdbc.update("INSERT INTO consents (user_id, version, request_id) VALUES (?, ?, ?)"
                + " ON CONFLICT (user_id, version) DO NOTHING", userId, version, requestId);
    }

    Optional<ConsentRow> latestConsent(String userId) {
        List<ConsentRow> rows = jdbc.query("SELECT version, accepted_at FROM consents WHERE user_id = ?"
                        + " ORDER BY accepted_at DESC, id DESC LIMIT 1",
                (ResultSet row, int index) -> new ConsentRow(row.getString("version"),
                        row.getTimestamp("accepted_at").toInstant()), userId);
        return rows.stream().findFirst();
    }
}
