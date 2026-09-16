package com.plug.foundation;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import com.networknt.schema.JsonSchemaFactory;
import com.networknt.schema.SpecVersion;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class ContractTest {
    @Autowired MockMvc mvc;
    private final ObjectMapper json = new ObjectMapper();

    private void validate(String schemaName, JsonNode body) throws Exception {
        var document = new ObjectMapper(new YAMLFactory()).readTree(Path.of("../contracts/openapi.yaml").toFile());
        ObjectNode schema = json.createObjectNode();
        schema.put("$schema", "https://json-schema.org/draft/2020-12/schema");
        schema.put("$ref", "#/components/schemas/" + schemaName);
        schema.set("components", document.get("components"));
        var errors = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012).getSchema(schema).validate(body);
        assertTrue(errors.isEmpty(), errors.toString());
    }

    @Test
    void sharedExamplesMatchTheirSchemas() throws Exception {
        validate("HealthResponse", json.readTree(Path.of("../contracts/examples/health-response.json").toFile()));
        validate("RequestCreate", json.readTree(Path.of("../contracts/examples/request-create.json").toFile()));
        validate("RequestResponse", json.readTree(Path.of("../contracts/examples/request-response.json").toFile()));
        validate("ErrorResponse", json.readTree(Path.of("../contracts/examples/validation-error.json").toFile()));
        validate("ErrorResponse", json.readTree(Path.of("../contracts/examples/authorization-error.json").toFile()));
        validate("ErrorResponse", json.readTree(Path.of("../contracts/examples/transient-error.json").toFile()));
    }

    @Test
    void realProviderResponsesMatchTheContract() throws Exception {
        validate("HealthResponse", json.readTree(mvc.perform(get("/health")).andReturn().getResponse().getContentAsString()));
        String input = Files.readString(Path.of("../contracts/examples/request-create.json"));
        validate("RequestResponse", json.readTree(mvc.perform(post("/v1/requests")
                .contentType(MediaType.APPLICATION_JSON).content(input)).andReturn().getResponse().getContentAsString()));
        validate("ErrorResponse", json.readTree(mvc.perform(post("/v1/requests")
                .contentType(MediaType.APPLICATION_JSON).content("{bad")).andReturn().getResponse().getContentAsString()));
    }
}
