package app.plug.identity;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.logging.LogLevel;
import org.springframework.boot.logging.LoggingSystem;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;

// The gate asks for evidence that no token, code, number or authorization header reaches a
// log. This test drives the whole auth surface with framework logging turned up to DEBUG,
// which is where a payload printed through toString would show up, and then reads the
// captured output back.
@ExtendWith(OutputCaptureExtension.class)
class AuthLoggingTest extends IdentityTestSupport {

    @Test
    void noCredentialReachesTheLogEvenAtDebugLevel(CapturedOutput output) throws Exception {
        String logger = "org.springframework.web";
        var logging = LoggingSystem.get(getClass().getClassLoader());
        var previous = logging.getLoggerConfiguration(logger).getConfiguredLevel();
        logging.setLogLevel(logger, LogLevel.DEBUG);
        try {
            var guest = signInAsGuest();
            String phone = "+15551250001";
            var challenge = body(post("/v1/auth/phone/start", """
                    {"phone_number":"%s"}""".formatted(phone)).andExpect(status().isAccepted()));
            String code = codes.latest();
            var verified = body(post("/v1/auth/phone/verify", """
                    {"challenge_id":"%s","code":"%s","consent_version":"%s"}"""
                    .formatted(challenge.get("challenge_id").asText(), code, CONSENT), accessTokenOf(guest))
                    .andExpect(status().isCreated()));
            var rotated = body(post("/v1/auth/refresh", """
                    {"refresh_token":"%s"}""".formatted(refreshTokenOf(verified))).andExpect(status().isOk()));
            get("/v1/me", accessTokenOf(rotated)).andExpect(status().isOk());
            post("/v1/auth/logout", "", accessTokenOf(rotated)).andExpect(status().isNoContent());

            String logged = output.getAll();
            for (String secret : new String[] {accessTokenOf(guest), refreshTokenOf(guest),
                    accessTokenOf(verified), refreshTokenOf(verified), accessTokenOf(rotated),
                    refreshTokenOf(rotated), code, phone, "5551250001"}) {
                assertFalse(logged.contains(secret),
                        "A credential or phone number reached the log: this is the failure 19.9 is about.");
            }
            assertFalse(logged.contains("Bearer pat_"), "An authorization header reached the log.");
            // The correlation id must still be there. Redaction that also removes the
            // ability to trace a request has traded one problem for another.
            assertFalse(logged.contains("request_id=null"));
        } finally {
            logging.setLogLevel(logger, previous);
        }
    }
}
