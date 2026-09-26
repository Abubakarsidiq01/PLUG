package app.plug.identity;

import jakarta.servlet.http.HttpServletRequest;

// The network identity a rate limit counts against, reduced to a prefix before it is used
// or recorded. A full address is personal data (manual.docx 25.1); a prefix is enough to
// stop one network from exhausting a limit and is what the audit trail keeps.
//
// The address comes from the connection, never from a header. A caller can write any
// X-Forwarded-For it likes, and trusting one turns every per-address limit into a
// suggestion. Real ingress restrictions belong at the load balancer.
final class CallerAddress {
    private CallerAddress() {}

    static String prefixOf(HttpServletRequest request) {
        String address = request.getRemoteAddr();
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
