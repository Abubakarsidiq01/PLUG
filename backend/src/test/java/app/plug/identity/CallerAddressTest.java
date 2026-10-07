package app.plug.identity;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;

/// Per-address limits count the connection, except that a listed proxy (the staff console's
/// server) may say whose request it is passing on. Nobody else can.
class CallerAddressTest {
    @AfterEach void trustNobody() { CallerAddress.trust(List.of()); }

    static MockHttpServletRequest from(String address, String forwarded) {
        var request = new MockHttpServletRequest();
        request.setRemoteAddr(address);
        if (forwarded != null) request.addHeader("X-Forwarded-For", forwarded);
        return request;
    }

    @Test void onlyAListedProxyCanPassOnItsCallersAddress() {
        assertThat(CallerAddress.prefixOf(from("203.0.113.9", "198.51.100.7"))).isEqualTo("203.0.113.0/24");
        CallerAddress.trust(List.of("10.0.0.5"));
        assertThat(CallerAddress.prefixOf(from("10.0.0.5", "198.51.100.7"))).isEqualTo("198.51.100.0/24");
        // The caller's own entries come first; only the proxy's last hop is believed.
        assertThat(CallerAddress.prefixOf(from("10.0.0.5", "1.2.3.4, 198.51.100.7"))).isEqualTo("198.51.100.0/24");
        assertThat(CallerAddress.prefixOf(from("10.0.0.5", "not an address"))).isEqualTo("10.0.0.0/24");
        assertThat(CallerAddress.prefixOf(from("203.0.113.9", "198.51.100.7"))).isEqualTo("203.0.113.0/24");
    }
}
