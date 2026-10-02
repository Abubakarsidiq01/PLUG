package app.plug.request;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

@Configuration
@EnableScheduling
@ConditionalOnProperty(prefix = "plug.requests-v2", name = "enabled", havingValue = "true")
public class RequestV2Configuration {
    // Claude only when a key is configured; otherwise the null provider leaves the rules in charge.
    @Bean
    @org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean(IntentAdapter.Provider.class)
    IntentAdapter.Provider intentProvider(@Value("${plug.requests-v2.anthropic-api-key:}") String apiKey,
            @Value("${plug.requests-v2.anthropic-model:claude-opus-5-5}") String model,
            @Value("${plug.requests-v2.intent-timeout:6s}") Duration timeout) {
        if (apiKey.isBlank()) return (text, now, zone, deadline) -> null;
        return new ClaudeIntentProvider(apiKey, model, timeout);
    }
    @Bean RequestClock requestClock(Clock clock) { return new RequestClock(clock); }
    @Bean IntentAdapter intentAdapter(ObjectMapper mapper, RequestClock clock, IntentAdapter.Provider provider,
            @Value("${plug.requests-v2.intent-timeout:6s}") Duration timeout) {
        return new IntentAdapter(mapper, clock.clock(), provider, timeout);
    }
}
