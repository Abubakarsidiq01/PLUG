package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.security.PlugPrincipal;
import com.fasterxml.jackson.annotation.JsonInclude;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import org.slf4j.MDC;
import org.springframework.jdbc.core.JdbcTemplate;

/// Read-only staff inspection of the skill vocabulary and recent classification decisions
/// (manual v4 P2-TWO.S12; docs/handoff/phase2-admin-contract-review.md). Every route sits under
/// /v1/admin, which SecurityConfiguration already limits to the admin scope with a completed
/// second factor. Nothing here returns ask text, coordinates or identities; a refusal is only
/// its rule and time. Every read is itself written to the audit log.
public class AdminInspection {
    public record Skill(String tag, String display, String parent, boolean requiresLicence, int providerCount) {}
    public record CustomSkill(String tag, String label, int providerCount) {}
    public record Vocabulary(List<Skill> skills, List<CustomSkill> customSkills) {}
    public record Gap(String term, int seenCount, Instant firstSeen, Instant lastSeen) {}
    // Always present, null included: the console must tell "unclassified" from "missing".
    public record Classification(String askId, Instant createdAt,
            @JsonInclude(JsonInclude.Include.ALWAYS) String askType, String state, List<String> skillTags) {}
    public record Refusal(String rule, Instant occurredAt) {}
    public record Page<T>(List<T> items, @JsonInclude(JsonInclude.Include.ALWAYS) String nextCursor) {}

    static final int DEFAULT_LIMIT = 50;
    static final int MAX_LIMIT = 100;

    private final JdbcTemplate jdbc;
    private final Clock clock;
    private final SkillVocabulary vocabulary;

    public AdminInspection(JdbcTemplate jdbc, Clock clock, SkillVocabulary vocabulary) {
        this.jdbc = jdbc;
        this.clock = clock;
        this.vocabulary = vocabulary;
    }

    public Vocabulary vocabulary(PlugPrincipal staff) {
        audit(staff, "vocabulary");
        var counts = new java.util.HashMap<String, Integer>();
        jdbc.query("SELECT skill_tag, count(*) FROM provider_skills GROUP BY skill_tag",
                rs -> { counts.put(rs.getString(1), rs.getInt(2)); });
        List<Skill> skills = vocabulary.all().stream()
                .map(s -> new Skill(s.tag(), s.display(), s.parent(), s.requiresLicence(), counts.getOrDefault(s.tag(), 0)))
                .toList();
        List<CustomSkill> custom = jdbc.query("""
                SELECT tag, min(label) AS label, count(*) AS providers FROM provider_custom_skills
                 GROUP BY tag ORDER BY count(*) DESC, tag LIMIT 500
                """, (rs, n) -> new CustomSkill(rs.getString("tag"), rs.getString("label"), rs.getInt("providers")));
        return new Vocabulary(skills, custom);
    }

    /// Terms providers used that matched no listed skill. User content: the console shows it
    /// redacted by default and never sends it to analytics.
    public Page<Gap> gaps(PlugPrincipal staff, String cursor, int limit) {
        audit(staff, "vocabulary_gaps");
        int size = size(limit);
        String[] after = cursor == null ? null : decode(cursor, 2);
        List<Gap> rows = after == null
                ? jdbc.query("SELECT term,seen_count,first_seen,last_seen FROM vocabulary_gaps"
                        + " ORDER BY last_seen DESC, term LIMIT ?", this::gap, size + 1)
                : jdbc.query("SELECT term,seen_count,first_seen,last_seen FROM vocabulary_gaps"
                        + " WHERE (last_seen, term) < (?, ?) ORDER BY last_seen DESC, term LIMIT ?",
                        this::gap, Timestamp.from(instant(after[0])), after[1], size + 1);
        return page(rows, size, g -> encode(g.lastSeen().toString(), g.term()));
    }

    /// Current decisions only: asks keep their resolved type, not a history of reclassification.
    public Page<Classification> classifications(PlugPrincipal staff, String cursor, int limit) {
        audit(staff, "classifications");
        int size = size(limit);
        String[] after = cursor == null ? null : decode(cursor, 2);
        String select = """
                SELECT a.id, a.created_at, a.ask_type, a.clarification_id IS NOT NULL AS awaiting,
                       COALESCE(c.skill_tags, '{}') AS skill_tags
                  FROM asks a LEFT JOIN request_constraints c ON c.request_id = a.request_id
                """;
        List<Classification> rows = after == null
                ? jdbc.query(select + " ORDER BY a.created_at DESC, a.id DESC LIMIT ?", this::classification, size + 1)
                : jdbc.query(select + " WHERE (a.created_at, a.id) < (?, ?) ORDER BY a.created_at DESC, a.id DESC LIMIT ?",
                        this::classification, Timestamp.from(instant(after[0])), after[1], size + 1);
        return page(rows, size, c -> encode(c.createdAt().toString(), c.askId()));
    }

    /// Restricted-intent refusals from the audit log: the rule and the time, nothing else.
    public Page<Refusal> refusals(PlugPrincipal staff, String cursor, int limit) {
        audit(staff, "refusals");
        int size = size(limit);
        String[] after = cursor == null ? null : decode(cursor, 1);
        long before;
        try { before = after == null ? Long.MAX_VALUE : Long.parseLong(after[0]); }
        catch (NumberFormatException invalid) { throw invalidCursor(); }
        List<long[]> ids = new ArrayList<>();
        List<Refusal> rows = jdbc.query("""
                SELECT id, occurred_at, substring(reason from 19) AS rule FROM audit_events
                 WHERE reason LIKE 'restricted_intent:%' AND id < ? ORDER BY id DESC LIMIT ?
                """, (rs, n) -> {
                    ids.add(new long[] {rs.getLong("id")});
                    return new Refusal(rs.getString("rule"), rs.getTimestamp("occurred_at").toInstant());
                }, before, size + 1);
        String next = rows.size() > size ? encode(Long.toString(ids.get(size - 1)[0])) : null;
        return new Page<>(rows.subList(0, Math.min(size, rows.size())), next);
    }

    private Gap gap(java.sql.ResultSet rs, int n) throws java.sql.SQLException {
        return new Gap(rs.getString("term"), rs.getInt("seen_count"), rs.getTimestamp("first_seen").toInstant(),
                rs.getTimestamp("last_seen").toInstant());
    }

    private Classification classification(java.sql.ResultSet rs, int n) throws java.sql.SQLException {
        String[] tags = (String[]) rs.getArray("skill_tags").getArray();
        String type = rs.getString("ask_type");
        String state = type != null ? "resolved" : rs.getBoolean("awaiting") ? "awaiting_clarification" : "unresolved";
        return new Classification(rs.getString("id"), rs.getTimestamp("created_at").toInstant(), type, state,
                Arrays.asList(tags));
    }

    private static <T> Page<T> page(List<T> rows, int size, java.util.function.Function<T, String> cursorOf) {
        String next = rows.size() > size ? cursorOf.apply(rows.get(size - 1)) : null;
        return new Page<>(rows.subList(0, Math.min(size, rows.size())), next);
    }

    /// The page size from the query string, as text so a non-number is a 400, not a 500.
    static int limit(String value) {
        if (value == null) return DEFAULT_LIMIT;
        try { return size(Integer.parseInt(value)); }
        catch (NumberFormatException invalid) { return size(-1); }
    }

    private static int size(int limit) {
        if (limit < 1 || limit > MAX_LIMIT) {
            throw ApiException.validation("limit", "out_of_range", "Use a page size from 1 to " + MAX_LIMIT + ".");
        }
        return limit;
    }

    private static String encode(String... parts) {
        return Base64.getUrlEncoder().withoutPadding()
                .encodeToString(String.join("\n", parts).getBytes(StandardCharsets.UTF_8));
    }

    private static String[] decode(String cursor, int parts) {
        try {
            if (cursor.length() > 512) throw invalidCursor();
            String[] values = new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8).split("\n", -1);
            if (values.length != parts) throw invalidCursor();
            return values;
        } catch (IllegalArgumentException invalid) {
            throw invalidCursor();
        }
    }

    private static Instant instant(String value) {
        try { return Instant.parse(value); }
        catch (RuntimeException invalid) { throw invalidCursor(); }
    }

    private static ApiException invalidCursor() {
        return ApiException.validation("cursor", "invalid", "Start again from the first page.");
    }

    private void audit(PlugPrincipal staff, String resource) {
        jdbc.update("INSERT INTO audit_events(occurred_at,actor_id,actor_role,action,resource,resource_id,reason,request_id)"
                        + " VALUES(?,?,'admin','admin.read',?,'list',NULL,?)",
                Timestamp.from(clock.instant()), staff.userId(), resource, MDC.get("request_id"));
    }
}
