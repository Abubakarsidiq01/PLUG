package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ContractSchemas;
import app.plug.security.PlugPrincipal;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/// The staff inspection routes (P2-TWO.S12): only an admin session that completed a second
/// factor may read them, they never cache, they audit every read, they page with opaque
/// cursors, and they never return what a person typed.
@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
class AdminInspectionTest {
    static final String HERE = "{\"latitude\":32.528,\"longitude\":-92.714,\"precision\":\"coarse\"}";
    static final List<String> ROUTES = List.of("/v1/admin/skills", "/v1/admin/skills/gaps",
            "/v1/admin/classifications", "/v1/admin/refusals");

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    @Autowired org.springframework.transaction.PlatformTransactionManager transactions;
    private final java.util.List<String> users = new java.util.ArrayList<>();

    /// Requests left behind would sit in the shared worker's queue and starve other suites.
    @org.junit.jupiter.api.AfterEach void removeOnlyThisTestsRecords() {
        new org.springframework.transaction.support.TransactionTemplate(transactions).executeWithoutResult(ignored -> {
            for (String user : users) {
                jdbc.update("DELETE FROM asks WHERE user_id=?", user);
                jdbc.update("DELETE FROM request_idempotency WHERE user_id=?", user);
                jdbc.update("DELETE FROM requests WHERE user_id=?", user);
                jdbc.update("DELETE FROM users WHERE id=?", user);
            }
        });
    }

    static MockHttpServletRequestBuilder as(PlugPrincipal principal, MockHttpServletRequestBuilder request) {
        return request.with(authentication(new UsernamePasswordAuthenticationToken(principal, null, List.of())));
    }
    static PlugPrincipal staff(boolean secondFactor) {
        return new PlugPrincipal("usr_staff-" + UUID.randomUUID(), "ses_staff", Set.of(PlugPrincipal.SCOPE_ADMIN), secondFactor);
    }
    JsonNode body(ResultActions result, String schema) throws Exception {
        JsonNode body = mapper.readTree(result.andReturn().getResponse().getContentAsString());
        ContractSchemas.validate(body.has("error") ? "Error" : schema, body);
        return body;
    }
    JsonNode guest() throws Exception {
        JsonNode session = mapper.readTree(mvc.perform(post("/v1/auth/guest").with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .contentType(MediaType.APPLICATION_JSON).content("{\"consent_version\":\"2026-09-01\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString());
        users.add(session.at("/account/user_id").asText());
        return session;
    }
    void ask(JsonNode who, String text, int expected) throws Exception {
        mvc.perform(post("/v1/asks").with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                .header("Authorization", "Bearer " + who.get("access_token").asText())
                .header("Idempotency-Key", "admin-test-" + UUID.randomUUID())
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"text\":\"" + text + "\",\"location\":" + HERE + ",\"time_zone\":\"America/Chicago\"}"))
                .andExpect(status().is(expected));
    }

    @Test
    void onlyAnAdminWithASecondFactorCanRead() throws Exception {
        String guestToken = guest().get("access_token").asText();
        var member = new PlugPrincipal("usr_member", "ses_member", Set.of(PlugPrincipal.SCOPE_MEMBER), true);
        for (String route : ROUTES) {
            mvc.perform(get(route)).andExpect(status().isUnauthorized());
            mvc.perform(get(route).header("Authorization", "Bearer " + guestToken)).andExpect(status().isForbidden());
            mvc.perform(as(member, get(route))).andExpect(status().isForbidden());
            mvc.perform(as(staff(false), get(route))).andExpect(status().isForbidden());
            mvc.perform(as(staff(true), get(route))).andExpect(status().isOk())
                    .andExpect(header().string("Cache-Control", "no-store"));
        }
    }

    @Test
    void readsAreAuditedAndNeverExposeWhatPeopleTyped() throws Exception {
        var person = guest();
        ask(person, "Someone to do knotless braids for my sister Ada at 12 Oak Street", 201);
        ask(person, "Track my ex girlfriend's phone", 422);
        var admin = staff(true);

        var vocabulary = body(mvc.perform(as(admin, get("/v1/admin/skills"))).andExpect(status().isOk()), "AdminSkillVocabulary");
        assertThat(vocabulary.path("skills").size()).isEqualTo(SkillVocabulary.load().all().size());

        var classifications = body(mvc.perform(as(admin, get("/v1/admin/classifications?limit=100"))).andExpect(status().isOk()),
                "AdminClassificationPage");
        assertThat(classifications.toString()).doesNotContain("Ada").doesNotContain("Oak Street").doesNotContain("knotless");
        assertThat(classifications.path("items").findValuesAsText("skill_tags").toString()).isNotNull();

        var refusals = body(mvc.perform(as(admin, get("/v1/admin/refusals"))).andExpect(status().isOk()), "AdminRefusalPage");
        assertThat(refusals.path("items").findValuesAsText("rule")).contains("stalking_tracking");
        assertThat(refusals.toString()).doesNotContain("girlfriend").doesNotContain(person.at("/account/user_id").asText());

        assertThat(jdbc.queryForObject("SELECT count(*) FROM audit_events WHERE actor_id=? AND action='admin.read'",
                Integer.class, admin.userId())).isEqualTo(3);
    }

    @Test
    void pagesWithOpaqueCursorsAndRejectsBadPaging() throws Exception {
        var person = guest();
        for (int i = 0; i < 3; i++) ask(person, "Barber under $35 number " + i, 201);
        var admin = staff(true);
        var first = body(mvc.perform(as(admin, get("/v1/admin/classifications?limit=2"))).andExpect(status().isOk()),
                "AdminClassificationPage");
        assertThat(first.path("items").size()).isEqualTo(2);
        String cursor = first.path("next_cursor").asText();
        assertThat(cursor).isNotBlank();
        var second = body(mvc.perform(as(admin, get("/v1/admin/classifications?limit=2&cursor=" + cursor)))
                .andExpect(status().isOk()), "AdminClassificationPage");
        assertThat(second.path("items").get(0).path("ask_id").asText())
                .isNotIn(first.path("items").findValuesAsText("ask_id"));

        for (String query : List.of("?limit=0", "?limit=101", "?limit=abc", "?cursor=not-a-cursor", "?cursor=" + "A".repeat(600))) {
            body(mvc.perform(as(admin, get("/v1/admin/classifications" + query))).andExpect(status().isBadRequest()), "Error");
        }
    }
}
