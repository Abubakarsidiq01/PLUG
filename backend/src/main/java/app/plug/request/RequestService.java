package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.foundation.FixedWindowLimiter;
import app.plug.foundation.RateWindow;
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
import app.plug.request.RequestPayloads.Reservation;
import app.plug.request.RequestPayloads.Resource;
import app.plug.request.RequestPayloads.Selection;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
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
    private final RestrictedIntentPolicy policy;
    private final MatchService matches;
    private final String consent;
    final FixedWindowLimiter limiter = new FixedWindowLimiter(4096);
    final RateWindow window;
    public RequestService(JdbcTemplate jdbc, PlatformTransactionManager manager, ObjectMapper mapper, RequestClock clock,
            IntentAdapter intent, RestrictedIntentPolicy policy, MatchService matches, RateWindow window,
            @Value("${plug.identity.consent-version}") String consent) {
        this.jdbc = jdbc;
        this.transaction = new TransactionTemplate(manager);
        this.mapper = mapper;
        this.clock = clock.clock();
        this.intent = intent;
        this.policy = policy;
        this.matches = matches;
        this.consent = consent;
        this.window = window;
    }
    public Resource create(PlugPrincipal caller, String key, Create input) {
        requireCaller(caller);
        requireConsent(caller);
        refuseRestricted(caller, input.text());
        Resource prior = prepareCreate(caller, "create", key, input, Resource.class);
        if (prior != null) return prior;
        // A slow provider must not hold the account lock or a database connection.
        IntentAdapter.Result extracted;
        try {
            extracted = intent.extract(input, caller.userId());
        } catch (IntentAdapter.Refused refused) {
            refuse(caller, refused.rule());
            throw refused;
        }
        return transaction.execute(ignored -> {
            lockAccount(caller);
            requireConsent(caller);
            Resource replay = replay(caller, "create", key, input, Resource.class);
            if (replay != null) return replay;
            Resource result = insert(caller, input.text(), extracted);
            remember(caller, "create", key, input, result);
            return result;
        });
    }
    /// Cheap admission before external classification. The final transaction checks replay
    /// again: concurrent retries may both classify, but can only persist one result.
    <T> T prepareCreate(PlugPrincipal caller, String operation, String key, Object input, Class<T> type) {
        return transaction.execute(ignored -> {
            lockAccount(caller);
            requireConsent(caller);
            T prior = replay(caller, operation, key, input, type);
            if (prior != null) return prior;
            if (!limiter.tryConsume(caller.userId(), 10, window.length())) throw ApiException.rateLimited(window.retryAfterSeconds());
            return null;
        });
    }
    /// The restricted-intent policy runs first, before any extraction (manual v4 §19A.1).
    /// A refused ask creates nothing but its audit event, whose reason names the rule.
    void refuseRestricted(PlugPrincipal caller, String text) {
        var refusal = policy.refusal(text);
        if (refusal.isPresent()) refuse(caller, refusal.get());
    }
    void refuse(PlugPrincipal caller, String rule) {
        if (!limiter.tryConsume(caller.userId(), 10, window.length())) throw ApiException.rateLimited(window.retryAfterSeconds());
        jdbc.update("INSERT INTO audit_events(actor_id,actor_role,action,resource,resource_id,reason,request_id)"
                + " VALUES(?,?,'request.restricted','request','none',?,?)",
                caller.userId(), "customer", "restricted_intent:" + rule, MDC.get("request_id"));
        throw ApiException.requestError(422, "restricted_intent", null, null, "PLUG can't help with this request.");
    }
    /// Creates the request inside the caller's transaction. Used by POST /v1/requests and by
    /// the ask entry point, so both produce exactly the same request.
    Resource insert(PlugPrincipal caller, String text, IntentAdapter.Result extracted) {
        {
            Constraints constraints = extracted.constraints();
            Instant now = clock.instant();
            String id = "req_" + UUID.randomUUID();
            String clarification = constraints.category() == null ? "cla_" + UUID.randomUUID() : null;
            Instant expires = constraints.neededBy() == null ? now.plus(Duration.ofMinutes(30)) : constraints.neededBy();
            jdbc.update("INSERT INTO requests(id,user_id,text,status,clarification_id,clarification_options,"
                    + "created_at,updated_at,expires_at) VALUES(?,?,?,?,?,?::jsonb,?,?,?)", id, caller.userId(), text,
                    clarification == null ? "submitted" : "draft", clarification,
                    clarification == null ? null : json(extracted.clarificationOptions()), time(now), time(now), time(expires));
            jdbc.update("INSERT INTO request_constraints(request_id,category,service_name,skill_tags,licence_required,"
                    + "budget_cents,currency,needed_by,max_distance_m,latitude,longitude,precision) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)", id,
                    constraints.category(), constraints.serviceName(), constraints.skillTags().toArray(String[]::new),
                    constraints.licenceRequired(),
                    constraints.budgetCents(), constraints.currency(), time(constraints.neededBy()),
                    constraints.maxDistanceM(), constraints.location().latitude(), constraints.location().longitude(),
                    constraints.location().precision());
            return read(id);
        }
    }
    public Resource get(PlugPrincipal caller, String id) {
        return transaction.execute(ignored -> { lockOwned(caller, id); expire(id); return read(id); });
    }
    public Resource clarify(PlugPrincipal caller, String id, String key, Answer answer) {
        return transaction.execute(ignored -> {
            // Account first is the common lock ordering for all idempotency writers.
            lockAccount(caller);
            lockOwned(caller, id);
            Resource replay = replay(caller, "clarify:" + id, key, answer, Resource.class);
            if (replay != null) return replay;
            expire(id);
            Resource current = read(id);
            if (!current.status().equals("draft") || !current.clarification().clarificationId().equals(answer.clarificationId())) {
                throw stateConflict("clarification_id", "not_awaiting_clarification", "This request is not awaiting that clarification.");
            }
            Option chosen = current.clarification().options().stream()
                    .filter(option -> option.value().equals(answer.value())).findFirst()
                    .orElseThrow(() -> ApiException.validation("value", "not_an_option", "Choose one of the offered options."));
            var skill = intent.vocabulary().get(chosen.value());
            if (skill == null) throw ApiException.validation("value", "not_an_option", "Choose one of the offered options.");
            jdbc.update("UPDATE request_constraints SET category=?,service_name=?,skill_tags=?,licence_required=? WHERE request_id=?",
                    skill.tag(), skill.display(), new String[] {skill.tag()}, skill.requiresLicence(), id);
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
            // Contract Reservation: confirmed_at only while confirmed, ended_at once ended.
            jdbc.update("UPDATE request_reservations SET status='canceled',confirmed_at=NULL,ended_at=?"
                    + " WHERE request_id=? AND status IN ('pending','confirmed')", time(clock.instant()), id);
            return read(id);
        });
    }
    private static final String BOOKING_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    private final SecureRandom random = new SecureRandom();
    /// P3.S6 selectOffer. The account lock serialises a caller's selections, so a race has one
    /// winner; the partial unique index on live reservations is the backstop.
    Resource select(PlugPrincipal caller, String id, String key, Selection selection) {
        return transaction.execute(ignored -> {
            lockAccount(caller);
            requireConsent(caller);
            // A stored answer is the caller's own, so a retry replays it without spending budget.
            Resource replay = replay(caller, "select:" + id, key, selection, Resource.class);
            if (replay != null) return replay;
            // Before the ownership check, so probing other people's ids spends the caller's budget.
            if (!limiter.tryConsume("select:" + caller.userId(), 10, window.length())) {
                throw ApiException.rateLimited(window.retryAfterSeconds());
            }
            lockOwned(caller, id);
            expire(id);
            String state = status(id);
            if (List.of("user_selected", "confirmed", "completed").contains(state)) {
                throw stateConflict("offer_id", "already_selected", "You already chose an offer for this request.");
            }
            if (!state.equals("ranked")) throw stateConflict("request_id", "not_selectable", "This request is not ready for a choice.");
            Instant now = clock.instant();
            var offers = jdbc.queryForList("SELECT available_at,provider_id FROM request_offers"
                    + " WHERE id=? AND request_id=? AND expires_at>? AND withdrawn_at IS NULL", selection.offerId(), id, time(now));
            if (offers.isEmpty()) {
                throw stateConflict("offer_id", "offer_unavailable", "That offer is no longer available. Choose another.");
            }
            Instant available = ((Timestamp) offers.getFirst().get("available_at")).toInstant();
            // Owner rule (contract 0.7.1): min(now + 20 min, max(available_at, now + 10 min)).
            Instant floor = now.plus(Duration.ofMinutes(10));
            Instant cap = now.plus(Duration.ofMinutes(20));
            Instant confirmBy = available.isAfter(floor) ? (available.isBefore(cap) ? available : cap) : floor;
            StringBuilder ref = new StringBuilder();
            for (int n = 0; n < 4; n++) ref.append(BOOKING_ALPHABET.charAt(random.nextInt(BOOKING_ALPHABET.length())));
            jdbc.update("INSERT INTO request_reservations(id,request_id,offer_id,provider_id,status,booking_ref,confirm_by,created_at)"
                    + " VALUES(?,?,?,?,'pending',?,?,?)", "rsv_" + UUID.randomUUID(), id, selection.offerId(),
                    offers.getFirst().get("provider_id"), ref.toString(),
                    time(confirmBy), time(now));
            transition(id, "user_selected", null);
            Resource result = read(id);
            remember(caller, "select:" + id, key, selection, result);
            return result;
        });
    }
    /// The provider's answer to a pending reservation, on a match they own. Only "confirm"
    /// moves a request to confirmed (manual v4 19.6). The HTTP route calls it through answer().
    ReservationService.ProviderDecisionResult decide(String provider, String matchId, String decision) {
        if (!List.of("confirm", "release").contains(decision)) {
            throw ApiException.validation("decision", "invalid", "Choose confirm or release.");
        }
        if (provider == null || matchId == null || matchId.length() > 64 || !matchId.matches("mat_[A-Za-z0-9-]+")) {
            throw ApiException.notFound("Match not found.");
        }
        if (!limiter.tryConsume("reservation:" + provider, 30, window.length())) throw ApiException.rateLimited(window.retryAfterSeconds());
        return transaction.execute(ignored -> {
            var match = jdbc.queryForList("SELECT request_id FROM request_matches WHERE match_id=? AND provider_id=?",
                    String.class, matchId, provider);
            if (match.isEmpty()) throw ApiException.notFound("Match not found.");
            String id = match.getFirst();
            // Request first, then match: the same order every request-level writer uses.
            jdbc.queryForList("SELECT id FROM requests WHERE id=? FOR UPDATE", id);
            jdbc.queryForList("SELECT match_id FROM request_matches WHERE match_id=? FOR UPDATE", matchId);
            expire(id);
            var rows = jdbc.queryForList("SELECT id,offer_id,status,confirm_by FROM request_reservations"
                    + " WHERE request_id=? AND provider_id=? ORDER BY created_at DESC,id DESC LIMIT 1", id, provider);
            if (rows.isEmpty()) throw stateConflict("match_id", "no_reservation", "There is no reservation waiting for you.");
            var row = rows.getFirst();
            String current = (String) row.get("status");
            String wanted = decision.equals("confirm") ? "confirmed" : "released";
            Instant now = clock.instant();
            if (current.equals(wanted)) return new ReservationService.ProviderDecisionResult(current, status(id));
            if (!current.equals("pending") || !now.isBefore(((Timestamp) row.get("confirm_by")).toInstant())) {
                throw stateConflict("match_id", "reservation_closed", "This reservation is closed.");
            }
            if (wanted.equals("confirmed")) {
                jdbc.update("UPDATE request_reservations SET status='confirmed',confirmed_at=? WHERE id=?", time(now), row.get("id"));
                transition(id, "confirmed", null, true);
            } else {
                endReservation(id, (String) row.get("id"), (String) row.get("offer_id"), "released", now);
            }
            return new ReservationService.ProviderDecisionResult(wanted, status(id));
        });
    }
    /// Contract 0.7.1 answerReservation. Account, then request, then match: the common lock order.
    /// The match row's foreign key means only a provider with a profile can own one.
    RequestPayloads.InboxItem answer(PlugPrincipal caller, String matchId, String decision) {
        return transaction.execute(ignored -> {
            lockAccount(caller);
            // shortcut: ProviderProfile.standing (0.7.0) is not stored yet, so no provider is suspended;
            // refuse suspended providers here once the admin standing route stores it.
            decide(caller.userId(), matchId, decision);
            return inboxItem(caller.userId(), matchId);
        });
    }
    private static final List<String> LIVE = List.of("submitted", "routed", "awaiting_responses", "ranked");
    /// A phone number (seven or more digits, separators allowed), an email address or a link.
    private static final java.util.regex.Pattern CONTACT = java.util.regex.Pattern.compile(
            "(?:\\+?\\d[\\s().-]*){7,}|[^\\s@]+@[^\\s@]+\\.[^\\s@]+|(?i:https?://|www\\.)"
                    + "|(?i:\\b[a-z0-9-]+(?:\\.[a-z0-9-]+)*\\.(?:com|net|org|io|co|me|app|ly|us|info|biz|xyz|link|site)\\b)");
    /// Contract 0.7.1 sendProviderOffer, the in-app path. The caller is a provider matched to the
    /// request; anyone else, the asker included, gets the same 404 as a request that does not exist.
    Offer sendOffer(PlugPrincipal caller, String id, String key, RequestPayloads.OfferCreate input) {
        return transaction.execute(ignored -> {
            lockAccount(caller);
            requireConsent(caller);
            Offer replay = replay(caller, "offer:" + id, key, input, Offer.class);
            if (replay != null) return replay;
            // Before the match lookup, so probing request ids spends the caller's budget.
            if (!limiter.tryConsume("offer:" + caller.userId(), 10, window.length())) {
                throw ApiException.rateLimited(window.retryAfterSeconds());
            }
            // shortcut: ProviderProfile.standing is not stored yet, so no provider is suspended (403
            // suspended); refuse suspended providers here once the admin standing route stores it.
            List<String> matched = id.length() > 64 || !id.matches("req_[A-Za-z0-9-]+") ? List.of()
                    : jdbc.queryForList("SELECT m.match_id FROM request_matches m JOIN requests r ON r.id=m.request_id"
                            + " WHERE m.request_id=? AND m.provider_id=? AND r.user_id<>?", String.class, id, caller.userId(), caller.userId());
            if (matched.isEmpty()) throw ApiException.notFound("Request not found.");
            // Request first, then match: the same order every request-level writer uses.
            jdbc.queryForList("SELECT id FROM requests WHERE id=? FOR UPDATE", id);
            var match = jdbc.queryForMap("SELECT distance_m,replied_at FROM request_matches WHERE match_id=? FOR UPDATE",
                    matched.getFirst());
            expire(id);
            if (jdbc.queryForObject("SELECT count(*) FROM request_offers WHERE request_id=? AND provider_id=?", Integer.class,
                    id, caller.userId()) > 0) {
                throw stateConflict("request_id", "already_offered", "You already sent an offer for this request.");
            }
            // shortcut: nothing writes a decline until P3.S12; a reply with no offer is one.
            if (!LIVE.contains(status(id)) || match.get("replied_at") != null) {
                throw stateConflict("request_id", "request_closed", "This request has closed.");
            }
            Constraints c = read(id).constraints();
            Instant now = clock.instant();
            Instant available = input.availableAt();
            if (c.budgetCents() != null && input.priceCents() > c.budgetCents()) {
                throw ApiException.validation("price_cents", "over_budget", "That is above the customer's budget.");
            }
            if (available.isBefore(now) || available.isAfter(now.plus(Duration.ofDays(7)))
                    || (c.neededBy() != null && available.isAfter(c.neededBy()))) {
                throw ApiException.validation("available_at", "outside_window", "Choose a time before the customer needs it.");
            }
            if (input.note() != null && CONTACT.matcher(input.note()).find()) {
                throw ApiException.validation("note", "contact_in_note", "Leave out phone numbers, emails and links.");
            }
            String offerId = "off_" + UUID.randomUUID();
            // Owner decision 2026-11-17: a portal offer is valid until 15 minutes after its slot starts.
            jdbc.update("INSERT INTO request_offers(id,request_id,service_name,price_cents,currency,available_at,expires_at,"
                    + "observed_at,truth_label,source,provider_id,note,distance_m) VALUES(?,?,?,?,?,?,?,?,'confirmed','portal',?,?,?)",
                    offerId, id, c.serviceName(), input.priceCents(), input.currency(), time(available),
                    time(available.plus(Duration.ofMinutes(15))), time(now), caller.userId(), input.note(),
                    roundedDistance((Integer) match.get("distance_m")));
            jdbc.update("UPDATE request_matches SET replied_at=? WHERE match_id=?", time(now), matched.getFirst());
            Offer result = jdbc.queryForObject(OFFER_SELECT + " WHERE o.id=?", OFFER_ROW, offerId);
            remember(caller, "offer:" + id, key, input, result);
            return result;
        });
    }
    /// Contract 0.7.1 getProviderInbox: open items first, then the last seven days, newest first, at
    /// most 50. Only the caller's own matches; a caller with no provider profile is 404.
    RequestPayloads.ProviderInbox inbox(PlugPrincipal caller) {
        requireCaller(caller);
        if (!limiter.tryConsume("inbox:" + caller.userId(), 30, window.length())) throw ApiException.rateLimited(window.retryAfterSeconds());
        Instant now = clock.instant();
        return transaction.execute(ignored -> {
            // The same account check as answerReservation: 401 for an inactive account.
            lockAccount(caller);
            if (jdbc.queryForObject("SELECT count(*) FROM provider_profiles WHERE user_id=?", Integer.class, caller.userId()) == 0) {
                throw ApiException.notFound("You have not offered a service yet.");
            }
            // The first sort key is inboxItem's "open", in SQL, so the 50 kept are the right 50.
            List<String> ids = jdbc.queryForList("SELECT m.match_id FROM request_matches m JOIN requests r ON r.id=m.request_id"
                    + " WHERE m.provider_id=? AND m.notified_at>? ORDER BY (m.replied_at IS NULL AND m.notified_at>?"
                    + " AND r.status IN ('submitted','routed','awaiting_responses','ranked') AND NOT EXISTS (SELECT 1 FROM request_offers o"
                    + " WHERE o.request_id=m.request_id AND o.provider_id=m.provider_id)"
                    + " AND NOT EXISTS (SELECT 1 FROM request_reservations v WHERE v.request_id=m.request_id)) DESC,m.notified_at DESC,m.match_id LIMIT 50",
                    String.class, caller.userId(), time(now.minus(Duration.ofDays(7))), time(now.minus(REPLY_WINDOW)));
            return new RequestPayloads.ProviderInbox(ids.stream().map(id -> inboxItem(caller.userId(), id)).toList(),
                    MatchService.NOTIFICATIONS_PER_HOUR);
        });
    }
    /// Contract 0.7.1: respond_by is notified_at plus this outreach reply window.
    private static final Duration REPLY_WINDOW = Duration.ofMinutes(5);
    /// The provider's view of one match: never the asker's words, location or identity.
    RequestPayloads.InboxItem inboxItem(String provider, String matchId) {
        MatchRow match = jdbc.queryForObject("SELECT m.request_id,m.distance_m,m.notified_at,m.replied_at,r.status,r.updated_at,"
                + "c.service_name,c.skill_tags,c.budget_cents,c.currency,c.needed_by FROM request_matches m"
                + " JOIN requests r ON r.id=m.request_id JOIN request_constraints c ON c.request_id=m.request_id"
                + " WHERE m.match_id=? AND m.provider_id=?", (rs, row) -> new MatchRow(rs.getString("request_id"),
                        rs.getInt("distance_m"), instant(rs, "notified_at"), instant(rs, "replied_at"), rs.getString("status"),
                        instant(rs, "updated_at"), rs.getString("service_name"),
                        List.of((String[]) rs.getArray("skill_tags").getArray()), (Integer) rs.getObject("budget_cents"),
                        rs.getString("currency"), instant(rs, "needed_by")), matchId, provider);
        String requestId = match.requestId();
        Reservation reservation = jdbc.query("SELECT * FROM request_reservations WHERE request_id=? AND provider_id=?"
                + " ORDER BY created_at DESC,id DESC LIMIT 1", RESERVATION_ROW, requestId, provider).stream().findFirst().orElse(null);
        Instant now = clock.instant();
        // A pending reservation past confirm_by reads as the timeout settleReservation will write, so the
        // list takes no request or match lock and never waits for the worker.
        if (reservation != null && reservation.status().equals("pending") && !now.isBefore(reservation.confirmBy())) {
            reservation = new Reservation(reservation.reservationId(), reservation.offerId(), "timed_out", reservation.bookingRef(),
                    reservation.confirmBy(), null, reservation.confirmBy(), reservation.createdAt());
        }
        // A released or timed-out offer is withdrawn but still shown, as in the contract examples.
        Offer found = reservation != null
                ? reservation.offerId() == null ? null
                        : jdbc.query(OFFER_SELECT + " WHERE o.id=?", OFFER_ROW, reservation.offerId()).stream().findFirst().orElse(null)
                : jdbc.query(OFFER_SELECT + " WHERE o.request_id=? AND o.provider_id=? ORDER BY o.observed_at DESC,o.id DESC LIMIT 1",
                        OFFER_ROW, requestId, provider).stream().findFirst().orElse(null);
        // The provider sees the asker's distance only to the nearest 100 m (§25 data minimisation).
        // A portal offer's distance was rounded when it was written.
        Offer offer = found == null || found.place() == null ? found : new Offer(found.offerId(),
                new RequestPayloads.Place(found.place().placeId(), found.place().name(), found.place().address(),
                        roundedDistance(found.place().distanceM())), roundedDistance(found.distanceM()), found.note(),
                found.serviceName(), found.priceCents(), found.currency(), found.availableAt(), found.expiresAt(),
                found.observedAt(), found.truthLabel(), found.source(), found.providerScore(), found.business());
        Instant respondBy = match.notifiedAt().plus(REPLY_WINDOW);
        String request = match.requestStatus();
        boolean live = List.of("submitted", "routed", "awaiting_responses", "ranked").contains(request);
        // Contract 0.7.1 MatchStatus.
        String status = reservation != null ? switch (reservation.status()) {
            case "pending" -> "selected";
            case "confirmed" -> "confirmed";
            case "released", "timed_out" -> "not_chosen";
            case "canceled" -> "closed";
            default -> throw new IllegalStateException("Unknown reservation status");
        } : offer != null ? (request.equals("canceled") ? "closed"
                : live && offer.expiresAt().isAfter(now) ? "offered" : "not_chosen")
        // shortcut: nothing records a decline yet (P3.S12); a reply without an offer is one.
        : match.repliedAt() != null ? "declined"
        // Silent so far. Whether the reply window closed before the request did decides silence.
        : silentStatus(requestId, provider, request, match.updatedAt(), respondBy, now);
        return new RequestPayloads.InboxItem(matchId, requestId, status, match.serviceName(), match.skillTags(),
                match.budgetCents(), match.currency(), match.neededBy(), roundedDistance(match.distanceM()),
                respondBy, match.notifiedAt(), offer, reservation);
    }
    /// MatchStatus for a provider who neither offered nor replied (contract 0.7.1).
    private String silentStatus(String requestId, String provider, String request, Instant updatedAt, Instant respondBy, Instant now) {
        // When the asker first chose someone else's offer: exact, from the reservation.
        Timestamp chosen = jdbc.queryForObject("SELECT min(created_at) FROM request_reservations WHERE request_id=?"
                + " AND provider_id IS DISTINCT FROM ?", Timestamp.class, requestId, provider);
        if (chosen != null) return chosen.toInstant().isBefore(respondBy) ? "not_chosen" : "expired";
        // Canceled is terminal and only transition() writes updated_at, so it is the cancel time.
        if (request.equals("canceled")) return updatedAt.isBefore(respondBy) ? "closed" : "expired";
        // shortcut: expired (and blocked) are set lazily, so no end time is recorded; such a match is
        // closed rather than counted as silence. Record the end time if P3.S12 scores silence from it.
        if (!List.of("submitted", "routed", "awaiting_responses", "ranked").contains(request)) return "closed";
        return now.isBefore(respondBy) ? "open" : "expired";
    }
    private record MatchRow(String requestId, int distanceM, Instant notifiedAt, Instant repliedAt, String requestStatus,
            Instant updatedAt, String serviceName, List<String> skillTags, Integer budgetCents, String currency, Instant neededBy) {}
    private static int roundedDistance(int metres) { return (int) Math.min(80_000, Math.round(metres / 100.0) * 100); }
    /// Release or timeout: the offer is withdrawn and the asker gets the other live offers back.
    private void endReservation(String id, String reservationId, String offerId, String outcome, Instant endedAt) {
        jdbc.update("UPDATE request_reservations SET status=?,ended_at=? WHERE id=?", outcome, time(endedAt), reservationId);
        if (offerId != null) jdbc.update("UPDATE request_offers SET withdrawn_at=? WHERE id=? AND withdrawn_at IS NULL", time(endedAt), offerId);
        if (progress(id).offersReady() > 0) transition(id, "ranked", null);
        else transition(id, "expired", "not_confirmed");
    }
    /// Reservation timers, run under the request lock: timeout at confirm_by, completion three
    /// hours after the chosen offer's slot.
    private void settleReservation(String id) {
        Instant now = clock.instant();
        String state = status(id);
        if (state.equals("user_selected")) {
            var due = jdbc.queryForList("SELECT id,offer_id,confirm_by FROM request_reservations"
                    + " WHERE request_id=? AND status='pending' AND confirm_by<=?", id, time(now));
            if (!due.isEmpty()) {
                var row = due.getFirst();
                endReservation(id, (String) row.get("id"), (String) row.get("offer_id"), "timed_out",
                        ((Timestamp) row.get("confirm_by")).toInstant());
            }
        } else if (state.equals("confirmed") && jdbc.queryForObject("SELECT count(*) FROM request_reservations v"
                + " JOIN request_offers o ON o.id=v.offer_id WHERE v.request_id=? AND v.status='confirmed'"
                + " AND o.available_at + interval '3 hours' <= ?", Integer.class, id, time(now)) > 0) {
            transition(id, "completed", null);
        }
    }
    public Offers offers(PlugPrincipal caller, String id) {
        return transaction.execute(ignored -> {
            lockOwned(caller, id);
            expire(id);
            String status = status(id);
            return new Offers(id, List.of("awaiting_responses", "ranked").contains(status) ? listOffers(id) : List.of());
        });
    }
    void requireCaller(PlugPrincipal caller) {
        if (caller == null) throw ApiException.unauthenticated("Sign in to continue.");
        if (!caller.hasScope("guest") && !caller.hasScope("member")) throw ApiException.forbidden("This operation is not allowed.");
    }
    void lockAccount(PlugPrincipal caller) {
        requireCaller(caller);
        if (jdbc.queryForList("SELECT id FROM users WHERE id=? AND status='active' FOR UPDATE", caller.userId()).isEmpty()) {
            throw ApiException.unauthenticated("Sign in to continue.");
        }
    }
    void requireConsent(PlugPrincipal caller) {
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
    <T> T replay(PlugPrincipal caller, String operation, String key, Object input, Class<T> type) {
        if (key == null) return null;
        jdbc.update("DELETE FROM request_idempotency WHERE user_id=? AND operation=? AND key_hash=? AND created_at<=?",
                caller.userId(), operation, digest(key), time(clock.instant().minus(Duration.ofHours(24))));
        var rows = jdbc.queryForList("SELECT body_hash,response::text FROM request_idempotency"
                + " WHERE user_id=? AND operation=? AND key_hash=?", caller.userId(), operation, digest(key));
        if (rows.isEmpty()) return null;
        if (!rows.getFirst().get("body_hash").equals(digest(encode(input)))) {
            throw stateConflict("Idempotency-Key", "idempotency_key_reused", "Use a new idempotency key for a different request.");
        }
        try { return mapper.readValue((String) rows.getFirst().get("response"), type); }
        catch (com.fasterxml.jackson.core.JsonProcessingException corrupt) { throw new IllegalStateException("Invalid stored response"); }
    }
    void remember(PlugPrincipal caller, String operation, String key, Object input, Object response) {
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
    ApiException stateConflict(String field, String code, String message) {
        return ApiException.requestError(409, "conflict", field, code, message);
    }
    private String status(String id) { return jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, id); }
    private void transition(String id, String next, String reason) { transition(id, next, reason, false); }
    /// supplierEvent is true only on the provider's confirm (decide); nothing else may confirm.
    private void transition(String id, String next, String reason, boolean supplierEvent) {
        RequestStateMachine.require(status(id), next, supplierEvent);
        jdbc.update("UPDATE requests SET status=?,no_result_reason=?,updated_at=? WHERE id=?", next, reason, time(clock.instant()), id);
    }
    private void expire(String id) {
        settleReservation(id);
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
    Resource read(String id) {
        return jdbc.queryForObject("SELECT r.*,c.category,c.service_name,c.skill_tags,c.licence_required,c.budget_cents,c.currency,c.needed_by,c.max_distance_m,"
                + "c.latitude,c.longitude,c.precision FROM requests r JOIN request_constraints c ON c.request_id=r.id WHERE r.id=?",
                (rs, row) -> {
                    String state = rs.getString("status");
                    String action = RequestStateMachine.action(state);
                    Constraints constraints = new Constraints(rs.getString("category"), rs.getString("service_name"),
                            List.of((String[]) rs.getArray("skill_tags").getArray()), rs.getBoolean("licence_required"),
                            (Integer) rs.getObject("budget_cents"),
                            rs.getString("currency"), instant(rs, "needed_by"), rs.getInt("max_distance_m"),
                            new Location(rs.getDouble("latitude"), rs.getDouble("longitude"), rs.getString("precision")));
                    Clarification question = state.equals("draft") ? new Clarification(rs.getString("clarification_id"), "category",
                            "What should PLUG look for?", options(rs.getString("clarification_options"))) : null;
                    Integer poll = switch (action) {
                        case "wait_for_offers" -> 1;
                        case "await_supplier_confirmation" -> 5;
                        default -> null;
                    };
                    return new Resource(id, state, action, rs.getString("text"), constraints, progress(id), question,
                            rs.getString("no_result_reason"), reservation(id), poll,
                            instant(rs, "created_at"), instant(rs, "updated_at"), instant(rs, "expires_at"));
                }, id);
    }
    private Reservation reservation(String id) {
        return jdbc.query("SELECT * FROM request_reservations WHERE request_id=?"
                + " ORDER BY (status IN ('pending','confirmed')) DESC,created_at DESC,id DESC LIMIT 1",
                RESERVATION_ROW, id).stream().findFirst().orElse(null);
    }
    private static final org.springframework.jdbc.core.RowMapper<Reservation> RESERVATION_ROW = (rs, row) -> new Reservation(
            rs.getString("id"), rs.getString("offer_id"), rs.getString("status"), rs.getString("booking_ref"),
            instant(rs, "confirm_by"), instant(rs, "confirmed_at"), instant(rs, "ended_at"), instant(rs, "created_at"));
    private Progress progress(String id) {
        Integer contacted = jdbc.queryForObject("SELECT (SELECT count(*) FROM request_seed_work WHERE request_id=?)"
                + " + (SELECT count(*) FROM request_matches WHERE request_id=?)", Integer.class, id, id);
        Integer replied = jdbc.queryForObject("SELECT (SELECT count(*) FROM request_seed_work WHERE request_id=? AND replied_at IS NOT NULL)"
                + " + (SELECT count(*) FROM request_matches WHERE request_id=? AND replied_at IS NOT NULL)", Integer.class, id, id);
        Integer offers = jdbc.queryForObject("SELECT count(*) FROM request_offers WHERE request_id=? AND expires_at>? AND withdrawn_at IS NULL", Integer.class, id, time(clock.instant()));
        return new Progress(contacted, replied, offers);
    }
    private List<Offer> listOffers(String id) {
        return jdbc.query(OFFER_SELECT + " WHERE o.request_id=? AND o.expires_at>? AND o.withdrawn_at IS NULL"
                + " ORDER BY o.available_at,o.price_cents,offer_distance_m,o.id LIMIT 20", OFFER_ROW, id, time(clock.instant()));
    }
    /// Seed offers take their place and distance from the seed work; portal offers have neither and
    /// carry their own rounded distance.
    private static final String OFFER_SELECT = "SELECT o.*,p.name,p.address,COALESCE(w.distance_m,o.distance_m) AS offer_distance_m,"
            + "b.business,ps.completed_jobs,ps.trust_score FROM request_offers o LEFT JOIN places p ON p.id=o.place_id"
            + " LEFT JOIN request_seed_work w ON w.request_id=o.request_id AND w.place_id=o.place_id"
            + " LEFT JOIN provider_profiles b ON b.user_id=o.provider_id LEFT JOIN provider_scores ps ON ps.user_id=o.provider_id";
    private static final org.springframework.jdbc.core.RowMapper<Offer> OFFER_ROW = (rs, row) -> new Offer(rs.getString("id"),
            rs.getString("place_id") == null ? null
                    : new Place(rs.getString("place_id"), rs.getString("name"), rs.getString("address"), rs.getInt("offer_distance_m")),
            rs.getInt("offer_distance_m"), rs.getString("note"), rs.getString("service_name"), rs.getInt("price_cents"),
            rs.getString("currency"), instant(rs, "available_at"), instant(rs, "expires_at"), instant(rs, "observed_at"),
            rs.getString("truth_label"), rs.getString("source"),
            // Seeded demo suppliers have no completed PLUG jobs: New, never a zero.
            RequestPayloads.ProviderScore.of(rs.getInt("completed_jobs"), (Integer) rs.getObject("trust_score")),
            BusinessProfiles.read(rs.getString("business")));
    private String json(List<Option> options) {
        try { return mapper.writeValueAsString(options); }
        catch (com.fasterxml.jackson.core.JsonProcessingException failure) { throw new IllegalStateException("options"); }
    }
    private List<Option> options(String stored) {
        try { return List.of(mapper.readValue(stored, Option[].class)); }
        catch (com.fasterxml.jackson.core.JsonProcessingException failure) { throw new IllegalStateException("options"); }
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
                    + " OR (status='ranked' AND NOT EXISTS (SELECT 1 FROM request_offers o WHERE o.request_id=requests.id"
                    + " AND o.expires_at>? AND o.withdrawn_at IS NULL))"
                    + " OR (status='user_selected' AND EXISTS (SELECT 1 FROM request_reservations v WHERE v.request_id=requests.id"
                    + " AND v.status='pending' AND v.confirm_by<=?))"
                    + " OR (status='confirmed' AND EXISTS (SELECT 1 FROM request_reservations v JOIN request_offers o ON o.id=v.offer_id"
                    + " WHERE v.request_id=requests.id AND v.status='confirmed' AND o.available_at + interval '3 hours'<=?))"
                    + " ORDER BY updated_at,id LIMIT 20 FOR UPDATE SKIP LOCKED", String.class,
                    time(clock.instant()), time(clock.instant()), time(clock.instant()), time(clock.instant()));
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
                + " FROM places p JOIN supplier_seeds s ON s.place_id=p.id WHERE p.category = ANY(?) AND s.enabled"
                + " AND ST_DWithin(p.location,ST_SetSRID(ST_MakePoint(?,?),4326)::geography,?)"
                + " ORDER BY p.location <-> ST_SetSRID(ST_MakePoint(?,?),4326)::geography,p.id LIMIT 50",
                resource.requestId(), c.location().longitude(), c.location().latitude(), c.skillTags().toArray(String[]::new),
                c.location().longitude(), c.location().latitude(), c.maxDistanceM(), c.location().longitude(), c.location().latitude());
        // Real providers who opted in: their skills, inside their own radius, available in the window.
        matches.notify(resource);
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
        int seedsWaiting = jdbc.queryForObject("SELECT count(*) FROM request_seed_work WHERE request_id=? AND replied_at IS NULL",
                Integer.class, id);
        // Matched providers answer from their inbox in Phase 3; until then they count as
        // contacted, not replied, and a request with no offers waits for its deadline.
        if (seedsWaiting == 0 && progress.offersReady() > 0) transition(id, "ranked", null);
        else if (progress.replied() == progress.contacted()) transition(id, "expired", "no_offers");
    }
}
