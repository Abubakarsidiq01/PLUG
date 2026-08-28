import SwiftUI

struct HealthView: View {
    let client: APIClient
    @State private var response: HealthResponse?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("API Status").font(.title2.bold())

                if isLoading {
                    ProgressView("Connecting…")
                } else if let response {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    LabeledContent("Environment", value: response.environment)
                    LabeledContent("Service", value: response.service)
                } else if let errorMessage {
                    Label("Not connected", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                }

                Button("Retry", action: load).buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
            .navigationTitle("PLUG")
            .task { load() }
        }
    }

    private func load() {
        isLoading = true
        errorMessage = nil
        Task {
            do { response = try await client.health() }
            catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }
}
