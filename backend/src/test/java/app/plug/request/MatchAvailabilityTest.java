package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;

class MatchAvailabilityTest {
    private final MatchService.Candidate morning = new MatchService.Candidate("provider", 100, 0.5, 50,
            "America/Chicago", List.of(new int[] {480, 720}), List.of("every_day"));

    @Test void springForwardUsesEightAmWallTime() {
        assertThat(MatchService.available(morning, Instant.parse("2026-03-08T13:00:00Z"),
                Instant.parse("2026-03-08T13:30:00Z"))).isTrue();
        assertThat(MatchService.available(morning, Instant.parse("2026-03-08T17:00:00Z"),
                Instant.parse("2026-03-08T17:30:00Z"))).isFalse();
    }

    @Test void fallBackDoesNotStartAnHourEarly() {
        assertThat(MatchService.available(morning, Instant.parse("2026-11-01T13:00:00Z"),
                Instant.parse("2026-11-01T13:30:00Z"))).isFalse();
        assertThat(MatchService.available(morning, Instant.parse("2026-11-01T17:30:00Z"),
                Instant.parse("2026-11-01T18:00:00Z"))).isTrue();
    }

    @Test void midnightEndStaysOnTheNextCalendarDay() {
        var allDay = new MatchService.Candidate("provider", 100, 0.5, 50, "America/Chicago",
                List.of(new int[] {0, 1440}), List.of("weekends"));
        assertThat(MatchService.available(allDay, Instant.parse("2026-11-02T05:30:00Z"),
                Instant.parse("2026-11-02T06:00:00Z"))).isTrue();
        assertThat(MatchService.available(allDay, Instant.parse("2026-03-09T05:00:00Z"),
                Instant.parse("2026-03-09T05:30:00Z"))).isFalse();
    }
}
