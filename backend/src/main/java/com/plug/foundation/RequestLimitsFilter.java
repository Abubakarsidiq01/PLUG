package com.plug.foundation;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 20)
public class RequestLimitsFilter extends OncePerRequestFilter {
    private static final int MAX_BODY = 16_384;
    private final Map<String, Window> clients = new HashMap<>();
    private final int limit;
    private long lastCleanup;

    public RequestLimitsFilter(@Value("${plug.requests-per-minute}") int limit) {
        if (limit < 1) throw new IllegalArgumentException("The request limit must be positive.");
        this.limit = limit;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        if (!request.getRequestURI().equals("/v1/requests")) {
            chain.doFilter(request, response);
            return;
        }
        // Do not trust caller-supplied forwarded addresses. The ingress adds its own rate limit in staging.
        if (!allow(request.getRemoteAddr())) {
            response.setHeader("Retry-After", "60");
            HttpErrors.write(request, response, 429, "rate_limited", "Too many requests. Try again shortly.");
            return;
        }
        if (!request.getMethod().equals("POST")) {
            chain.doFilter(request, response);
            return;
        }
        // Read one extra byte to detect oversized chunked requests as well as declared lengths.
        if (request.getContentLengthLong() > MAX_BODY) {
            HttpErrors.write(request, response, 413, "payload_too_large", "The request body is too large.");
            return;
        }
        byte[] body = request.getInputStream().readNBytes(MAX_BODY + 1);
        if (body.length > MAX_BODY) {
            HttpErrors.write(request, response, 413, "payload_too_large", "The request body is too large.");
            return;
        }
        chain.doFilter(new HttpServletRequestWrapper(request) {
            @Override
            public ServletInputStream getInputStream() {
                var input = new ByteArrayInputStream(body);
                return new ServletInputStream() {
                    @Override public int read() { return input.read(); }
                    @Override public boolean isFinished() { return input.available() == 0; }
                    @Override public boolean isReady() { return true; }
                    @Override public void setReadListener(ReadListener listener) {
                        throw new UnsupportedOperationException("Request intake uses blocking reads.");
                    }
                };
            }
        }, response);
    }

    private synchronized boolean allow(String client) {
        long now = System.nanoTime();
        long duration = 60_000_000_000L;
        if (now - lastCleanup >= 1_000_000_000L) {
            clients.entrySet().removeIf(entry -> now - entry.getValue().started >= duration);
            lastCleanup = now;
        }
        Window window = clients.get(client);
        if (window != null && now - window.started >= duration) {
            clients.remove(client);
            window = null;
        }
        if (window == null) {
            // Refuse new buckets when full rather than allowing unbounded memory growth.
            if (clients.size() >= 4096) return false;
            window = new Window(now);
            clients.put(client, window);
        }
        if (window.count >= limit) return false;
        window.count++;
        return true;
    }

    private static final class Window {
        final long started;
        int count;
        Window(long started) { this.started = started; }
    }
}
