package app.plug.security;

import java.util.Set;

// Who is calling, resolved from the session on every single request. Deliberately small:
// it carries what an authorization decision needs and nothing an attacker would enjoy
// finding in a heap dump or a log line. There is no token here, and no phone number.
//
// The scopes are the account's capabilities, not its identity provider. A guest holds
// "guest"; an account that verified with Apple or a phone holds "member". Code that asks
// "may this caller do X" asks about a scope, which is why adding a fourth sign-in method
// later does not mean revisiting every authorization check.
public record PlugPrincipal(String userId, String sessionId, Set<String> scopes, boolean multiFactorVerified) {
    public static final String SCOPE_GUEST = "guest";
    public static final String SCOPE_MEMBER = "member";
    public static final String SCOPE_ADMIN = "admin";

    public PlugPrincipal {
        scopes = Set.copyOf(scopes);
    }

    public boolean hasScope(String scope) {
        return scopes.contains(scope);
    }

    // The only representation that may ever reach a log line or an analytics event. A user
    // id is a stable identifier for a real person, so the full value stays in the database
    // and in admin views that record who looked at it.
    public String userHash() {
        return hashForLogging(userId);
    }

    public static String hashForLogging(String value) {
        return Integer.toHexString(value.hashCode() & 0x7fffffff);
    }
}
