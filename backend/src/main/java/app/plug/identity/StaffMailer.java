package app.plug.identity;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;

// How staff invitations and sign-in codes reach an inbox. Like PhoneCodeSender, there is no
// implementation that writes a code or an invitation to the application log, in any
// environment: a code in a log is a credential in a log (manual.docx 19.9).
interface StaffMailer {
    void send(String to, String subject, String text);

    // Answered before a code or an invitation is created, so an environment without mail says
    // so with dependency_unavailable instead of storing something nobody will receive.
    boolean isAvailable();

    // The default, including staging until a sender is configured.
    final class None implements StaffMailer {
        @Override
        public void send(String to, String subject, String text) {
            throw new UnsupportedOperationException("No staff mail delivery is configured.");
        }

        @Override
        public boolean isAvailable() {
            return false;
        }
    }

    // One developer's own machine: messages go to an owner-only file under build/, which is
    // gitignored and never shipped. It refuses to exist outside plug.environment=local.
    final class Development implements StaffMailer {
        private final Path destination;

        Development(String environment, Path destination) {
            if (!"local".equals(environment)) {
                throw new IllegalStateException(
                        "plug.staff.mail-delivery=development is only permitted when plug.environment=local.");
            }
            this.destination = destination;
        }

        @Override
        public void send(String to, String subject, String text) {
            try {
                Files.createDirectories(destination.getParent());
                if (destination.getFileSystem().supportedFileAttributeViews().contains("posix")) {
                    var ownerOnly = java.nio.file.attribute.PosixFilePermissions.fromString("rw-------");
                    try {
                        Files.createFile(destination, java.nio.file.attribute.PosixFilePermissions.asFileAttribute(ownerOnly));
                    } catch (java.nio.file.FileAlreadyExistsException existing) {
                        // Tightened below either way.
                    }
                    Files.setPosixFilePermissions(destination, ownerOnly);
                }
                Files.writeString(destination, "--- " + Instant.now() + " to " + to + System.lineSeparator()
                        + subject + System.lineSeparator() + text + System.lineSeparator(),
                        StandardCharsets.UTF_8, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            } catch (IOException exception) {
                throw new IllegalStateException("Could not write the development mail file.", exception);
            }
        }

        @Override
        public boolean isAvailable() {
            return true;
        }
    }

    // Resend's HTTP API. The key comes from secret storage and is sent only to Resend.
    final class Resend implements StaffMailer {
        private static final URI ENDPOINT = URI.create("https://api.resend.com/emails");
        private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
        private final com.fasterxml.jackson.databind.ObjectMapper json = new com.fasterxml.jackson.databind.ObjectMapper();
        private final String apiKey;
        private final String from;

        Resend(String apiKey, String from) {
            if (apiKey == null || apiKey.isBlank() || from == null || !from.contains("@")) {
                throw new IllegalStateException("plug.staff.mail-delivery=resend needs plug.staff.resend-api-key and plug.staff.mail-from.");
            }
            this.apiKey = apiKey;
            this.from = from;
        }

        @Override
        public void send(String to, String subject, String text) {
            try {
                String body = json.writeValueAsString(Map.of("from", from, "to", List.of(to), "subject", subject, "text", text));
                HttpResponse<Void> response = http.send(HttpRequest.newBuilder(ENDPOINT).timeout(Duration.ofSeconds(10))
                        .header("Authorization", "Bearer " + apiKey).header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(body)).build(), HttpResponse.BodyHandlers.discarding());
                if (response.statusCode() / 100 != 2) {
                    throw new IllegalStateException("Resend refused the message with status " + response.statusCode() + ".");
                }
            } catch (IOException exception) {
                throw new IllegalStateException("Resend could not be reached.", exception);
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("Interrupted while sending mail.", exception);
            }
        }

        @Override
        public boolean isAvailable() {
            return true;
        }
    }
}
