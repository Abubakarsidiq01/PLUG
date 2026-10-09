package app.plug.foundation;

import java.time.Duration;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

// The window behind every per-minute API limit (manual v4 §12A): reads and creations per
// address, creations per account, and skill proposals. It is one minute. A disposable local
// run may shorten it so the acceptance suites need not sit out real minutes; any other
// environment refuses to start with anything but one minute.
@Component
public class RateWindow {
    public static final RateWindow MINUTE = new RateWindow(Duration.ofMinutes(1));

    private final Duration length;

    @Autowired
    public RateWindow(@Value("${plug.rate-window-seconds:60}") int seconds,
            @Value("${plug.environment}") String environment) {
        this(Duration.ofSeconds(seconds));
        if (seconds != 60 && !environment.equals("local")) {
            throw new IllegalArgumentException("Only a local run may shorten the rate window.");
        }
    }

    private RateWindow(Duration length) {
        if (length.isNegative() || length.isZero() || length.compareTo(Duration.ofMinutes(1)) > 0) {
            throw new IllegalArgumentException("The rate window must be between one second and one minute.");
        }
        this.length = length;
    }

    public Duration length() {
        return length;
    }

    // A caller retrying after this many seconds always lands in a fresh window.
    public int retryAfterSeconds() {
        return (int) length.toSeconds();
    }
}
