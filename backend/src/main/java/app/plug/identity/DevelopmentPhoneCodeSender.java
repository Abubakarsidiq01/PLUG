package app.plug.identity;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;

// Lets one developer exercise the phone flow on their own machine before Twilio exists.
// It writes the code to a file under the build directory, which is gitignored and never
// shipped, rather than to the application log, which is collected and shared.
//
// It refuses to construct outside a local environment. A convenience that only fails to be
// dangerous because nobody selected it in staging is not a safe convenience.
class DevelopmentPhoneCodeSender implements PhoneCodeSender {
    private final Path destination;

    DevelopmentPhoneCodeSender(String environment, Path destination) {
        if (!"local".equals(environment)) {
            throw new IllegalStateException(
                    "plug.identity.phone-delivery=development is only permitted when plug.environment=local.");
        }
        this.destination = destination;
    }

    @Override
    public void send(String phoneNumber, String code) {
        try {
            Files.createDirectories(destination.getParent());
            if (destination.getFileSystem().supportedFileAttributeViews().contains("posix")) {
                var ownerOnly = java.nio.file.attribute.PosixFilePermissions.fromString("rw-------");
                try {
                    Files.createFile(destination, java.nio.file.attribute.PosixFilePermissions.asFileAttribute(ownerOnly));
                } catch (java.nio.file.FileAlreadyExistsException existing) {
                    // Tighten files created by older development builds too.
                }
                Files.setPosixFilePermissions(destination, ownerOnly);
            }
            Files.writeString(destination, Instant.now() + " " + phoneNumber + " " + code + System.lineSeparator(),
                    StandardCharsets.UTF_8, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (IOException exception) {
            throw new IllegalStateException("Could not write the development code file.", exception);
        }
    }

    @Override
    public boolean isAvailable() {
        return true;
    }
}
