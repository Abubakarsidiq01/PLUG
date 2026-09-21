package app.plug.health;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.sql.Connection;
import java.sql.SQLException;
import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.FlywayException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.support.DefaultListableBeanFactory;
import org.springframework.boot.info.BuildProperties;

class ReadinessFailureTest {
    @Test
    void unavailableMigrationMetadataReturnsTheReadinessEnvelope() throws Exception {
        var beans = new DefaultListableBeanFactory();
        var source = mock(DataSource.class);
        var connection = mock(Connection.class);
        when(source.getConnection()).thenReturn(connection);
        when(connection.isValid(2)).thenReturn(true);
        var flyway = mock(Flyway.class);
        when(flyway.info()).thenThrow(new FlywayException("sensitive database connection details"));
        beans.registerSingleton("source", source);
        beans.registerSingleton("flyway", flyway);
        var controller = new HealthController(beans.getBeanProvider(BuildProperties.class),
                beans.getBeanProvider(DataSource.class), beans.getBeanProvider(Flyway.class));

        var response = controller.ready();
        assertEquals(503, response.getStatusCode().value());
        assertNotNull(response.getBody());
        assertEquals("DOWN", response.getBody().get("status"));
        assertEquals(java.util.Map.of("database", "UP", "migrations", "DOWN"), response.getBody().get("checks"));

        when(source.getConnection()).thenThrow(new SQLException("sensitive connection details"));
        assertEquals(503, controller.ready().getStatusCode().value());
    }
}
