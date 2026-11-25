package app.plug.foundation;

import org.apache.commons.logging.LogFactory;
import org.springframework.context.annotation.Lazy;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

@Component
@Lazy(false) // lazy initialisation must not skip this check; no bean depends on it
public class EnvironmentSafetyCheck {
    public EnvironmentSafetyCheck(Environment settings) {
        String name = settings.getRequiredProperty("plug.environment");
        if (!name.equals("local") && !name.equals("staging")) {
            throw new IllegalArgumentException("Use the agreed local or staging environment.");
        }
        if (name.equals("staging") && !settings.acceptsProfiles(Profiles.of("staging"))) {
            throw new IllegalArgumentException("Staging must activate the staging profile; changing the label is not enough.");
        }
        // At DEBUG these print request paths, bodies and raw headers. Spring Boot applies levels before refresh, so
        // this reads the effective level and catches child loggers, logging groups and a DEBUG root.
        for (String logger : new String[] {"org.springframework.web.servlet.DispatcherServlet",
                "org.springframework.web.servlet.mvc.method.annotation.RequestResponseBodyMethodProcessor",
                "org.springframework.web.servlet.mvc.method.annotation.HttpEntityMethodProcessor",
                "org.apache.coyote.http11.Http11InputBuffer"}) {
            if (name.equals("staging") && LogFactory.getLog(logger).isDebugEnabled()) {
                throw new IllegalArgumentException("Staging must not log " + logger + " at DEBUG or TRACE.");
            }
        }
    }
}
