package app.plug.foundation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.time.Duration;
import org.junit.jupiter.api.Test;

class RateWindowTest {
    @Test
    void oneMinuteEverywhere() {
        assertEquals(Duration.ofMinutes(1), new RateWindow(60, "staging").length());
        assertEquals(60, new RateWindow(60, "staging").retryAfterSeconds());
    }

    @Test
    void onlyALocalRunMayShortenIt() {
        assertEquals(Duration.ofSeconds(10), new RateWindow(10, "local").length());
        assertEquals(10, new RateWindow(10, "local").retryAfterSeconds());
        assertThrows(IllegalArgumentException.class, () -> new RateWindow(10, "staging"));
    }

    @Test
    void neverZeroNorLongerThanAMinute() {
        assertThrows(IllegalArgumentException.class, () -> new RateWindow(0, "local"));
        assertThrows(IllegalArgumentException.class, () -> new RateWindow(61, "local"));
    }
}
