package app.plug.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

// Turns a bearer token into an authenticated caller, or leaves the request anonymous so
// the filter chain's deny-by-default rule refuses it. It never writes a response itself:
// one entry point produces every 401 in the service, which is how the body, the status and
// the WWW-Authenticate header stay identical whatever the reason for the refusal.
//
// The token is never logged, never put in the MDC and never attached to the principal.
public class SessionAuthenticationFilter extends OncePerRequestFilter {
    private static final String PREFIX = "Bearer ";
    private static final int MAX_TOKEN_LENGTH = 512;

    private final ObjectProvider<SessionAuthenticator> authenticator;

    public SessionAuthenticationFilter(ObjectProvider<SessionAuthenticator> authenticator) {
        this.authenticator = authenticator;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        SessionAuthenticator sessions = authenticator.getIfAvailable();
        String token = bearerToken(request);
        if (sessions != null && token != null && isUnauthenticated()) {
            sessions.authenticate(token).ifPresent(principal -> {
                var authorities = principal.scopes().stream()
                        .map(scope -> (org.springframework.security.core.GrantedAuthority)
                                new SimpleGrantedAuthority("SCOPE_" + scope))
                        .toList();
                var authentication = new UsernamePasswordAuthenticationToken(principal, null, authorities);
                var context = SecurityContextHolder.createEmptyContext();
                context.setAuthentication(authentication);
                SecurityContextHolder.setContext(context);
            });
        }
        // The context is not cleared here. Spring Security's own SecurityContextHolderFilter
        // runs earlier in the chain and clears it in a finally block, and clearing it here
        // as well would remove the anonymous authentication before the exception translator
        // reads it — which is the difference between answering 401 and answering 403.
        chain.doFilter(request, response);
    }

    // The filter runs ahead of the chain's anonymous authentication, but another
    // mechanism may already have identified the caller. Overwriting a real authentication
    // with one resolved from a header is how a caller ends up acting as someone else.
    private boolean isUnauthenticated() {
        var current = SecurityContextHolder.getContext().getAuthentication();
        return current == null
                || current instanceof org.springframework.security.authentication.AnonymousAuthenticationToken;
    }

    private String bearerToken(HttpServletRequest request) {
        List<String> headers = java.util.Collections.list(request.getHeaders("Authorization"));
        // More than one Authorization header is never legitimate here, and picking the
        // first of two is how a proxy and an application end up disagreeing about the caller.
        if (headers.size() != 1) {
            return null;
        }
        String header = headers.get(0);
        if (!header.startsWith(PREFIX)) {
            return null;
        }
        String token = header.substring(PREFIX.length()).trim();
        return token.isEmpty() || token.length() > MAX_TOKEN_LENGTH ? null : token;
    }
}
