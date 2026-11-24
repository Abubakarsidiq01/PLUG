package app.plug.request;

import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/// Shared setup for the P3.S15 fan-out tests: a row of providers north of one ask, each 111 m
/// further away than the last, so rank order is index order. Far from the seeded suppliers and
/// every other suite's providers.
abstract class FanOutSupport {
    static final double LATITUDE = 47.0;
    static final double LONGITUDE = -110.0;

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    @Autowired RequestService service;
    @Autowired PlatformTransactionManager transactions;
    final List<String> users = new ArrayList<>();

    @AfterEach void removeOnlyThisTestsRecords() {
        new TransactionTemplate(transactions).executeWithoutResult(ignored -> {
            for (String user : users) {
                jdbc.update("DELETE FROM request_reservations WHERE request_id IN (SELECT id FROM requests WHERE user_id=?)", user);
                jdbc.update("DELETE FROM asks WHERE user_id=?", user);
                jdbc.update("DELETE FROM request_idempotency WHERE user_id=?", user);
                jdbc.update("DELETE FROM requests WHERE user_id=?", user);
            }
            for (String user : users) jdbc.update("DELETE FROM provider_profiles WHERE user_id=?", user);
            for (String user : users) jdbc.update("DELETE FROM users WHERE id=?", user);
        });
        users.clear();
    }

    static String location(double latitude) {
        return "{\"latitude\":" + latitude + ",\"longitude\":" + LONGITUDE + ",\"precision\":\"coarse\"}";
    }
    JsonNode guest() throws Exception {
        JsonNode session = mapper.readTree(mvc.perform(MockMvcRequestBuilders.post("/v1/auth/guest")
                .with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .contentType(MediaType.APPLICATION_JSON).content("{\"consent_version\":\"2026-09-01\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString());
        users.add(session.at("/account/user_id").asText());
        return session;
    }
    static String userId(JsonNode session) { return session.at("/account/user_id").asText(); }
    ResultActions post(JsonNode who, String path, String body) throws Exception {
        return mvc.perform(MockMvcRequestBuilders.post(path).with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .header("Authorization", "Bearer " + who.get("access_token").asText())
                .header("Idempotency-Key", "fanout-test-" + UUID.randomUUID())
                .contentType(MediaType.APPLICATION_JSON).content(body));
    }
    /// count providers, provider n at n * 111 m from the ask: providers.get(0) ranks best.
    List<JsonNode> providers(int count) throws Exception {
        List<JsonNode> providers = new ArrayList<>();
        for (int n = 1; n <= count; n++) {
            JsonNode provider = guest();
            post(provider, "/v1/providers/skills", "{\"skill_tags\":[\"barber\"],\"travel_radius_m\":4828,\"base_location\":"
                    + location(LATITUDE + n * 0.001) + ",\"availability\":[{\"days\":\"every_day\",\"from\":\"09:00\",\"to\":\"24:00\"}],"
                    + "\"time_zone\":\"America/Chicago\"}").andExpect(status().isOk());
            providers.add(provider);
        }
        return providers;
    }
    String ask(JsonNode asker) throws Exception {
        return mapper.readTree(post(asker, "/v1/requests", "{\"text\":\"Barber under $35 in 30 minutes\",\"location\":"
                + location(LATITUDE) + "}").andExpect(status().isCreated()).andReturn().getResponse().getContentAsString())
                .path("request_id").asText();
    }
    /// Provider ids contacted for the request, best rank first.
    List<String> contacted(String requestId) {
        return jdbc.queryForList("SELECT provider_id FROM request_matches WHERE request_id=? ORDER BY rank_score DESC,distance_m",
                String.class, requestId);
    }
    List<String> contactedInWave(String requestId, int wave) {
        return jdbc.queryForList("SELECT provider_id FROM request_matches WHERE request_id=? AND wave=? ORDER BY rank_score DESC,distance_m",
                String.class, requestId, wave);
    }
    List<Instant> notifiedAt(String requestId, int wave) {
        return jdbc.queryForList("SELECT notified_at FROM request_matches WHERE request_id=? AND wave=?", Timestamp.class, requestId, wave)
                .stream().map(Timestamp::toInstant).toList();
    }
    String requestStatus(String requestId) {
        return jdbc.queryForObject("SELECT status FROM requests WHERE id=?", String.class, requestId);
    }
    /// A request written straight to the tables at the ask's location.
    String seedRequest(String owner, String state, Instant createdAt) {
        String id = "req_" + UUID.randomUUID();
        jdbc.update("INSERT INTO requests(id,user_id,text,status,created_at,updated_at,expires_at) VALUES(?,?,?,?,?,?,?)",
                id, owner, "Barber near the market", state, Timestamp.from(createdAt), Timestamp.from(createdAt),
                Timestamp.from(createdAt.plusSeconds(3600)));
        jdbc.update("INSERT INTO request_constraints(request_id,category,service_name,skill_tags,licence_required,budget_cents,"
                + "currency,needed_by,max_distance_m,latitude,longitude,precision) VALUES(?,'barber','Haircut',ARRAY['barber'],false,"
                + "3500,'USD',NULL,4828,?,?,'coarse')", id, LATITUDE, LONGITUDE);
        return id;
    }
    void seedMatch(String requestId, String provider, Instant notifiedAt) {
        jdbc.update("INSERT INTO request_matches(request_id,provider_id,distance_m,rank_score,notified_at) VALUES(?,?,?,?,?)",
                requestId, provider, 500, 50, Timestamp.from(notifiedAt));
    }
    static List<String> ids(List<JsonNode> providers) { return providers.stream().map(FanOutSupport::userId).toList(); }
}
