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
                .overlay { LaunchSplash() }
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

/// The cold start: it begins where the static launch screen ends (the espresso mark on cream)
/// and fades away quickly. It never takes a touch or VoiceOver focus, and it does not run for UI
/// tests or under Reduce Motion (the launch screen then simply gives way to the app).
private struct LaunchSplash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showing = !ProcessInfo.processInfo.arguments.contains("-plug-ui-test-reset")
    @State private var faded = false
    /// The launch image's point size: plug-mark.svg has a 256-unit viewBox and no width.
    private static let markSize = PlugTokens.Layout.launchMark

    var body: some View {
        ZStack {
            if showing && !reduceMotion {
                PlugTokens.Color.paper
                PlugMark().frame(width: Self.markSize, height: Self.markSize)
            }
        }
        .opacity(faded ? 0 : 1)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard showing, !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(PlugTokens.Motion.slow))
            withAnimation(.easeOut(duration: PlugTokens.Motion.reveal)) { faded = true }
            try? await Task.sleep(for: .seconds(PlugTokens.Motion.reveal))
            showing = false
        }
    }
}

/// Nothing in the app is reachable before the session question is answered. A signed-out
/// person sees the welcome screen; a signed-in one sees the product. Keeping that decision
/// in one place is what stops a screen from being reachable without a session later.
struct RootView: View {
    @State private var hasRestored = false
    @State private var provider: ProviderProfile?
    @State private var selectedTab = "Ask"
    // Fixed like a system tab bar; its labels are capped and use the large-content viewer.
    private var tabGlyph: CGFloat { PlugTokens.Layout.tabIcon - 2 }
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
        // Every colour is a fixed palette value; the app is drawn light whatever the system says.
        .preferredColorScheme(.light)
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
            .plugTab("Ask")
            if environment.requestsEnabled, let provider {
                InboxView(service: requests, profile: provider) { self.provider = $0 }
                    .plugTab("Inbox")
            }
            ActivityView { select("Ask") }
                .plugTab("Activity")
            ProfileView(model: model, session: session, environment: environment)
                .plugTab("Profile")
        }
        // One bar over every tab, so the selected key can travel between items.
        .overlay(alignment: .bottom) { navigationBar.ignoresSafeArea(.keyboard, edges: .bottom) }
        .tint(PlugColor.brand)
        .task(id: session.account.userId) {
            provider = nil
            guard environment.requestsEnabled else { return }
            provider = try? await requests.providerProfile()
        }
    }

    private func select(_ tab: String) { selectedTab = tab }

    /// The only bottom navigation: a cream bar with a top hairline across the full width, like
    /// the system tab bar. The selected tab is forest green under a short brass line; the others
    /// are the muted brown.
    private var navigationBar: some View {
        VStack(spacing: 0) {
            PlugDivider()
            HStack(spacing: 0) {
                navigationItem("Ask", symbol: "magnifyingglass")
                navigationItem("Activity", symbol: "list.bullet")
                if environment.requestsEnabled, provider != nil {
                    navigationItem("Inbox", symbol: "tray")
                }
                navigationItem("Profile", symbol: "person")
            }
            .padding(.horizontal, PlugTokens.Space.s2)
            .padding(.top, PlugTokens.Space.s1)
        }
        .background(PlugTokens.Color.paper.ignoresSafeArea(edges: .bottom))
    }

    private func navigationItem(_ title: String, symbol: String) -> some View {
        let selected = selectedTab == title
        return Button { select(title) } label: {
            VStack(spacing: 3) {
                Image(systemName: selected ? symbol + (symbol == "magnifyingglass" || symbol == "list.bullet" ? "" : ".fill") : symbol)
                    .font(.system(size: tabGlyph, weight: selected ? .medium : .regular)).frame(height: tabGlyph + PlugTokens.Space.s1)
                Text(title).font(.system(size: PlugTokens.TypeSize.caption - 1, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: PlugShape.buttonHeight - 4)
            // ink.400 is under 4.5:1 on cream, so unselected labels use ink.600.
            .foregroundStyle(selected ? PlugTokens.Color.brandGreen : PlugTokens.Color.ink600)
            .overlay(alignment: .top) {
                PlugTokens.Color.brandBrass.frame(width: PlugTokens.Space.s6, height: 2)
                    .offset(y: -PlugTokens.Space.s1)
                    .opacity(selected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: symbol) }
        .accessibilityLabel(title)
        .accessibilityIdentifier("navigation-" + title.lowercased())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func foundationPage(_ title: String, detail: String) -> some View {
        NavigationStack {
            ScrollView {
                Text(detail)
                    .foregroundStyle(PlugTokens.Color.ink600)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(PlugSpacing.large)
            }
            .navigationTitle(title)
        }
    }
}

enum PlugNavigationBar {
    /// Bar height (48 pt items, hairline, top padding) plus a gap.
    static let reserved: CGFloat = PlugTokens.Layout.tabReserve
}

private extension View {
    /// One page of the bottom navigation: no system tab bar, and a bottom margin on every scroll
    /// view in the tab (pushed pages included) so its last control can always scroll clear of the
    /// bar. A safe-area inset applied here did not reach scroll views inside the tab's navigation
    /// stack on iOS 26.
    func plugTab(_ name: String) -> some View {
        toolbar(.hidden, for: .tabBar)
            .contentMargins(.bottom, PlugNavigationBar.reserved, for: .scrollContent)
            .contentMargins(.bottom, PlugNavigationBar.reserved, for: .scrollIndicators)
            .tag(name)
    }
}

/// A serif page title.
struct PageTitle: View {
    let title: String
    var body: some View {
        Text(title).plugText(.hero).accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Activity shows only what exists: until past asks are listed, it points to the live one.
private struct ActivityView: View {
    let goToAsk: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    PageTitle(title: "Activity")
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
                        IllustrationTile(name: "IllActivity", size: 88)
                        Text("Your asks, in one place")
                            .plugText(.title)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Your active ask is on the Ask tab. Past requests aren’t shown here yet.")
                            .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Go to Ask", action: goToAsk)
                            .buttonStyle(FlowActionStyle(primary: true))
                            .padding(.top, PlugTokens.Space.s2)
                    }
                }
                .foregroundStyle(PlugTokens.Color.ink900)
                .frame(maxWidth: PlugTokens.Layout.measure, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, PlugTokens.Space.s6).padding(.vertical, PlugTokens.Space.s4)
            }
            .background(PlugTokens.Color.paper)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// What the account is, and the way out of it. A guest is told plainly what a guest is and
/// offered the upgrade, because a limit nobody can see is a limit that feels like a bug.
struct ProfileView: View {
    @ObservedObject var model: AuthenticationModel
    let session: Session
    let environment: AppEnvironment

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    PageTitle(title: "Profile")
                    HStack(alignment: .center, spacing: PlugTokens.Space.s4) {
                        PlugMark(ink: PlugTokens.Color.paper, dot: PlugTokens.Color.paper)
                            .padding(PlugTokens.Space.s4 + 2)
                            .frame(width: PlugTokens.Layout.portrait, height: PlugTokens.Layout.portrait)
                            .background(PlugTokens.Color.brandGreen, in: Circle())
                        VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                            Text("Your corner of PLUG")
                                .plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(session.account.isGuest ? "Exploring as a guest" : "Signed in")
                                .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                        }
                    }
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                        Text("Account").plugText(.title2).padding(.bottom, PlugTokens.Space.s1)
                        PlugDivider()
                        detailRow("Signed in with", description(of: session.account.type))
                        PlugDivider()
                        detailRow("Terms accepted", session.consent.acceptedVersion ?? "Not yet")
                        PlugDivider()
                    }
                    if session.account.isGuest {
                        VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
                            Text("Make yourself at home")
                                .plugText(.title)
                            Text("Create an account to keep your guest requests. Signing in to an existing account switches "
                                 + "accounts; guest activity is not merged into that account.")
                                .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Create account or sign in") { model.startOver() }
                                .buttonStyle(FlowActionStyle(primary: true))
                        }
                        .foregroundStyle(PlugTokens.Color.ink900)
                        .plugCard(PlugTokens.Color.sunk)
                    }
                    #if DEBUG
                    NavigationLink { HealthView(client: APIClient(environment: environment)) } label: {
                        HStack {
                            Label("Developer tools", systemImage: "wrench.and.screwdriver.fill")
                            Spacer(minLength: PlugTokens.Space.s2)
                            Image(systemName: "chevron.right").fontWeight(.medium)
                        }.plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                        .padding(.vertical, PlugTokens.Space.s3)
                        .overlay(alignment: .bottom) { PlugDivider() }
                    }.buttonStyle(PlugPressStyle())
                    #endif
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                        .buttonStyle(FlowActionStyle(destructive: true))
                        .accessibilityHint("Ends this session on PLUG's servers as well as on this device")
                }
                .foregroundStyle(PlugTokens.Color.ink900)
                .frame(maxWidth: PlugTokens.Layout.measure, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, PlugTokens.Space.s6).padding(.vertical, PlugTokens.Space.s4)
            }
            .background(PlugTokens.Color.paper)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// A label and its value, side by side while that fits and stacked when it does not, so
    /// the value is never clipped at the largest Dynamic Type size.
    private func detailRow(_ label: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            // Both sides keep their full width here, so a row that does not fit stacks instead of
            // truncating.
            HStack(alignment: .firstTextBaseline) {
                Text(label).plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: PlugTokens.Space.s2)
                Text(value).plugText(.body).fontWeight(.medium).foregroundStyle(PlugTokens.Color.ink900)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: PlugSpacing.small / 2) {
                Text(label).plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                Text(value).plugText(.title3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, PlugTokens.Space.s2)
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
