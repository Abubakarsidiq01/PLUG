package com.plug.foundation;

import com.fasterxml.jackson.databind.MapperFeature;
import org.springframework.boot.autoconfigure.jackson.Jackson2ObjectMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class JsonConfiguration {
    @Bean
    Jackson2ObjectMapperBuilderCustomizer strictNumbers() {
        // Coordinates must be JSON numbers, not strings silently converted to numbers.
        return builder -> builder.featuresToDisable(MapperFeature.ALLOW_COERCION_OF_SCALARS)
                .postConfigurer(mapper -> mapper.getFactory().setStreamReadConstraints(
                        com.fasterxml.jackson.core.StreamReadConstraints.builder()
                                .maxNestingDepth(20).maxStringLength(1000).maxNumberLength(32).build()));
    }
}
