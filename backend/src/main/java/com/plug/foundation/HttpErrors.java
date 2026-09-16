package com.plug.foundation;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.json.JsonMapper;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Instant;
import java.util.List;
import java.util.Map;

final class HttpErrors {
    private static final ObjectMapper mapper = JsonMapper.builder().build();

    private HttpErrors() {}

    static void write(HttpServletRequest request, HttpServletResponse response, int status, String code, String message)
            throws IOException {
        response.setStatus(status);
        if (status == 401) response.setHeader("WWW-Authenticate", "Bearer");
        response.setContentType("application/json");
        mapper.writeValue(response.getOutputStream(), Map.of(
                "code", code, "message", message,
                "correlation_id", String.valueOf(request.getAttribute("correlationId")),
                "timestamp", Instant.now().toString(), "path", request.getRequestURI(), "details", List.of()));
    }
}
