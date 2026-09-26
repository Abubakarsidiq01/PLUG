package app.plug.foundation;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

// Every file under /fixtures is what the Bruno collection, Playwright and the iOS decoding
// tests build against, so each one is checked against the same schema the server answers
// with. A fixture written from memory rather than from the contract fails here instead of
// in the other lane's client.
class FixtureContractTest {
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final Path FIXTURES = Path.of("../fixtures");

    // The schema of the successful body for each operation folder. Error files are
    // recognised by their envelope and always checked against Error.
    private static final Map<String, String> SUCCESS_SCHEMA = Map.ofEntries(
            Map.entry("requests.create", "RequestResponse"),
            Map.entry("auth.apple", "Session"),
            Map.entry("auth.google", "Session"),
            Map.entry("auth.guest", "Session"),
            Map.entry("auth.phone.start", "PhoneChallenge"),
            Map.entry("auth.phone.verify", "Session"),
            Map.entry("auth.refresh", "Session"),
            Map.entry("me.get", "Me"),
            Map.entry("me.consent", "Consent"),
            Map.entry("me.sessions", "SessionList"));

    @Test
    void everyFixtureMatchesItsSchema() throws Exception {
        List<Path> files;
        try (Stream<Path> walk = Files.walk(FIXTURES)) {
            files = walk.filter(path -> path.toString().endsWith(".json")).toList();
        }
        assertFalse(files.isEmpty(), "no fixtures found");
        for (Path file : files) {
            String operation = file.getParent().getFileName().toString();
            JsonNode body = JSON.readTree(file.toFile());
            String schema = body.has("error") ? "Error" : SUCCESS_SCHEMA.get(operation);
            assertNotNull(schema, "no schema mapped for fixture folder " + operation);
            ContractSchemas.validate(schema, body);
        }
    }

    @Test
    void phaseOneRequestAndResponseExamplesMatchTheirSchemas() throws Exception {
        ContractSchemas.validateExample("AppleSignIn", "auth-apple-request.json");
        ContractSchemas.validateExample("GoogleSignIn", "auth-google-request.json");
        ContractSchemas.validateExample("GuestSignIn", "auth-guest-request.json");
        ContractSchemas.validateExample("PhoneStart", "auth-phone-start-request.json");
        ContractSchemas.validateExample("PhoneVerify", "auth-phone-verify-request.json");
        ContractSchemas.validateExample("RefreshRequest", "auth-refresh-request.json");
        ContractSchemas.validateExample("ConsentAcceptance", "consent-acceptance.json");
        ContractSchemas.validateExample("Session", "session-guest.json");
        ContractSchemas.validateExample("SessionList", "session-list.json");
        ContractSchemas.validateExample("Error", "account-exists-error.json");
        ContractSchemas.validateExample("Error", "account-not-found-error.json");
        ContractSchemas.validateExample("Error", "phone-unavailable-error.json");
    }

    // The server does not replay auth responses: two guest calls with the same key create
    // two sessions. The contract must therefore not promise replay on any identity route,
    // while the Phase 0 request route keeps the guarantee it already had.
    @Test
    void onlyTheRequestRouteAcceptsAnIdempotencyKey() throws Exception {
        JsonNode paths = new ObjectMapper(new YAMLFactory())
                .readTree(Path.of("../contracts/openapi.yaml").toFile()).get("paths");
        assertTrue(declaresIdempotencyKey(paths.get("/v1/requests")), "/v1/requests lost its Idempotency-Key");
        paths.fieldNames().forEachRemaining(route -> {
            if (route.startsWith("/v1/auth") || route.startsWith("/v1/me")) {
                assertFalse(declaresIdempotencyKey(paths.get(route)), route + " promises an unimplemented replay");
            }
        });
    }

    private static boolean declaresIdempotencyKey(JsonNode pathItem) {
        return pathItem.findValues("parameters").stream()
                .flatMap(parameters -> Stream.iterate(0, i -> i < parameters.size(), i -> i + 1).map(parameters::get))
                .anyMatch(parameter -> "Idempotency-Key".equals(parameter.path("name").asText())
                        || parameter.path("$ref").asText().endsWith("/IdempotencyKeyHeader"));
    }
}
