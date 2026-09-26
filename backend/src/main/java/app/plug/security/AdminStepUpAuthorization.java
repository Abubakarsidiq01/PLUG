package app.plug.security;

import org.springframework.security.authorization.AuthorizationDecision;
import org.springframework.security.authorization.AuthorizationManager;
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;

// Admin routes need two things, not one: the admin scope, and a session that actually
// completed a second factor. Checking only the scope means a stolen admin access token is
// full admin access, which is the exact outcome multi-factor authentication exists to
// prevent (manual.docx 25.2, 25.8).
//
// This is in place before the first admin route exists on purpose. Wiring the control
// after the routes are live means there is a window where it is missing, and windows like
// that are what get found by someone else.
public final class AdminStepUpAuthorization {
    private AdminStepUpAuthorization() {}

    public static AuthorizationManager<RequestAuthorizationContext> required() {
        return (authentication, context) -> {
            var current = authentication.get();
            if (current == null || !(current.getPrincipal() instanceof PlugPrincipal principal)) {
                return new AuthorizationDecision(false);
            }
            return new AuthorizationDecision(
                    principal.hasScope(PlugPrincipal.SCOPE_ADMIN) && principal.multiFactorVerified());
        };
    }
}
