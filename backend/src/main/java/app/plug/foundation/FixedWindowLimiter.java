package app.plug.foundation;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

// One counter shared by everything that has to bound a caller: request intake, one-time
// code requests and code verification attempts. Keeping a single implementation means the
// bucket cap that stops an attacker from growing the tracking table is written once and
// holds at every call site, rather than being remembered again each time a new limit is
// added. Each key carries its own window length, so callers with different windows can
// share one instance safely.
public final class FixedWindowLimiter {
    private final Map<String, Window> windows = new HashMap<>();
    private final int maximumKeys;
    private long lastSweep;

    public FixedWindowLimiter(int maximumKeys) {
        if (maximumKeys < 1) {
            throw new IllegalArgumentException("The tracking table must hold at least one key.");
        }
        this.maximumKeys = maximumKeys;
    }

    // Returns false when the caller is over the limit, or when the tracking table is full
    // and this key has no bucket yet. Refusing a new bucket is deliberate: under a flood of
    // unique keys, running out of memory would take the whole service down, and a refusal
    // only affects callers that are already indistinguishable from the flood.
    public synchronized boolean tryConsume(String key, int maximum, Duration window) {
        long now = System.nanoTime();
        long windowNanos = window.toNanos();
        sweepExpired(now);
        Window current = windows.get(key);
        if (current != null && now - current.started >= current.windowNanos) {
            windows.remove(key);
            current = null;
        }
        if (current == null) {
            if (windows.size() >= maximumKeys) {
                return false;
            }
            current = new Window(now, windowNanos);
            windows.put(key, current);
        }
        if (current.count >= maximum) {
            return false;
        }
        current.count++;
        return true;
    }

    // Called when the thing being limited is finished with — a verified code, for example —
    // so a legitimate caller does not carry a spent budget into their next attempt.
    public synchronized void forget(String key) {
        windows.remove(key);
    }

    private void sweepExpired(long now) {
        if (now - lastSweep < 1_000_000_000L) {
            return;
        }
        windows.entrySet().removeIf(entry -> now - entry.getValue().started >= entry.getValue().windowNanos);
        lastSweep = now;
    }

    private static final class Window {
        private final long started;
        private final long windowNanos;
        private int count;

        Window(long started, long windowNanos) {
            this.started = started;
            this.windowNanos = windowNanos;
        }
    }
}
