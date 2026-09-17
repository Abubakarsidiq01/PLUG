package app.plug.foundation;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

@Tag("database")
@SpringBootTest
@ActiveProfiles("db")
class DatabaseTest {
    @Autowired JdbcTemplate jdbc;
    @Autowired Flyway flyway;

    @Test
    void migrationsAndPostgisAreAvailable() {
        flyway.validate();
        assertTrue(flyway.info().applied().length >= 1);
        assertFalse(jdbc.queryForObject("SELECT PostGIS_Version()", String.class).isBlank());
    }
}
