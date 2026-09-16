import Foundation
import OSLog

struct HealthResponse: Decodable, Equatable {
    let status: String
    let service: String
    let environment: String
}

struct APIClient {
    let environment: AppEnvironment
    var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    func health() async throws -> HealthCheck {
        guard let baseURL = environment.baseURL else { throw URLError(.badURL) }
        var request = URLRequest(url: baseURL.appending(path: "health"))
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, Self.isJSON(http) else {
            throw URLError(.badServerResponse)
        }
        guard data.count <= 16_384 else { throw URLError(.dataLengthExceedsMaximum) }
        let health = try JSONDecoder().decode(HealthResponse.self, from: data)
        guard health.status == "ok", health.service == "plug-api", !health.environment.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        let suppliedID = http.value(forHTTPHeaderField: "X-Correlation-ID")
        let correlationID = suppliedID.flatMap { value in
            value.count <= 80 && value.range(of: "^corr_[A-Za-z0-9-]+$", options: .regularExpression) != nil ? value : nil
        }
        if let correlationID {
            Logger(subsystem: "com.plug.app", category: "Networking")
                .info("health_check correlation_id=\(correlationID, privacy: .public)")
        }
        return HealthCheck(response: health, correlationID: correlationID)
    }

    private static func isJSON(_ response: HTTPURLResponse) -> Bool {
        let value = response.value(forHTTPHeaderField: "Content-Type") ?? response.mimeType ?? ""
        let type = value.split(separator: ";", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces).lowercased()
        return type == "application/json"
    }
}

struct HealthCheck {
    let response: HealthResponse
    let correlationID: String?
}
