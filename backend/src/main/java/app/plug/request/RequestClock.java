package app.plug.request;

import java.time.Clock;

// The request module's own time source. It wraps the application clock in production, and
// exists as a separate type so a test can pin request time (the labelled dataset is written
// against a fixed "now") without also moving identity time: sessions are issued from the
// identity clock but checked against the database's now(), so a pinned identity clock
// issues tokens that are already expired.
public record RequestClock(Clock clock) {}
