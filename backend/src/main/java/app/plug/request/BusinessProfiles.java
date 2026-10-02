package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.request.ProviderPayloads.BusinessLink;
import app.plug.request.ProviderPayloads.BusinessProfile;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.util.Base64;
import javax.imageio.ImageIO;

/** Bounded public thumbnails and provider-supplied links. No server-side URL fetching. */
final class BusinessProfiles {
    private static final ObjectMapper JSON = new ObjectMapper().setPropertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE);
    private BusinessProfiles() {}

    static BusinessProfile validated(BusinessProfile profile) {
        if (profile == null) return null;
        if (profile.links() != null) for (BusinessLink link : profile.links()) {
            try {
                URI uri = URI.create(link.url());
                String host = uri.getHost();
                if (!"https".equals(uri.getScheme()) || host == null || !host.contains(".")
                        || host.endsWith(".local") || host.endsWith(".localhost") || host.contains(":")
                        || host.matches("[0-9.]+") || uri.getRawUserInfo() != null
                        || (uri.getPort() != -1 && uri.getPort() != 443)) throw new IllegalArgumentException();
            } catch (IllegalArgumentException invalid) {
                throw ApiException.validation("business.links", "invalid", "Use a complete public https:// website or social profile link.");
            }
        }
        return new BusinessProfile(clean(profile.name()), clean(profile.about()), photo(profile.photoBase64()), profile.links());
    }

    private static String clean(String value) { return value == null || value.isBlank() ? null : value.strip(); }

    private static String photo(String value) {
        if (value == null) return null;
        try {
            byte[] bytes = Base64.getDecoder().decode(value);
            if (bytes.length > 49152) throw new IllegalArgumentException();
            try (var input = ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))) {
                var readers = ImageIO.getImageReaders(input);
                if (!readers.hasNext()) throw new IllegalArgumentException();
                var reader = readers.next();
                try {
                    reader.setInput(input, true, true);
                    if (!"JPEG".equalsIgnoreCase(reader.getFormatName()) || reader.getWidth(0) > 512
                            || reader.getHeight(0) > 512) throw new IllegalArgumentException();
                    // Decode only after the dimensions are checked; writing pixels drops EXIF/GPS.
                    var image = reader.read(0);
                    var output = new ByteArrayOutputStream();
                    if (!ImageIO.write(image, "jpeg", output) || output.size() > 49152) throw new IllegalArgumentException();
                    return Base64.getEncoder().encodeToString(output.toByteArray());
                } finally { reader.dispose(); }
            }
        } catch (Exception invalid) {
            throw ApiException.validation("business.photo_base64", "invalid", "Choose a JPEG photo up to 512 pixels and 48 KB.");
        }
    }

    static String json(BusinessProfile profile) {
        try { return JSON.writeValueAsString(profile); }
        catch (Exception invalid) { throw new IllegalStateException("business profile encoding"); }
    }
    static BusinessProfile read(String json) {
        try { return json == null ? null : JSON.readValue(json, BusinessProfile.class); }
        catch (Exception invalid) { throw new IllegalStateException("business profile decoding"); }
    }
}
