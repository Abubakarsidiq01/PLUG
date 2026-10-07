package app.plug.identity;

import app.plug.security.PlugPrincipal;
import java.util.Locale;
import java.util.Set;

// What a person proved about themselves. The account keeps one user id for its whole
// life, so upgrading from a guest changes this value and nothing else that matters.
public enum AccountType {
    GUEST, PHONE, APPLE, GOOGLE, STAFF;

    public static AccountType fromStorage(String value) {
        return valueOf(value.toUpperCase(Locale.ROOT));
    }

    public String storage() {
        return name().toLowerCase(Locale.ROOT);
    }

    // A guest can do guest things. Anyone who verified with Apple or a phone number is a
    // member. No account is granted the admin scope in Phase 1, which means every route
    // under /v1/admin is refused until an admin identity model exists to grant it.
    //
    // A staff account (ADR-013) holds admin and nothing else: it cannot ask, offer or act as
    // a customer, and /v1/admin still requires the emailed second factor on its session.
    public Set<String> scopes() {
        if (this == STAFF) return Set.of(PlugPrincipal.SCOPE_ADMIN);
        return this == GUEST ? Set.of(PlugPrincipal.SCOPE_GUEST) : Set.of(PlugPrincipal.SCOPE_MEMBER);
    }
}
