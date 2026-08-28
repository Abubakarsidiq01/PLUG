import SwiftUI

@main
struct PlugApp: App {
    var body: some Scene {
        WindowGroup {
            HealthView(client: APIClient(environment: .local))
        }
    }
}
