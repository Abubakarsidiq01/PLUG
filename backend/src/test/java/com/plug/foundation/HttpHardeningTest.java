package com.plug.foundation;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
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
    void overlongIdempotencyHeaderIsRejected() throws Exception {
        mvc.perform(post("/v1/requests").header("Idempotency-Key", "a".repeat(256))
                .contentType(MediaType.APPLICATION_JSON).content("""
                {"query":"Barber","location":{"latitude":32,"longitude":-92}}
                """)).andExpect(status().isBadRequest());
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
