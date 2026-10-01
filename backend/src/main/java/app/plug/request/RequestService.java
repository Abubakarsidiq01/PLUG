package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.foundation.FixedWindowLimiter;
import app.plug.security.PlugPrincipal;
import app.plug.request.RequestPayloads.Answer;
import app.plug.request.RequestPayloads.Clarification;
import app.plug.request.RequestPayloads.Constraints;
import app.plug.request.RequestPayloads.Create;
import app.plug.request.RequestPayloads.Location;
import app.plug.request.RequestPayloads.Offer;
import app.plug.request.RequestPayloads.Offers;
import app.plug.request.RequestPayloads.Option;
import app.plug.request.RequestPayloads.Place;
import app.plug.request.RequestPayloads.Progress;
import app.plug.request.RequestPayloads.Resource;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@Service
@ConditionalOnProperty(prefix = "plug.requests-v2", name = "enabled", havingValue = "true")
public class RequestService {
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transaction;
    private final ObjectMapper mapper;
    private final Clock clock;
    private final IntentAdapter intent;
    private final String consent;
    private final FixedWindowLimiter limiter = new FixedWindowLimiter(4096);
    public RequestService(JdbcTemplate jdbc, PlatformTransactionManager manager, ObjectMapper mapper, RequestClock clock,
            IntentAdapter intent, @Value("${plug.identity.consent-version}") String consent) {
        this.jdbc = jdbc;
        this.transaction = new TransactionTemplate(manager);
        this.mapper = mapper;
        this.clock = clock.clock();
        this.intent = intent;
        this.consent = consent;
    }
    public Resource create(PlugPrincipal caller, String key, Create input) {
        requireCaller(caller);
        requireConsent(caller);
        // Restricted attempts leave an append-only event even though no request is created.
        if (intent.restricted(input.text())) {
            if (!limiter.tryConsume(caller.userId(), 10, Duration.ofMinutes(1))) throw ApiException.rateLimited(60);
            jdbc.update("INSERT INTO audit_events(actor_id,actor_role,action,resource,resource_id,reason,request_id)"
                    + " VALUES(?,?,'request.restricted','request','none','restricted_intent',?)",
                    caller.userId(), "customer", MDC.get("request_id"));
            throw ApiException.requestError(422, "restricted_intent", null, null, "This request cannot be supported.");
        }
        return transaction.execute(ignored -> {
            lockAccount(caller);
            requireConsent(caller);
            Resource replay = replay(caller, "create", key, input);
            if (replay != null) return replay;
            if (!limiter.tryConsume(caller.userId(), 10, Duration.ofMinutes(1))) throw ApiException.rateLimited(60);
            Constraints constraints = intent.extract(input);
            Instant now = clock.instant();
            String id = "req_" + UUID.randomUUID();
            String clarification = constraints.category() == null ? "cla_" + UUID.randomUUID() : null;
            Instant expires = constraints.neededBy() == null ? now.plus(Duration.ofMinutes(30)) : constraints.neededBy();
            jdbc.update("INSERT INTO requests(id,user_id,text,status,clarification_id,created_at,updated_at,expires_at)"
                    + " VALUES(?,?,?,?,?,?,?,?)", id, caller.userId(), input.text(),
                    clarification == null ? "submitted" : "draft", clarification, time(now), time(now), time(expires));
            jdbc.update("INSERT INTO request_constraints VALUES(?,?,?,?,?,?,?,?,?)", id, constraints.category(),
                    constraints.budgetCents(), constraints.currency(), time(constraints.neededBy()),
                    constraints.maxDistanceM(), constraints.location().latitude(), constraints.location().longitude(),
                    constraints.location().precision());
            Resource result = read(id);
            remember(caller, "create", key, input, result);
            return result;
        });
    }
    public Resource get(PlugPrincipal caller, String id) {
        return transaction.execute(ignored -> { lockOwned(caller, id); expire(id); return read(id); });
    }
    public Resource clarify(PlugPrincipal caller, String id, String key, Answer answer) {
        return transaction.execute(ignored -> {
            // Account first is the common lock ordering for all idempotency writers.
            lockAccount(caller);
            lockOwned(caller, id);
            Resource replay = replay(caller, "clarify:" + id, key, answer);
            if (replay != null) return replay;
            expire(id);
            Resource current = read(id);
            if (!current.status().equals("draft") || !current.clarification().clarificationId().equals(answer.clarificationId())) {
                throw stateConflict("clarification_id", "not_awaiting_clarification", "This request is not awaiting that clarification.");
            }
            if (!List.of("barber", "beauty").contains(answer.value())) {
                throw ApiException.validation("value", "not_an_option", "Choose one of the offered options.");
            }
            jdbc.update("UPDATE request_constraints SET category=? WHERE request_id=?", answer.value(), id);
            transition(id, "submitted", null);
            Resource result = read(id);
            remember(caller, "clarify:" + id, key, answer, result);
            return result;
        });
    }
    public Resource cancel(PlugPrincipal caller, String id) {
        return transaction.execute(ignored -> {
            lockOwned(caller, id);
            expire(id);
            Resource current = read(id);
            if (current.status().equals("canceled")) return current;
            if (!RequestStateMachine.allows(current.status(), "canceled", false)) {
                throw stateConflict("request_id", "not_cancelable", "This request can no longer be canceled.");
            }
            transition(id, "canceled", null);
            return read(id);
        });
    }
    public Offers offers(PlugPrincipal caller, String id) {
        return transaction.execute(ignored -> {
            lockOwned(caller, id);
            expire(id);
            String status = status(id);
            return new Offers(id, List.of("awaiting_responses", "ranked").contains(status) ? listOffers(id) : List.of());
        });
    }
    private void requireCaller(PlugPrincipal caller) {
        if (caller == null) throw ApiException.unauthenticated("Sign in to continue.");
        if (!caller.hasScope("guest") && !caller.hasScope("member")) throw ApiException.forbidden("This operation is not allowed.");
    }
    private void lockAccount(PlugPrincipal caller) {
        requireCaller(caller);
        if (jdbc.queryForList("SELECT id FROM users WHERE id=? AND status='active' FOR UPDATE", caller.userId()).isEmpty()) {
            throw ApiException.unauthenticated("Sign in to continue.");
        }
    }
    private void requireConsent(PlugPrincipal caller) {
        if (jdbc.queryForObject("SELECT count(*) FROM consents WHERE user_id=? AND version=?", Integer.class,
                caller.userId(), consent) == 0) {
            throw ApiException.requestError(403, "forbidden", "consent", "consent_required", "Accept the current terms to continue.");
        }
    }
    private void lockOwned(PlugPrincipal caller, String id) {
        requireCaller(caller);
        if (id.length() > 64 || !id.matches("req_[A-Za-z0-9-]+") || jdbc.queryForList(
                "SELECT id FROM requests WHERE id=? AND user_id=? FOR UPDATE", id, caller.userId()).isEmpty()) {
            throw ApiException.notFound("Request not found.");
        }
    }
    private Resource replay(PlugPrincipal caller, String operation, String key, Object input) {
        if (key == null) return null;
        jdbc.update("DELETE FROM request_idempotency WHERE user_id=? AND operation=? AND key_hash=? AND created_at<=?",
                caller.userId(), operation, digest(key), time(clock.instant().minus(Duration.ofHours(24))));
        var rows = jdbc.queryForList("SELECT body_hash,response::text FROM request_idempotency"
                + " WHERE user_id=? AND operation=? AND key_hash=?", caller.userId(), operation, digest(key));
        if (rows.isEmpty()) return null;
        if (!rows.getFirst().get("body_hash").equals(digest(encode(input)))) {
            throw stateConflict("Idempotency-Key", "idempotency_key_reused", "Use a new idempotency key for a different request.");
        }
        try { return mapper.readValue((String) rows.getFirst().get("response"), Resource.class); }
        catch (com.fasterxml.jackson.core.JsonProcessingException corrupt) { throw new IllegalStateException("Invalid stored response"); }
    }
    private void remember(PlugPrincipal caller, String operation, String key, Object input, Resource response) {
        if (key != null) jdbc.update("INSERT INTO request_idempotency VALUES(?,?,?,?,?::jsonb,?)", caller.userId(),
                operation, digest(key), digest(encode(input)), encode(response), time(clock.instant()));
    }
    private String encode(Object value) {
        try { return mapper.writeValueAsString(value); }
        catch (com.fasterxml.jackson.core.JsonProcessingException failure) { throw new IllegalStateException("Cannot encode request"); }
    }
    private static String digest(String value) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8))); }
        catch (java.security.NoSuchAlgorithmException impossible) { throw new IllegalStateException(impossible); }
    }
    private ApiException stateConflict(String field, String code, String message) {
        return ApiException.requestError(409, "conflict", field, code, message);
    }
    private String status(String id) { return jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, id); }
    private void transition(String id, String next, String reason) {
        RequestStateMachine.require(status(id), next, false);
        jdbc.update("UPDATE requests SET status=?,no_result_reason=?,updated_at=? WHERE id=?", next, reason, time(clock.instant()), id);
    }
    private void expire(String id) {
        Resource resource = read(id);
        if (!List.of("draft", "submitted", "routed", "awaiting_responses", "ranked").contains(resource.status())) return;
        boolean deadline = !resource.expiresAt().isAfter(clock.instant());
        boolean offersGone = resource.status().equals("ranked") && resource.progress().offersReady() == 0;
        if (!deadline && !offersGone) return;
        if (resource.status().equals("submitted")) transition(id, "routed", null);
        String reason = resource.status().equals("draft") ? "clarification_unanswered"
                : resource.progress().contacted() == 0 ? "no_coverage" : "no_offers";
        transition(id, "expired", reason);
    }
    private Resource read(String id) {
        return jdbc.queryForObject("SELECT r.*,c.category,c.budget_cents,c.currency,c.needed_by,c.max_distance_m,"
                + "c.latitude,c.longitude,c.precision FROM requests r JOIN request_constraints c ON c.request_id=r.id WHERE r.id=?",
                (rs, row) -> {
                    String state = rs.getString("status");
                    String action = RequestStateMachine.action(state);
                    Constraints constraints = new Constraints(rs.getString("category"), (Integer) rs.getObject("budget_cents"),
                            rs.getString("currency"), instant(rs, "needed_by"), rs.getInt("max_distance_m"),
                            new Location(rs.getDouble("latitude"), rs.getDouble("longitude"), rs.getString("precision")));
                    Clarification question = state.equals("draft") ? new Clarification(rs.getString("clarification_id"), "category",
                            "Which service do you need?", List.of(new Option("barber", "Barber"), new Option("beauty", "Beauty"))) : null;
                    return new Resource(id, state, action, rs.getString("text"), constraints, progress(id), question,
                            rs.getString("no_result_reason"), action.equals("wait_for_offers") ? 1 : null,
                            instant(rs, "created_at"), instant(rs, "updated_at"), instant(rs, "expires_at"));
                }, id);
    }
    private Progress progress(String id) {
        Integer contacted = jdbc.queryForObject("SELECT count(*) FROM request_seed_work WHERE request_id=?", Integer.class, id);
        Integer replied = jdbc.queryForObject("SELECT count(*) FROM request_seed_work WHERE request_id=? AND replied_at IS NOT NULL", Integer.class, id);
        Integer offers = jdbc.queryForObject("SELECT count(*) FROM request_offers WHERE request_id=? AND expires_at>?", Integer.class, id, time(clock.instant()));
        return new Progress(contacted, replied, offers);
    }
    private List<Offer> listOffers(String id) {
        return jdbc.query("SELECT o.*,p.name,p.address,w.distance_m FROM request_offers o JOIN places p ON p.id=o.place_id"
                + " JOIN request_seed_work w ON w.request_id=o.request_id AND w.place_id=o.place_id"
                + " WHERE o.request_id=? AND o.expires_at>? ORDER BY o.available_at,o.price_cents,w.distance_m,o.id LIMIT 20",
                (rs, row) -> new Offer(rs.getString("id"), new Place(rs.getString("place_id"), rs.getString("name"),
                        rs.getString("address"), rs.getInt("distance_m")), rs.getString("service_name"), rs.getInt("price_cents"),
                        rs.getString("currency"), instant(rs, "available_at"), instant(rs, "expires_at"), instant(rs, "observed_at"),
                        rs.getString("truth_label"), rs.getString("source")), id, time(clock.instant()));
    }
    static Timestamp time(Instant instant) { return instant == null ? null : Timestamp.from(instant); }
    private static Instant instant(ResultSet rs, String name) throws SQLException {
        Timestamp value = rs.getTimestamp(name);
        return value == null ? null : value.toInstant();
    }
    // Each invocation performs one bounded unit of persisted work under the same row lock
    // as cancellation. Multiple instances skip locked rows; a restart resumes from the DB.
    public void workOnce() {
        transaction.executeWithoutResult(ignored -> {
            List<String> ids = jdbc.queryForList("SELECT id FROM requests WHERE status IN"
                    + " ('submitted','routed','awaiting_responses')"
                    + " OR (status IN ('draft','ranked') AND expires_at<=?)"
                    + " OR (status='ranked' AND NOT EXISTS (SELECT 1 FROM request_offers o WHERE o.request_id=requests.id AND o.expires_at>?))"
                    + " ORDER BY updated_at,id LIMIT 20 FOR UPDATE SKIP LOCKED", String.class, time(clock.instant()), time(clock.instant()));
            for (String id : ids) {
                expire(id);
                Resource resource = read(id);
                switch (resource.status()) {
                    case "submitted" -> route(resource);
                    case "routed" -> transition(id, "awaiting_responses", null);
                    case "awaiting_responses" -> reply(resource);
                    default -> { }
                }
            }
        });
    }
    private void route(Resource resource) {
        Constraints c = resource.constraints();
        jdbc.update("INSERT INTO request_seed_work(request_id,place_id,distance_m)"
                + " SELECT ?,p.id,round(ST_Distance(p.location,ST_SetSRID(ST_MakePoint(?,?),4326)::geography))::integer"
                + " FROM places p JOIN supplier_seeds s ON s.place_id=p.id WHERE p.category=? AND s.enabled"
                + " AND ST_DWithin(p.location,ST_SetSRID(ST_MakePoint(?,?),4326)::geography,?)"
                + " ORDER BY p.location <-> ST_SetSRID(ST_MakePoint(?,?),4326)::geography,p.id LIMIT 50",
                resource.requestId(), c.location().longitude(), c.location().latitude(), c.category(),
                c.location().longitude(), c.location().latitude(), c.maxDistanceM(), c.location().longitude(), c.location().latitude());
        transition(resource.requestId(), "routed", null);
        if (progress(resource.requestId()).contacted() == 0) transition(resource.requestId(), "expired", "no_coverage");
    }
    private void reply(Resource resource) {
        String id = resource.requestId();
        var rows = jdbc.queryForList("SELECT w.place_id,s.service_name,s.price_cents,s.available_after_minutes,s.valid_for_minutes"
                + " FROM request_seed_work w JOIN supplier_seeds s ON s.place_id=w.place_id"
                + " WHERE w.request_id=? AND w.replied_at IS NULL ORDER BY w.distance_m,w.place_id LIMIT 1", id);
        if (!rows.isEmpty()) {
            var row = rows.getFirst();
            Instant now = clock.instant();
            // Synthetic availability comes from the seeded schedule and the creation instant,
            // not a model, a polling timer, or a claim about real supplier confirmation.
            Instant available = resource.createdAt().plusSeconds(((Integer) row.get("available_after_minutes")) * 60L);
            Instant expires = available.plusSeconds(((Integer) row.get("valid_for_minutes")) * 60L);
            int price = (Integer) row.get("price_cents");
            Constraints c = resource.constraints();
            if (available.isAfter(now) && (c.budgetCents() == null || price <= c.budgetCents())
                    && (c.neededBy() == null || !available.isAfter(c.neededBy())) && progress(id).offersReady() < 20) {
                jdbc.update("INSERT INTO request_offers VALUES(?,?,?,?,?,'USD',?,?,?,'estimated','seed')", "off_" + UUID.randomUUID(),
                        id, row.get("place_id"), row.get("service_name"), price, time(available), time(expires), time(now));
            }
            jdbc.update("UPDATE request_seed_work SET replied_at=? WHERE request_id=? AND place_id=?", time(now), id, row.get("place_id"));
            jdbc.update("UPDATE requests SET updated_at=? WHERE id=?", time(now), id);
        }
        Progress progress = progress(id);
        if (progress.replied() == progress.contacted()) {
            transition(id, progress.offersReady() > 0 ? "ranked" : "expired", progress.offersReady() > 0 ? null : "no_offers");
        }
    }
}
