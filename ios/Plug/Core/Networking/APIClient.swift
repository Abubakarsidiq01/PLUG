import Foundation
import OSLog

struct HealthResponse: Decodable, Equatable {
    let status: String
    let version: String
    let commit: String?
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

    private static let maximumBytes = 16_384

    func health() async throws -> HealthCheck {
        let (http, data) = try await perform(try request(method: "GET", path: "health"), expectingBody: true)
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let health = try JSONDecoder().decode(HealthResponse.self, from: data)
        guard health.status == "UP", !health.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return HealthCheck(response: health, correlationID: correlationID(of: http))
    }

    /// Every call other than the health probe goes through here. The bounded read, the
    /// content-type check and the correlation logging are written once, so a route added
    /// later cannot quietly skip one of them.
    ///
    /// A non-2xx becomes an APIError carrying the server's stable error code, because the
    /// screens branch on that code and never on the status alone.
    func send<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type) async throws -> Response {
        let (http, data) = try await perform(try request(for: endpoint), expectingBody: true)
        let requestID = correlationID(of: http)
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, body: data, requestID: requestID)
        }
        do {
            return try PlugJSON.decoder.decode(Response.self, from: data)
        } catch {
            // A response that does not match the contract is a server problem, reported
            // with the request id so it can be found in the backend log rather than
            // guessed at from the device.
            throw APIError.contractViolation(requestID: requestID)
        }
    }

    /// For the routes that answer 204. Kept separate so no caller has to invent a type to
    /// decode an empty body into.
    func sendExpectingNoContent(_ endpoint: Endpoint) async throws {
        let (http, data) = try await perform(try request(for: endpoint), expectingBody: false)
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, body: data, requestID: correlationID(of: http))
        }
    }

    private func request(for endpoint: Endpoint) throws -> URLRequest {
        var built = try request(method: endpoint.method, path: endpoint.path)
        if let body = endpoint.body {
            built.httpBody = body
            built.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken = endpoint.accessToken {
            built.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return built
    }

    private func request(method: String, path: String) throws -> URLRequest {
        guard let baseURL = environment.baseURL else { throw URLError(.badURL) }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Bounds the download while it arrives. Checking Data.count after data(for:) has
    /// already buffered an arbitrarily large response is too late.
    private func perform(_ request: URLRequest, expectingBody: Bool) async throws -> (HTTPURLResponse, Data) {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 204 {
            return (http, Data())
        }
        guard Self.isJSON(http) else { throw URLError(.badServerResponse) }
        guard response.expectedContentLength <= Int64(Self.maximumBytes) else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        if expectingBody && data.isEmpty { throw URLError(.cannotParseResponse) }
        return (http, data)
    }

    /// The server's request id goes into the device log too. This is the mechanic that
    /// makes the connected checkpoint possible: one identifier, found in both logs.
    /// It is validated before it is logged, because it arrives from the network.
    private func correlationID(of http: HTTPURLResponse) -> String? {
        let supplied = http.value(forHTTPHeaderField: "X-Request-Id")
        let correlationID = supplied.flatMap { value in
            value.count <= 64 && value.range(of: "\\A[A-Za-z0-9_-]+\\z", options: .regularExpression) != nil
                ? value : nil
        }
        if let correlationID {
            Logger(subsystem: "app.plug", category: "Networking")
                .info("api_response request_id=\(correlationID, privacy: .public)")
        }
        return correlationID
    }

    private static func isJSON(_ response: HTTPURLResponse) -> Bool {
        let value = response.value(forHTTPHeaderField: "Content-Type") ?? response.mimeType ?? ""
        let type = value.split(separator: ";", maxSplits: 1).first
            .map(String.init)?.trimmingCharacters(in: .whitespaces).lowercased()
        return type == "application/json"
    }
}

struct HealthCheck {
    let response: HealthResponse
    let correlationID: String?
}
