import XCTest
@testable import Plug

@MainActor
final class RequestTests: XCTestCase {
    private let location = RequestLocation(latitude: 32.528, longitude: -92.714, precision: .coarse)

    override func tearDown() { TestTransport.handler = nil; super.tearDown() }

    func testEverySharedRequestFixtureDecodesAndSatisfiesStateInvariants() throws {
        var checked = 0
        for folder in ["requests.create", "requests.get", "requests.clarify", "requests.cancel", "requests.offers"] {
            let directory = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(folder))
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                let data = try Data(contentsOf: url)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                if json["error"] != nil { continue }
                if folder == "requests.offers" {
                    let offers = try PlugJSON.decoder.decode(ServiceOfferList.self, from: data)
                    _ = try offers.validated(for: offers.requestId)
                } else {
                    _ = try PlugJSON.decoder.decode(ServiceRequest.self, from: data).validated()
                }
                checked += 1
            }
        }
        XCTAssertEqual(checked, 20)
    }

    func testEveryAskAndProviderFixtureDecodesAndValidates() throws {
        var checked = 0
        for folder in ["asks.create", "asks.get", "asks.clarify", "providers.propose", "providers.skills", "providers.me"] {
            let directory = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(folder))
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                let data = try Data(contentsOf: url)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                if json["error"] != nil { continue }
                switch folder {
                case "providers.propose": _ = try PlugJSON.decoder.decode(SkillProposal.self, from: data)
                case "providers.skills", "providers.me":
                    let profile = try PlugJSON.decoder.decode(ProviderProfile.self, from: data)
                    XCTAssertTrue(profile.score.isValid)
                default: _ = try PlugJSON.decoder.decode(AskResult.self, from: data).validated()
                }
                checked += 1
            }
        }
        XCTAssertEqual(checked, 9)
    }

    func testWebAnswerCannotBePromotedAboveNotVerified() throws {
        var json = try object("asks.create", "place-question")
        var place = try XCTUnwrap(json["place_question"] as? [String: Any])
        place["web_answer"] = ["headline": "Usually busy", "summary": "Pattern", "source_name": "Example",
                               "retrieved_at": "2026-05-01T12:00:00Z", "truth_label": "confirmed"]
        json["place_question"] = place
        let result = try PlugJSON.decoder.decode(AskResult.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try result.validated())
    }

    func testAskingPlaceQuestionPollsWithoutInventingAnswers() async throws {
        let service = StubRequests()
        var json = try object("asks.create", "place-question")
        var place = try XCTUnwrap(json["place_question"] as? [String: Any])
        place["status"] = "asking"
        place["answer"] = NSNull()
        json["place_question"] = place
        let asking = try PlugJSON.decoder.decode(AskResult.self, from: JSONSerialization.data(withJSONObject: json))
        service.onAsk = { _, _ in asking }
        var interval: Int?
        let model = RequestModel(service: service, sleep: { value in interval = value; throw CancellationError() })
        model.text = "How long is the line at Walmart right now?"
        await model.submit(location: location)
        while interval == nil { await Task.yield() }
        XCTAssertEqual(interval, RequestModel.placePollSeconds)
        XCTAssertNil(model.request)
        XCTAssertNil(model.placeQuestion?.answer)
        model.setActive(false)
    }

    func testActivePlaceAskSurvivesBackAndCannotBeReplaced() async throws {
        let service = StubRequests()
        var json = try object("asks.create", "place-question")
        var place = try XCTUnwrap(json["place_question"] as? [String: Any])
        place["status"] = "asking"
        place["answer"] = NSNull()
        json["place_question"] = place
        let result = try PlugJSON.decoder.decode(AskResult.self, from: JSONSerialization.data(withJSONObject: json))
        var submissions = 0
        service.onAsk = { _, _ in submissions += 1; return result }
        let model = RequestModel(service: service)
        model.setActive(false)
        model.text = "Is the DMV busy?"
        await model.submit(location: location)
        XCTAssertTrue(model.hasActiveAsk)
        model.startAgain()
        XCTAssertEqual(model.askId, result.askId)
        model.text = "A different ask"
        await model.submit(location: location)
        XCTAssertEqual(submissions, 1)
        await model.refresh() // Offline place reads must label the saved snapshot.
        XCTAssertTrue(model.isCached)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.placeQuestion, result.placeQuestion)
    }

    func testMalformedPlaceProgressCannotBecomeVisible() throws {
        for counts in [["notified": 2, "opened": -1, "answered": 0],
                       ["notified": 2, "opened": 1, "answered": -1],
                       ["notified": 2, "opened": 1, "answered": 3]] {
            var json = try object("asks.create", "place-question")
            var place = try XCTUnwrap(json["place_question"] as? [String: Any])
            place["progress"] = counts
            json["place_question"] = place
            let result = try PlugJSON.decoder.decode(AskResult.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertThrowsError(try result.validated())
        }
    }

    func testAskServicePostsToAsksWithIdempotencyHeader() async throws {
        let data = try fixture("asks.create", "service-request")
        TestTransport.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/asks")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "ask-key")
            return (try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 201,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])), data)
        }
        let service = try await liveService()
        let result = try await service.ask(AskBody(text: "Barber", location: location), key: "ask-key")
        XCTAssertEqual(result.askType, .serviceRequest)
    }

    func testMissingProviderProfileIsNotAnError() async throws {
        let data = try fixture("providers.me", "not-a-provider")
        TestTransport.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/providers/me")
            return (try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 404,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])), data)
        }
        let service = try await liveService()
        let profile = try await service.providerProfile()
        XCTAssertNil(profile)
    }

    func testMalformedServerProgressAndNextActionFailClosed() throws {
        var json = try object("requests.get", "submitted")
        json["progress"] = ["contacted": 1, "replied": 2, "offers_ready": 1]
        XCTAssertThrowsError(try decode(json).validated())
        json = try object("requests.get", "submitted")
        json["next_action"] = "choose_offer"
        XCTAssertThrowsError(try decode(json).validated())
        json["next_action"] = "future_action"
        XCTAssertThrowsError(try decode(json))
    }

    func testSeedCannotBePromotedToConfirmed() throws {
        var json = try object("requests.offers", "success")
        var offers = try XCTUnwrap(json["offers"] as? [[String: Any]])
        offers[0]["truth_label"] = "confirmed"
        json["offers"] = offers
        let decoded = try PlugJSON.decoder.decode(ServiceOfferList.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try decoded.validated(for: decoded.requestId))
    }

    func testRetryAfterLostCreateResponseReusesIdenticalBodyAndKey() async throws {
        let service = StubRequests()
        var bodies: [CreateServiceRequest] = []
        var keys: [String] = []
        let result = try resource("requests.create", "success")
        service.onCreate = { body, key in
            bodies.append(body); keys.append(key)
            if keys.count == 1 { throw URLError(.networkConnectionLost) }
            return result
        }
        let model = RequestModel(service: service)
        model.setActive(false)
        model.text = "Barber under $35"
        await model.submit(location: location)
        XCTAssertNil(model.request)
        XCTAssertEqual(model.text, "Barber under $35")
        XCTAssertNotNil(model.errorMessage)
        await model.submit(location: location)
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies[0], bodies[1])
        XCTAssertEqual(keys[0], keys[1])
        XCTAssertEqual(model.request?.requestId, result.requestId)
    }

    func testChangedInputGetsNewIdempotencyKey() async throws {
        let service = StubRequests()
        var keys: [String] = []
        service.onCreate = { _, key in keys.append(key); throw URLError(.notConnectedToInternet) }
        let model = RequestModel(service: service)
        model.text = "Barber"
        await model.submit(location: location)
        model.text = "Beauty"
        await model.submit(location: location)
        XCTAssertEqual(keys.count, 2)
        XCTAssertNotEqual(keys[0], keys[1])
    }

    func testSameWordsAfterStoppingCreateANewAsk() async throws {
        let service = StubRequests()
        let submitted = try resource("requests.get", "submitted")
        let canceled = try resource("requests.get", "canceled")
        var keys: [String] = []
        service.onCreate = { _, key in keys.append(key); return submitted }
        service.onCancel = { _ in canceled }
        let model = RequestModel(service: service)
        model.setActive(false)
        model.text = "Barber"
        await model.submit(location: location)
        await model.cancel()
        XCTAssertFalse(model.hasActiveAsk)
        await model.submit(location: location)
        XCTAssertEqual(keys.count, 2)
        XCTAssertNotEqual(keys.first, keys.last)
        XCTAssertTrue(model.hasActiveAsk)
    }

    func testBusinessDetailsRoundTripAndUnsafeLinksStayInert() throws {
        let business = BusinessProfile(name: "Studio B", about: "Cuts", links: [
            BusinessLink(label: "Website", url: "https://example.com/work")])
        let data = try PlugJSON.encoder.encode(business)
        XCTAssertEqual(try PlugJSON.decoder.decode(BusinessProfile.self, from: data), business)
        XCTAssertNil(BusinessLink(label: "Bad", url: "javascript:alert(1)").destination)
        XCTAssertNil(BusinessLink(label: "Bad", url: "https://user:secret@example.com").destination)
        XCTAssertNotNil(business.links?.first?.destination)
    }

    func testLatePollCannotUndoCancellation() async throws {
        let service = StubRequests()
        let submitted = try resource("requests.get", "submitted")
        let canceled = try resource("requests.get", "canceled")
        service.onCreate = { _, _ in submitted }
        service.onCancel = { _ in canceled }
        var continuation: CheckedContinuation<ServiceRequest, Error>?
        service.onGet = { _ in try await withCheckedThrowingContinuation { continuation = $0 } }
        let model = RequestModel(service: service)
        model.setActive(false)
        model.text = "Barber"
        await model.submit(location: location)
        let refresh = Task { await model.refresh() }
        while continuation == nil { await Task.yield() }
        await model.cancel()
        continuation?.resume(returning: submitted)
        await refresh.value
        XCTAssertEqual(model.request?.status, .canceled)
        XCTAssertEqual(model.request?.nextAction, ServiceRequest.NextAction.none)
        XCTAssertFalse(model.isWorking)
    }

    func testCancellationFailureKeepsCanonicalState() async throws {
        let service = StubRequests()
        let submitted = try resource("requests.get", "submitted")
        service.onCreate = { _, _ in submitted }
        service.onCancel = { _ in throw URLError(.notConnectedToInternet) }
        let model = RequestModel(service: service)
        model.setActive(false)
        model.text = "Barber"
        await model.submit(location: location)
        await model.cancel()
        XCTAssertEqual(model.request?.status, .submitted)
        XCTAssertTrue(model.isCached)
        XCTAssertNotNil(model.errorMessage)
    }

    func testOfflineRefreshRetainsOffersAndMarksSnapshotCached() async throws {
        let service = StubRequests()
        let ranked = try resource("requests.get", "success")
        let offers = try offerList()
        service.onCreate = { _, _ in ranked }
        service.onOffers = { _ in offers }
        service.onGet = { _ in throw URLError(.notConnectedToInternet) }
        let model = RequestModel(service: service)
        model.setActive(false)
        model.text = "Barber"
        await model.submit(location: location)
        await model.refresh()
        XCTAssertEqual(model.offers, offers.offers)
        XCTAssertTrue(model.isCached)
    }

    func testSessionRevocationClearsPrivateSnapshot() async throws {
        let service = StubRequests()
        let submitted = try resource("requests.get", "submitted")
        service.onCreate = { _, _ in submitted }
        service.onGet = { _ in throw APIError.signedOut() }
        let model = RequestModel(service: service)
        model.setActive(false)
        model.text = "Barber"
        await model.submit(location: location)
        await model.refresh()
        XCTAssertNil(model.request)
        XCTAssertTrue(model.offers.isEmpty)
    }

    func testClarificationRetriesSameOptionWithSameKey() async throws {
        let service = StubRequests()
        let draft = try resource("requests.get", "draft")
        service.onCreate = { _, _ in draft }
        var keys: [String] = []
        service.onAnswer = { _, _, _, key in keys.append(key); throw URLError(.networkConnectionLost) }
        let model = RequestModel(service: service)
        model.setActive(false)
        model.text = "Fresh cut and nails"
        await model.submit(location: location)
        await model.answer("barber")
        await model.answer("barber")
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys.first, keys.last)
        XCTAssertEqual(model.request?.clarification, draft.clarification)
    }

    func testPollingUsesServerIntervalWithoutInventingProgress() async throws {
        let service = StubRequests()
        let submitted = try resource("requests.get", "submitted")
        service.onCreate = { _, _ in submitted }
        var interval: Int?
        let model = RequestModel(service: service, sleep: { value in interval = value; throw CancellationError() })
        model.text = "Barber"
        await model.submit(location: location)
        while interval == nil { await Task.yield() }
        XCTAssertEqual(interval, submitted.pollAfterSeconds)
        XCTAssertEqual(model.request?.progress, submitted.progress)
        model.setActive(false)
    }

    func testClientValidationStopsWhitespaceOversizeAndInvalidLocation() async {
        let service = StubRequests()
        service.onCreate = { _, _ in XCTFail("Invalid input must not reach transport"); throw CancellationError() }
        let model = RequestModel(service: service)
        model.text = " \n "
        await model.submit(location: location)
        XCTAssertNotNil(model.textError)
        model.text = String(repeating: "a", count: 501)
        await model.submit(location: location)
        XCTAssertNotNil(model.textError)
        model.text = "Barber"
        await model.submit(location: RequestLocation(latitude: .nan, longitude: 0, precision: .coarse))
        XCTAssertNotNil(model.errorMessage)
    }

    func testRequestServiceSendsAuthenticationAndIdempotencyHeader() async throws {
        let data = try fixture("requests.create", "success")
        TestTransport.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/requests")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "stable-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer pat_test")
            return (try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 201,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])), data)
        }
        let service = try await liveService()
        _ = try await service.create(CreateServiceRequest(text: "Barber", location: location), key: "stable-key")
    }

    func testServiceRefusesDifferentAccountBeforeNetworkCall() async throws {
        let service = try await liveService(userId: "usr_someone-else")
        TestTransport.handler = { _ in XCTFail("Must not send another account's token"); throw CancellationError() }
        do {
            _ = try await service.create(CreateServiceRequest(text: "Barber", location: location), key: "key")
            XCTFail("Should reject changed account")
        } catch let error as APIError { XCTAssertEqual(error.code, "unauthenticated") }
    }

    func testOfferPayloadMayExceedIdentityResponseBoundButRemainsBounded() async throws {
        var json = try object("requests.offers", "success")
        let original = try XCTUnwrap((json["offers"] as? [[String: Any]])?.first)
        json["offers"] = (0..<20).map { index -> [String: Any] in
            var offer = original
            offer["offer_id"] = "off_\(index)"
            var place = (offer["place"] as? [String: Any]) ?? [:]
            place["address"] = String(repeating: "A", count: 200)
            place["name"] = String(repeating: "B", count: 120)
            offer["place"] = place
            offer["service_name"] = String(repeating: "C", count: 80)
            return offer
        }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        XCTAssertGreaterThan(data.count, 16_384)
        TestTransport.handler = { request in
            (try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])), data)
        }
        let service = try await liveService()
        let list = try await service.offers(try XCTUnwrap(json["request_id"] as? String))
        XCTAssertEqual(list.offers.count, 20)
    }

    private func liveService(userId: String? = nil) async throws -> RequestService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestTransport.self]
        let client = APIClient(environment: .local, session: URLSession(configuration: configuration))
        let sessions = SessionStore(client: client, credentials: InMemoryCredentialStore())
        let session = TestSessions.make(accessExpiresIn: 900, refreshExpiresIn: 86_400)
        try await sessions.adopt(session)
        return RequestService(client: client, sessions: sessions, userId: userId ?? session.account.userId)
    }
    private func fixture(_ folder: String, _ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: folder)))
    }
    private func resource(_ folder: String, _ name: String) throws -> ServiceRequest {
        try PlugJSON.decoder.decode(ServiceRequest.self, from: fixture(folder, name))
    }
    private func object(_ folder: String, _ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: fixture(folder, name)) as? [String: Any])
    }
    private func decode(_ json: [String: Any]) throws -> ServiceRequest {
        try PlugJSON.decoder.decode(ServiceRequest.self, from: JSONSerialization.data(withJSONObject: json))
    }
    private func offerList() throws -> ServiceOfferList {
        try PlugJSON.decoder.decode(ServiceOfferList.self, from: fixture("requests.offers", "success"))
    }
}

@MainActor
private final class StubRequests: RequestServing {
    var onCreate: ((CreateServiceRequest, String) async throws -> ServiceRequest)?
    var onGet: ((String) async throws -> ServiceRequest)?
    var onAnswer: ((String, String, String, String) async throws -> ServiceRequest)?
    var onOffers: ((String) async throws -> ServiceOfferList)?
    var onCancel: ((String) async throws -> ServiceRequest)?
    func create(_ body: CreateServiceRequest, key: String) async throws -> ServiceRequest { try await XCTUnwrap(onCreate)(body, key) }
    func get(_ id: String) async throws -> ServiceRequest { try await XCTUnwrap(onGet)(id) }
    func answer(_ id: String, clarificationId: String, value: String, key: String) async throws -> ServiceRequest {
        try await XCTUnwrap(onAnswer)(id, clarificationId, value, key)
    }
    func offers(_ id: String) async throws -> ServiceOfferList { try await XCTUnwrap(onOffers)(id) }
    func cancel(_ id: String) async throws -> ServiceRequest { try await XCTUnwrap(onCancel)(id) }

    var onAsk: ((AskBody, String) async throws -> AskResult)?
    /// Without onAsk, an ask is routed through onCreate, so a request test reads as before.
    func ask(_ body: AskBody, key: String) async throws -> AskResult {
        if let onAsk { return try await onAsk(body, key) }
        let request = try await XCTUnwrap(onCreate)(CreateServiceRequest(text: body.text, location: body.location), key)
        return AskResult(askId: "ask_test", askType: .serviceRequest, request: request, placeQuestion: nil,
                         clarification: nil, createdAt: request.createdAt)
    }
    func getAsk(_ id: String) async throws -> AskResult { throw URLError(.notConnectedToInternet) }
    func answerAsk(_ id: String, clarificationId: String, value: String, key: String) async throws -> AskResult {
        throw URLError(.notConnectedToInternet)
    }
    func proposeSkills(_ description: String) async throws -> SkillProposal { SkillProposal(skills: [], unmatched: []) }
    func setProvider(_ setup: ProviderSetup) async throws -> ProviderProfile { throw URLError(.notConnectedToInternet) }
    func providerProfile() async throws -> ProviderProfile? { nil }
}
