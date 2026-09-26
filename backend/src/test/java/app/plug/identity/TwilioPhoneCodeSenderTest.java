package app.plug.identity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import app.plug.foundation.ApiException;
import java.io.IOException;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class TwilioPhoneCodeSenderTest {
    private final HttpClient client = mock(HttpClient.class);

    private TwilioPhoneCodeSender sender() {
        return new TwilioPhoneCodeSender("AC" + "0".repeat(32), "synthetic-test-value", "MG" + "0".repeat(32), client);
    }

    @Test
    void rejectsMissingConfiguration() {
        assertThrows(IllegalArgumentException.class, () -> new TwilioPhoneCodeSender("", "", ""));
    }

    @Test
    @SuppressWarnings("unchecked")
    void sendsToTwilioWithBoundedTimeout() throws Exception {
        HttpResponse<Void> response = mock(HttpResponse.class);
        when(response.statusCode()).thenReturn(201);
        when(client.send(any(HttpRequest.class), any(HttpResponse.BodyHandler.class))).thenReturn(response);
        sender().send("+15555550123", "123456");
        var request = ArgumentCaptor.forClass(HttpRequest.class);
        verify(client).send(request.capture(), any(HttpResponse.BodyHandler.class));
        assertEquals("https", request.getValue().uri().getScheme());
        assertEquals("api.twilio.com", request.getValue().uri().getHost());
        assertEquals("POST", request.getValue().method());
        assertEquals(10, request.getValue().timeout().orElseThrow().toSeconds());
    }

    @Test
    @SuppressWarnings("unchecked")
    void providerRejectionAndTimeoutNeverReportSuccess() throws Exception {
        HttpResponse<Void> response = mock(HttpResponse.class);
        when(response.statusCode()).thenReturn(400);
        when(client.send(any(HttpRequest.class), any(HttpResponse.BodyHandler.class))).thenReturn(response);
        assertThrows(ApiException.class, () -> sender().send("+15555550123", "123456"));
        when(client.send(any(HttpRequest.class), any(HttpResponse.BodyHandler.class))).thenThrow(new IOException());
        assertThrows(ApiException.class, () -> sender().send("+15555550123", "123456"));
    }

    @Test
    void rejectsAnInvalidSenderWithoutAService() {
        assertThrows(IllegalArgumentException.class, () -> new TwilioPhoneCodeSender(
                "AC" + "0".repeat(32), "synthetic", "", "3125550100"));
        assertThrows(IllegalArgumentException.class, () -> new TwilioPhoneCodeSender(
                "AC" + "0".repeat(32), "synthetic", "invalid-service", "+15555550100"));
    }

    @Test
    void sendsFromATwilioNumberWithoutAMessagingService() throws Exception {
        String body = sentBody("", "+15555550100");
        assertTrue(body.contains("From=%2B15555550100"));
        assertTrue(body.contains("To=%2B15555550123"));
        assertFalse(body.contains("MessagingServiceSid"));
    }

    @Test
    void messagingServiceTakesPrecedenceOverStandaloneSender() throws Exception {
        String body = sentBody("MG" + "0".repeat(32), "+15555550100");
        assertTrue(body.contains("MessagingServiceSid=MG" + "0".repeat(32)));
        assertFalse(body.contains("From="));
    }

    @SuppressWarnings("unchecked")
    private String sentBody(String service, String from) throws Exception {
        HttpResponse<Void> response = mock(HttpResponse.class);
        when(response.statusCode()).thenReturn(201);
        when(client.send(any(HttpRequest.class), any(HttpResponse.BodyHandler.class))).thenReturn(response);
        new TwilioPhoneCodeSender("AC" + "0".repeat(32), "synthetic", service, from, client)
                .send("+15555550123", "123456");
        var captured = ArgumentCaptor.forClass(HttpRequest.class);
        verify(client).send(captured.capture(), any(HttpResponse.BodyHandler.class));
        var result = new java.util.concurrent.CompletableFuture<String>();
        captured.getValue().bodyPublisher().orElseThrow().subscribe(new java.util.concurrent.Flow.Subscriber<>() {
            private final java.io.ByteArrayOutputStream bytes = new java.io.ByteArrayOutputStream();
            public void onSubscribe(java.util.concurrent.Flow.Subscription subscription) { subscription.request(Long.MAX_VALUE); }
            public void onNext(java.nio.ByteBuffer buffer) {
                byte[] chunk = new byte[buffer.remaining()];
                buffer.get(chunk);
                bytes.writeBytes(chunk);
            }
            public void onError(Throwable error) { result.completeExceptionally(error); }
            public void onComplete() { result.complete(bytes.toString(java.nio.charset.StandardCharsets.UTF_8)); }
        });
        return result.get(5, java.util.concurrent.TimeUnit.SECONDS);
    }
}
