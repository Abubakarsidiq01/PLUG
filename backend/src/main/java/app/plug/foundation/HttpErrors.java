package app.plug.foundation;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.json.JsonMapper;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

// Every non-2xx response has exactly this shape: manual.docx §18.2. The envelope
// wraps everything in a top-level "error" object so a client can always read
// response.error.code without first checking whether the request succeeded.
final class HttpErrors {
    private static final ObjectMapper mapper = JsonMapper.builder().build();

    private HttpErrors() {}

    static void write(HttpServletRequest request, HttpServletResponse response, int status, String code, String message)
            throws IOException {
        write(request, response, status, code, message, List.of(), null);
    }

    static void write(HttpServletRequest request, HttpServletResponse response, int status, String code,
            String message, List<Map<String, String>> details, Integer retryAfterSeconds) throws IOException {
        response.setStatus(status);
        if (status == 401) {
            response.setHeader("WWW-Authenticate", "Bearer");
        }
        response.setContentType("application/json");
        var error = new LinkedHashMap<String, Object>();
        error.put("code", code);
        error.put("message", message);
        error.put("request_id", String.valueOf(request.getAttribute(CorrelationFilter.REQUEST_ATTRIBUTE)));
        if (!details.isEmpty()) {
            error.put("details", details);
        }
        if (retryAfterSeconds != null) {
            error.put("retry_after_seconds", retryAfterSeconds);
        }
        mapper.writeValue(response.getOutputStream(), Map.of("error", error));
    }
}
