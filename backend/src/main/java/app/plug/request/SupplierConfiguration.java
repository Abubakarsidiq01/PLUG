package app.plug.request;

import app.plug.foundation.RateWindow;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

/// P3.S2 supplier_messaging (contract 0.7.7). Off: no bean and no controller, so every supplier
/// route is 404. On: the phone key and pepper are checked at startup, and a delivery of off makes
/// the two routes that queue a text answer 503.
@Configuration
// Gated on supplier_messaging alone (lead decision 2026-11-24): it must not need requests-v2.
@ConditionalOnProperty(prefix = "plug.supplier-messaging", name = "enabled", havingValue = "true")
public class SupplierConfiguration {
    @Bean SupplierPhones supplierPhones(@Value("${plug.identity.pepper:}") String pepper,
            @Value("${plug.supplier-messaging.phone-key:}") String key) {
        return new SupplierPhones(pepper, key);
    }

    @Bean SupplierService supplierService(JdbcTemplate jdbc, PlatformTransactionManager manager, Clock clock, ObjectMapper mapper,
            SupplierPhones phones, RateWindow window, @Value("${plug.supplier-messaging.delivery:off}") String delivery) {
        if (!List.of("off", "simulator", "twilio").contains(delivery)) {
            throw new IllegalStateException("plug.supplier-messaging.delivery must be off, simulator or twilio.");
        }
        // Its own copy of contracts/skills.yaml: this module must not depend on requests-v2 being on.
        return new SupplierService(jdbc, manager, clock, mapper, phones, SkillVocabulary.load(), window, !delivery.equals("off"));
    }
}
