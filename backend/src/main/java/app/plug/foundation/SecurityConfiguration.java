package app.plug.foundation;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
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
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;

@Configuration
public class SecurityConfiguration {
    private HttpSecurity base(HttpSecurity http) throws Exception {
        // This API uses explicit bearer headers, not browser cookies or sessions.
        return http.csrf(csrf -> csrf.ignoringRequestMatchers("/v1/requests"))
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .requestCache(cache -> cache.disable())
                .formLogin(form -> form.disable()).httpBasic(basic -> basic.disable())
                .exceptionHandling(errors -> errors
                        .authenticationEntryPoint((request, response, exception) ->
                                HttpErrors.write(request, response, 401, "unauthenticated", "Authentication is required."))
                        .accessDeniedHandler((request, response, exception) ->
                                HttpErrors.write(request, response, 403, "forbidden", "This operation is not allowed.")));
    }

    @Bean
    @Profile("!staging")
    SecurityFilterChain local(HttpSecurity http) throws Exception {
        return base(http).authorizeHttpRequests(auth -> auth
                .requestMatchers(HttpMethod.GET, "/health").permitAll()
                .requestMatchers(HttpMethod.GET, "/health/ready", "/actuator/health", "/actuator/health/readiness", "/actuator/health/liveness")
                    .access(directProbeOnly())
                .requestMatchers(HttpMethod.POST, "/v1/requests").permitAll()
                .anyRequest().denyAll()).build();
    }

    @Bean
    @Profile("staging")
    SecurityFilterChain staging(HttpSecurity http) throws Exception {
        // Infrastructure still restricts direct probes. Forwarded requests (including
        // the Phase 0 Quick Tunnel) must not expose operational dependency details.
        return base(http).authorizeHttpRequests(auth -> auth
                .requestMatchers(HttpMethod.GET, "/health").permitAll()
                .requestMatchers(HttpMethod.GET, "/health/ready", "/actuator/health", "/actuator/health/readiness", "/actuator/health/liveness")
                    .access(directProbeOnly())
                .requestMatchers(HttpMethod.POST, "/v1/requests").hasAuthority("SCOPE_plug.requests.write")
                .anyRequest().denyAll())
                .oauth2ResourceServer(resource -> resource.jwt(jwt -> {})
                        .authenticationEntryPoint((request, response, exception) ->
                                HttpErrors.write(request, response, 401, "unauthenticated", "A valid access token is required.")))
                .build();
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

    static org.springframework.security.oauth2.core.OAuth2TokenValidator<org.springframework.security.oauth2.jwt.Jwt>
            validators(String issuer, String audience) {
        return new DelegatingOAuth2TokenValidator<>(JwtValidators.createDefaultWithIssuer(issuer),
                token -> token.getExpiresAt() != null && token.getAudience() != null && token.getAudience().contains(audience)
                        ? OAuth2TokenValidatorResult.success()
                        : OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token")));
    }
}
