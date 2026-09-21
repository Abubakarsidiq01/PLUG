package app.plug.health;

import java.sql.Connection;
import java.sql.SQLException;
import java.util.LinkedHashMap;
import java.util.Map;
import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.FlywayException;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.info.BuildProperties;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

// Two endpoints, deliberately different. /health is public and says almost nothing.
// /health/ready is what a load balancer uses and may check dependencies, but it must
// stay off the public internet at the infra layer: dependency topology is information
// an attacker is glad to have.
@RestController
public class HealthController {
    private final BuildProperties buildProperties;
    private final ObjectProvider<DataSource> dataSource;
    private final ObjectProvider<Flyway> flyway;

    public HealthController(ObjectProvider<BuildProperties> buildProperties, ObjectProvider<DataSource> dataSource,
            ObjectProvider<Flyway> flyway) {
        this.buildProperties = buildProperties.getIfAvailable();
        this.dataSource = dataSource;
        this.flyway = flyway;
    }

    @GetMapping("/health")
    ResponseEntity<Map<String, String>> health() {
        var body = new LinkedHashMap<String, String>();
        body.put("status", "UP");
        body.put("version", buildProperties != null ? buildProperties.getVersion() : "0.0.0-dev");
        String commit = buildProperties != null ? buildProperties.get("commit") : null;
        if (commit != null) {
            body.put("commit", commit);
        }
        // No database status, no queue depth, no environment name, no hostname.
        return ResponseEntity.ok(body);
    }

    @GetMapping("/health/ready")
    ResponseEntity<Map<String, Object>> ready() {
        var checks = new LinkedHashMap<String, String>();
        boolean healthy = true;

        DataSource source = dataSource.getIfAvailable();
        if (source != null) {
            boolean reachable = isReachable(source);
            checks.put("database", reachable ? "UP" : "DOWN");
            healthy = healthy && reachable;
        } else {
            checks.put("database", "DISABLED");
        }

        Flyway migrations = flyway.getIfAvailable();
        if (migrations != null) {
            boolean upToDate = migrationsAreCurrent(migrations);
            checks.put("migrations", upToDate ? "UP" : "DOWN");
            healthy = healthy && upToDate;
        } else {
            checks.put("migrations", "DISABLED");
        }

        Map<String, Object> body = Map.of("status", healthy ? "UP" : "DOWN", "checks", checks);
        return healthy ? ResponseEntity.ok(body) : ResponseEntity.status(503).body(body);
    }

    private boolean isReachable(DataSource source) {
        try (Connection connection = source.getConnection()) {
            return connection.isValid(2);
        } catch (SQLException exception) {
            return false;
        }
    }

    private boolean migrationsAreCurrent(Flyway migrations) {
        try {
            return migrations.info().pending().length == 0;
        } catch (FlywayException exception) {
            // An unavailable database is a failed readiness check, not an unexpected
            // controller error. Keep the 503 readiness contract and omit driver details.
            return false;
        }
    }
}
