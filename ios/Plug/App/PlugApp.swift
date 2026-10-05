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
    @State private var provider: ProviderProfile?
    @State private var selectedTab = "Ask"
    @ObservedObject var model: AuthenticationModel
    let environment: AppEnvironment

    var body: some View {
        Group {
            switch model.state {
            case .signedIn(let session):
                signedIn(session)
            default:
                WelcomeView(model: model, environment: environment)
                    // Reset while signed out, so every sign-in starts on Ask and nothing changes
                    // the tab after the person has started using the app.
                    .onAppear { selectedTab = "Ask" }
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
        let requests = RequestService(client: APIClient(environment: environment),
                                      sessions: model.sessions, userId: session.account.userId)
        // The system tab bar is hidden from inside each tab, where SwiftUI applies it; hidden on the
        // TabView itself it stayed in the layout and kept taking taps at the bottom of every page.
        // Each tab reserves the custom bar's height, so nothing scrolls out of reach beneath it.
        return TabView(selection: $selectedTab) {
            Group {
                if environment.requestsEnabled {
                    AskView(service: requests) { provider = $0 }
                        .id(session.account.userId)
                } else {
                    foundationPage("Ask", detail: "Request intake is not enabled in this environment.")
                }
            }
            .plugTab("Ask", bar: navigationBar)
            if environment.requestsEnabled, let provider {
                InboxView(service: requests, profile: provider) { self.provider = $0 }
                    .plugTab("Inbox", bar: navigationBar)
            }
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Activity").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        VStack(alignment: .leading, spacing: 20) {
                            FlowEmblem(symbol: "clock.arrow.circlepath", size: 88)
                            Text("Your asks, in one place")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text("Your active ask is on the Ask tab. Past requests aren’t shown here yet.")
                                .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                            Button("Go to Ask") { selectedTab = "Ask" }
                                .buttonStyle(FlowActionStyle(primary: true))
                        }.marketCard()
                    }
                    .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
                    .padding(.horizontal, 16).padding(.vertical, 24)
                }.background(PlugTokens.Color.paper)
                .toolbar(.hidden, for: .navigationBar)
            }
            .plugTab("Activity", bar: navigationBar)
            ProfileView(model: model, session: session, environment: environment)
                .plugTab("Profile", bar: navigationBar)
        }
        .tint(PlugColor.brand)
        .task(id: session.account.userId) {
            provider = nil
            guard environment.requestsEnabled else { return }
            provider = try? await requests.providerProfile()
        }
    }

    /// The only bottom navigation. Pages get its height as safe area, so nothing scrolls under it.
    private var navigationBar: some View {
        HStack(spacing: 0) {
            navigationItem("Ask", symbol: "square.grid.2x2", selectedSymbol: "square.grid.2x2.fill")
            if environment.requestsEnabled, provider != nil {
                navigationItem("Inbox", symbol: "bubble.left.and.bubble.right", selectedSymbol: "bubble.left.and.bubble.right.fill")
            }
            navigationItem("Activity", symbol: "clock", selectedSymbol: "clock.fill")
            navigationItem("Profile", symbol: "person.crop.circle", selectedSymbol: "person.crop.circle.fill")
        }
        .padding(.top, 10).padding(.bottom, 4)
        // Down to the screen edge, so nothing shows through beside the home indicator.
        .background(PlugTokens.Color.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { PlugTokens.Color.rule200.frame(height: 0.5) }
    }

    private func navigationItem(_ title: String, symbol: String, selectedSymbol: String) -> some View {
        Button { selectedTab = title } label: {
            VStack(spacing: 5) {
                Image(systemName: selectedTab == title ? selectedSymbol : symbol)
                    .font(.system(size: 22, weight: .medium)).frame(height: 26)
                Text(title).font(.system(.caption2, weight: selectedTab == title ? .bold : .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(selectedTab == title ? PlugTokens.Color.ink900 : PlugTokens.Color.ink600)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: symbol) }
        .accessibilityLabel(title)
        .accessibilityIdentifier("navigation-" + title.lowercased())
        .accessibilityAddTraits(selectedTab == title ? .isSelected : [])
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
enum PlugNavigationBar {
    /// Bar height (48 pt items, 10 + 4 pt padding) at its largest capped label size, plus a gap.
    static let reserved: CGFloat = 96
}

private extension View {
    /// One page of the bottom navigation: no system tab bar, the custom bar along the bottom, and
    /// a bottom margin on every scroll view in the tab (pushed pages included) so its last control
    /// can always scroll clear of the bar. A safe-area inset applied here did not reach scroll
    /// views inside the tab's navigation stack on iOS 26.
    func plugTab<Bar: View>(_ name: String, bar: Bar) -> some View {
        toolbar(.hidden, for: .tabBar)
            .contentMargins(.bottom, PlugNavigationBar.reserved, for: .scrollContent)
            .contentMargins(.bottom, PlugNavigationBar.reserved, for: .scrollIndicators)
            // Like a system tab bar, it stays behind the keyboard instead of riding up over the field.
            .overlay(alignment: .bottom) { bar.ignoresSafeArea(.keyboard, edges: .bottom) }
            .tag(name)
    }
}

struct ProfileView: View {
    @ObservedObject var model: AuthenticationModel
    let session: Session
    let environment: AppEnvironment

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Profile").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 56, weight: .light)).accessibilityHidden(true)
                        Text("Your corner of PLUG")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(session.account.isGuest ? "Exploring as a guest" : "Your account, your connections")
                            .plugText(.body).opacity(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    .foregroundStyle(PlugTokens.Color.card)
                    .background(PlugTokens.Color.ink900, in: RoundedRectangle(cornerRadius: 28))
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Account", systemImage: "person.crop.square").font(.system(.title3, design: .rounded, weight: .bold))
                        detailRow("Signed in with", description(of: session.account.type))
                        detailRow("Terms accepted", session.consent.acceptedVersion ?? "Not yet")
                    }.marketCard()
                    if session.account.isGuest {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Make yourself at home", systemImage: "house")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                            Text("Create an account to keep your guest requests. Signing in to an existing account switches "
                                 + "accounts; guest activity is not merged into that account.")
                                .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                            Button("Create account or sign in") { model.startOver() }
                                .buttonStyle(FlowActionStyle(primary: true))
                        }.marketCard()
                    }
                    #if DEBUG
                    NavigationLink { HealthView(client: APIClient(environment: environment)) } label: {
                        HStack {
                            Label("Developer tools", systemImage: "wrench.and.screwdriver")
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                        }.plugText(.body).marketCard()
                    }.buttonStyle(.plain)
                    #endif
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                        .buttonStyle(FlowActionStyle(destructive: true))
                        .accessibilityHint("Ends this session on PLUG's servers as well as on this device")
                }
                .foregroundStyle(PlugTokens.Color.ink900)
                .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.vertical, 24)
            }
            .background(PlugTokens.Color.paper)
            .toolbar(.hidden, for: .navigationBar)
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
