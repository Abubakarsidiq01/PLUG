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
///     outranks a high scorer who has gone quiet.
///  3. Cap: the best few are notified; there is a hard ceiling that is never lifted.
/// Notified providers are recorded in request_matches; Phase 3's inbox delivers to them.
public class MatchService {
    static final int INITIAL_FANOUT = 6;
    static final int ABSOLUTE_CAP = 16;
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

    public MatchService(JdbcTemplate jdbc, Clock clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    /// Notifies the best matching providers once per request. Returns how many were notified.
    public int notify(Resource request) {
        Constraints c = request.constraints();
        if (c.skillTags().isEmpty()) return 0;
        int already = jdbc.queryForObject("SELECT count(*) FROM request_matches WHERE request_id=?", Integer.class,
                request.requestId());
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
                 WHERE pp.accepting
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
                // A provider-described skill (ADR-011) reaches every provider whose own words share its keywords.
                (c.category() != null && c.category().startsWith("custom_") ? CustomSkills.keywords(request.text())
                        : List.<String>of()).toArray(String[]::new),
                c.location().longitude(), c.location().latitude(), c.licenceRequired(), request.requestId());
        List<Candidate> chosen = candidates.stream()
                .filter(candidate -> available(candidate, start, end))
                .sorted(Comparator.comparingDouble(Candidate::rank).reversed().thenComparing(Candidate::distanceM))
                .limit(Math.min(INITIAL_FANOUT, ABSOLUTE_CAP - already))
                .toList();
        Timestamp now = Timestamp.from(clock.instant());
        for (Candidate candidate : chosen) {
            jdbc.update("INSERT INTO request_matches(request_id,provider_id,distance_m,rank_score,notified_at) VALUES(?,?,?,?,?)",
                    request.requestId(), candidate.userId(), candidate.distanceM(), Math.round(candidate.rank() * 100) / 100.0, now);
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
