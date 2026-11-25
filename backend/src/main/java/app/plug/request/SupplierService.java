package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.foundation.FixedWindowLimiter;
import app.plug.foundation.RateWindow;
import app.plug.request.ProviderPayloads.AvailabilityWindow;
import app.plug.request.SupplierPayloads.Consent;
import app.plug.request.SupplierPayloads.ConsentEvent;
import app.plug.request.SupplierPayloads.OptOut;
import app.plug.request.SupplierPayloads.Supplier;
import app.plug.request.SupplierPayloads.Verification;
import app.plug.security.PlugPrincipal;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.DateTimeException;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.TreeSet;
import java.util.UUID;
import org.slf4j.MDC;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/// P3.S2 supplier onboarding (contract 0.7.7). Consent is explicit and recorded: the form and staff
/// only ever write pending_confirmation and queue one optin_confirm text; granted comes only from
/// the phone itself (P3.S5). Every staff write and read is audited; numbers leave only masked.
public class SupplierService {
    /// The SMS terms version the server publishes (contracts/messages/templates.v1.json consent_version).
    static final String CONSENT_VERSION = "sms-2026-10-09";
    private static final String COLUMNS = "s.*, p.address, ST_Y(p.location::geometry) AS latitude, ST_X(p.location::geometry) AS longitude";
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transaction;
    private final Clock clock;
    private final ObjectMapper mapper;
    private final SupplierPhones phones;
    private final SkillVocabulary vocabulary;
    private final RateWindow window;
    private final boolean delivery;
    // Their own key spaces: a flood of opt-ins cannot lock staff out, nor the other way round.
    private final FixedWindowLimiter adminLimiter = new FixedWindowLimiter(4096);
    private final FixedWindowLimiter optInLimiter = new FixedWindowLimiter(4096);

    public SupplierService(JdbcTemplate jdbc, PlatformTransactionManager manager, Clock clock, ObjectMapper mapper,
            SupplierPhones phones, SkillVocabulary vocabulary, RateWindow window, boolean delivery) {
        this.jdbc = jdbc;
        this.transaction = new TransactionTemplate(manager);
        this.clock = clock;
        this.mapper = mapper;
        this.phones = phones;
        this.vocabulary = vocabulary;
        this.window = window;
        this.delivery = delivery;
    }

    // ---- authorization -------------------------------------------------------------------

    /// SecurityConfiguration already requires the admin scope and a completed second factor on
    /// /v1/admin. The per-staff limit runs first, before the role check and any id lookup, so a
    /// non-owner cannot make unlimited 403 calls (the ProviderService.requireOwner pattern).
    void requireStaff(PlugPrincipal caller, String bucket, int limit, boolean owner) {
        if (caller == null) throw ApiException.unauthenticated("Sign in to continue.");
        String key = bucket + ":" + caller.userId();
        if (!adminLimiter.tryConsume(key, limit, window.length())) {
            throw ApiException.rateLimited((int) adminLimiter.secondsUntilReset(key, window.length()));
        }
        if (jdbc.queryForObject("SELECT count(*) FROM staff_accounts WHERE user_id=? AND status='active' AND (role='owner' OR NOT ?)",
                Integer.class, caller.userId(), owner) == 0) {
            throw ApiException.forbidden("This operation is not allowed.");
        }
    }

    private void requireDelivery() {
        if (!delivery) throw ApiException.dependencyUnavailable("Text messages are not available on this server.", 60);
    }

    // ---- public opt-in -------------------------------------------------------------------

    /// The same answer whatever the number's state. Over 5 an hour from one address nothing is stored;
    /// once a number has 3 opt-in texts queued in 24 hours nothing more is queued. Same answer either way.
    void optIn(String address, String key, SupplierPayloads.OptIn input) {
        requireDelivery();
        String body = phones.keyed("supplier-opt-in:" + encode(input));
        transaction.executeWithoutResult(ignored -> {
            String keyHash = lockKey("opt-in", key);
            if (replayed("opt-in", keyHash, body) != null) return;
            String phoneHash = phones.hash(input.phone());
            if (optInLimiter.tryConsume("address:" + address, 5, Duration.ofHours(1))) {
                Timestamp now = Timestamp.from(clock.instant());
                jdbc.update("""
                        INSERT INTO suppliers(id,business_name,phone_hash,phone_ciphertext,phone_last2,consent_state,consent_version,
                                              consent_changed_at,created_at,updated_at)
                        VALUES (?,?,?,?,?,'pending_confirmation',?,?,?,?) ON CONFLICT (phone_hash) DO NOTHING
                        """, "sup_" + UUID.randomUUID(), input.businessName(), phoneHash, phones.encrypt(input.phone(), phoneHash),
                        input.phone().substring(input.phone().length() - 2), CONSENT_VERSION, now, now, now);
                // A known number is never renamed or unverified from the form. Only one still waiting
                // for START is texted again; granted, paused and revoked ones change nothing.
                // The per-number cap is counted from the outbox under the row lock, so it holds across restarts.
                var rows = jdbc.queryForList("SELECT id FROM suppliers WHERE phone_hash=? AND consent_state='pending_confirmation' FOR UPDATE",
                        String.class, phoneHash);
                if (!rows.isEmpty() && jdbc.queryForObject("SELECT count(*) FROM sms_outbox WHERE supplier_id=? AND template='optin_confirm'"
                        + " AND created_at > ?", Integer.class, rows.getFirst(), Timestamp.from(now.toInstant().minus(Duration.ofDays(1)))) < 3) {
                    pending(rows.getFirst(), "web_form", now);
                }
            }
            remember("opt-in", keyHash, body, SupplierPayloads.Receipt.SENT_IF_ELIGIBLE);
        });
    }

    private void pending(String id, String source, Timestamp now) {
        jdbc.update("INSERT INTO supplier_consent_events(supplier_id,state,source,version,occurred_at) VALUES(?,'pending_confirmation',?,?,?)",
                id, source, CONSENT_VERSION, now);
        jdbc.update("INSERT INTO sms_outbox(id,supplier_id,template,status,created_at) VALUES(?,?,'optin_confirm','queued',?)",
                "msg_" + UUID.randomUUID(), id, now);
    }

    // ---- staff ---------------------------------------------------------------------------

    /// The same pending record the form writes, with a staff_entry event: staff never mark consent given.
    Supplier create(PlugPrincipal caller, String key, SupplierPayloads.Create input) {
        requireDelivery();
        String scope = "create:" + caller.userId();
        String body = phones.keyed("supplier-create:" + encode(input));
        return transaction.execute(ignored -> {
            String keyHash = lockKey(scope, key);
            String prior = replayed(scope, keyHash, body);
            if (prior != null) {
                try { return mapper.readValue(prior, Supplier.class); }
                catch (JsonProcessingException corrupt) { throw new IllegalStateException("Invalid stored response"); }
            }
            String id = "sup_" + UUID.randomUUID();
            String phoneHash = phones.hash(input.phone());
            Timestamp now = Timestamp.from(clock.instant());
            if (jdbc.update("""
                    INSERT INTO suppliers(id,business_name,phone_hash,phone_ciphertext,phone_last2,consent_state,consent_version,
                                          consent_changed_at,created_at,updated_at)
                    VALUES (?,?,?,?,?,'pending_confirmation',?,?,?,?) ON CONFLICT (phone_hash) DO NOTHING
                    """, id, input.businessName(), phoneHash, phones.encrypt(input.phone(), phoneHash),
                    input.phone().substring(input.phone().length() - 2), CONSENT_VERSION, now, now, now) == 0) {
                throw ApiException.requestError(409, "conflict", "phone", "supplier_exists", "That number is already a supplier.");
            }
            pending(id, "staff_entry", now);
            audit(caller, "supplier.created", id, input.reason());
            Supplier result = load(id, false);
            remember(scope, keyHash, body, result);
            return result;
        });
    }

    AdminInspection.Page<Supplier> list(PlugPrincipal caller, String cursor, int limit, String verification) {
        if (verification != null && !List.of("pending_verification", "verified", "rejected", "suspended").contains(verification)) {
            throw ApiException.validation("verification", "invalid", "Choose a listed verification status.");
        }
        String[] after = cursor == null ? null : AdminInspection.decode(cursor, 2);
        Timestamp afterTime = after == null ? null : Timestamp.from(AdminInspection.instant(after[0]));
        audit(caller, "admin.read", "list", null);
        List<Supplier> rows = jdbc.query("SELECT " + COLUMNS + " FROM suppliers s LEFT JOIN places p ON p.id=s.place_id"
                + " WHERE (?::text IS NULL OR s.verification_status=?) AND (?::timestamptz IS NULL OR (s.created_at, s.id) < (?, ?))"
                + " ORDER BY s.created_at DESC, s.id DESC LIMIT ?", (rs, n) -> supplier(rs, null),
                verification, verification, afterTime, afterTime, after == null ? null : after[1], limit + 1);
        return AdminInspection.page(rows, limit, s -> AdminInspection.encode(s.createdAt().toString(), s.supplierId()));
    }

    Supplier get(PlugPrincipal caller, String id) {
        requireKnown(id, false);
        audit(caller, "admin.read", id, null);
        return load(id, true);
    }

    /// Changing services or the service area (place or radius) of a verified supplier returns it to
    /// pending_verification. The audit row carries before and after of those fields, never a phone.
    Supplier update(PlugPrincipal caller, String id, SupplierPayloads.Profile profile) {
        boolean licensed = false;
        for (String tag : profile.skillTags()) {
            var skill = vocabulary.get(tag);
            if (skill == null) throw ApiException.validation("skill_tags", "unknown_skill", "Choose skills PLUG lists.");
            licensed |= skill.requiresLicence();
        }
        if (licensed && profile.licenceRef() == null) {
            throw ApiException.validation("licence_ref", "licence_required", "Add the licence number for licensed work.");
        }
        try { ZoneId.of(profile.timeZone()); }
        catch (DateTimeException invalid) { throw ApiException.validation("time_zone", "invalid", "Use an IANA time zone."); }
        var location = profile.location().rounded();
        return transaction.execute(ignored -> {
            requireKnown(id, true);
            var before = jdbc.queryForMap("SELECT " + COLUMNS + " FROM suppliers s LEFT JOIN places p ON p.id=s.place_id WHERE s.id=?", id);
            var skillsBefore = new TreeSet<>(Arrays.asList((String[]) toArray(before.get("skill_tags"))));
            var skillsAfter = new TreeSet<>(profile.skillTags());
            Integer radiusBefore = (Integer) before.get("service_radius_m");
            boolean placeChanged = before.get("place_id") == null || !profile.address().equals(before.get("address"))
                    || Math.abs((Double) before.get("latitude") - location.latitude()) > 1e-9
                    || Math.abs((Double) before.get("longitude") - location.longitude()) > 1e-9;
            boolean areaChanged = !skillsBefore.equals(skillsAfter) || placeChanged
                    || radiusBefore == null || radiusBefore != profile.serviceRadiusM();
            String verificationBefore = (String) before.get("verification_status");
            String verificationAfter = areaChanged && verificationBefore.equals("verified") ? "pending_verification" : verificationBefore;
            Timestamp now = Timestamp.from(clock.instant());
            String placeId = (String) before.get("place_id");
            if (placeId == null) {
                placeId = "plc_" + UUID.randomUUID();
                jdbc.update("INSERT INTO places(id,name,address,category,location,is_seed)"
                        + " VALUES(?,?,?,?,ST_SetSRID(ST_MakePoint(?,?),4326)::geography,FALSE)", placeId, profile.businessName(),
                        profile.address(), profile.skillTags().getFirst(), location.longitude(), location.latitude());
            } else {
                jdbc.update("UPDATE places SET name=?,address=?,category=?,location=ST_SetSRID(ST_MakePoint(?,?),4326)::geography WHERE id=?",
                        profile.businessName(), profile.address(), profile.skillTags().getFirst(), location.longitude(),
                        location.latitude(), placeId);
            }
            jdbc.update("""
                    UPDATE suppliers SET business_name=?,skill_tags=?,place_id=?,service_radius_m=?,hours=?::jsonb,time_zone=?,licence_ref=?,
                        contact_name=?,verification_status=?,
                        verification_decided_at=CASE WHEN ?<>verification_status THEN NULL ELSE verification_decided_at END,
                        verification_reason=CASE WHEN ?<>verification_status THEN NULL ELSE verification_reason END,updated_at=?
                    WHERE id=?
                    """, profile.businessName(), profile.skillTags().toArray(String[]::new), placeId, profile.serviceRadiusM(),
                    encode(profile.hours()), profile.timeZone(), profile.licenceRef(), profile.contactName(), verificationAfter,
                    verificationAfter, verificationAfter, now, id);
            audit(caller, "supplier.profile_updated", id, "skill_tags: " + skillsBefore + " -> " + skillsAfter
                    + "; service_radius_m: " + radiusBefore + " -> " + profile.serviceRadiusM()
                    + "; place: " + (placeChanged ? "changed" : "same")
                    + "; verification: " + verificationBefore + " -> " + verificationAfter);
            return load(id, false);
        });
    }

    /// verified needs a service, hours and a place; verified also reinstates a suspended supplier.
    Supplier decide(PlugPrincipal caller, String id, String status, String reason) {
        return transaction.execute(ignored -> {
            requireKnown(id, true);
            if (status.equals("verified") && jdbc.queryForObject("SELECT cardinality(skill_tags)=0 OR hours IS NULL OR place_id IS NULL"
                    + " FROM suppliers WHERE id=?", Boolean.class, id)) {
                throw ApiException.validation("status", "profile_incomplete", "Add services, hours and a place before verifying.");
            }
            Timestamp now = Timestamp.from(clock.instant());
            jdbc.update("UPDATE suppliers SET verification_status=?,verification_decided_at=?,verification_reason=?,updated_at=? WHERE id=?",
                    status, now, reason, now, id);
            audit(caller, "supplier.verification", id, reason);
            return load(id, false);
        });
    }

    /// Suppressed numbers: revoked, or paused and still inside the pause, whose latest consent event
    /// came from the phone (sms_keyword) or the carrier. Newest change first.
    AdminInspection.Page<OptOut> optOuts(PlugPrincipal caller, String cursor, int limit) {
        String[] after = cursor == null ? null : AdminInspection.decode(cursor, 2);
        Timestamp afterTime = after == null ? null : Timestamp.from(AdminInspection.instant(after[0]));
        jdbc.update("INSERT INTO audit_events(occurred_at,actor_id,actor_role,action,resource,resource_id,reason,request_id)"
                + " VALUES(?,?,'admin','admin.read','opt_outs','list',NULL,?)", Timestamp.from(clock.instant()), caller.userId(),
                MDC.get("request_id"));
        List<OptOut> rows = jdbc.query("""
                SELECT s.id, s.phone_last2, s.consent_state, s.consent_changed_at, s.paused_until, e.source FROM suppliers s
                JOIN LATERAL (SELECT source FROM supplier_consent_events WHERE supplier_id=s.id ORDER BY id DESC LIMIT 1) e ON TRUE
                WHERE (s.consent_state='revoked' OR (s.consent_state='paused' AND s.paused_until > ?))
                  AND e.source IN ('sms_keyword','carrier')
                  AND (?::timestamptz IS NULL OR (s.consent_changed_at, s.id) < (?, ?))
                ORDER BY s.consent_changed_at DESC, s.id DESC LIMIT ?
                """, (rs, n) -> new OptOut(SupplierPhones.mask(rs.getString("phone_last2")), rs.getString("id"),
                        rs.getString("consent_state"), rs.getString("source"), rs.getTimestamp("consent_changed_at").toInstant(),
                        instant(rs.getTimestamp("paused_until"))),
                Timestamp.from(clock.instant()), afterTime, afterTime, after == null ? null : after[1], limit + 1);
        return AdminInspection.page(rows, limit, o -> AdminInspection.encode(o.since().toString(), o.supplierId()));
    }

    // ---- helpers -------------------------------------------------------------------------

    /// A malformed id and an unknown one are both 404, so the two cannot be told apart.
    private void requireKnown(String id, boolean lock) {
        if (id.length() > 64 || !id.matches("sup_[A-Za-z0-9-]+")
                || jdbc.queryForList("SELECT id FROM suppliers WHERE id=?" + (lock ? " FOR UPDATE" : ""), id).isEmpty()) {
            throw ApiException.notFound("That supplier was not found.");
        }
    }

    private Supplier load(String id, boolean trail) {
        List<ConsentEvent> events = trail ? jdbc.query(
                // Append-only, so id order is the order events were recorded: newest first.
                "SELECT state,source,version,occurred_at FROM supplier_consent_events WHERE supplier_id=? ORDER BY id DESC LIMIT 50",
                (rs, n) -> new ConsentEvent(rs.getString(1), rs.getString(2), rs.getString(3), rs.getTimestamp(4).toInstant()), id) : null;
        return jdbc.queryForObject("SELECT " + COLUMNS + " FROM suppliers s LEFT JOIN places p ON p.id=s.place_id WHERE s.id=?",
                (rs, n) -> supplier(rs, events), id);
    }

    private Supplier supplier(ResultSet rs, List<ConsentEvent> trail) throws SQLException {
        String[] tags = (String[]) rs.getArray("skill_tags").getArray();
        String hours = rs.getString("hours");
        List<AvailabilityWindow> windows;
        try { windows = hours == null ? null : mapper.readValue(hours, new TypeReference<List<AvailabilityWindow>>() {}); }
        catch (JsonProcessingException corrupt) { throw new IllegalStateException("Invalid stored hours"); }
        return new Supplier(rs.getString("id"), rs.getString("business_name"), SupplierPhones.mask(rs.getString("phone_last2")),
                tags.length == 0 ? null : List.of(tags), rs.getString("place_id"), rs.getString("address"),
                (Integer) rs.getObject("service_radius_m"), windows, rs.getString("time_zone"), rs.getString("licence_ref") != null,
                rs.getString("contact_name"),
                new Verification(rs.getString("verification_status"), instant(rs.getTimestamp("verification_decided_at")),
                        rs.getString("verification_reason")),
                new Consent(rs.getString("consent_state"), rs.getString("consent_version"),
                        rs.getTimestamp("consent_changed_at").toInstant(), instant(rs.getTimestamp("paused_until"))),
                trail, rs.getTimestamp("created_at").toInstant(), rs.getTimestamp("updated_at").toInstant());
    }

    /// Serialises concurrent retries of one key, then drops a stale (over 24 h) record of it.
    private String lockKey(String scope, String key) {
        String keyHash = phones.keyed("supplier-idempotency-key:" + key);
        jdbc.queryForList("SELECT pg_advisory_xact_lock(hashtext(?))", scope + ":" + keyHash);
        jdbc.update("DELETE FROM supplier_idempotency WHERE scope=? AND key_hash=? AND created_at<=?", scope, keyHash,
                Timestamp.from(clock.instant().minus(Duration.ofHours(24))));
        return keyHash;
    }

    private String replayed(String scope, String keyHash, String bodyHash) {
        var rows = jdbc.queryForList("SELECT body_hash,response::text AS response FROM supplier_idempotency WHERE scope=? AND key_hash=?",
                scope, keyHash);
        if (rows.isEmpty()) return null;
        if (!rows.getFirst().get("body_hash").equals(bodyHash)) {
            throw ApiException.requestError(409, "conflict", "Idempotency-Key", "idempotency_key_reused",
                    "Use a new idempotency key for a different request.");
        }
        return (String) rows.getFirst().get("response");
    }

    private void remember(String scope, String keyHash, String bodyHash, Object response) {
        // Bounded sweep of expired keys on each write, through the retention index.
        jdbc.update("DELETE FROM supplier_idempotency WHERE ctid IN (SELECT ctid FROM supplier_idempotency WHERE created_at <= ? LIMIT 100)",
                Timestamp.from(clock.instant().minus(Duration.ofHours(24))));
        jdbc.update("INSERT INTO supplier_idempotency VALUES(?,?,?,?::jsonb,?)", scope, keyHash, bodyHash, encode(response),
                Timestamp.from(clock.instant()));
    }

    private void audit(PlugPrincipal caller, String action, String resourceId, String reason) {
        jdbc.update("INSERT INTO audit_events(occurred_at,actor_id,actor_role,action,resource,resource_id,reason,request_id)"
                + " VALUES(?,?,'admin',?,'supplier',?,?,?)", Timestamp.from(clock.instant()), caller.userId(), action, resourceId,
                reason, MDC.get("request_id"));
    }

    private String encode(Object value) {
        try { return mapper.writeValueAsString(value); }
        catch (JsonProcessingException failure) { throw new IllegalStateException("Cannot encode a supplier value"); }
    }

    private static Object toArray(Object sqlArray) {
        try { return ((java.sql.Array) sqlArray).getArray(); }
        catch (SQLException failure) { throw new IllegalStateException("Invalid stored skills"); }
    }

    private static Instant instant(Timestamp value) { return value == null ? null : value.toInstant(); }
}
