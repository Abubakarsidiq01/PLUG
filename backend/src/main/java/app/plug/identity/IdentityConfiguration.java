package app.plug.identity;

import java.nio.file.Path;
import java.time.Clock;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;

// The module's wiring, and the flag that turns it on.
//
// Identity is off unless a database is present, which is what makes the rollback in the
// contract changelog a configuration change rather than a revert: with the flag off the
// routes are not registered at all, the migration stays applied and harmless, and Phase 0
// behaviour is exactly what it was. It is on in the db profile and in staging.
//
// The beans are declared here rather than annotated one by one so that nothing in this
// module can be picked up by a component scan while the flag is off.
@Configuration
@ConditionalOnProperty(prefix = "plug.identity", name = "enabled", havingValue = "true")
@EnableConfigurationProperties(IdentitySettings.class)
public class IdentityConfiguration {
    @Bean
    Clock identityClock() {
        return Clock.systemUTC();
    }

    @Bean
    Secrets identitySecrets(IdentitySettings settings) {
        return new Secrets(settings.pepper());
    }

    @Bean
    AuditLog auditLog(JdbcTemplate jdbc) {
        return new AuditLog(jdbc);
    }

    @Bean
    IdentityRepository identityRepository(JdbcTemplate jdbc) {
        return new IdentityRepository(jdbc);
    }

    @Bean
    SessionRepository sessionRepository(JdbcTemplate jdbc) {
        return new SessionRepository(jdbc);
    }

    @Bean
    PhoneChallengeRepository phoneChallengeRepository(JdbcTemplate jdbc) {
        return new PhoneChallengeRepository(jdbc);
    }

    // Registered as the security module's SessionAuthenticator by implementing its
    // interface. That is the only thing outside this package that depends on it.
    @Bean
    SessionService sessionService(SessionRepository sessions, IdentityRepository identities,
            AuditLog audit, IdentitySettings settings, Clock clock) {
        return new SessionService(sessions, identities, audit, settings, clock);
    }

    @Bean
    AppleIdentityVerifier appleIdentityVerifier(IdentitySettings settings, JdbcTemplate jdbc) {
        return new AppleIdentityVerifier(settings, jdbc);
    }

    @Bean
    GoogleIdentityVerifier googleIdentityVerifier(Environment environment, JdbcTemplate jdbc) {
        return new GoogleIdentityVerifier(environment.getProperty("plug.identity.google-client-id", ""), jdbc);
    }

    @Bean
    OtpRateLimiter otpRateLimiter(AuditLog audit) {
        return new OtpRateLimiter(audit);
    }

    // SMS is opt-in; development delivery remains confined to local environments.
    @Bean
    PhoneCodeSender phoneCodeSender(IdentitySettings settings, Environment environment) {
        if (settings.phoneDelivery() == IdentitySettings.PhoneDelivery.DEVELOPMENT) {
            return new DevelopmentPhoneCodeSender(environment.getRequiredProperty("plug.environment"),
                    Path.of(environment.getProperty("plug.identity.development-code-file", "build/development-phone-codes.txt")));
        }
        if (settings.phoneDelivery() == IdentitySettings.PhoneDelivery.TWILIO) {
            return new TwilioPhoneCodeSender(environment.getRequiredProperty("plug.sms.account-sid"),
                    environment.getRequiredProperty("plug.sms.auth-token"),
                    environment.getProperty("plug.sms.messaging-service-sid", ""),
                    environment.getProperty("plug.sms.from-number", ""));
        }
        return new NoPhoneCodeSender();
    }

    @Bean
    PhoneVerificationService phoneVerificationService(PhoneChallengeRepository challenges, OtpRateLimiter limiter,
            PhoneCodeSender sender, AuditLog audit, Secrets secrets, IdentitySettings settings, Clock clock) {
        return new PhoneVerificationService(challenges, limiter, sender, audit, secrets, settings, clock);
    }

    @Bean
    AccountService accountService(IdentityRepository identities, SessionService sessions,
            AppleIdentityVerifier apple, GoogleIdentityVerifier google, PhoneVerificationService phones, AuditLog audit,
            Secrets secrets, IdentitySettings settings) {
        return new AccountService(identities, sessions, apple, google, phones, audit, secrets, settings);
    }
}
