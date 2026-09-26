package app.plug.identity;

import app.plug.foundation.ApiException;
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Base64;

// Never log the request, provider response, phone number or code. No automatic retries:
// a timeout may mean Twilio accepted the message and retrying would send duplicate SMS.
final class TwilioPhoneCodeSender implements PhoneCodeSender {
    private final HttpClient client;
    private final URI endpoint;
    private final String authorization;
    private final String service;
    private final String fromNumber;

    TwilioPhoneCodeSender(String account, String token, String service) {
        this(account, token, service, "");
    }

    TwilioPhoneCodeSender(String account, String token, String service, String fromNumber) {
        this(account, token, service, fromNumber, HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build());
    }

    TwilioPhoneCodeSender(String account, String token, String service, HttpClient client) {
        this(account, token, service, "", client);
    }

    TwilioPhoneCodeSender(String account, String token, String service, String fromNumber, HttpClient client) {
        this.client = client;
        if (!account.matches("AC[0-9a-fA-F]{32}") || token.isBlank()
                || (!service.isBlank() && !service.matches("MG[0-9a-fA-F]{32}"))
                || (service.isBlank() && !fromNumber.matches("\\+[1-9][0-9]{7,14}"))) {
            throw new IllegalArgumentException("Configure the Twilio account, auth token and either a Messaging Service SID or SMS sender number.");
        }
        this.endpoint = URI.create("https://api.twilio.com/2010-04-01/Accounts/" + account + "/Messages.json");
        this.authorization = "Basic " + Base64.getEncoder().encodeToString(
                (account + ":" + token).getBytes(StandardCharsets.UTF_8));
        this.service = service;
        this.fromNumber = fromNumber;
    }

    @Override
    public boolean isAvailable() { return true; }

    @Override
    public void send(String phoneNumber, String code) {
        String sender = service.isBlank() ? "&From=" + encode(fromNumber) : "&MessagingServiceSid=" + encode(service);
        String body = "To=" + encode(phoneNumber) + sender
                + "&Body=" + encode("Your PLUG verification code is " + code + ". Do not share this code.");
        var request = HttpRequest.newBuilder(endpoint).timeout(Duration.ofSeconds(10))
                .header("Authorization", authorization)
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString(body)).build();
        try {
            var response = client.send(request, HttpResponse.BodyHandlers.discarding());
            if (response.statusCode() != 201) { throw unavailable(); }
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw unavailable();
        } catch (IOException failed) {
            throw unavailable();
        }
    }

    private static String encode(String value) { return URLEncoder.encode(value, StandardCharsets.UTF_8); }

    private static ApiException unavailable() {
        return ApiException.dependencyUnavailable("We could not send a text. Check your number or try again later.", 60);
    }
}
