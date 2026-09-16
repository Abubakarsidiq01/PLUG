package com.plug.foundation;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.core.annotation.Order;
import org.springframework.core.Ordered;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
public class CorrelationFilter extends OncePerRequestFilter {
    private static final Logger log = LoggerFactory.getLogger(CorrelationFilter.class);

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String correlationId = "corr_" + UUID.randomUUID();
        request.setAttribute("correlationId", correlationId);
        response.setHeader("X-Correlation-ID", correlationId);
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("X-Content-Type-Options", "nosniff");
        response.setHeader("X-Frame-Options", "DENY");
        response.setHeader("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'");
        try {
            chain.doFilter(request, response);
        } finally {
            log.info("http_request correlation_id={} method={} path={} status={}",
                    correlationId, request.getMethod(), safePath(request.getRequestURI()), response.getStatus());
        }
    }

    private String safePath(String path) {
        // Unknown paths may contain private information or log-control characters.
        return switch (path) {
            case "/health", "/v1/requests", "/actuator/health", "/actuator/health/readiness",
                    "/actuator/health/liveness" -> path;
            default -> "unmapped";
        };
    }
}
