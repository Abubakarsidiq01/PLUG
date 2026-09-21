package app.plug.foundation;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.junit.jupiter.api.Assertions.assertFalse;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.logging.LogLevel;
import org.springframework.boot.logging.LoggingSystem;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ExtendWith(OutputCaptureExtension.class)
class HttpHardeningTest {
    @Autowired MockMvc mvc;

    @Test
    void healthIsNotCachedAndUnknownRoutesAreDenied() throws Exception {
        mvc.perform(get("/health")).andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(header().string("X-Content-Type-Options", "nosniff"));
        mvc.perform(get("/actuator/env")).andExpect(status().isUnauthorized());
    }

    @Test
    void frameworkDebugLogsDoNotExposeQueryOrCoordinates(CapturedOutput output) throws Exception {
        String logger = "org.springframework.web.servlet.mvc.method.annotation";
        var logging = LoggingSystem.get(getClass().getClassLoader());
        var previous = logging.getLoggerConfiguration(logger).getConfiguredLevel();
        logging.setLogLevel(logger, LogLevel.DEBUG);
        try {
            mvc.perform(post("/v1/requests").contentType(MediaType.APPLICATION_JSON).content("""
                    {"query":"private-customer-request","location":{"latitude":12.3456789,"longitude":23.456789}}
                    """)).andExpect(status().isAccepted());
            assertFalse(output.getAll().contains("private-customer-request"));
            assertFalse(output.getAll().contains("12.3456789"));
            assertFalse(output.getAll().contains("23.456789"));
        } finally {
            logging.setLogLevel(logger, previous);
        }
    }

    @Test
    void tunnelRequestsCanReadPublicHealthButNotOperationalProbes() throws Exception {
        for (String headerName : new String[] {"Forwarded", "X-Forwarded-For", "X-Forwarded-Host",
                "X-Forwarded-Proto", "CF-Connecting-IP"}) {
            mvc.perform(get("/health").header(headerName, "external"))
                    .andExpect(status().isOk());
            for (String path : new String[] {"/health/ready", "/actuator/health", "/actuator/health/readiness",
                    "/actuator/health/liveness"}) {
                mvc.perform(get(path).header(headerName, "external"))
                        .andExpect(status().isUnauthorized());
            }
        }
    }

    @Test
    void oversizedBodiesAreRejectedBeforeParsing() throws Exception {
        mvc.perform(post("/v1/requests").contentType(MediaType.APPLICATION_JSON).content("x".repeat(16385)))
                .andExpect(status().isPayloadTooLarge());
    }

    @Test
    void unexpectedFieldsAndStringCoordinatesAreRejected() throws Exception {
        mvc.perform(post("/v1/requests").contentType(MediaType.APPLICATION_JSON).content("""
                {"query":"Barber","location":{"latitude":32,"longitude":-92},"admin":true}
                """)).andExpect(status().isBadRequest());
        mvc.perform(post("/v1/requests").contentType(MediaType.APPLICATION_JSON).content("""
                {"query":"Barber","location":{"latitude":"32","longitude":-92}}
                """)).andExpect(status().isBadRequest());
    }

    @Test
    void nonStringQueriesAreRejectedInsteadOfCoerced() throws Exception {
        for (String query : new String[] {"123", "1.5", "true"}) {
            mvc.perform(post("/v1/requests").contentType(MediaType.APPLICATION_JSON).content(
                    "{\"query\":" + query + ",\"location\":{\"latitude\":32,\"longitude\":-92}}"))
                    .andExpect(status().isBadRequest());
        }
    }

    @Test
    void overlongIdempotencyHeaderIsRejected() throws Exception {
        mvc.perform(post("/v1/requests").header("Idempotency-Key", "a".repeat(256))
                .contentType(MediaType.APPLICATION_JSON).content("""
                {"query":"Barber","location":{"latitude":32,"longitude":-92}}
                """)).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.details[0].code").value("size"));
    }

    @Test
    void duplicateFieldsAndTrailingDocumentsAreRejected() throws Exception {
        mvc.perform(post("/v1/requests").contentType(MediaType.APPLICATION_JSON).content("""
                {"query":"Barber","query":"Other","location":{"latitude":32,"longitude":-92}}
                """)).andExpect(status().isBadRequest());
        mvc.perform(post("/v1/requests").contentType(MediaType.APPLICATION_JSON).content("""
                {"query":"Barber","location":{"latitude":32,"longitude":-92}} {}
                """)).andExpect(status().isBadRequest());
    }
}
