package com.plug.health;

import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {
    private final String environment;

    public HealthController(@Value("${plug.environment}") String environment) {
        this.environment = environment;
    }

    @GetMapping("/health")
    ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of("status", "ok", "service", "plug-api", "environment", environment));
    }
}
