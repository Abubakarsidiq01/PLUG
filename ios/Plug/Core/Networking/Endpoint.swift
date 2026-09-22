import Foundation

/// One request, described rather than assembled at the call site. Keeping the access token
/// on the endpoint means a route that needs authentication says so in one place, and a
/// route that must stay anonymous — the sign-in routes — cannot pick one up by accident.
struct Endpoint {
    let method: String
    let path: String
    let body: Data?
    let accessToken: String?

    static func get(_ path: String, accessToken: String? = nil) -> Endpoint {
        Endpoint(method: "GET", path: path, body: nil, accessToken: accessToken)
    }

    static func delete(_ path: String, accessToken: String? = nil) -> Endpoint {
        Endpoint(method: "DELETE", path: path, body: nil, accessToken: accessToken)
    }

    static func post<Body: Encodable>(_ path: String, body: Body,
                                      accessToken: String? = nil) throws -> Endpoint {
        return Endpoint(method: "POST", path: path, body: try PlugJSON.encoder.encode(body),
                        accessToken: accessToken)
    }

    static func post(_ path: String, accessToken: String? = nil) -> Endpoint {
        Endpoint(method: "POST", path: path, body: nil, accessToken: accessToken)
    }
}
