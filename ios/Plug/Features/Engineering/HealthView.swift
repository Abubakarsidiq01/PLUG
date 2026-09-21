import SwiftUI

struct HealthView: View {
    let client: APIClient
    @State private var check: HealthCheck?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var retryTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("API Status").font(.title2.bold())

                    if isLoading {
                        ProgressView("Connecting…")
                    } else if let check {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        LabeledContent("Version", value: check.response.version)
                        if let commit = check.response.commit {
                            LabeledContent("Commit", value: commit)
                        }
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .navigationTitle("PLUG")
            .task { await loadHealth() }
            .onDisappear { retryTask?.cancel() }
        }
    }

    private func load() {
        retryTask?.cancel()
        retryTask = Task { await loadHealth() }
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
        catch let error as URLError where error.code == .cancelled { return }
        catch {
            errorMessage = HealthFailure.message(for: error)
        }
    }
}

enum HealthFailure {
    static func message(for error: Error) -> String {
        guard let urlError = error as? URLError else {
            return "The server returned an invalid response. Please try again."
        }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "Check your internet connection, then try again."
        case .timedOut:
            return "The connection timed out. Please try again."
        case .badURL:
            return "The API address is not configured correctly."
        case .badServerResponse, .cannotParseResponse, .dataLengthExceedsMaximum:
            return "The server returned an invalid response. Please try again."
        default:
            return "The server could not be reached. Please try again."
        }
    }
}
