package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.request.RequestPayloads.Answer;
import app.plug.request.RequestPayloads.AskBody;
import app.plug.request.RequestPayloads.AskResult;
import app.plug.request.RequestPayloads.Clarification;
import app.plug.request.RequestPayloads.Option;
import app.plug.request.RequestPayloads.PlaceProgress;
import app.plug.request.RequestPayloads.PlaceQuestion;
import app.plug.security.PlugPrincipal;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/// POST /v1/asks: one field, two kinds of ask (manual v4 §12A, P2.S10). The policy runs first,
/// then the server classifies. A service ask becomes a Request through exactly the code
/// POST /v1/requests uses. A place question is recorded; the people-nearby pipeline is
/// Phase 4, so until it exists the answer is an honest Unknown with real zero counts. An ask
/// that cannot be classified safely gets one question, never a guess.
public class AskService {
    /// How long a place question stays open before it is Unknown.
    static final Duration PLACE_WINDOW = Duration.ofMinutes(10);

    private final JdbcTemplate jdbc;
    private final TransactionTemplate transaction;
    private final ObjectMapper mapper;
    private final Clock clock;
    private final IntentAdapter intent;
    private final RestrictedIntentPolicy policy;
    private final RequestService requests;

    public AskService(JdbcTemplate jdbc, PlatformTransactionManager manager, ObjectMapper mapper, Clock clock,
            IntentAdapter intent, RestrictedIntentPolicy policy, RequestService requests) {
        this.jdbc = jdbc;
        this.transaction = new TransactionTemplate(manager);
        this.mapper = mapper;
        this.clock = clock;
        this.intent = intent;
        this.policy = policy;
        this.requests = requests;
    }

    public AskResult create(PlugPrincipal caller, String key, AskBody body) {
        requests.requireCaller(caller);
        requests.requireConsent(caller);
        requests.refuseRestricted(caller, body.text());
        // Classified outside the transaction: the model call holds no row lock, and a refusal's
        // audit event is written on its own so a rollback can never erase it.
        IntentAdapter.Result result = intent.classify(body.text(), body.location(), body.timeZone());
        if (result.askType() == IntentAdapter.AskType.PLACE_QUESTION) refusePrivatePlace(caller, body.text());
        return transaction.execute(ignored -> {
            requests.lockAccount(caller);
            requests.requireConsent(caller);
            AskResult replay = requests.replay(caller, "ask", key, body, AskResult.class);
            if (replay != null) return replay;
            if (!requests.limiter.tryConsume(caller.userId(), 10, Duration.ofMinutes(1))) throw ApiException.rateLimited(60);
            String id = "ask_" + UUID.randomUUID();
            Instant now = clock.instant();
            var location = body.location().rounded();
            jdbc.update("INSERT INTO asks(id,user_id,text,latitude,longitude,location_precision,time_zone,created_at,updated_at)"
                    + " VALUES(?,?,?,?,?,?,?,?,?)", id, caller.userId(), body.text(), location.latitude(),
                    location.longitude(), location.precision(), body.timeZone(), time(now), time(now));
            resolve(caller, id, body.text(), result);
            AskResult created = read(caller, id);
            requests.remember(caller, "ask", key, body, created);
            return created;
        });
    }

    public AskResult get(PlugPrincipal caller, String id) {
        return transaction.execute(ignored -> { lockOwned(caller, id); return read(caller, id); });
    }

    public AskResult clarify(PlugPrincipal caller, String id, String key, Answer answer) {
        if (IntentAdapter.PLACE_OPTION.value().equals(answer.value())) {
            requests.requireCaller(caller);
            jdbc.queryForList("SELECT text FROM asks WHERE id=? AND user_id=?", String.class, id, caller.userId())
                    .forEach(text -> refusePrivatePlace(caller, text));
        }
        return transaction.execute(ignored -> {
            requests.lockAccount(caller);
            lockOwned(caller, id);
            AskResult replay = requests.replay(caller, "ask-clarify:" + id, key, answer, AskResult.class);
            if (replay != null) return replay;
            AskResult current = read(caller, id);
            if (current.clarification() == null || !current.clarification().clarificationId().equals(answer.clarificationId())) {
                throw requests.stateConflict("clarification_id", "not_awaiting_clarification", "This ask is not awaiting that answer.");
            }
            Option chosen = current.clarification().options().stream().filter(o -> o.value().equals(answer.value())).findFirst()
                    .orElseThrow(() -> ApiException.validation("value", "not_an_option", "Choose one of the offered options."));
            var row = jdbc.queryForMap("SELECT text,latitude,longitude,location_precision,time_zone FROM asks WHERE id=?", id);
            String text = (String) row.get("text");
            var location = new RequestPayloads.Location((Double) row.get("latitude"), (Double) row.get("longitude"),
                    (String) row.get("location_precision"));
            jdbc.update("UPDATE asks SET clarification_id=NULL,clarification_options=NULL,updated_at=? WHERE id=?",
                    time(clock.instant()), id);
            if (chosen.value().equals(IntentAdapter.PLACE_OPTION.value())) {
                resolve(caller, id, text, new IntentAdapter.Result(IntentAdapter.AskType.PLACE_QUESTION, null, null, null,
                        IntentAdapter.placeName(text)));
            } else {
                // The chosen skill is now explicit; money, time and distance still come from the words.
                var create = new RequestPayloads.Create(text, chosen.value(), null, null, null, null, location,
                        (String) row.get("time_zone"));
                resolve(caller, id, text, intent.extract(create));
            }
            AskResult result = read(caller, id);
            requests.remember(caller, "ask-clarify:" + id, key, answer, result);
            return result;
        });
    }

    private void resolve(PlugPrincipal caller, String id, String text, IntentAdapter.Result result) {
        Instant now = clock.instant();
        switch (result.askType()) {
            case PLACE_QUESTION -> {
                String questionId = "plq_" + UUID.randomUUID();
                var row = jdbc.queryForMap("SELECT latitude,longitude FROM asks WHERE id=?", id);
                jdbc.update("INSERT INTO place_questions(id,user_id,text,place_name,status,latitude,longitude,created_at,expires_at)"
                        + " VALUES(?,?,?,?,'unknown',?,?,?,?)", questionId, caller.userId(), text, result.placeName(),
                        row.get("latitude"), row.get("longitude"), time(now), time(now.plus(PLACE_WINDOW)));
                jdbc.update("UPDATE asks SET ask_type='place_question',place_question_id=?,updated_at=? WHERE id=?",
                        questionId, time(now), id);
            }
            case SERVICE_REQUEST -> {
                var request = requests.insert(caller, text, result);
                jdbc.update("UPDATE asks SET ask_type='service_request',request_id=?,updated_at=? WHERE id=?",
                        request.requestId(), time(now), id);
            }
            case UNCLEAR -> jdbc.update("UPDATE asks SET clarification_id=?,clarification_options=?::jsonb,updated_at=? WHERE id=?",
                    "cla_" + UUID.randomUUID(), json(result.clarificationOptions()), time(now), id);
        }
    }

    /// A place question must be about a public place, with no exception path (§19A.1).
    private void refusePrivatePlace(PlugPrincipal caller, String text) {
        policy.placeRefusal(text).ifPresent(rule -> requests.refuse(caller, rule));
    }

    private AskResult read(PlugPrincipal caller, String id) {
        var row = jdbc.queryForMap("SELECT ask_type,request_id,place_question_id,clarification_id,clarification_options::text"
                + " AS options,created_at FROM asks WHERE id=?", id);
        Instant created = ((Timestamp) row.get("created_at")).toInstant();
        String type = (String) row.get("ask_type");
        if ("service_request".equals(type)) {
            return new AskResult(id, type, requests.get(caller, (String) row.get("request_id")), null, null, created);
        }
        if ("place_question".equals(type)) return new AskResult(id, type, null, place((String) row.get("place_question_id")), null, created);
        Clarification question = new Clarification((String) row.get("clarification_id"), "ask",
                "What would you like PLUG to do?", options((String) row.get("options")));
        return new AskResult(id, null, null, null, question, created);
    }

    private PlaceQuestion place(String id) {
        return jdbc.queryForObject("SELECT * FROM place_questions WHERE id=?", (rs, n) -> new PlaceQuestion(rs.getString("id"),
                rs.getString("text"), rs.getString("place_name"), rs.getString("status"),
                new PlaceProgress(rs.getInt("notified"), rs.getInt("opened"), rs.getInt("answered")), null, null,
                rs.getTimestamp("created_at").toInstant(), rs.getTimestamp("expires_at").toInstant()), id);
    }

    private void lockOwned(PlugPrincipal caller, String id) {
        requests.requireCaller(caller);
        if (id.length() > 64 || !id.matches("ask_[A-Za-z0-9-]+") || jdbc.queryForList(
                "SELECT id FROM asks WHERE id=? AND user_id=? FOR UPDATE", id, caller.userId()).isEmpty()) {
            throw ApiException.notFound("Ask not found.");
        }
    }

    private String json(List<Option> options) {
        try { return mapper.writeValueAsString(options); }
        catch (com.fasterxml.jackson.core.JsonProcessingException failure) { throw new IllegalStateException("options"); }
    }
    private List<Option> options(String stored) {
        try { return List.of(mapper.readValue(stored, Option[].class)); }
        catch (com.fasterxml.jackson.core.JsonProcessingException failure) { throw new IllegalStateException("options"); }
    }
    private static Timestamp time(Instant instant) { return Timestamp.from(instant); }
}
