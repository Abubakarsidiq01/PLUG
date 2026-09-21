package app.plug.foundation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;

import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class CorrelationFilterTest {
    @Test
    void unknownPathsAreRedactedThroughoutTheRequest() throws Exception {
        var request = new MockHttpServletRequest("GET", "/private/customer-phone-number");
        request.addHeader("X-Request-Id", "invalid\r\nidentifier");
        var response = new MockHttpServletResponse();
        new CorrelationFilter().doFilter(request, response, (req, res) -> {
            assertEquals("GET unmapped", MDC.get("route"));
            assertNotNull(MDC.get("request_id"));
            assertEquals(MDC.get("request_id"), response.getHeader("X-Request-Id"));
        });
        assertNull(MDC.get("request_id"));
        assertNull(MDC.get("route"));
    }
}
