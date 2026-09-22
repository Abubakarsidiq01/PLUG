package app.plug.identity;

// How a one-time code reaches a phone. The messaging provider is Phase 3 work, so this is
// the seam it will arrive through, and nothing above it has to change when it does.
//
// There is no implementation that writes a code to the application log, in any
// environment. A code in a log is a credential in a log, and manual.docx 19.9 forbids it
// without an exception for convenience.
interface PhoneCodeSender {
    void send(String phoneNumber, String code);

    // Answered before a challenge is created. An environment with no channel says so with
    // dependency_unavailable rather than storing a code nobody will ever receive.
    boolean isAvailable();
}
