package app.plug.identity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermissions;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class DevelopmentPhoneCodeSenderTest {
    @TempDir Path directory;

    @Test
    void refusesNonlocalDelivery() {
        assertThrows(IllegalStateException.class,
                () -> new DevelopmentPhoneCodeSender("staging", directory.resolve("codes.txt")));
    }

    @Test
    void writesTestCodesWithOwnerOnlyAccessWhereSupported() throws Exception {
        Path file = directory.resolve("codes.txt");
        var sender = new DevelopmentPhoneCodeSender("local", file);
        sender.send("+15555550100", "123456");
        assertTrue(Files.readString(file).contains("+15555550100 123456"));
        if (file.getFileSystem().supportedFileAttributeViews().contains("posix")) {
            assertEquals(PosixFilePermissions.fromString("rw-------"), Files.getPosixFilePermissions(file));
            Files.setPosixFilePermissions(file, PosixFilePermissions.fromString("rw-r--r--"));
            sender.send("+15555550100", "654321");
            assertEquals(PosixFilePermissions.fromString("rw-------"), Files.getPosixFilePermissions(file));
        }
    }
}
