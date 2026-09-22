package app.plug.identity;

import app.plug.security.PlugPrincipal;
import java.util.Locale;
import java.util.Set;

// What a person proved about themselves. The account keeps one user id for its whole
// life, so upgrading from a guest changes this value and nothing else that matters.
public enum AccountType {
    GUEST, PHONE, APPLE;

    public static AccountType fromStorage(String value) {
        return valueOf(value.toUpperCase(Locale.ROOT));
    }

    public String storage() {
        return name().toLowerCase(Locale.ROOT);
    }

    // A guest can do guest things. Anyone who verified with Apple or a phone number is a
    // member. No account is granted the admin scope in Phase 1, which means every route
    // under /v1/admin is refused until an admin identity model exists to grant it.
    public Set<String> scopes() {
        return this == GUEST ? Set.of(PlugPrincipal.SCOPE_GUEST) : Set.of(PlugPrincipal.SCOPE_MEMBER);
    }
}
