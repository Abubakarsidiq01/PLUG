package app.plug.identity;

import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

// The record of what happened to an account, written to a table a rule makes append-only.
// Support answers questions from here rather than from a database client, and the gate
// checks consent against it.
//
// What goes in is an identifier, a category, an outcome and the correlation id. What never
// goes in is a token, a phone number, a code or an authorization header (manual.docx 19.9).
class AuditLog {
    static final String ACTOR_ANONYMOUS = "anonymous";

    private static final Logger log = LoggerFactory.getLogger(AuditLog.class);

    private final JdbcTemplate jdbc;

    AuditLog(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    // Written in its own transaction so a refusal that rolls the caller's work back still
    // leaves the evidence that it was attempted. An audit row that disappears with the
    // thing it was recording is not an audit row.
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void record(String actorId, String actorRole, String action, String resource, String resourceId, String reason) {
        jdbc.update("INSERT INTO audit_events (actor_id, actor_role, action, resource, resource_id, reason, request_id)"
                        + " VALUES (?, ?, ?, ?, ?, ?, ?)",
                actorId, actorRole, action, resource, resourceId, reason, org.slf4j.MDC.get("request_id"));
        log.info("audit action={} resource={} outcome={}", action, resource, reason == null ? "ok" : reason);
    }

    // The counterpart for things that never reach a user row: a rate limit reached before
    // anyone was identified, for example. Counting these is how abuse becomes visible.
    // Its own transaction for the same reason as record above — the caller is usually
    // about to throw, and the rollback would take the evidence with it.
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void recordAnonymous(String action, String addressPrefix, String reason) {
        record(ACTOR_ANONYMOUS, ACTOR_ANONYMOUS, action, "address", addressPrefix, reason);
    }

    Map<String, Object> mostRecent(String actorId) {
        var rows = jdbc.queryForList("SELECT action, resource, reason, occurred_at FROM audit_events"
                + " WHERE actor_id = ? ORDER BY occurred_at DESC, id DESC LIMIT 1", actorId);
        return rows.isEmpty() ? Map.of() : rows.get(0);
    }
}
