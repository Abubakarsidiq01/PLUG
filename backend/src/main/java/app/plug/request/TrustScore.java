package app.plug.request;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import org.springframework.jdbc.core.JdbcTemplate;

/// Trust score v1 (P3.S13 and P3.S14; manual v4 §12C.2, §12C.3, §19A.5; contract 0.7.0
/// ProviderScoreBreakdown). Owner decisions 2026-11-17, the honest v1 rules:
///  - completion: completed jobs / confirmed bookings whose outcome is known. A booking still in
///    progress (before its slot + 3 h completion) does not count yet. An asker's cancellation leaves
///    the denominator (the schema records no cancel actor, and cancel clears confirmed_at); a release
///    or timeout before confirming is not a booking. Null below 3 such bookings. PLUG records no
///    provider failure after confirming yet (no provider cancel or no-show), so in v1 the only known
///    outcome is completed and completion is 100 whenever it has evidence. That is the rule, not a bug:
///    a provider-side failure, once recorded, is the second outcome counted in "decided" below.
///  - responsiveness: answered / (answered + silent). Answered is an offer or a decline by respond_by;
///    a reply after it is still silence (owner rule: silence is no reply by respond_by). An open match
///    still inside respond_by counts as neither. Null below 5 matches.
///  - reliability: null until on-time and price evidence exists (Phase 5 reviews), never faked; its
///    basis is the confirmed jobs it will rest on (contract ScoreComponent.basis), as completion's.
///  - standing: 100 while active, 0 while suspended; basis is days since the profile was created or
///    its standing last changed.
///  - value: the weighted mean of the non-null components, completion 25, reliability 15,
///    responsiveness 10, standing 10 (customer rating, 40, arrives in Phase 5). No recency weighting.
///  - New: fewer than 3 completed jobs shows state new and no value, never 0 (§12C.3).
/// Reads compute it live, stamped with the last recompute. recompute() runs in the transaction of every event that can move it and
/// writes provider_scores (offers and match ranking read it) and a score_history row per change.
class TrustScore {
    record Component(@JsonInclude(JsonInclude.Include.ALWAYS) Integer value, int basis) {}
    record Breakdown(String version, Component completion, Component reliability, Component responsiveness,
            Component standing, @JsonInclude(JsonInclude.Include.ALWAYS) Object customerRating, Instant updatedAt) {}
    record Score(RequestPayloads.ProviderScore score, Breakdown breakdown, String standing, int value, Double responseRate) {}

    static final int MIN_BOOKINGS = 3;
    static final int MIN_MATCHES = 5;
    static final int MIN_COMPLETED_FOR_VALUE = 3;

    private final JdbcTemplate jdbc;
    private final Clock clock;

    TrustScore(JdbcTemplate jdbc, Clock clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    /// The live score of a provider who has a profile.
    Score compute(String provider) {
        Instant now = clock.instant();
        var facts = jdbc.queryForMap("""
                SELECT pp.standing, COALESCE(pp.standing_changed_at, pp.created_at) AS since,
                       -- The last recompute (every event runs one), else the profile's creation: stable across reads.
                       COALESCE(max(ps.updated_at), pp.created_at) AS updated_at,
                       -- Confirmed bookings with a known outcome. Completed is the only one PLUG records today;
                       -- a provider cancel or no-show joins this count, and only this one, once recorded.
                       count(v.id) FILTER (WHERE v.status = 'confirmed' AND r.status = 'completed') AS decided
                  FROM provider_profiles pp
                  LEFT JOIN request_reservations v ON v.provider_id = pp.user_id
                  LEFT JOIN requests r ON r.id = v.request_id
                  LEFT JOIN provider_scores ps ON ps.user_id = pp.user_id
                 WHERE pp.user_id = ? GROUP BY pp.user_id
                """, provider);
        int decided = ((Number) facts.get("decided")).intValue();
        int completed = decided;
        boolean active = "active".equals(facts.get("standing"));
        Instant since = ((Timestamp) facts.get("since")).toInstant();
        Instant updated = ((Timestamp) facts.get("updated_at")).toInstant();
        RequestService.Responsiveness replies = responsiveness(provider);
        int matches = replies.answered() + replies.silent();
        Component completion = new Component(decided >= MIN_BOOKINGS ? percent(completed, decided) : null, decided);
        Component reliability = new Component(null, decided);
        Component responsiveness = new Component(matches >= MIN_MATCHES ? percent(replies.answered(), matches) : null, matches);
        Component standing = new Component(active ? 100 : 0, (int) Math.max(0, Duration.between(since, now).toDays()));
        double weighted = 0;
        int weights = 0;
        for (var part : new Object[][] {{completion, 25}, {reliability, 15}, {responsiveness, 10}, {standing, 10}}) {
            Integer value = ((Component) part[0]).value();
            if (value == null) continue;
            weighted += value * (int) part[1];
            weights += (int) part[1];
        }
        // Standing is never null, so there is always a weight.
        int value = (int) Math.round(weighted / weights);
        var score = completed < MIN_COMPLETED_FOR_VALUE ? new RequestPayloads.ProviderScore("new", null, completed)
                : new RequestPayloads.ProviderScore("scored", value, completed);
        Double rate = matches >= MIN_MATCHES ? Math.round(1000.0 * replies.answered() / matches) / 1000.0 : null;
        return new Score(score, new Breakdown("v1", completion, reliability, responsiveness, standing, null, updated),
                active ? "active" : "suspended", value, rate);
    }

    /// Recomputes and stores a provider's score; a change is logged with its cause. Does nothing for
    /// a seed offer's missing provider or a provider without a profile.
    void recompute(String provider, String cause) {
        if (provider == null) return;
        // The score row is the per-provider lock, so concurrent events log one change each, in order.
        if (jdbc.update("INSERT INTO provider_scores(user_id) SELECT user_id FROM provider_profiles WHERE user_id=?"
                + " ON CONFLICT (user_id) DO UPDATE SET user_id=EXCLUDED.user_id", provider) == 0) return;
        Score s = compute(provider);
        Breakdown b = s.breakdown();
        Instant now = clock.instant();
        int completed = s.score().completedJobs();
        jdbc.update("UPDATE provider_scores SET completed_jobs=?,response_rate=?,trust_score=?,updated_at=? WHERE user_id=?",
                completed, s.responseRate(), s.score().value(), Timestamp.from(now), provider);
        // Standing's day count moves daily on its own, so the log keeps only its value.
        String components = "{\"completion\":" + json(b.completion()) + ",\"reliability\":" + json(b.reliability())
                + ",\"responsiveness\":" + json(b.responsiveness()) + ",\"standing\":{\"value\":" + b.standing().value() + "}}";
        jdbc.update("""
                WITH last AS (SELECT new_value, completed_jobs, components FROM score_history
                               WHERE provider_id = ? ORDER BY id DESC LIMIT 1)
                INSERT INTO score_history(provider_id, old_value, new_value, completed_jobs, components, cause, at)
                SELECT ?, (SELECT new_value FROM last), ?, ?, ?::jsonb, ?, ?
                 WHERE NOT EXISTS (SELECT 1 FROM last WHERE new_value = ? AND completed_jobs = ? AND components = ?::jsonb)
                """, provider, provider, s.value(), completed, components, cause, Timestamp.from(now),
                s.value(), completed, components);
    }

    private static String json(Component component) {
        return "{\"value\":" + component.value() + ",\"basis\":" + component.basis() + "}";
    }

    private static int percent(int part, int whole) { return (int) Math.round(100.0 * part / whole); }

    /// The facts responsiveness rests on, in one query: matches answered by respond_by (an offer or a
    /// decline) and matches left silent: a reply after respond_by, or no reply where the inbox shows
    /// MatchStatus expired. Closed, not_chosen and open count as neither.
    RequestService.Responsiveness responsiveness(String provider) {
        String respondBy = "m.notified_at + interval '" + RequestService.REPLY_WINDOW.toSeconds() + " seconds'";
        return jdbc.queryForObject("""
                SELECT count(*) FILTER (WHERE m.replied_at <= %1$s) AS answered,
                       count(*) FILTER (WHERE m.replied_at > %1$s OR (m.replied_at IS NULL
                           AND NOT EXISTS (SELECT 1 FROM request_reservations v
                                            WHERE v.request_id = m.request_id AND v.provider_id = m.provider_id)
                           AND NOT EXISTS (SELECT 1 FROM request_offers o
                                            WHERE o.request_id = m.request_id AND o.provider_id = m.provider_id)
                           AND CASE WHEN c.chosen IS NOT NULL THEN c.chosen >= %1$s
                                    WHEN r.status = 'canceled' THEN r.updated_at >= %1$s
                                    WHEN r.status = 'expired' THEN LEAST(r.expires_at, r.updated_at) >= %1$s
                                    WHEN r.status IN ('submitted','routed','awaiting_responses','ranked') THEN ? >= %1$s
                                    ELSE false END)) AS silent
                  FROM request_matches m
                  JOIN requests r ON r.id = m.request_id
                  -- When the asker first chose someone else's offer.
                  LEFT JOIN LATERAL (SELECT min(v.created_at) AS chosen FROM request_reservations v
                                      WHERE v.request_id = m.request_id AND v.provider_id IS DISTINCT FROM m.provider_id) c ON true
                 WHERE m.provider_id = ?
                """.formatted(respondBy), (rs, row) -> new RequestService.Responsiveness(rs.getInt("answered"), rs.getInt("silent")),
                Timestamp.from(clock.instant()), provider);
    }
}
