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
import java.util.List;
import java.util.Map;
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
    // Shared with the identity module's one-time-code limits through FixedWindowLimiter,
    // so the bucket cap and sweep behaviour are defined in one place.
    private final FixedWindowLimiter limiter = new FixedWindowLimiter(4096);
    private final int limit;
    private final RateWindow window;
    @Value("${plug.requests-v2.enabled:false}")
    private boolean requestsV2;

    public RequestLimitsFilter(@Value("${plug.requests-per-minute}") int limit, RateWindow window) {
        if (limit < 1) throw new IllegalArgumentException("The request limit must be positive.");
        this.limit = limit;
        this.window = window;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        // Match the decoded application path, as the controller does. Comparing the
        // raw URI lets /v1/%72equests reach the same controller without these limits.
        String path = UrlPathHelper.defaultInstance.getPathWithinApplication(request);
        boolean v2Route = requestsV2 && (path.startsWith("/v1/requests/") || path.equals("/v1/asks")
                || path.startsWith("/v1/asks/") || path.startsWith("/v1/providers/"));
        if (!path.equals("/v1/requests") && !v2Route) {
            chain.doFilter(request, response);
            return;
        }
        // Do not trust caller-supplied forwarded addresses. The ingress adds its own rate limit in staging.
        // Both entry points share one creation budget, so switching endpoints cannot double it.
        boolean creation = requestsV2 && (path.equals("/v1/requests") || path.equals("/v1/asks"))
                && request.getMethod().equals("POST");
        if (!limiter.tryConsume(request.getRemoteAddr() + (creation ? ":create" : ":read"),
                creation ? 30 : limit, window.length())) {
            response.setHeader("Retry-After", String.valueOf(window.retryAfterSeconds()));
            HttpErrors.write(request, response, 429, "rate_limited", "Too many requests. Try again shortly.",
                    List.of(), window.retryAfterSeconds());
            return;
        }
        if (!request.getMethod().equals("POST")) {
            chain.doFilter(request, response);
            return;
        }
        // Read one extra byte to detect oversized chunked requests as well as declared lengths.
        // "payload_too_large" is not in the frozen error-code vocabulary (manual.docx §18.2), so this
        // maps to validation_failed with a details entry that names the actual problem.
        int bodyLimit = requestsV2 && path.equals("/v1/providers/skills") ? 98_304 : MAX_BODY;
        if (request.getContentLengthLong() > bodyLimit) {
            tooLarge(request, response);
            return;
        }
        byte[] body = request.getInputStream().readNBytes(bodyLimit + 1);
        if (body.length > bodyLimit) {
            tooLarge(request, response);
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

    private static void tooLarge(HttpServletRequest request, HttpServletResponse response) throws IOException {
        HttpErrors.write(request, response, 413, "validation_failed", "The request body is too large.",
                List.of(Map.of("field", "body", "code", "too_large")), null);
    }
}
