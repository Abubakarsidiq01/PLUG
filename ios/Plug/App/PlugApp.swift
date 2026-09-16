import SwiftUI

@main
struct PlugApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                foundationPage("Ask", detail: "Request intake will be connected in Phase 2.")
                    .tabItem { Label("Ask", systemImage: "magnifyingglass") }
                foundationPage("Activity", detail: "Your requests will appear here once request history is implemented.")
                    .tabItem { Label("Activity", systemImage: "clock") }
                foundationPage("Contribute", detail: "Scout contributions will be available in Phase 4.")
                    .tabItem { Label("Contribute", systemImage: "plus.circle") }
                foundationPage("Profile", detail: "Account settings will be connected after identity and consent.")
                    .tabItem { Label("Profile", systemImage: "person") }
                HealthView(client: APIClient(environment: .configured))
                    .tabItem { Label("Engineering", systemImage: "wrench") }
            }
            .tint(PlugColor.brand)
        }
    }

    private func foundationPage(_ title: String, detail: String) -> some View {
        NavigationStack {
            Text(detail).foregroundStyle(.secondary).padding(PlugSpacing.large)
                .navigationTitle(title)
        }
    }
}
