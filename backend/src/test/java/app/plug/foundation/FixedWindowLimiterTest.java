package app.plug.foundation;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import org.junit.jupiter.api.Test;

// The counter behind both the request-intake limit and the one-time-code limits. Its two
// jobs are counting correctly per key, and refusing to grow without bound when a caller
// arrives with an endless supply of new keys.
class FixedWindowLimiterTest {

    @Test
    void eachKeyIsCountedSeparately() {
        var limiter = new FixedWindowLimiter(16);
        assertTrue(limiter.tryConsume("phone:a", 2, Duration.ofMinutes(15)));
        assertTrue(limiter.tryConsume("phone:a", 2, Duration.ofMinutes(15)));
        assertFalse(limiter.tryConsume("phone:a", 2, Duration.ofMinutes(15)));
        assertTrue(limiter.tryConsume("phone:b", 2, Duration.ofMinutes(15)));
    }

    @Test
    void keysWithDifferentWindowsShareOneInstanceWithoutInterfering() {
        var limiter = new FixedWindowLimiter(16);
        assertTrue(limiter.tryConsume("short", 1, Duration.ofNanos(1)));
        assertTrue(limiter.tryConsume("long", 1, Duration.ofHours(1)));
        assertFalse(limiter.tryConsume("long", 1, Duration.ofHours(1)));
        // The short window has already passed, so its budget is back.
        assertTrue(limiter.tryConsume("short", 1, Duration.ofNanos(1)));
    }

    @Test
    void anEndlessSupplyOfNewKeysIsRefusedRatherThanAllowedToExhaustMemory() {
        var limiter = new FixedWindowLimiter(4);
        for (int key = 0; key < 4; key++) {
            assertTrue(limiter.tryConsume("key-" + key, 5, Duration.ofMinutes(1)));
        }
        assertFalse(limiter.tryConsume("key-5", 5, Duration.ofMinutes(1)));
        // A key that already has a bucket is still served, so the flood does not lock out
        // callers that were already being tracked.
        assertTrue(limiter.tryConsume("key-0", 5, Duration.ofMinutes(1)));
    }

    @Test
    void forgettingAKeyReturnsItsBudget() {
        var limiter = new FixedWindowLimiter(16);
        assertTrue(limiter.tryConsume("challenge", 1, Duration.ofMinutes(10)));
        assertFalse(limiter.tryConsume("challenge", 1, Duration.ofMinutes(10)));
        limiter.forget("challenge");
        assertTrue(limiter.tryConsume("challenge", 1, Duration.ofMinutes(10)));
    }
}
