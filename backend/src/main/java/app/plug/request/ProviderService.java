package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.foundation.FixedWindowLimiter;
import app.plug.request.ProviderPayloads.AvailabilityWindow;
import app.plug.request.ProviderPayloads.ProviderProfile;
import app.plug.request.ProviderPayloads.ProviderSetup;
import app.plug.request.ProviderPayloads.SkillProposal;
import app.plug.request.ProviderPayloads.SkillTag;
import app.plug.security.PlugPrincipal;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.DateTimeException;
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
    // Its own key space, as StaffAccounts has: a flood of user keys in the shared limiter cannot lock staff out.
    final FixedWindowLimiter adminLimiter = new FixedWindowLimiter(4096);

    private final CustomSkills customSkills;

    public ProviderService(JdbcTemplate jdbc, PlatformTransactionManager manager, Clock clock, IntentAdapter intent,
            RestrictedIntentPolicy policy, RequestService requests, CustomSkills customSkills) {
        this.customSkills = customSkills;
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
        requests.limit(requests.limiter, "propose:" + caller.userId(), 30);
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
        // Own-words skills (ADR-011): the same policy as asks refuses unsafe ones, with its audit event.
        if (setup.customSkills() != null) {
            for (String label : setup.customSkills()) {
                if (label != null) policy.refusal(label).ifPresent(rule -> requests.refuse(caller, rule));
            }
        }
        // Direct entry accepts familiar and new skills alike. Canonical skills retain all
        // their matching and licence rules instead of becoming unregulated custom tags.
        List<String> ownLabels = new ArrayList<>();
        if (setup.customSkills() != null) {
            for (String label : setup.customSkills()) {
                var listed = label == null ? List.<SkillVocabulary.Skill>of() : vocabulary.findIn(label);
                if (listed.isEmpty()) ownLabels.add(label);
                else for (var skill : listed) if (!skills.contains(skill)) skills.add(skill);
            }
        }
        if (skills.size() > 10) throw ApiException.validation("skill_tags", "too_many", "Keep up to ten listed skills.");
        var custom = setup.customSkills() == null ? null : customSkills.prepare(ownLabels, vocabulary);
        boolean keepsCustom = custom == null && !customSkills.labels(caller.userId()).isEmpty();
        if (skills.isEmpty() && (custom == null ? !keepsCustom : custom.isEmpty())) {
            throw ApiException.validation("skill_tags", "required", "Add at least one skill.");
        }
        if (skills.stream().anyMatch(SkillVocabulary.Skill::requiresLicence) && (setup.licenceRef() == null || setup.licenceRef().isBlank())) {
            throw ApiException.validation("licence_ref", "licence_required", "Add your licence number for licensed work.");
        }
        try { ZoneId.of(setup.timeZone()); }
        catch (DateTimeException invalid) { throw ApiException.validation("time_zone", "invalid", "Use an IANA time zone."); }
        for (AvailabilityWindow window : setup.availability()) {
            if (minutes(window.to()) <= minutes(window.from())) {
                throw ApiException.validation("availability", "invalid", "Each window must end after it starts.");
            }
        }
        var business = BusinessProfiles.validated(setup.business());
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
            if (business != null) jdbc.update("UPDATE provider_profiles SET business=?::jsonb WHERE user_id=?",
                    BusinessProfiles.json(business), caller.userId());
            if (custom != null) customSkills.replace(caller.userId(), custom);
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
        var score = requests.scores.compute(userId);
        return jdbc.queryForObject("SELECT * FROM provider_profiles WHERE user_id=?", (rs, n) -> new ProviderProfile(userId,
                skills, rs.getInt("travel_radius_m"), availability, rs.getString("time_zone"), rs.getBoolean("accepting"),
                rs.getString("licence_ref") != null, score.score(), score.breakdown(), score.standing(),
                rs.getTimestamp("created_at").toInstant(), BusinessProfiles.read(rs.getString("business")),
                customSkills.labels(userId)), userId);
    }

    /// Contract 0.7.0 listProviders and setProviderStanding are for an owner only: SecurityConfiguration
    /// already requires the admin scope and a completed second factor; the role is checked here, against
    /// the staff account, as StaffAccounts checks it for staff management. The per-staff limit runs
    /// first, so a non-owner session cannot make unlimited 403 calls, and before any id lookup.
    void requireOwner(PlugPrincipal caller, String bucket, int limit) {
        if (caller == null) throw ApiException.unauthenticated("Sign in to continue.");
        requests.limit(adminLimiter, bucket + ":" + caller.userId(), limit);
        if (jdbc.queryForObject("SELECT count(*) FROM staff_accounts WHERE user_id=? AND role='owner' AND status='active'",
                Integer.class, caller.userId()) == 0) {
            throw ApiException.forbidden("This operation is not allowed.");
        }
    }

    /// Newest first, with the same opaque cursors as the other admin pages. Each read is audited. The
    /// controller has checked the owner.
    /// shortcut: each row computes its score live (two queries a provider, at most 100 a page); store the
    /// breakdown with provider_scores if the console needs larger pages.
    AdminInspection.Page<ProviderPayloads.AdminProvider> list(PlugPrincipal caller, String cursor, int limit) {
        audit(caller, "admin.read", "providers", "list", null);
        String[] after = cursor == null ? null : AdminInspection.decode(cursor, 2);
        List<String> ids = after == null
                ? jdbc.queryForList("SELECT user_id FROM provider_profiles ORDER BY created_at DESC, user_id DESC LIMIT ?",
                        String.class, limit + 1)
                : jdbc.queryForList("SELECT user_id FROM provider_profiles WHERE (created_at, user_id) < (?, ?)"
                        + " ORDER BY created_at DESC, user_id DESC LIMIT ?", String.class,
                        Timestamp.from(AdminInspection.instant(after[0])), after[1], limit + 1);
        return AdminInspection.page(ids.stream().map(this::admin).toList(), limit,
                p -> AdminInspection.encode(p.createdAt().toString(), p.userId()));
    }

    /// Suspends or reinstates a provider (P3.S14). Suspending withdraws their live offers and releases
    /// their pending reservations first, then the standing changes, the score is recomputed and the
    /// decision is audited with its reason, all in one transaction. The controller has checked the owner.
    ProviderPayloads.AdminProvider setStanding(PlugPrincipal caller, String userId, String standing, String reason) {
        return transaction.execute(ignored -> {
            if (userId.length() > 64 || !userId.matches("usr_[A-Za-z0-9-]{1,60}") || jdbc.queryForObject(
                    "SELECT count(*) FROM provider_profiles WHERE user_id=?", Integer.class, userId) == 0) {
                throw ApiException.notFound("That provider was not found.");
            }
            // The provider's account row first, as their offer, decline and reservation answer lock it
            // first: one of them either finishes before the suspension or sees it and is refused (403).
            jdbc.queryForList("SELECT id FROM users WHERE id=? FOR UPDATE", userId);
            if (standing.equals("suspended")) requests.suspend(userId);
            // Suspending also stops accepting (fixture admin.providers.standing/suspended.json); reinstating
            // leaves it off, so the provider turns it back on themselves through POST /v1/providers/skills.
            if (jdbc.update("UPDATE provider_profiles SET standing=?,standing_changed_at=?,"
                    + "accepting=CASE WHEN ?='suspended' THEN false ELSE accepting END WHERE user_id=? AND standing<>?",
                    standing, Timestamp.from(clock.instant()), standing, userId, standing) > 0) {
                requests.scores.recompute(userId, "standing_changed");
            }
            audit(caller, "provider.standing_changed", "provider", userId, standing + ": " + reason);
            return admin(userId);
        });
    }

    private ProviderPayloads.AdminProvider admin(String userId) {
        ProviderProfile p = read(userId);
        return new ProviderPayloads.AdminProvider(userId, p.business() == null ? null : p.business().name(), p.skills(),
                p.customSkills(), p.travelRadiusM(), p.accepting(), p.licenceOnFile(), p.standing(), p.score(), p.scoreBreakdown(),
                p.createdAt());
    }

    private void audit(PlugPrincipal caller, String action, String resource, String resourceId, String reason) {
        jdbc.update("INSERT INTO audit_events(occurred_at,actor_id,actor_role,action,resource,resource_id,reason,request_id)"
                + " VALUES(?,?,'admin',?,?,?,?,?)", Timestamp.from(clock.instant()), caller.userId(), action, resource, resourceId,
                reason, org.slf4j.MDC.get("request_id"));
    }

    static int minutes(String clockText) {
        if (clockText.equals("24:00")) return 1440;
        return Integer.parseInt(clockText.substring(0, 2)) * 60 + Integer.parseInt(clockText.substring(3));
    }
    static String clockText(int minutes) {
        return minutes == 1440 ? "24:00" : "%02d:%02d".formatted(minutes / 60, minutes % 60);
    }
}
