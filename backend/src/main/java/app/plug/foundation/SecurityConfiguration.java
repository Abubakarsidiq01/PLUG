package app.plug.foundation;

import app.plug.security.AdminStepUpAuthorization;
import app.plug.security.PlugPrincipal;
import app.plug.security.SessionAuthenticationFilter;
import app.plug.security.SessionAuthenticator;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.authorization.AuthorizationDecision;
import org.springframework.security.authorization.AuthorizationManager;
import org.springframework.security.web.authentication.AnonymousAuthenticationFilter;
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;

@Configuration
public class SecurityConfiguration {
    private HttpSecurity base(HttpSecurity http) throws Exception {
        // This API uses explicit bearer headers, not browser cookies or sessions, so a
        // cross-site request cannot carry a caller's credentials in the first place.
        return http.csrf(csrf -> csrf.ignoringRequestMatchers("/v1/**"))
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .requestCache(cache -> cache.disable())
                .formLogin(form -> form.disable()).httpBasic(basic -> basic.disable())
                .exceptionHandling(errors -> errors
                        .authenticationEntryPoint((request, response, exception) ->
                                HttpErrors.write(request, response, 401, "unauthenticated", "Authentication is required."))
                        .accessDeniedHandler((request, response, exception) ->
                                HttpErrors.write(request, response, 403, "forbidden", "This operation is not allowed.")));
    }

    // The identity routes, expressed once so the local and staging chains cannot drift
    // apart. Everything not named here falls through to denyAll: a route added without a
    // rule is refused rather than quietly published (manual.docx 19.4).
    private void identityRules(
            org.springframework.security.config.annotation.web.configurers.AuthorizeHttpRequestsConfigurer<HttpSecurity>
                    .AuthorizationManagerRequestMatcherRegistry auth) {
        auth.requestMatchers(HttpMethod.POST, "/v1/auth/apple", "/v1/auth/phone/start", "/v1/auth/phone/verify",
                        "/v1/auth/guest", "/v1/auth/refresh").permitAll()
                .requestMatchers(HttpMethod.POST, "/v1/auth/logout", "/v1/me/consent").authenticated()
                .requestMatchers(HttpMethod.GET, "/v1/me").authenticated()
                // Listing and remotely revoking sessions is an account-security capability.
                // A guest's identity is one device credential, so there is no second session
                // for it to manage and POST /v1/auth/logout already ends the one it has.
                .requestMatchers("/v1/me/sessions", "/v1/me/sessions/*")
                    .hasAuthority("SCOPE_" + PlugPrincipal.SCOPE_MEMBER)
                .requestMatchers("/v1/admin/**").access(AdminStepUpAuthorization.required());
    }

    // Built here rather than registered as a bean on purpose. Spring Boot adds any Filter
    // bean to the servlet container's own chain as well, where it would run before the
    // security chain, have its work discarded when the security context is established, and
    // then be skipped inside the chain because OncePerRequestFilter had already seen the
    // request. Constructing it in place keeps it in exactly one chain.
    private SessionAuthenticationFilter sessionFilter(ObjectProvider<SessionAuthenticator> authenticator) {
        return new SessionAuthenticationFilter(authenticator);
    }

    @Bean
    @Profile("!staging")
    SecurityFilterChain local(HttpSecurity http, ObjectProvider<SessionAuthenticator> authenticator)
            throws Exception {
        return base(http).authorizeHttpRequests(auth -> {
            auth.requestMatchers(HttpMethod.GET, "/health").permitAll()
                    .requestMatchers(HttpMethod.GET, "/health/ready", "/actuator/health",
                            "/actuator/health/readiness", "/actuator/health/liveness")
                        .access(directProbeOnly())
                    .requestMatchers(HttpMethod.POST, "/v1/requests").permitAll();
            identityRules(auth);
            auth.anyRequest().denyAll();
        }).addFilterBefore(sessionFilter(authenticator), AnonymousAuthenticationFilter.class).build();
    }

    // Phase 0 froze POST /v1/requests behind an externally issued JWT with a write scope.
    // That route keeps its own chain so the resource-server filter only ever sees tokens
    // meant for it: a PLUG session token is opaque, and a JWT decoder asked to read one
    // would reject the caller before the identity routes got a chance to look.
    @Bean
    @Profile("staging")
    @Order(1)
    SecurityFilterChain stagingRequests(HttpSecurity http) throws Exception {
        return base(http).securityMatcher("/v1/requests")
                .authorizeHttpRequests(auth -> auth.anyRequest().hasAuthority("SCOPE_plug.requests.write"))
                .oauth2ResourceServer(resource -> resource.jwt(jwt -> {})
                        .authenticationEntryPoint((request, response, exception) ->
                                HttpErrors.write(request, response, 401, "unauthenticated", "A valid access token is required.")))
                .build();
    }

    @Bean
    @Profile("staging")
    @Order(2)
    SecurityFilterChain staging(HttpSecurity http, ObjectProvider<SessionAuthenticator> authenticator)
            throws Exception {
        // Infrastructure still restricts direct probes. Forwarded requests (including
        // the Phase 0 Quick Tunnel) must not expose operational dependency details.
        return base(http).authorizeHttpRequests(auth -> {
            auth.requestMatchers(HttpMethod.GET, "/health").permitAll()
                    .requestMatchers(HttpMethod.GET, "/health/ready", "/actuator/health",
                            "/actuator/health/readiness", "/actuator/health/liveness")
                        .access(directProbeOnly());
            identityRules(auth);
            auth.anyRequest().denyAll();
        }).addFilterBefore(sessionFilter(authenticator), AnonymousAuthenticationFilter.class).build();
    }

    private AuthorizationManager<RequestAuthorizationContext> directProbeOnly() {
        return (authentication, context) -> {
            HttpServletRequest request = context.getRequest();
            // These untrusted headers can only deny access, never establish trust or
            // bypass authentication. Keep forwarded-header rewriting disabled so the
            // application can see them; enforce network restrictions at real ingress.
            boolean forwarded = request.getHeader("Forwarded") != null
                    || request.getHeader("X-Forwarded-For") != null
                    || request.getHeader("X-Forwarded-Host") != null
                    || request.getHeader("X-Forwarded-Proto") != null
                    || request.getHeader("CF-Connecting-IP") != null;
            return new AuthorizationDecision(!forwarded);
        };
    }

    @Bean
    @Profile("staging")
    JwtDecoder decoder(@Value("${spring.security.oauth2.resourceserver.jwt.issuer-uri}") String issuer,
            @Value("${plug.jwt-audience}") String audience) {
        if (!issuer.startsWith("https://") || audience.isBlank()) {
            throw new IllegalArgumentException("Staging requires an HTTPS token issuer and an audience.");
        }
        var decoder = NimbusJwtDecoder.withIssuerLocation(issuer).build();
        decoder.setJwtValidator(validators(issuer, audience));
        return decoder;
    }

    // Shared by the staging resource server and by Apple identity-token verification in the
    // identity module. Both need the same four answers — signature, issuer, audience and
    // expiry — and a second copy of this is a second place for one of them to go missing.
    public static org.springframework.security.oauth2.core.OAuth2TokenValidator<org.springframework.security.oauth2.jwt.Jwt>
            validators(String issuer, String audience) {
        return new DelegatingOAuth2TokenValidator<>(JwtValidators.createDefaultWithIssuer(issuer),
                token -> token.getExpiresAt() != null && token.getAudience() != null && token.getAudience().contains(audience)
                        ? OAuth2TokenValidatorResult.success()
                        : OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token")));
    }
}
