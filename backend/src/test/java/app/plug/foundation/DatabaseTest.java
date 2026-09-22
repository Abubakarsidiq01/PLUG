package app.plug.foundation;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.zaxxer.hikari.HikariDataSource;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.ArrayList;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

@Tag("database")
@SpringBootTest
@ActiveProfiles("db")
@AutoConfigureMockMvc
class DatabaseTest {
    @Autowired JdbcTemplate jdbc;
    @Autowired Flyway flyway;
    @Autowired HikariDataSource dataSource;
    @Autowired MockMvc mvc;

    @Test
    void migrationsAndPostgisAreAvailable() {
        flyway.validate();
        assertTrue(flyway.info().applied().length >= 1);
        assertFalse(jdbc.queryForObject("SELECT PostGIS_Version()", String.class).isBlank());
    }

    @Test
    void exhaustedPoolFailsReadinessWithinABoundAndRecovers() throws Exception {
        var held = new ArrayList<Connection>();
        try {
            for (int index = 0; index < dataSource.getMaximumPoolSize(); index++) {
                held.add(dataSource.getConnection());
            }
            long started = System.nanoTime();
            mvc.perform(get("/health/ready")).andExpect(status().isServiceUnavailable());
            assertTrue((System.nanoTime() - started) / 1_000_000 < 12000,
                    "Exhausted-pool readiness must fail within a bounded interval");
            mvc.perform(get("/health")).andExpect(status().isOk());
        } finally {
            for (Connection connection : held) {
                connection.close();
            }
        }
        mvc.perform(get("/health/ready")).andExpect(status().isOk());
    }

    @Test
    void slowQueryIsCancelledAndConnectionRemainsUsable() throws Exception {
        try (Connection connection = dataSource.getConnection();
                var statement = connection.createStatement()) {
            long started = System.nanoTime();
            SQLException failure = assertThrows(SQLException.class,
                    () -> statement.execute("SELECT pg_sleep(15)"));
            assertEquals("57014", failure.getSQLState());
            assertTrue((System.nanoTime() - started) / 1_000_000 < 10000,
                    "Database must cancel the query before its 15-second sleep completes");
            try (var result = statement.executeQuery("SELECT 1")) {
                assertTrue(result.next());
                assertEquals(1, result.getInt(1));
            }
        }
        mvc.perform(get("/health/ready")).andExpect(status().isOk());
    }
}
