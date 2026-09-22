package app.plug.identity;

// Lets a test find the row behind a token it holds. Sessions are looked up by the hash of
// their access token, and a test asserting on one particular session has to identify it
// the same way the service does rather than assuming the newest row is the right one.
final class TestTokens {
    private TestTokens() {}

    static String hashOf(String accessToken) {
        return Secrets.hashToken(accessToken);
    }
}
