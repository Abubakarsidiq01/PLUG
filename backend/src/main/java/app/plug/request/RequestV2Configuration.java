package app.plug.request;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Duration;
import java.util.Set;
import java.util.TreeSet;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration
@EnableScheduling
@ConditionalOnProperty(prefix = "plug.requests-v2", name = "enabled", havingValue = "true")
public class RequestV2Configuration {
    /// The contract file and the database must agree, or matching silently drifts (manual v4
    /// §12B.3 rule 1). A tag added to skills.yaml without its migration stops the application.
    @Bean SkillVocabulary skillVocabulary(JdbcTemplate jdbc) {
        SkillVocabulary vocabulary = SkillVocabulary.load();
        Set<String> contract = new TreeSet<>();
        vocabulary.all().forEach(skill -> contract.add(skill.tag()));
        Set<String> database = new TreeSet<>(jdbc.queryForList("SELECT tag FROM skill_vocabulary", String.class));
        if (!contract.equals(database)) {
            throw new IllegalStateException("contracts/skills.yaml and skill_vocabulary disagree; add a migration");
        }
        return vocabulary;
    }
    @Bean RestrictedIntentPolicy restrictedIntentPolicy() { return new RestrictedIntentPolicy(); }
    // Claude only when a key is configured; otherwise the null provider leaves the rules in charge.
    @Bean
    @org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean(IntentAdapter.Provider.class)
    IntentAdapter.Provider intentProvider(@Value("${plug.requests-v2.anthropic-api-key:}") String apiKey,
            @Value("${plug.requests-v2.anthropic-model:claude-opus-5-5}") String model,
            @Value("${plug.requests-v2.intent-timeout:6s}") Duration timeout, SkillVocabulary vocabulary) {
        if (apiKey.isBlank()) return (text, now, zone, deadline) -> null;
        return new ClaudeIntentProvider(apiKey, model, timeout, vocabulary);
    }
    @Bean RequestClock requestClock(Clock clock) { return new RequestClock(clock); }
    @Bean IntentAdapter intentAdapter(ObjectMapper mapper, RequestClock clock, IntentAdapter.Provider provider,
            @Value("${plug.requests-v2.intent-timeout:6s}") Duration timeout, SkillVocabulary vocabulary) {
        return new IntentAdapter(mapper, clock.clock(), provider, timeout, vocabulary);
    }
    @Bean MatchService matchService(JdbcTemplate jdbc, RequestClock clock) { return new MatchService(jdbc, clock.clock()); }
    @Bean AskService askService(JdbcTemplate jdbc, PlatformTransactionManager manager, ObjectMapper mapper, RequestClock clock,
            IntentAdapter intent, RestrictedIntentPolicy policy, RequestService requests) {
        return new AskService(jdbc, manager, mapper, clock.clock(), intent, policy, requests);
    }
    @Bean ProviderService providerService(JdbcTemplate jdbc, PlatformTransactionManager manager, RequestClock clock,
            IntentAdapter intent, RestrictedIntentPolicy policy, RequestService requests) {
        return new ProviderService(jdbc, manager, clock.clock(), intent, policy, requests);
    }
}
