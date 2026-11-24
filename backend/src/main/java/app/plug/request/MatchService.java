package app.plug.request;

import app.plug.request.RequestPayloads.Constraints;
import app.plug.request.RequestPayloads.Resource;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.Comparator;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;

/// Provider matching (manual v4 §12B.2, §19A.3, P2.S17).
///  1. Match: skill-tag overlap, inside the PROVIDER's own stated radius (never a global
///     default), accepting requests, licensed when a tag requires it, and available in the
///     asked window. The requester never matches themselves.
///  2. Rank: response rate first, then trust score, then distance. A responsive newcomer
///     outranks a high scorer who has gone quiet. A New provider (fewer than three completed jobs,
///     so no stored trust score) and one without five matches of evidence (no response rate) rank
///     on a neutral 50 and 0.5, never 0 (manual v4 §12C.3, P3.S14).
///  A suspended provider is never matched (P3.S14).
///  3. Cap: the best few are notified; there is a hard ceiling that is never lifted, and no provider
///     is notified more than NOTIFICATIONS_PER_HOUR times in any hour (a capped provider is skipped
///     and the next candidate is used).
///  4. Expand (P3.S15, owner decision 2026-11-23, manual v4 SupplierMatcher): the best 6 at t0 (the
///     request's creation), 4 more at t+120s and 4 more at t+240s, each only while the request has
///     fewer than ENOUGH_OFFERS live offers; no new wave from t+300s; at most ABSOLUTE_CAP contacts per
///     request. A wave the worker misses is not caught up later. Every contact keeps its own reply
///     window (respond_by = notified_at + 5 minutes), which may run past t+300s. Only with the
///     provider inbox on: without it nobody can answer in-app, so Phase 2's single wave stands.
/// Notified providers are recorded in request_matches; Phase 3's inbox delivers to them.
public class MatchService {
    static final int INITIAL_FANOUT = 6;
    static final int EXPANSION_STEP = 4;
    /// Per request, in-app and SMS together (owner decision 2026-11-23, contract 0.7.4).
    static final int ABSOLUTE_CAP = 14;
    static final Duration WAVE_INTERVAL = Duration.ofSeconds(120);
    static final Duration FANOUT_STOP = Duration.ofSeconds(300);
    /// Fewer live offers than this and the request still needs offers (manual: "fewer than 2 replies").
    static final int ENOUGH_OFFERS = 2;
    /// A provider is notified at most this many times an hour (contract 0.7.0); a match over it is not made.
    static final int NOTIFICATIONS_PER_HOUR = 4;
    /// An as-soon-as-possible ask is served within this window.
    static final Duration ASAP_WINDOW = Duration.ofHours(2);

    record Candidate(String userId, int distanceM, double responseRate, int trustScore, String timeZone,
            List<int[]> availability, List<String> days) {
        double rank() {
            return responseRate * 100 * 0.6 + trustScore * 0.3 + (1 - Math.min(distanceM / 80_000.0, 1)) * 100 * 0.1;
        }
    }

    private final JdbcTemplate jdbc;
    private final Clock clock;
    private final boolean expansion;

    public MatchService(JdbcTemplate jdbc, Clock clock, boolean expansion) {
        this.jdbc = jdbc;
        this.clock = clock;
        this.expansion = expansion;
    }

    /// Wave 1: notifies the best matching providers when the request is routed. Returns how many.
    public int notify(Resource request) { return notify(request, 1); }

    /// Waves 2 and 3, run by the worker under the request's lock. Returns how many were notified.
    public int expand(Resource request) {
        int wave = dueWave(request.createdAt(), clock.instant());
        if (!expansion || wave == 0 || request.progress().offersReady() >= ENOUGH_OFFERS) return 0;
        if (jdbc.queryForObject("SELECT count(*) FROM request_matches WHERE request_id=? AND wave=?", Integer.class,
                request.requestId(), wave) > 0) return 0;
        return notify(request, wave);
    }

    /// True while a later wave may still contact someone, so a request whose contacts all declined
    /// waits for it instead of ending as no_offers.
    public boolean wavesPending(Resource request) {
        if (!expansion || !clock.instant().isBefore(request.createdAt().plus(FANOUT_STOP))) return false;
        int contacted = contacted(request.requestId());
        return contacted > 0 && contacted < ABSOLUTE_CAP && jdbc.queryForObject(
                "SELECT count(*) FROM request_matches WHERE request_id=? AND wave=3", Integer.class, request.requestId()) == 0;
    }

    /// The expansion wave whose slot holds now: 2 from t+120s, 3 from t+240s, none before or from t+300s.
    static int dueWave(Instant createdAt, Instant now) {
        Duration elapsed = Duration.between(createdAt, now);
        if (elapsed.compareTo(WAVE_INTERVAL) < 0 || elapsed.compareTo(FANOUT_STOP) >= 0) return 0;
        return (int) elapsed.dividedBy(WAVE_INTERVAL) + 1;
    }

    /// Everyone contacted for the request, the one counter the ceiling is checked against.
    /// shortcut: only in-app contacts exist; SMS outreach (P3.S4 SMS, P3.S9) must add its rows here.
    private int contacted(String requestId) {
        return jdbc.queryForObject("SELECT count(*) FROM request_matches WHERE request_id=?", Integer.class, requestId);
    }

    private int notify(Resource request, int wave) {
        Constraints c = request.constraints();
        if (c.skillTags().isEmpty()) return 0;
        int already = contacted(request.requestId());
        if (already >= ABSOLUTE_CAP) return 0;
        String requester = jdbc.queryForObject("SELECT user_id FROM requests WHERE id=?", String.class, request.requestId());
        Instant start = clock.instant();
        Instant end = c.neededBy() != null ? c.neededBy() : start.plus(ASAP_WINDOW);
        List<Candidate> candidates = jdbc.query("""
                SELECT pp.user_id, pp.time_zone,
                       round(ST_Distance(pp.base_location, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography))::integer AS distance_m,
                       COALESCE(ps.response_rate, 0.5) AS response_rate, COALESCE(ps.trust_score, 50) AS trust_score
                  FROM provider_profiles pp
                  LEFT JOIN provider_scores ps ON ps.user_id = pp.user_id
                 WHERE pp.accepting AND pp.standing = 'active'
                   AND pp.user_id <> ?
                   AND (EXISTS (SELECT 1 FROM provider_skills s WHERE s.user_id = pp.user_id AND s.skill_tag = ANY(?))
                        OR EXISTS (SELECT 1 FROM provider_custom_skills cs WHERE cs.user_id = pp.user_id
                                    AND cardinality(ARRAY(SELECT unnest(cs.keywords) INTERSECT SELECT unnest(?::text[])))
                                        >= LEAST(2, cardinality(cs.keywords))))
                   AND ST_DWithin(pp.base_location, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, pp.travel_radius_m)
                   AND (NOT ? OR pp.licence_ref IS NOT NULL)
                   AND NOT EXISTS (SELECT 1 FROM request_matches m WHERE m.request_id = ? AND m.provider_id = pp.user_id)
                """, (rs, row) -> new Candidate(rs.getString("user_id"), rs.getInt("distance_m"),
                        rs.getDouble("response_rate"), rs.getInt("trust_score"), rs.getString("time_zone"),
                        windows(rs.getString("user_id")), days(rs.getString("user_id"))),
                c.location().longitude(), c.location().latitude(), requester, c.skillTags().toArray(String[]::new),
                // A provider-described skill (ADR-011) reaches every provider whose own words share its keywords:
                // the asker's words and the request's name, which for an own-words request is Claude's label.
                (c.category() != null && c.category().startsWith("custom_")
                        ? CustomSkills.keywords(c.serviceName() + " " + request.text())
                        : List.<String>of()).toArray(String[]::new),
                c.location().longitude(), c.location().latitude(), c.licenceRequired(), request.requestId());
        List<Candidate> eligible = candidates.stream()
                .filter(candidate -> available(candidate, start, end))
                .sorted(Comparator.comparingDouble(Candidate::rank).reversed().thenComparing(Candidate::distanceM))
                .toList();
        if (eligible.isEmpty()) return 0;
        // Concurrent requests must not both take a provider's last notification of the hour: lock the
        // candidates in id order (no deadlock between workers) and count only once the lock is held.
        // Standing and accepting are read again under the lock, so a suspension that committed after the
        // candidate query is never matched (P3.S14).
        var stillEligible = new java.util.HashSet<>(jdbc.queryForList("SELECT user_id FROM provider_profiles"
                + " WHERE user_id = ANY(?) AND standing = 'active' AND accepting ORDER BY user_id FOR NO KEY UPDATE",
                String.class, (Object) eligible.stream().map(Candidate::userId).toArray(String[]::new)));
        Timestamp hourAgo = Timestamp.from(start.minus(Duration.ofHours(1)));
        List<Candidate> chosen = eligible.stream()
                .filter(candidate -> stillEligible.contains(candidate.userId()))
                .filter(candidate -> jdbc.queryForObject("SELECT count(*) FROM request_matches WHERE provider_id=? AND notified_at>?",
                        Integer.class, candidate.userId(), hourAgo) < NOTIFICATIONS_PER_HOUR)
                .limit(Math.min(wave == 1 ? INITIAL_FANOUT : EXPANSION_STEP, ABSOLUTE_CAP - already))
                .toList();
        Timestamp now = Timestamp.from(clock.instant());
        for (Candidate candidate : chosen) {
            jdbc.update("INSERT INTO request_matches(request_id,provider_id,distance_m,rank_score,notified_at,wave) VALUES(?,?,?,?,?,?)",
                    request.requestId(), candidate.userId(), candidate.distanceM(), Math.round(candidate.rank() * 100) / 100.0, now, wave);
        }
        return chosen.size();
    }

    private List<int[]> windows(String userId) {
        return jdbc.query("SELECT from_minute,to_minute FROM provider_availability WHERE user_id=? ORDER BY position",
                (rs, row) -> new int[] {rs.getInt(1), rs.getInt(2)}, userId);
    }
    private List<String> days(String userId) {
        return jdbc.queryForList("SELECT days FROM provider_availability WHERE user_id=? ORDER BY position", String.class, userId);
    }

    /// True when any weekly window, read in the provider's own time zone, overlaps [start, end].
    static boolean available(Candidate candidate, Instant start, Instant end) {
        ZoneId zone;
        try { zone = ZoneId.of(candidate.timeZone()); } catch (RuntimeException invalid) { return false; }
        LocalDate first = start.atZone(zone).toLocalDate();
        LocalDate last = end.atZone(zone).toLocalDate();
        for (LocalDate day = first; !day.isAfter(last) && !day.isAfter(first.plusDays(8)); day = day.plusDays(1)) {
            boolean weekend = day.getDayOfWeek() == DayOfWeek.SATURDAY || day.getDayOfWeek() == DayOfWeek.SUNDAY;
            for (int i = 0; i < candidate.availability().size(); i++) {
                String days = candidate.days().get(i);
                if (days.equals("weekdays") && weekend || days.equals("weekends") && !weekend) continue;
                int[] window = candidate.availability().get(i);
                ZonedDateTime open = day.atTime(LocalTime.ofSecondOfDay(window[0] * 60L)).atZone(zone);
                ZonedDateTime close = window[1] == 1440 ? day.plusDays(1).atStartOfDay(zone)
                        : day.atTime(LocalTime.ofSecondOfDay(window[1] * 60L)).atZone(zone);
                if (open.toInstant().isBefore(end) && close.toInstant().isAfter(start)) return true;
            }
        }
        return false;
    }
}
