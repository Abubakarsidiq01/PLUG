package app.plug.foundation;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.util.UrlPathHelper;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 20)
public class RequestLimitsFilter extends OncePerRequestFilter {
    private static final int MAX_BODY = 16_384;
    private static final Duration WINDOW = Duration.ofMinutes(1);
    // Shared with the identity module's one-time-code limits through FixedWindowLimiter,
    // so the bucket cap and sweep behaviour are defined in one place.
    private final FixedWindowLimiter limiter = new FixedWindowLimiter(4096);
    private final int limit;

    public RequestLimitsFilter(@Value("${plug.requests-per-minute}") int limit) {
        if (limit < 1) throw new IllegalArgumentException("The request limit must be positive.");
        this.limit = limit;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        // Match the decoded application path, as the controller does. Comparing the
        // raw URI lets /v1/%72equests reach the same controller without these limits.
        if (!UrlPathHelper.defaultInstance.getPathWithinApplication(request).equals("/v1/requests")) {
            chain.doFilter(request, response);
            return;
        }
        // Do not trust caller-supplied forwarded addresses. The ingress adds its own rate limit in staging.
        if (!limiter.tryConsume(request.getRemoteAddr(), limit, WINDOW)) {
            response.setHeader("Retry-After", "60");
            HttpErrors.write(request, response, 429, "rate_limited", "Too many requests. Try again shortly.",
                    java.util.List.of(), 60);
            return;
        }
        if (!request.getMethod().equals("POST")) {
            chain.doFilter(request, response);
            return;
        }
        // Read one extra byte to detect oversized chunked requests as well as declared lengths.
        // "payload_too_large" is not in the frozen error-code vocabulary (manual.docx §18.2), so this
        // maps to validation_failed with a details entry that names the actual problem.
        if (request.getContentLengthLong() > MAX_BODY) {
            HttpErrors.write(request, response, 413, "validation_failed", "The request body is too large.",
                    java.util.List.of(java.util.Map.of("field", "body", "code", "too_large")), null);
            return;
        }
        byte[] body = request.getInputStream().readNBytes(MAX_BODY + 1);
        if (body.length > MAX_BODY) {
            HttpErrors.write(request, response, 413, "validation_failed", "The request body is too large.",
                    java.util.List.of(java.util.Map.of("field", "body", "code", "too_large")), null);
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
}
