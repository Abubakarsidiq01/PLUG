package app.plug.identity;

import jakarta.servlet.http.HttpServletRequest;

// The network identity a rate limit counts against, reduced to a prefix before it is used
// or recorded. A full address is personal data (manual.docx 25.1); a prefix is enough to
// stop one network from exhausting a limit and is what the audit trail keeps.
//
// The address comes from the connection, never from a header a caller controls. A caller
// can write any X-Forwarded-For it likes, and trusting one turns every per-address limit into
// a suggestion. The one exception is a proxy listed in plug.identity.trusted-proxies (the
// staff console's server, ADR-013), whose own last hop is believed.
final class CallerAddress {
    private CallerAddress() {}

    // Proxies allowed to say whose request they are passing on (plug.identity.trusted-proxies),
    // such as the staff console's web server. Empty by default: nobody is trusted.
    private static volatile java.util.Set<String> trustedProxies = java.util.Set.of();

    static void trust(java.util.Collection<String> proxies) {
        trustedProxies = java.util.Set.copyOf(proxies);
    }

    static String prefixOf(HttpServletRequest request) {
        String address = request.getRemoteAddr();
        // Only a listed proxy's X-Forwarded-For counts, and only its last entry: the address
        // that proxy itself saw. Anything earlier in the header came from the caller.
        String forwarded = request.getHeader("X-Forwarded-For");
        if (address != null && trustedProxies.contains(address) && forwarded != null && !forwarded.isBlank()) {
            String[] hops = forwarded.split(",");
            String last = hops[hops.length - 1].strip();
            if (last.matches("[0-9A-Fa-f.:]{2,45}")) address = last;
        }
        if (address == null || address.isBlank()) {
            return "unknown";
        }
        if (address.indexOf(':') >= 0) {
            // IPv6: keep the first three groups, roughly the site a caller was given.
            String[] groups = address.split(":");
            return String.join(":", java.util.Arrays.copyOf(groups, Math.min(3, groups.length))) + "::/48";
        }
        int lastDot = address.lastIndexOf('.');
        return lastDot < 0 ? address : address.substring(0, lastDot) + ".0/24";
    }
}
