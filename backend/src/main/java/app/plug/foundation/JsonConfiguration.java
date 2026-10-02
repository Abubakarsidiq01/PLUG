package app.plug.foundation;

import com.fasterxml.jackson.databind.MapperFeature;
import com.fasterxml.jackson.databind.cfg.CoercionAction;
import com.fasterxml.jackson.databind.cfg.CoercionInputShape;
import com.fasterxml.jackson.databind.type.LogicalType;
import org.springframework.boot.autoconfigure.jackson.Jackson2ObjectMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class JsonConfiguration {
    @Bean
    Jackson2ObjectMapperBuilderCustomizer strictNumbers(
            @org.springframework.beans.factory.annotation.Value("${plug.requests-v2.enabled:false}") boolean requestsV2) {
        // Coordinates must be JSON numbers, not strings silently converted to numbers.
        return builder -> builder.featuresToDisable(MapperFeature.ALLOW_COERCION_OF_SCALARS,
                        com.fasterxml.jackson.databind.DeserializationFeature.ACCEPT_FLOAT_AS_INT)
                .postConfigurer(mapper -> {
                    // ALLOW_COERCION_OF_SCALARS does not disable number/boolean-to-String coercion.
                    mapper.coercionConfigFor(LogicalType.Textual)
                            .setCoercion(CoercionInputShape.Integer, CoercionAction.Fail)
                            .setCoercion(CoercionInputShape.Float, CoercionAction.Fail)
                            .setCoercion(CoercionInputShape.Boolean, CoercionAction.Fail);
                    mapper.getFactory().setStreamReadConstraints(
                            com.fasterxml.jackson.core.StreamReadConstraints.builder()
                                    // P2 allows bounded JPEG thumbnails. All other fields retain their bean limits;
                                    // only provider setup has the larger 96 KiB HTTP body allowance.
                                    .maxNestingDepth(20).maxStringLength(requestsV2 ? 65536 : 4096).maxNumberLength(32).build());
                });
    }
}
