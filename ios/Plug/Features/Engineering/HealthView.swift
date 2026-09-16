import SwiftUI

struct HealthView: View {
    let client: APIClient
    @State private var check: HealthCheck?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("API Status").font(.title2.bold())

                if isLoading {
                    ProgressView("Connecting…")
                } else if let check {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    LabeledContent("Environment", value: check.response.environment)
                    LabeledContent("Service", value: check.response.service)
                    if let id = check.correlationID {
                        LabeledContent("Request ID", value: id).font(.caption).textSelection(.enabled)
                    }
                } else if let errorMessage {
                    Label("Not connected", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                }

                Button("Retry", action: load).buttonStyle(.borderedProminent)
                    .frame(minHeight: 44).disabled(isLoading)
                Spacer()
            }
            .padding()
            .navigationTitle("PLUG")
            .task { await loadHealth() }
        }
    }

    private func load() {
        Task { await loadHealth() }
    }

    @MainActor
    private func loadHealth() async {
        guard !isLoading else { return }
        isLoading = true
        check = nil
        errorMessage = nil
        defer { isLoading = false }
        do { check = try await client.health() }
        catch is CancellationError { return }
        catch {
            print("PLUG HEALTH ERROR:", error)
            print("PLUG HEALTH URL:", client.environment.baseURL as Any)

            errorMessage = """
            \(error.localizedDescription)
            """
        }
    }
}
