import AuthenticationServices
import SwiftUI
import GoogleSignIn

/// Separate method selection, verification and recovery; one model owns the session.
struct WelcomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: AuthenticationModel
    let environment: AppEnvironment

    private enum Page: Hashable { case welcome, signIn, signUp, phone, recovery, phoneRecovery, googleRecovery, appleRecovery }
    @State private var page: Page = .welcome
    @State private var creatingAccount = false
    @State private var googlePending = false
    @State private var nonce = SignInNonce()
    @State private var phoneNumber = ""

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    if page != .welcome { navigation }
                    if isMethodSelection { Spacer(minLength: PlugTokens.Space.s8) }
                    if page == .welcome {
                        Spacer(minLength: PlugTokens.Space.s8)
                        header
                    }
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s6) { content }
                        .disabled(googlePending)
                        .frame(maxWidth: isMethodSelection ? PlugTokens.Space.s16 * 5 : .infinity, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer(minLength: PlugTokens.Space.s6)
                    ConsentNotice(environment: environment)
                }
                .padding(.horizontal, PlugTokens.Space.s4)
                .padding(.vertical, PlugTokens.Space.s6)
                .frame(maxWidth: AuthLayout.contentWidth)
                .frame(minHeight: viewport.size.height, alignment: .top)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .id(page)
        }
        .background(PlugTokens.Color.surface0.ignoresSafeArea())
        .foregroundStyle(PlugTokens.Color.ink900)
        .buttonStyle(AuthActionStyle())
        .preferredColorScheme(.light)
        .animation(reduceMotion ? nil : .easeOut(duration: PlugTokens.Motion.base), value: page)
    }

    private var isMethodSelection: Bool { page == .signIn || page == .signUp }

    private var navigation: some View {
        HStack {
            Button { page = .welcome; model.startOver() } label: {
                Image(systemName: "chevron.left").font(.body.weight(.medium))
                    .frame(width: PlugTokens.minTouchTarget, height: PlugTokens.minTouchTarget)
            }
            .buttonStyle(.plain).accessibilityLabel("Back to welcome")
            Spacer()
            Button { page = .welcome; model.startOver() } label: { PlugWordmark() }
                .buttonStyle(.plain).accessibilityLabel("PLUG home")
            Spacer()
            Color.clear.frame(width: PlugTokens.minTouchTarget, height: PlugTokens.minTouchTarget)
                .accessibilityHidden(true)
        }
        .disabled(googlePending || model.isWorking)
        .frame(minHeight: PlugTokens.minTouchTarget)
    }

    private var appleEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "PlugAppleSignInEnabled") as? String) == "YES"
    }

    private var phoneEnabled: Bool {
        #if DEBUG
        if CommandLine.arguments.contains("-plug-ui-test-reset") {
            return ProcessInfo.processInfo.environment["PLUG_PHONE_SIGN_IN_ENABLED"] == "YES"
        }
        #endif
        return (Bundle.main.object(forInfoDictionaryKey: "PlugPhoneSignInEnabled") as? String) == "YES"
    }

    private var header: some View {
        VStack(spacing: PlugTokens.Space.s6) {
            Image("PlugMark").resizable().scaledToFit()
                .frame(width: PlugTokens.Space.s16, height: PlugTokens.Space.s16 + PlugTokens.Space.s4)
                .accessibilityHidden(true)
            Text("PLUG").plugText(.title).accessibilityAddTraits(.isHeader)
            Text("Real-time truth.\nBetter local decisions.")
                .plugText(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(PlugTokens.Color.ink600)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Image("Neighbourhood").resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .signedOut:
            selectedPage
        case .working(let step):
            ProgressView(title(for: step))
                .frame(maxWidth: .infinity, minHeight: PlugTokens.Space.s16 + PlugTokens.Space.s8)
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
            if canRetry { retryButton }
            if page != .welcome { backToMethods }
        case .offline(let retryPreserved):
            StateMessage(title: "You are offline",
                         detail: retryPreserved
                            ? "Nothing was lost. We will pick up where you left off once you are back online."
                            : "Reconnect and try again.",
                         systemImage: "wifi.slash")
            retryButton
        case .rateLimited(let retryAfterSeconds):
            StateMessage(title: "Too many attempts",
                         detail: "Wait about \(max(1, retryAfterSeconds / 60)) minutes, then try again.",
                         systemImage: "clock")
            startOverButton("Start over")
        case .unavailable(let message):
            // The message names the paths that still work, so this is not a dead end.
            StateMessage(title: "Sign-in is unavailable",
                         detail: page == .phone ? "Text-message sign-in is unavailable. Choose another method." : message,
                         systemImage: "message.badge.circle")
            selectedPage
        case .accountExists:
            StateMessage(title: "You already have an account",
                         detail: "Sign in with the same method to access your PLUG account.",
                         systemImage: "person.crop.circle")
            Button("Sign in") { creatingAccount = false; page = .signIn; model.startOver() }
                .buttonStyle(AuthActionStyle(primary: true))
        case .accountNotFound:
            StateMessage(title: "Create an account first",
                         detail: "This sign-in method is not connected to a PLUG account yet.",
                         systemImage: "person.crop.circle")
            Button("Create account") { creatingAccount = true; page = .signUp; model.startOver() }
                .buttonStyle(AuthActionStyle(primary: true))
        case .accountLinkConflict(let message):
            StateMessage(title: "That account already exists", detail: message, systemImage: "person.badge.key")
            startOverButton("Choose another way to sign in")
        case .notificationsDenied:
            // Notifications are declined, not sign-in. The manual path is still open, which
            // is the difference between a permission state and a dead end.
            StateMessage(title: "Notifications are off",
                         detail: "You can still ask for what you need and check back in the app for replies.",
                         systemImage: "bell.slash")
            selectedPage
        }
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch page {
        case .welcome:
            VStack(spacing: PlugTokens.Space.s3) {
                Button("Get started") { creatingAccount = true; page = .signUp }
                    .buttonStyle(AuthActionStyle(primary: true))
                Button("I have an account") { creatingAccount = false; page = .signIn }
                    .buttonStyle(.plain).plugText(.action)
                    .foregroundStyle(PlugTokens.Color.brand600)
                    .frame(maxWidth: .infinity, minHeight: PlugTokens.minTouchTarget)
                Button("Continue as guest") { Task { await model.continueAsGuest() } }
                    .buttonStyle(.plain).foregroundStyle(PlugTokens.Color.ink600)
                    .plugText(.body)
                    .frame(maxWidth: .infinity, minHeight: PlugTokens.minTouchTarget)
            }
        case .signIn, .signUp:
            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                Text(creatingAccount ? "Create your account" : "Welcome back").plugText(.title)
                Text(creatingAccount ? "Choose how you’d like to create your account." : "Use the method linked to your PLUG account.")
                    .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            providerChoices
            if !creatingAccount {
                Button("Trouble signing in?") { page = .recovery }
                    .buttonStyle(.plain).plugText(.body).foregroundStyle(PlugColor.brand)
                    .frame(maxWidth: .infinity, minHeight: PlugTokens.minTouchTarget)
            }
            Rectangle().fill(PlugTokens.Color.line200).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PlugTokens.Space.s2) { accountSwitch }
                VStack(spacing: PlugTokens.Space.s1) { accountSwitch }
            }
            .frame(maxWidth: .infinity)
        case .phone:
            if phoneEnabled {
                phoneEntry
            } else {
                StateMessage(title: "Phone sign-in is not available yet",
                             detail: "Text-message verification is being set up. You can use Google now, or continue as a guest from the welcome page.",
                             systemImage: "message")
            }
            backToMethods
        case .recovery:
            Text("How did you sign in?").plugText(.title)
            Button("Phone number") { page = .phoneRecovery }
            Button("Google") { page = .googleRecovery }
            Button("Apple") { page = .appleRecovery }
            backToMethods
        case .phoneRecovery:
            Text("Get a new sign-in code").plugText(.title)
            Text("Phone accounts do not use a password. Verify the same number with a new text message. If you lost that number, contact your mobile provider to recover it first.")
            if phoneEnabled {
                PlugPrimaryButton(title: "Continue with phone") { page = .phone }
            } else {
                Text("Text message sign-in is currently unavailable.").foregroundStyle(PlugTokens.Color.ink600)
            }
            backToMethods
        case .googleRecovery:
            Text("Recover your Google account").plugText(.title)
            Text("Your password is managed by Google. Recover it with Google, then return and choose Continue with Google.")
            if let url = URL(string: "https://accounts.google.com/signin/recovery") {
                Link("Open Google account recovery", destination: url)
            }
            backToMethods
        case .appleRecovery:
            Text("Recover your Apple Account").plugText(.title)
            Text("Your password is managed by Apple. Recover it with Apple, then return and sign in with Apple.")
            if let url = URL(string: "https://iforgot.apple.com") {
                Link("Open Apple account recovery", destination: url)
            }
            backToMethods
        }
    }

    private var accountSwitch: some View {
        Group {
            Text(creatingAccount ? "Already have an account?" : "New to PLUG?")
                .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
            Button(creatingAccount ? "Sign in" : "Create account") {
                creatingAccount.toggle()
                page = creatingAccount ? .signUp : .signIn
            }
            .buttonStyle(.plain).plugText(.action).foregroundStyle(PlugColor.brand)
            .frame(minHeight: PlugTokens.minTouchTarget)
        }
        .fixedSize()
    }

    private var backToMethods: some View {
        Button("Other sign-in methods") { page = creatingAccount ? .signUp : .signIn; model.startOver() }
            .buttonStyle(.plain).font(.subheadline).foregroundStyle(PlugColor.brand)
            .frame(maxWidth: .infinity, minHeight: PlugTokens.minTouchTarget)
    }

    private var providerChoices: some View {
        VStack(spacing: PlugTokens.Space.s3) {
            Button { Task { await handleGoogle() } } label: {
                HStack(spacing: PlugTokens.Space.s3) {
                    if let icon = Self.googleIcon {
                        Image(uiImage: icon).resizable().scaledToFit().frame(width: PlugTokens.Space.s6, height: PlugTokens.Space.s6)
                            .accessibilityHidden(true)
                    }
                    if googlePending { ProgressView().controlSize(.small) }
                    Text(creatingAccount ? "Sign up with Google" : "Sign in with Google")
                        .plugText(.action)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("googleAuthButton")
            if appleEnabled {
                SignInWithAppleButton(creatingAccount ? .signUp : .signIn) { request in
                    request.requestedScopes = [.fullName]
                    request.nonce = nonce.hashedForApple
                } onCompletion: { result in handleApple(result) }
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: .infinity).frame(height: PlugTokens.Space.s12)
                .clipShape(RoundedRectangle(cornerRadius: PlugTokens.Radius.md))
            }
            Button { page = .phone } label: {
                HStack(spacing: PlugTokens.Space.s3) {
                    Image(systemName: "phone").accessibilityHidden(true)
                    Text("Continue with phone").plugText(.action)
                }
                .frame(maxWidth: .infinity)
            }
            if !phoneEnabled {
                Text("Phone verification is not available yet.")
                    .plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // Reuse Google's unmodified bundled brand image; no remote image/font loading.
    private static let googleIcon: UIImage? = {
        guard let path = Bundle.main.path(forResource: "GoogleSignIn_GoogleSignIn", ofType: "bundle"),
              let bundle = Bundle(path: path) else { return nil }
        return UIImage(named: "google", in: bundle, compatibleWith: nil)
    }()

    @MainActor
    private func handleGoogle() async {
        guard !googlePending else { return }
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              let serverID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String,
              clientID.hasSuffix(".apps.googleusercontent.com"),
              serverID.hasSuffix(".apps.googleusercontent.com") else {
            model.providerFailed("Google sign-in is not available yet. Please choose another sign-in method.")
            return
        }
        let reversedID = clientID.split(separator: ".").reversed().joined(separator: ".")
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        guard urlTypes.contains(where: { ($0["CFBundleURLSchemes"] as? [String])?.contains(reversedID) == true }) else {
            model.providerFailed("Google sign-in is not available yet. Please choose another sign-in method.")
            return
        }
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        googlePending = true
        defer { googlePending = false }
        let attempt = SignInNonce()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID, serverClientID: serverID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: attempt.raw)
            guard let token = result.user.idToken?.tokenString else {
                model.providerFailed("Google did not complete sign-in. Please try again.")
                return
            }
            await model.signInWithGoogle(identityToken: token, nonce: attempt.raw, creatingAccount: creatingAccount)
            GIDSignIn.sharedInstance.signOut()
        } catch {
            if (error as NSError).code != GIDSignInError.canceled.rawValue {
                model.providerFailed("Google sign-in could not finish. Please try again.")
            }
        }
    }

    private var phoneEntry: some View {
        VStack(alignment: .leading, spacing: PlugSpacing.small) {
            Text(creatingAccount ? "Sign up with your phone" : "Sign in with your phone").font(.subheadline.weight(.semibold))
            PlugTextField(title: "Phone number, including country code", text: $phoneNumber)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
            Text("Include + and your country code, such as +1 312 555 0123 or +234 803 123 4567. We will text you a six-digit code; no password is needed.")
                .font(.footnote).foregroundStyle(PlugTokens.Color.ink600)
            PlugPrimaryButton(title: "Send me a code") {
                Task { await model.sendCode(to: phoneNumber.trimmingCharacters(in: .whitespaces)) }
            }
            .disabled(AuthenticationModel.normalizedPhone(phoneNumber) == nil)
        }
    }

    private func codeEntry(challengeID: String, expiresAt: Date?, attemptsRemaining: Int?,
                           problem: AuthenticationState.CodeRejection?) -> some View {
        CodeEntryView(challengeID: challengeID, expiresAt: expiresAt, attemptsRemaining: attemptsRemaining,
                      problem: problem, environment: environment,
                      onSubmit: { code in Task { await model.verifyCode(code, challengeID: challengeID, creatingAccount: creatingAccount) } },
                      onStartOver: { page = .phone; model.startOver() },
                      onResend: { Task { await model.sendCode(to: phoneNumber) } })
    }

    private var consentUpdate: some View {
        VStack(alignment: .leading, spacing: PlugSpacing.medium) {
            StateMessage(title: "Our Terms have been updated",
                         detail: "Please review them before you continue.",
                         systemImage: "doc.text")
            Text("Review the notices below before continuing.").foregroundStyle(PlugTokens.Color.ink600)
            PlugPrimaryButton(title: "I agree") {
                Task { await model.acceptConsent() }
            }
        }
    }

    private func startOverButton(_ title: String) -> some View {
        Button(title) { model.startOver() }
            .buttonStyle(AuthActionStyle())
            .frame(minHeight: PlugTokens.minTouchTarget)
    }

    private var retryButton: some View {
        Button("Try again") {
            if page == .welcome { Task { await model.retry() } }
            else { model.startOver() }
        }
            .buttonStyle(AuthActionStyle())
            .frame(minHeight: PlugTokens.minTouchTarget)
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
            model.providerFailed("Apple sign-in could not finish. Please try again or choose another method.")
            return
        }
        let raw = nonce.raw
        // A fresh nonce for the next attempt, so one cannot be reused across two sign-ins.
        nonce = SignInNonce()
        Task { await model.signInWithApple(identityToken: identityToken, rawNonce: raw, creatingAccount: creatingAccount) }
    }

    private func title(for step: AuthenticationState.SignInStep) -> String {
        switch step {
        case .google: return "Signing you in with Google"
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
                .foregroundStyle(PlugTokens.Color.ink600)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
