import SwiftUI

@main
struct PlugApp: App {
    private let environment: AppEnvironment
    @StateObject private var authentication: AuthenticationModel

    init() {
        let environment = AppEnvironment.configured
        let client = APIClient(environment: environment)
        self.environment = environment
        _authentication = StateObject(wrappedValue: AuthenticationModel(
            client: client, sessions: SessionStore(client: client)))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: authentication, environment: environment)
        }
    }
}

/// Nothing in the app is reachable before the session question is answered. A signed-out
/// person sees the welcome screen; a signed-in one sees the product. Keeping that decision
/// in one place is what stops a screen from being reachable without a session later.
struct RootView: View {
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
        .task { await model.restore() }
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
            Text(detail).foregroundStyle(.secondary).padding(PlugSpacing.large)
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
                    LabeledContent("Signed in with", value: description(of: session.account.type))
                    LabeledContent("Terms accepted", value: session.consent.acceptedVersion ?? "Not yet")
                }
                if session.account.isGuest {
                    Section("Guest account") {
                        Text("You are browsing as a guest. Sign in with Apple or your phone number to keep "
                             + "your requests if you change device — nothing you have started will be lost.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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

    private func description(of type: Account.AccountType) -> String {
        switch type {
        case .apple: return "Apple"
        case .phone: return "Phone number"
        case .guest: return "Guest"
        }
    }
}
