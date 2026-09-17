package app.plug.foundation;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.mock.web.MockFilterChain;
import static org.junit.jupiter.api.Assertions.assertEquals;

class RateLimitTest {
    @Test
    void newClientsCannotGrowTheTrackingTableWithoutLimit() throws Exception {
        var filter = new RequestLimitsFilter(2);
        for (int i = 0; i <= 4096; i++) {
            var request = new MockHttpServletRequest("POST", "/v1/requests");
            request.setRemoteAddr("client-" + i);
            var response = new MockHttpServletResponse();
            filter.doFilter(request, response, new MockFilterChain());
            assertEquals(i == 4096 ? 429 : 200, response.getStatus());
        }
    }

    @Test
    void forwardedHeadersCannotBypassTheLimit() throws Exception {
        var filter = new RequestLimitsFilter(2);
        for (int i = 0; i < 3; i++) {
            var request = new MockHttpServletRequest("POST", "/v1/requests");
            request.setRemoteAddr("127.0.0.1");
            request.addHeader("X-Forwarded-For", "10.0.0." + i);
            request.setContent("{}".getBytes(java.nio.charset.StandardCharsets.UTF_8));
            var response = new MockHttpServletResponse();
            filter.doFilter(request, response, new MockFilterChain());
            assertEquals(i == 2 ? 429 : 200, response.getStatus());
        }
    }
}
