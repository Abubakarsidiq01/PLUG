package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ContractSchemas;
import app.plug.security.PlugPrincipal;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
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
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;

/// P3.S2 flag switch (contract 0.7.7): with plug.supplier-messaging.enabled=false every supplier
/// route, public and admin, is 404 NotFound and nothing is stored.
@Tag("database")
@SpringBootTest(properties = {"plug.supplier-messaging.enabled=false",
        "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
class SupplierMessagingSwitchTest {
    static final String OPT_IN = "{\"business_name\":\"Sup-test Switch\",\"phone\":\"+12125550142\","
            + "\"consent_version\":\"sms-2026-10-09\",\"consent\":true}";
    static final String CREATE = "{\"business_name\":\"Sup-test Switch\",\"phone\":\"+12125550143\",\"reason\":\"In person visit.\"}";

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    private String staffId;

    @AfterEach void removeStaff() { if (staffId != null) jdbc.update("DELETE FROM users WHERE id=?", staffId); }

    PlugPrincipal owner() {
        staffId = "usr_staff-" + UUID.randomUUID();
        jdbc.update("INSERT INTO users(id,account_type) VALUES(?,'staff')", staffId);
        jdbc.update("INSERT INTO staff_accounts(user_id,email,password_hash,role) VALUES(?,?,'not-a-real-hash','owner')", staffId,
                staffId.substring(4, 24).toLowerCase() + "@example.com");
        return new PlugPrincipal(staffId, "ses_staff", Set.of(PlugPrincipal.SCOPE_ADMIN), true);
    }
    ResultActions send(PlugPrincipal who, MockHttpServletRequestBuilder request) throws Exception {
        request.with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; });
        if (who != null) request.with(authentication(new UsernamePasswordAuthenticationToken(who, null, List.of())));
        return mvc.perform(request);
    }
    void notFound(ResultActions result) throws Exception {
        result.andExpect(status().isNotFound());
        ContractSchemas.validate("Error", mapper.readTree(result.andReturn().getResponse().getContentAsString()));
    }

    @Test void withTheFlagOffEverySupplierRouteIsNotFoundAndNothingIsStored() throws Exception {
        PlugPrincipal admin = owner();
        notFound(send(null, MockMvcRequestBuilders.post("/v1/suppliers/opt-in").contentType(MediaType.APPLICATION_JSON)
                .header("Idempotency-Key", "k-" + UUID.randomUUID()).content(OPT_IN)));
        notFound(send(admin, MockMvcRequestBuilders.get("/v1/admin/suppliers")));
        notFound(send(admin, MockMvcRequestBuilders.post("/v1/admin/suppliers").contentType(MediaType.APPLICATION_JSON)
                .header("Idempotency-Key", "k-" + UUID.randomUUID()).content(CREATE)));
        notFound(send(admin, MockMvcRequestBuilders.get("/v1/admin/opt-outs")));
        notFound(send(admin, MockMvcRequestBuilders.get("/v1/admin/suppliers/sup_" + UUID.randomUUID())));
        assertThat(jdbc.queryForObject("SELECT count(*) FROM suppliers WHERE business_name='Sup-test Switch'", Integer.class)).isZero();
    }
}
