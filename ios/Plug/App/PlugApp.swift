import SwiftUI
import GoogleSignIn

@main
struct PlugApp: App {
    private let environment: AppEnvironment
    @StateObject private var authentication: AuthenticationModel

    init() {
        let environment = AppEnvironment.configured
        let client = APIClient(environment: environment)
        PlugApp.resetStoredSessionIfUITesting()
        self.environment = environment
        _authentication = StateObject(wrappedValue: AuthenticationModel(
            client: client, sessions: SessionStore(client: client)))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: authentication, environment: environment)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }

    /// Lets the screenshot tests start from a signed-out app every time, instead of from
    /// whatever the previous run left in the Keychain. Debug-only and driven by a launch
    /// argument, so there is no path to it in a shipping build.
    private static func resetStoredSessionIfUITesting() {
        #if DEBUG
        guard CommandLine.arguments.contains("-plug-ui-test-reset") else { return }
        try? KeychainStore().delete(account: SessionStore.account)
        #endif
    }
}

/// Nothing in the app is reachable before the session question is answered. A signed-out
/// person sees the welcome screen; a signed-in one sees the product. Keeping that decision
/// in one place is what stops a screen from being reachable without a session later.
struct RootView: View {
    @State private var hasRestored = false
    @ObservedObject var model: AuthenticationModel
    let environment: AppEnvironment

    var body: some View {
        Group {
            switch model.state {
            case .signedIn(let session):
                signedIn(session)
            default:
                WelcomeView(model: model, environment: environment)
            }
        }
        .tint(PlugColor.brand)
        .task {
            guard !hasRestored else { return }
            hasRestored = true
            await model.restore()
        }
    }

    private func signedIn(_ session: Session) -> some View {
        TabView {
            foundationPage("Ask", detail: "Request intake will be connected in Phase 2.")
                .tabItem { Label("Ask", systemImage: "magnifyingglass") }
            foundationPage("Activity", detail: "Your requests will appear here once request history is implemented.")
                .tabItem { Label("Activity", systemImage: "clock") }
            foundationPage("Contribute", detail: "Scout contributions will be available in Phase 4.")
                .tabItem { Label("Contribute", systemImage: "plus.circle") }
            ProfileView(model: model, session: session)
                .tabItem { Label("Profile", systemImage: "person") }
            HealthView(client: APIClient(environment: environment))
                .tabItem { Label("Engineering", systemImage: "wrench") }
        }
        .tint(PlugColor.brand)
    }

    private func foundationPage(_ title: String, detail: String) -> some View {
        NavigationStack {
            ScrollView {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(PlugSpacing.large)
            }
            .navigationTitle(title)
        }
    }
}

/// What the account is, and the way out of it. A guest is told plainly what a guest is and
/// offered the upgrade, because a limit nobody can see is a limit that feels like a bug.
struct ProfileView: View {
    @ObservedObject var model: AuthenticationModel
    let session: Session

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    detailRow("Signed in with", description(of: session.account.type))
                    detailRow("Terms accepted", session.consent.acceptedVersion ?? "Not yet")
                }
                if session.account.isGuest {
                    Section("Guest account") {
                        Text("Create an account to keep your guest requests. Signing in to an existing account switches "
                             + "accounts; guest activity is not merged into that account.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Create account or sign in") { model.startOver() }
                            .frame(minHeight: 44)
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await model.signOut() }
                    }
                    .frame(minHeight: 44)
                    .accessibilityHint("Ends this session on PLUG's servers as well as on this device")
                }
            }
            .navigationTitle("Profile")
        }
    }

    /// A label and its value, side by side while that fits and stacked when it does not.
    /// At the largest Dynamic Type size a side-by-side row leaves too little width for
    /// either half, and the value ends up clipped — which is the failure §20.3 means by
    /// "no fixed heights on text containers": let the layout grow instead.
    private func detailRow(_ label: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            LabeledContent(label, value: value)
            VStack(alignment: .leading, spacing: PlugSpacing.small / 2) {
                Text(label).foregroundStyle(.secondary)
                Text(value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }

    private func description(of type: Account.AccountType) -> String {
        switch type {
        case .apple: return "Apple"
        case .google: return "Google"
        case .phone: return "Phone number"
        case .guest: return "Guest"
        }
    }
}
