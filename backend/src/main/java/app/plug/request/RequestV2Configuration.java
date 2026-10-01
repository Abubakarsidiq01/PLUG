package app.plug.request;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

@Configuration
@EnableScheduling
@ConditionalOnProperty(prefix = "plug.requests-v2", name = "enabled", havingValue = "true")
public class RequestV2Configuration {
    @Bean
    @org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean(IntentAdapter.Provider.class)
    IntentAdapter.Provider intentProvider() { return (text, timeout) -> null; }
    @Bean RequestClock requestClock(Clock clock) { return new RequestClock(clock); }
    @Bean IntentAdapter intentAdapter(ObjectMapper mapper, RequestClock clock, IntentAdapter.Provider provider) {
        return new IntentAdapter(mapper, clock.clock(), provider);
    }
}
