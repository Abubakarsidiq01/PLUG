package app.plug.foundation;

import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.BadJwtException;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(properties = {
        "spring.autoconfigure.exclude=org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration,org.springframework.boot.autoconfigure.flyway.FlywayAutoConfiguration",
        "PLUG_JWT_ISSUER=https://issuer.invalid", "PLUG_JWT_AUDIENCE=plug-api",
        "PLUG_DATABASE_PASSWORD=test", "PLUG_MIGRATION_DATABASE_URL=jdbc:postgresql://localhost/unused",
        "PLUG_MIGRATION_DATABASE_USER=test", "PLUG_MIGRATION_DATABASE_PASSWORD=test"})
@AutoConfigureMockMvc
@ActiveProfiles("staging")
class StagingSecurityTest {
    @Autowired MockMvc mvc;
    @MockitoBean JwtDecoder decoder;
    private static final String INPUT = """
            {"query":"Barber","location":{"latitude":32,"longitude":-92}}
            """;

    @Test
    void anonymousWritesAreDenied() throws Exception {
        mvc.perform(post("/v1/requests").contentType(MediaType.APPLICATION_JSON).content(INPUT))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error.code").value("unauthenticated"));
    }

    @Test
    void validTokenStillRequiresTheWriteScope() throws Exception {
        mvc.perform(post("/v1/requests").with(jwt()).contentType(MediaType.APPLICATION_JSON).content(INPUT))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error.code").value("forbidden"));
        mvc.perform(post("/v1/requests").with(jwt().authorities(new SimpleGrantedAuthority("SCOPE_plug.requests.write")))
                .contentType(MediaType.APPLICATION_JSON).content(INPUT)).andExpect(status().isAccepted());
    }

    @Test
    void rejectedTokensReturnUnauthorized() throws Exception {
        when(decoder.decode("invalid")).thenThrow(new BadJwtException("Rejected token"));
        mvc.perform(post("/v1/requests").header("Authorization", "Bearer invalid")
                .contentType(MediaType.APPLICATION_JSON).content(INPUT)).andExpect(status().isUnauthorized());
    }
}
