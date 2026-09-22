package app.plug.foundation;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

// Every request gets an ID. It goes into the MDC, into every log line, into the response
// header, and into the client's diagnostics. This filter is what makes "find the same
// request in both logs" possible at the connected checkpoint. Header name and semantics
// follow the frozen Phase 0 contract: manual.docx §19.2.
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
public class CorrelationFilter extends OncePerRequestFilter {
    public static final String HEADER = "X-Request-Id";
    public static final String REQUEST_ATTRIBUTE = "requestId";

    private static final Logger log = LoggerFactory.getLogger(CorrelationFilter.class);

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String incoming = request.getHeader(HEADER);
        String requestId = isValid(incoming) ? incoming : "req_" + UUID.randomUUID();
        request.setAttribute(REQUEST_ATTRIBUTE, requestId);
        MDC.put("request_id", requestId);
        MDC.put("route", request.getMethod() + " " + safePath(request.getRequestURI()));
        response.setHeader(HEADER, requestId);
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("X-Content-Type-Options", "nosniff");
        response.setHeader("X-Frame-Options", "DENY");
        response.setHeader("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'");
        try {
            chain.doFilter(request, response);
        } finally {
            log.info("http_request request_id={} method={} path={} status={}",
                    requestId, request.getMethod(), safePath(request.getRequestURI()), response.getStatus());
            MDC.clear();
        }
    }

    // Never trust a client-supplied ID into logs without constraining it.
    private boolean isValid(String value) {
        return value != null && value.length() <= 64 && value.matches("[A-Za-z0-9_\\-]+");
    }

    private String safePath(String path) {
        // Unknown paths may contain private information or log-control characters. A route
        // is only ever logged once it appears here, which also keeps identifiers out of the
        // log: /v1/me/sessions/ses_... collapses to its template rather than the real id.
        return switch (path) {
            case "/health", "/health/ready", "/v1/requests", "/actuator/health",
                    "/actuator/health/readiness", "/actuator/health/liveness",
                    "/v1/auth/apple", "/v1/auth/phone/start", "/v1/auth/phone/verify",
                    "/v1/auth/guest", "/v1/auth/refresh", "/v1/auth/logout",
                    "/v1/me", "/v1/me/consent", "/v1/me/sessions" -> path;
            default -> path.startsWith("/v1/me/sessions/") ? "/v1/me/sessions/{session_id}" : "unmapped";
        };
    }
}
