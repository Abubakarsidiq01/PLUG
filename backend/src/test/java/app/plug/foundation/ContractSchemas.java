package app.plug.foundation;

import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import com.networknt.schema.JsonSchemaFactory;
import com.networknt.schema.SpecVersion;
import java.io.IOException;
import java.nio.file.Path;

// Validates a document against a named schema in contracts/openapi.yaml. Shared by the
// Phase 0 contract test and the identity one, so there is a single answer to "what does
// the contract actually say" rather than two copies that can disagree.
public final class ContractSchemas {
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final Path CONTRACT = Path.of("../contracts/openapi.yaml");

    private ContractSchemas() {}

    public static void validate(String schemaName, JsonNode body) throws IOException {
        var document = new ObjectMapper(new YAMLFactory()).readTree(CONTRACT.toFile());
        ObjectNode schema = JSON.createObjectNode();
        schema.put("$schema", "https://json-schema.org/draft/2020-12/schema");
        schema.put("$ref", "#/components/schemas/" + schemaName);
        schema.set("components", document.get("components"));
        var errors = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012)
                .getSchema(schema).validate(body);
        assertTrue(errors.isEmpty(), schemaName + ": " + errors);
    }

    public static void validate(String schemaName, String body) throws IOException {
        validate(schemaName, JSON.readTree(body));
    }

    public static void validateExample(String schemaName, String exampleFileName) throws IOException {
        validate(schemaName, JSON.readTree(Path.of("../contracts/examples/" + exampleFileName).toFile()));
    }
}
