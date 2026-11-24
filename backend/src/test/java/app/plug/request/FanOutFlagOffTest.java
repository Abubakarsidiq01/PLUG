package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.test.context.ActiveProfiles;

/// P3.S15 with plug.provider-inbox.enabled=false: matching is the Phase 2 single notification of
/// the best six, with no expansion waves.
@Tag("database")
@SpringBootTest(properties = {"plug.requests-v2.enabled=true", "plug.requests-v2.worker-enabled=false",
        "plug.provider-inbox.enabled=false", "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@Import(FanOutFlagOffTest.TimeConfiguration.class)
class FanOutFlagOffTest extends FanOutSupport {
    static final Instant START = ReservationTest.START;
    static final ReservationTest.MutableClock CLOCK = new ReservationTest.MutableClock();

    @TestConfiguration static class TimeConfiguration {
        @Bean @Primary RequestClock mutableRequestClock() { return new RequestClock(CLOCK); }
    }

    @Test void withTheProviderInboxOffOnlyTheBestSixAreEverContacted() throws Exception {
        CLOCK.now = START;
        var providers = providers(10);
        String id = ask(guest());
        for (int seconds : new int[] {0, 0, 0, 120, 240, 299}) {
            CLOCK.now = START.plusSeconds(seconds);
            service.workOnce();
        }
        assertThat(contacted(id)).containsExactlyElementsOf(ids(providers).subList(0, 6));
        assertThat(requestStatus(id)).isEqualTo("awaiting_responses");
    }
}
