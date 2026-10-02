import Foundation

@MainActor
protocol RequestServing {
    func create(_ body: CreateServiceRequest, key: String) async throws -> ServiceRequest
    func get(_ id: String) async throws -> ServiceRequest
    func answer(_ id: String, clarificationId: String, value: String, key: String) async throws -> ServiceRequest
    func offers(_ id: String) async throws -> ServiceOfferList
    func cancel(_ id: String) async throws -> ServiceRequest
    // Manual v4 §12A, §12B.
    func ask(_ body: AskBody, key: String) async throws -> AskResult
    func getAsk(_ id: String) async throws -> AskResult
    func answerAsk(_ id: String, clarificationId: String, value: String, key: String) async throws -> AskResult
    func proposeSkills(_ description: String) async throws -> SkillProposal
    func setProvider(_ setup: ProviderSetup) async throws -> ProviderProfile
    func providerProfile() async throws -> ProviderProfile?
}

@MainActor
struct RequestService: RequestServing {
    let client: APIClient
    let sessions: SessionStore
    let userId: String

    private func token() async throws -> String {
        let token = try await sessions.validAccessToken()
        guard await sessions.current()?.account.userId == userId else { throw APIError.signedOut() }
        return token
    }
    private func owned<Response: Decodable>(_ endpoint: Endpoint, as: Response.Type) async throws -> Response {
        let result = try await client.send(endpoint, as: Response.self)
        try Task.checkCancellation()
        guard await sessions.current()?.account.userId == userId else { throw APIError.signedOut() }
        return result
    }
    private func path(_ id: String) throws -> String {
        guard id.range(of: "^req_[A-Za-z0-9-]+$", options: .regularExpression) != nil else {
            throw APIError.contractViolation(requestID: nil)
        }
        return "v1/requests/\(id)"
    }
    func create(_ body: CreateServiceRequest, key: String) async throws -> ServiceRequest {
        var endpoint = try Endpoint.post("v1/requests", body: body, accessToken: await token())
        endpoint.idempotencyKey = key
        return try await owned(endpoint, as: ServiceRequest.self).validated()
    }
    func get(_ id: String) async throws -> ServiceRequest {
        let result = try await owned(Endpoint.get(try path(id), accessToken: await token()), as: ServiceRequest.self).validated()
        guard result.requestId == id else { throw APIError.contractViolation(requestID: nil) }
        return result
    }
    func answer(_ id: String, clarificationId: String, value: String, key: String) async throws -> ServiceRequest {
        struct Answer: Encodable { let clarificationId: String; let value: String }
        var endpoint = try Endpoint.post(try path(id) + "/clarifications",
            body: Answer(clarificationId: clarificationId, value: value), accessToken: await token())
        endpoint.idempotencyKey = key
        let result = try await owned(endpoint, as: ServiceRequest.self).validated()
        guard result.requestId == id else { throw APIError.contractViolation(requestID: nil) }
        return result
    }
    func offers(_ id: String) async throws -> ServiceOfferList {
        var endpoint = Endpoint.get(try path(id) + "/offers", accessToken: try await token())
        // Twenty valid offers can exceed the identity API's original 16 KB bound.
        endpoint.maximumResponseBytes = 2_097_152
        return try await owned(endpoint, as: ServiceOfferList.self).validated(for: id)
    }
    func cancel(_ id: String) async throws -> ServiceRequest {
        let result = try await owned(Endpoint.post(try path(id) + "/cancel", accessToken: await token()), as: ServiceRequest.self).validated()
        guard result.requestId == id, result.status == .canceled else { throw APIError.contractViolation(requestID: nil) }
        return result
    }
    private func askPath(_ id: String) throws -> String {
        guard id.range(of: "^ask_[A-Za-z0-9-]+$", options: .regularExpression) != nil else {
            throw APIError.contractViolation(requestID: nil)
        }
        return "v1/asks/\(id)"
    }
    func ask(_ body: AskBody, key: String) async throws -> AskResult {
        var endpoint = try Endpoint.post("v1/asks", body: body, accessToken: await token())
        endpoint.idempotencyKey = key
        return try await owned(endpoint, as: AskResult.self).validated()
    }
    func getAsk(_ id: String) async throws -> AskResult {
        let result = try await owned(Endpoint.get(try askPath(id), accessToken: await token()), as: AskResult.self).validated()
        guard result.askId == id else { throw APIError.contractViolation(requestID: nil) }
        return result
    }
    func answerAsk(_ id: String, clarificationId: String, value: String, key: String) async throws -> AskResult {
        struct Answer: Encodable { let clarificationId: String; let value: String }
        var endpoint = try Endpoint.post(try askPath(id) + "/clarifications",
            body: Answer(clarificationId: clarificationId, value: value), accessToken: await token())
        endpoint.idempotencyKey = key
        let result = try await owned(endpoint, as: AskResult.self).validated()
        guard result.askId == id else { throw APIError.contractViolation(requestID: nil) }
        return result
    }
    func proposeSkills(_ description: String) async throws -> SkillProposal {
        struct Body: Encodable { let description: String }
        return try await owned(try Endpoint.post("v1/providers/skills/propose", body: Body(description: description),
            accessToken: await token()), as: SkillProposal.self)
    }
    func setProvider(_ setup: ProviderSetup) async throws -> ProviderProfile {
        var endpoint = try Endpoint.post("v1/providers/skills", body: setup, accessToken: await token())
        endpoint.maximumResponseBytes = 98_304
        return try await owned(endpoint, as: ProviderProfile.self)
    }
    /// Nil when the caller has not offered a service yet (the server answers 404).
    func providerProfile() async throws -> ProviderProfile? {
        var endpoint = Endpoint.get("v1/providers/me", accessToken: try await token())
        endpoint.maximumResponseBytes = 98_304
        do { return try await owned(endpoint, as: ProviderProfile.self) }
        catch let error as APIError where error.code == "not_found" { return nil }
    }
}
