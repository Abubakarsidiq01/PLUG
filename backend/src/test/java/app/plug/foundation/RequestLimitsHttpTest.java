package app.plug.foundation;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "plug.requests-per-minute=2")
class RequestLimitsHttpTest {
    @LocalServerPort private int port;

    @Test
    void encodedRoutesCannotBypassBodyOrRateLimits() throws Exception {
        try (var client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build()) {
            String valid = "{\"query\":\"Barber\",\"location\":{\"latitude\":32,\"longitude\":-92}}";
            assertEquals(202, post(client, "/v1/%72equests", valid));
            assertEquals(413, post(client, "/v1/%72equests", " ".repeat(16_385)));
            assertEquals(429, post(client, "/v1/requests", valid));
            assertEquals(429, post(client, "/v1/%72equests", valid));
        }
    }

    private int post(HttpClient client, String path, String body) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + path))
                .timeout(Duration.ofSeconds(10))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body)).build();
        return client.send(request, HttpResponse.BodyHandlers.discarding()).statusCode();
    }
}
