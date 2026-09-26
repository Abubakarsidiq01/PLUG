package app.plug.security;

import java.util.Optional;

// The one question the security layer asks the identity module: does this access token
// name a live session, and if so, whose. Declaring it here and implementing it in
// identity keeps the dependency pointing one way — security never reaches into users,
// sessions or consents, and the identity module stays free to change how it stores them.
public interface SessionAuthenticator {
    // Returns empty for an unknown, expired or revoked token. It must not throw for a
    // malformed value: a caller pasting nonsense into the header is an ordinary 401, not
    // a 500, and the difference between the two is information an attacker can measure.
    Optional<PlugPrincipal> authenticate(String accessToken);
}
