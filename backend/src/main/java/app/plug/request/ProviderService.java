package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.request.ProviderPayloads.AvailabilityWindow;
import app.plug.request.ProviderPayloads.ProviderProfile;
import app.plug.request.ProviderPayloads.ProviderSetup;
import app.plug.request.ProviderPayloads.SkillProposal;
import app.plug.request.ProviderPayloads.SkillTag;
import app.plug.security.PlugPrincipal;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.DateTimeException;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/// Any user can also be a provider (manual v4 §2.3, P2.S15). The profile is keyed on the
/// caller's own user_id, so there is no second account and no role record to switch.
public class ProviderService {
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transaction;
    private final Clock clock;
    private final IntentAdapter intent;
    private final RestrictedIntentPolicy policy;
    private final RequestService requests;

    public ProviderService(JdbcTemplate jdbc, PlatformTransactionManager manager, Clock clock, IntentAdapter intent,
            RestrictedIntentPolicy policy, RequestService requests) {
        this.jdbc = jdbc;
        this.transaction = new TransactionTemplate(manager);
        this.clock = clock;
        this.intent = intent;
        this.policy = policy;
        this.requests = requests;
    }

    /// Plain words onto the vocabulary. Nothing is saved except the vocabulary gap backlog.
    public SkillProposal propose(PlugPrincipal caller, String description) {
        requests.requireCaller(caller);
        if (!requests.limiter.tryConsume("propose:" + caller.userId(), 30, Duration.ofMinutes(1))) throw ApiException.rateLimited(60);
        // "I sell weed" is not a skill. The same policy that guards asks guards offers.
        policy.refusal(description).ifPresent(rule -> requests.refuse(caller, rule));
        var vocabulary = intent.vocabulary();
        var skills = new LinkedHashSet<>(vocabulary.findIn(description));
        skills.addAll(intent.proposedSkills(description));
        List<String> unmatched = vocabulary.unmatchedTerms(description);
        Timestamp now = Timestamp.from(clock.instant());
        for (String term : unmatched) {
            jdbc.update("INSERT INTO vocabulary_gaps(term,first_seen,last_seen) VALUES(?,?,?)"
                    + " ON CONFLICT (term) DO UPDATE SET seen_count=vocabulary_gaps.seen_count+1, last_seen=EXCLUDED.last_seen",
                    term, now, now);
        }
        return new SkillProposal(skills.stream().limit(10).map(SkillTag::of).toList(), unmatched);
    }

    public ProviderProfile set(PlugPrincipal caller, ProviderSetup setup) {
        requests.requireCaller(caller);
        requests.requireConsent(caller);
        var vocabulary = intent.vocabulary();
        List<SkillVocabulary.Skill> skills = new ArrayList<>();
        for (String tag : new LinkedHashSet<>(setup.skillTags())) {
            var skill = vocabulary.get(tag);
            if (skill == null) throw ApiException.validation("skill_tags", "unknown_skill", "Choose skills PLUG lists.");
            skills.add(skill);
        }
        if (skills.stream().anyMatch(SkillVocabulary.Skill::requiresLicence) && setup.licenceRef() == null) {
            throw ApiException.validation("licence_ref", "licence_required", "Add your licence number for licensed work.");
        }
        try { ZoneId.of(setup.timeZone()); }
        catch (DateTimeException invalid) { throw ApiException.validation("time_zone", "invalid", "Use an IANA time zone."); }
        for (AvailabilityWindow window : setup.availability()) {
            if (minutes(window.to()) <= minutes(window.from())) {
                throw ApiException.validation("availability", "invalid", "Each window must end after it starts.");
            }
        }
        var location = setup.baseLocation().rounded();
        return transaction.execute(ignored -> {
            requests.lockAccount(caller);
            Timestamp now = Timestamp.from(clock.instant());
            jdbc.update("""
                    INSERT INTO provider_profiles(user_id,travel_radius_m,base_location,location_precision,time_zone,accepting,
                                                  licence_ref,created_at,updated_at)
                    VALUES (?,?,ST_SetSRID(ST_MakePoint(?,?),4326)::geography,?,?,?,?,?,?)
                    ON CONFLICT (user_id) DO UPDATE SET travel_radius_m=EXCLUDED.travel_radius_m,
                        base_location=EXCLUDED.base_location, location_precision=EXCLUDED.location_precision,
                        time_zone=EXCLUDED.time_zone, accepting=EXCLUDED.accepting, licence_ref=EXCLUDED.licence_ref,
                        updated_at=EXCLUDED.updated_at
                    """, caller.userId(), setup.travelRadiusM(), location.longitude(), location.latitude(),
                    location.precision(), setup.timeZone(), setup.accepting() == null || setup.accepting(),
                    setup.licenceRef(), now, now);
            jdbc.update("DELETE FROM provider_skills WHERE user_id=?", caller.userId());
            for (var skill : skills) jdbc.update("INSERT INTO provider_skills VALUES(?,?)", caller.userId(), skill.tag());
            jdbc.update("DELETE FROM provider_availability WHERE user_id=?", caller.userId());
            int position = 0;
            for (AvailabilityWindow window : setup.availability()) {
                jdbc.update("INSERT INTO provider_availability VALUES(?,?,?,?,?)", caller.userId(), window.days(),
                        minutes(window.from()), minutes(window.to()), position++);
            }
            return read(caller.userId());
        });
    }

    public ProviderProfile me(PlugPrincipal caller) {
        requests.requireCaller(caller);
        if (jdbc.queryForObject("SELECT count(*) FROM provider_profiles WHERE user_id=?", Integer.class, caller.userId()) == 0) {
            throw ApiException.notFound("You have not offered a service yet.");
        }
        return read(caller.userId());
    }

    private ProviderProfile read(String userId) {
        var vocabulary = intent.vocabulary();
        List<SkillTag> skills = jdbc.queryForList("SELECT skill_tag FROM provider_skills WHERE user_id=? ORDER BY skill_tag",
                String.class, userId).stream().map(vocabulary::get).map(SkillTag::of).toList();
        List<AvailabilityWindow> availability = jdbc.query(
                "SELECT days,from_minute,to_minute FROM provider_availability WHERE user_id=? ORDER BY position",
                (rs, n) -> new AvailabilityWindow(rs.getString(1), clockText(rs.getInt(2)), clockText(rs.getInt(3))), userId);
        var scores = jdbc.queryForList("SELECT completed_jobs,trust_score FROM provider_scores WHERE user_id=?", userId);
        int completed = scores.isEmpty() ? 0 : ((Number) scores.getFirst().get("completed_jobs")).intValue();
        Integer trust = scores.isEmpty() || scores.getFirst().get("trust_score") == null ? null
                : ((Number) scores.getFirst().get("trust_score")).intValue();
        return jdbc.queryForObject("SELECT * FROM provider_profiles WHERE user_id=?", (rs, n) -> new ProviderProfile(userId,
                skills, rs.getInt("travel_radius_m"), availability, rs.getString("time_zone"), rs.getBoolean("accepting"),
                rs.getString("licence_ref") != null, RequestPayloads.ProviderScore.of(completed, trust),
                rs.getTimestamp("created_at").toInstant()), userId);
    }

    static int minutes(String clockText) {
        if (clockText.equals("24:00")) return 1440;
        return Integer.parseInt(clockText.substring(0, 2)) * 60 + Integer.parseInt(clockText.substring(3));
    }
    static String clockText(int minutes) {
        return minutes == 1440 ? "24:00" : "%02d:%02d".formatted(minutes / 60, minutes % 60);
    }
}
