package app.plug.foundation;

import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

@Component
public class EnvironmentSafetyCheck {
    public EnvironmentSafetyCheck(Environment settings) {
        String name = settings.getRequiredProperty("plug.environment");
        if (!name.equals("local") && !name.equals("staging")) {
            throw new IllegalArgumentException("Use the agreed local or staging environment.");
        }
        if (name.equals("staging") && !settings.acceptsProfiles(Profiles.of("staging"))) {
            throw new IllegalArgumentException("Staging must activate the staging profile; changing the label is not enough.");
        }
    }
}
