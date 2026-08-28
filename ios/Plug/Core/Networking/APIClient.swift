import Foundation

struct HealthResponse: Decodable, Equatable {
    let status: String
    let service: String
    let environment: String
}

struct APIClient {
    let environment: AppEnvironment
    var session: URLSession = .shared

    func health() async throws -> HealthResponse {
        let url = environment.baseURL.appending(path: "health")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }
}
