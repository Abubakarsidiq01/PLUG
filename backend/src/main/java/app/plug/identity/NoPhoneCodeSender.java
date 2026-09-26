package app.plug.identity;

// The default everywhere, including staging, until Phase 3 connects the messaging
// provider. Saying so through dependency_unavailable is the honest answer; returning a
// challenge for a message that will never arrive is not.
class NoPhoneCodeSender implements PhoneCodeSender {
    @Override
    public void send(String phoneNumber, String code) {
        throw new UnsupportedOperationException("No code delivery channel is configured.");
    }

    @Override
    public boolean isAvailable() {
        return false;
    }
}
