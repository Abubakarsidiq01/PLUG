package app.plug.foundation;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.function.Executable;
import org.springframework.boot.logging.LogLevel;
import org.springframework.boot.logging.LoggingSystem;
import org.springframework.mock.env.MockEnvironment;

class EnvironmentSafetyCheckTest {
    private static final String DISPATCHER = "org.springframework.web.servlet.DispatcherServlet";

    private static MockEnvironment environment(String name) {
        var settings = new MockEnvironment().withProperty("plug.environment", name);
        if (name.equals("staging")) settings.setActiveProfiles("staging");
        return settings;
    }

    // Drives the real effective level, then restores the configured one.
    private void withDebug(String logger, Executable check) throws Throwable {
        var logging = LoggingSystem.get(getClass().getClassLoader());
        var configuration = logging.getLoggerConfiguration(logger); // null when nothing has created the logger yet
        var previous = configuration == null ? null : configuration.getConfiguredLevel();
        logging.setLogLevel(logger, LogLevel.DEBUG);
        try {
            check.execute();
        } finally {
            logging.setLogLevel(logger, previous);
        }
    }

    @Test void stagingRefusesTheDispatcherServletAtDebug() throws Throwable {
        withDebug(DISPATCHER, () -> assertThrows(IllegalArgumentException.class,
                () -> new EnvironmentSafetyCheck(environment("staging"))));
    }

    @Test void stagingRefusesAChildBodyLoggerAtDebug() throws Throwable {
        withDebug("org.springframework.web.servlet.mvc.method.annotation.RequestResponseBodyMethodProcessor",
                () -> assertThrows(IllegalArgumentException.class,
                        () -> new EnvironmentSafetyCheck(environment("staging"))));
    }

    @Test void stagingRefusesTheTomcatRequestBufferAtDebug() throws Throwable {
        // Stands in for a DEBUG root, which this logger inherits.
        withDebug("org.apache.coyote.http11.Http11InputBuffer", () -> assertThrows(IllegalArgumentException.class,
                () -> new EnvironmentSafetyCheck(environment("staging"))));
    }

    @Test void stagingStartsWithTheDefaultLevels() {
        assertDoesNotThrow(() -> new EnvironmentSafetyCheck(environment("staging")));
    }

    @Test void localMayRaiseTheDispatcherServlet() throws Throwable {
        withDebug(DISPATCHER, () -> assertDoesNotThrow(() -> new EnvironmentSafetyCheck(environment("local"))));
    }
}
