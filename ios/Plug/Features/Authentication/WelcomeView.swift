import AuthenticationServices
import SwiftUI

/// Welcome, sign in and create account are one screen, because on this product they are
/// one decision: how you want to be known. Every state from the matrix in manual.docx 12
/// is a case below, so none of them can be left out without the build failing.
struct WelcomeView: View {
    @ObservedObject var model: AuthenticationModel
    let environment: AppEnvironment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nonce = SignInNonce()
    @State private var phoneNumber = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugSpacing.large) {
                    header
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PlugSpacing.large)
            }
            .navigationTitle("PLUG")
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.state)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PlugSpacing.small) {
            Text("Ask for what you need nearby.")
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text("Sign in so your requests stay with you, or look around as a guest first.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .signedOut:
            signInChoices
        case .working(let step):
            StateMessage(title: title(for: step), detail: "This takes a moment.", systemImage: "hourglass")
                .accessibilityLabel(title(for: step))
        case .awaitingCode(let challengeID, let expiresAt, let attemptsRemaining):
            codeEntry(challengeID: challengeID, expiresAt: expiresAt,
                      attemptsRemaining: attemptsRemaining, problem: nil)
        case .codeRejected(let challengeID, let reason):
            codeEntry(challengeID: challengeID, expiresAt: nil, attemptsRemaining: nil, problem: reason)
        case .consentRequired:
            consentUpdate
        case .signedIn:
            StateMessage(title: "You are signed in.", detail: "Your requests will stay with this account.",
                         systemImage: "checkmark.circle")
        case .failed(let message, let canRetry):
            StateMessage(title: "That did not work", detail: message, systemImage: "exclamationmark.triangle")
            if canRetry { startOverButton("Try again") }
        case .offline(let retryPreserved):
            StateMessage(title: "You are offline",
                         detail: retryPreserved
                            ? "Nothing was lost. We will pick up where you left off once you are back online."
                            : "Reconnect and try again.",
                         systemImage: "wifi.slash")
            startOverButton("Try again")
        case .rateLimited(let retryAfterSeconds):
            StateMessage(title: "Too many attempts",
                         detail: "Wait about \(max(1, retryAfterSeconds / 60)) minutes, then try again.",
                         systemImage: "clock")
            startOverButton("Start over")
        case .unavailable(let message):
            // The message names the paths that still work, so this is not a dead end.
            StateMessage(title: "Codes are unavailable", detail: message, systemImage: "message.badge.circle")
            signInChoices
        case .accountLinkConflict(let message):
            StateMessage(title: "That account already exists", detail: message, systemImage: "person.badge.key")
            startOverButton("Choose another way to sign in")
        case .notificationsDenied:
            // Notifications are declined, not sign-in. The manual path is still open, which
            // is the difference between a permission state and a dead end.
            StateMessage(title: "Notifications are off",
                         detail: "You can still ask for what you need and check back in the app for replies.",
                         systemImage: "bell.slash")
            signInChoices
        }
    }

    private var signInChoices: some View {
        VStack(alignment: .leading, spacing: PlugSpacing.medium) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
                // Apple receives the digest; the raw value goes to PLUG's server, which
                // hashes it and compares. That is what binds the token to this attempt.
                request.nonce = nonce.hashedForApple
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 44)
            .accessibilityHint("Signs you in with your Apple Account")

            phoneEntry

            Button("Continue as guest") {
                Task { await model.continueAsGuest() }
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityHint("Look around without an account. You can sign in later and keep your requests.")

            ConsentNotice(environment: environment)
        }
    }

    private var phoneEntry: some View {
        VStack(alignment: .leading, spacing: PlugSpacing.small) {
            Text("Or use your phone number").font(.subheadline.weight(.semibold))
            PlugTextField(title: "Phone number, including country code", text: $phoneNumber)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
            PlugPrimaryButton(title: "Send me a code") {
                Task { await model.sendCode(to: phoneNumber.trimmingCharacters(in: .whitespaces)) }
            }
            .disabled(phoneNumber.trimmingCharacters(in: .whitespaces).count < 8)
        }
    }

    private func codeEntry(challengeID: String, expiresAt: Date?, attemptsRemaining: Int?,
                           problem: AuthenticationState.CodeRejection?) -> some View {
        CodeEntryView(challengeID: challengeID, expiresAt: expiresAt, attemptsRemaining: attemptsRemaining,
                      problem: problem, environment: environment,
                      onSubmit: { code in Task { await model.verifyCode(code, challengeID: challengeID) } },
                      onStartOver: { model.startOver() })
    }

    private var consentUpdate: some View {
        VStack(alignment: .leading, spacing: PlugSpacing.medium) {
            StateMessage(title: "Our Terms have been updated",
                         detail: "Please review them before you continue.",
                         systemImage: "doc.text")
            ConsentNotice(environment: environment)
            PlugPrimaryButton(title: "I agree") {
                Task { await model.acceptConsent() }
            }
        }
    }

    private func startOverButton(_ title: String) -> some View {
        Button(title) { model.startOver() }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            // A cancelled sign-in is not a failure to report. Anything else that leaves us
            // without a token is reported as a retryable problem rather than a silent stop.
            if case .failure(let error) = result,
               (error as? ASAuthorizationError)?.code == .canceled {
                return
            }
            model.startOver()
            return
        }
        let raw = nonce.raw
        // A fresh nonce for the next attempt, so one cannot be reused across two sign-ins.
        nonce = SignInNonce()
        Task { await model.signInWithApple(identityToken: identityToken, rawNonce: raw) }
    }

    private func title(for step: AuthenticationState.SignInStep) -> String {
        switch step {
        case .apple: return "Signing you in with Apple"
        case .guest: return "Setting up a guest account"
        case .sendingCode: return "Sending your code"
        case .checkingCode: return "Checking your code"
        case .restoring: return "Checking your session"
        }
    }
}

/// A named state with one explanation and, where there is one, one action. The layout is
/// the same in every state so the screen does not jump as it moves between them.
struct StateMessage: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: PlugSpacing.small) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .labelStyle(.titleAndIcon)
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
