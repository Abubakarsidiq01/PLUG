package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import app.plug.foundation.ApiException;
import app.plug.request.ProviderPayloads.BusinessLink;
import app.plug.request.ProviderPayloads.BusinessProfile;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.util.Base64;
import java.util.List;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;

class BusinessProfilesTest {
    @Test void imageIsDecodedAndReencodedRatherThanTrustingMimeOrBytes() throws Exception {
        var output = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(256, 256, BufferedImage.TYPE_INT_RGB), "jpeg", output);
        // Trailing bytes must not survive the pixel-only rewrite.
        output.write("private metadata".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        var cleaned = BusinessProfiles.validated(new BusinessProfile(null, null,
                Base64.getEncoder().encodeToString(output.toByteArray()), null));
        var bytes = Base64.getDecoder().decode(cleaned.photoBase64());
        assertThat(new String(bytes, java.nio.charset.StandardCharsets.ISO_8859_1)).doesNotContain("private metadata");
        assertThat(ImageIO.read(new java.io.ByteArrayInputStream(bytes)).getWidth()).isEqualTo(256);
        output.reset();
        ImageIO.write(new BufferedImage(513, 1, BufferedImage.TYPE_INT_RGB), "jpeg", output);
        assertThatThrownBy(() -> BusinessProfiles.validated(new BusinessProfile(null, null,
                Base64.getEncoder().encodeToString(output.toByteArray()), null))).isInstanceOf(ApiException.class);
    }
    @Test void unsafeLinksAreRejectedWithoutFetchingThem() {
        for (String url : List.of("javascript:alert(1)", "file:///etc/passwd", "http://example.com", "https://127.0.0.1",
                "https://someone:secret@example.com", "https://example.local")) {
            assertThatThrownBy(() -> BusinessProfiles.validated(new BusinessProfile(null, null, null,
                    List.of(new BusinessLink("Website", url))))).isInstanceOf(ApiException.class);
        }
        assertThat(BusinessProfiles.validated(new BusinessProfile(null, null, null,
                List.of(new BusinessLink("Instagram", "https://www.instagram.com/example")))).links()).hasSize(1);
    }
}
