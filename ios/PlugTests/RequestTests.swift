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
        XCTAssertEqual(checked, 26)
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

    func testDeviceFixGoesStaleAfterTenMinutesButATypedAddressDoesNot() {
        let now = Date()
        XCTAssertFalse(RequestLocationModel.isStale(fixedAt: nil, now: now))
        XCTAssertFalse(RequestLocationModel.isStale(fixedAt: now.addingTimeInterval(-9 * 60), now: now))
        XCTAssertTrue(RequestLocationModel.isStale(fixedAt: now.addingTimeInterval(-11 * 60), now: now))
        XCTAssertFalse(RequestLocationModel().isStale())
    }

    func testKnowBeforeQuestionsAreExactAndStayWithinTheAskLimit() throws {
        let place = KnowBefore.placeName("H-E-B", street: "South Congress Avenue")
        XCTAssertEqual(place, "H-E-B on South Congress Avenue")
        XCTAssertEqual(KnowBefore.placeName("Main Street Cafe", street: "Main Street"), "Main Street Cafe")
        XCTAssertEqual(KnowBefore.question(.line, place: place), "How long is the line at H-E-B on South Congress Avenue right now?")
        XCTAssertEqual(KnowBefore.question(.busy, place: " Walmart "), "How busy is Walmart right now?")
        XCTAssertEqual(KnowBefore.question(.open, place: "the DMV"), "Is the DMV open right now?")
        XCTAssertEqual(KnowBefore.question(.parking, place: "Zilker Park"), "Is parking easy at Zilker Park right now?")
        XCTAssertEqual(KnowBefore.question(.other, place: "Jo's", other: "Is there seating outside?"), "At Jo's: Is there seating outside?")
        XCTAssertNil(KnowBefore.question(.other, place: "Jo's", other: "  "))
        XCTAssertNil(KnowBefore.question(.busy, place: "  "))
        // The longest place and free text together still pass the composer's own check.
        let longest = try XCTUnwrap(KnowBefore.question(.other, place: String(repeating: "p", count: 400),
                                                        other: String(repeating: "q", count: 900)))
        let model = RequestModel(service: StubRequests())
        model.text = longest
        XCTAssertNil(model.textError)
        for topic in KnowBefore.Topic.allCases where topic != .other {
            model.text = try XCTUnwrap(KnowBefore.question(topic, place: String(repeating: "p", count: 400)))
            XCTAssertNil(model.textError)
        }
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

    // MARK: P3.S7 booking (contract 0.7.0 select and reservation)

    func testReservationFixturesValidateAndMalformedReservationsFailClosed() throws {
        XCTAssertEqual(try resource("requests.get", "reservation-pending").validated().reservation?.status, .pending)
        XCTAssertTrue(try resource("requests.get", "reservation-released").validated().isRecovering)
        XCTAssertEqual(try resource("requests.get", "confirmed").validated().reservation?.bookingRef, "K7QM")
        XCTAssertEqual(try resource("requests.get", "not-confirmed").validated().reservation?.status, .timedOut)
        XCTAssertEqual(try resource("requests.select", "success").validated().nextAction, .awaitSupplierConfirmation)
        func mutated(_ name: String, _ change: (inout [String: Any]) -> Void) throws -> ServiceRequest {
            var json = try object("requests.get", name)
            var reservation = (json["reservation"] as? [String: Any]) ?? [:]
            change(&reservation)
            json["reservation"] = reservation
            return try decode(json)
        }
        let bad: [ServiceRequest] = [
            try mutated("reservation-pending") { $0["status"] = "confirmed" },          // status pair, and no confirmed_at
            try mutated("reservation-pending") { $0["confirmed_at"] = "2026-10-01T20:03:41Z" },
            try mutated("reservation-pending") { $0["booking_ref"] = "K0OI" },
            try mutated("reservation-pending") { $0["confirm_by"] = "2026-10-01T19:00:00Z" },
            try mutated("reservation-released") { $0.removeValue(forKey: "ended_at") },
            try mutated("reservation-released") { $0["status"] = "pending"; $0.removeValue(forKey: "ended_at") },
            try mutated("confirmed") { $0["status"] = "pending"; $0.removeValue(forKey: "confirmed_at") },
            try mutated("not-confirmed") { $0["status"] = "pending"; $0.removeValue(forKey: "ended_at") },
            try mutated("submitted") { $0 = try! self.object("requests.get", "reservation-pending")["reservation"] as! [String: Any] }
        ]
        for request in bad { XCTAssertThrowsError(try request.validated()) }
        var missing = try object("requests.get", "reservation-pending")
        missing.removeValue(forKey: "reservation")
        XCTAssertThrowsError(try decode(missing).validated())
    }

    func testSelectRetriesSameOfferWithSameKeyAndShowsPendingReservation() async throws {
        let service = StubRequests()
        let ranked = try resource("requests.get", "success")
        let pending = try resource("requests.get", "reservation-pending")
        let offers = try PlugJSON.decoder.decode(ServiceOfferList.self, from: fixture("requests.offers", "sms-and-app"))
        service.onCreate = { _, _ in ranked }
        service.onOffers = { _ in offers }
        var keys: [String] = []
        service.onSelect = { _, offerId, key in
            keys.append(key)
            XCTAssertEqual(offerId, offers.offers[0].offerId)
            if keys.count == 1 { throw URLError(.networkConnectionLost) }
            return pending
        }
        let model = RequestModel(service: service)
        model.setActive(false)
        model.text = "Barber"
        await model.submit(location: location)
        await model.select(offers.offers[0])
        XCTAssertEqual(model.request?.status, .ranked)
        XCTAssertNotNil(model.errorMessage)
        await model.select(offers.offers[0])
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1])
        XCTAssertEqual(model.request?.status, .userSelected)
        XCTAssertEqual(model.request?.reservation?.bookingRef, "K7QM")
        XCTAssertNotEqual(model.request?.status, .confirmed) // Only a provider event confirms.
    }

    func testSelectionConflictReloadsServerStateAndSeedOffersAreNeverSelected() async throws {
        let service = StubRequests()
        let ranked = try resource("requests.get", "success")
        let seed = try offerList()
        let offers = try PlugJSON.decoder.decode(ServiceOfferList.self, from: fixture("requests.offers", "sms-and-app"))
        var served = seed
        service.onCreate = { _, _ in ranked }
        service.onOffers = { _ in served }
        var selections = 0
        service.onSelect = { _, _, _ in
            selections += 1
            throw APIError(status: 409, body: try self.fixture("requests.select", "offer-unavailable"), requestID: nil)
        }
        var reloads = 0
        service.onGet = { _ in reloads += 1; return ranked }
        let model = RequestModel(service: service)
        model.setActive(false)
        model.text = "Barber"
        await model.submit(location: location)
        await model.select(seed.offers[0])
        XCTAssertEqual(selections, 0)
        served = offers
        await model.refresh()
        reloads = 0
        await model.select(offers.offers[0])
        XCTAssertEqual(selections, 1)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(model.request?.status, .ranked)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isWorking)
    }

    func testSelectNotFoundMeansBookingIsOffAndNothingChanges() async throws {
        let service = StubRequests()
        let ranked = try resource("requests.get", "success")
        let offers = try PlugJSON.decoder.decode(ServiceOfferList.self, from: fixture("requests.offers", "sms-and-app"))
        service.onCreate = { _, _ in ranked }
        service.onOffers = { _ in offers }
        service.onSelect = { _, _, _ in throw APIError(status: 404, body: Data(), requestID: nil) }
        let model = RequestModel(service: service)
        model.setActive(false)
        model.text = "Barber"
        await model.submit(location: location)
        await model.select(offers.offers[1])
        XCTAssertTrue(model.bookingUnavailable)
        XCTAssertEqual(model.request, ranked)
        XCTAssertNil(model.errorMessage)
    }

    func testPollingContinuesWhileAwaitingSupplierConfirmation() async throws {
        let service = StubRequests()
        let pending = try resource("requests.get", "reservation-pending")
        service.onCreate = { _, _ in pending }
        service.onOffers = { _ in try self.offerList() }
        var interval: Int?
        let model = RequestModel(service: service, sleep: { value in interval = value; throw CancellationError() })
        model.text = "Barber"
        await model.submit(location: location)
        while interval == nil { await Task.yield() }
        XCTAssertEqual(interval, pending.pollAfterSeconds)
        model.setActive(false)
    }

    func testYoungRankedRequestIsCheckedGentlyThenLeftAlone() async throws {
        let ranked = try resource("requests.get", "success")
        for (age, expected) in [(TimeInterval(60), Optional(RequestModel.rankedPollSeconds)), (11 * 60, nil)] {
            let service = StubRequests()
            service.onCreate = { _, _ in ranked }
            service.onOffers = { _ in try self.offerList() }
            var interval: Int?
            let model = RequestModel(service: service, now: { ranked.createdAt.addingTimeInterval(age) },
                                     sleep: { value in interval = value; throw CancellationError() })
            model.text = "Barber"
            await model.submit(location: location)
            for _ in 0..<50 where interval == nil { await Task.yield() }
            XCTAssertEqual(interval, expected)
            model.setActive(false)
        }
    }

    func testSelectServicePostsOfferWithIdempotencyKey() async throws {
        let data = try fixture("requests.select", "success")
        TestTransport.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/requests/req_01J9Z6Q3V8M2K4P7R5T1W0XY3B/select")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "select-key-0000001")
            return (try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])), data)
        }
        let service = try await liveService()
        let result = try await service.select("req_01J9Z6Q3V8M2K4P7R5T1W0XY3B", offerId: "off_01JA3P0SMS4K7QM2V8X1Z5B9C3",
                                              key: "select-key-0000001")
        XCTAssertEqual(result.reservation?.status, .pending)
    }

    // MARK: P3.S16 provider inbox

    func testEveryInboxFixtureDecodesAndValidates() throws {
        var checked = 0
        for folder in ["providers.inbox", "providers.decline", "providers.reservation", "requests.send-offer"] {
            let directory = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(folder))
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                let data = try Data(contentsOf: url)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                if json["error"] != nil { continue }
                switch folder {
                case "providers.inbox": _ = try PlugJSON.decoder.decode(ProviderInbox.self, from: data).validated()
                case "requests.send-offer":
                    let offer = try PlugJSON.decoder.decode(ServiceOffer.self, from: data)
                    XCTAssertTrue(offer.isValid && offer.source == .portal)
                default: XCTAssertTrue(try PlugJSON.decoder.decode(InboxItem.self, from: data).isValid, url.lastPathComponent)
                }
                checked += 1
            }
        }
        XCTAssertEqual(checked, 7)
    }

    func testMalformedInboxItemsFailClosed() throws {
        let inbox = try object("providers.inbox", "success")
        let item = try XCTUnwrap((inbox["items"] as? [[String: Any]])?.first)
        let selected = try object("providers.reservation", "confirmed")
        let cases: [[String: Any]] = [
            item.merging(["distance_m": 950]) { $1 },
            item.merging(["skill_tags": []]) { $1 },
            item.merging(["budget_cents": 100]) { $1 },
            item.merging(["status": "offered"]) { $1 },               // offered with no offer
            selected.merging(["status": "selected"]) { $1 },          // selected with a confirmed reservation
            item.merging(["respond_by": item["notified_at"] as Any]) { $1 }
        ]
        for json in cases {
            let decoded = try PlugJSON.decoder.decode(InboxItem.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertFalse(decoded.isValid)
        }
    }

    func testInboxNotFoundMeansInboxIsOff() async throws {
        let data = try fixture("providers.inbox", "not-a-provider")
        TestTransport.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/providers/me/inbox")
            return (try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 404,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])), data)
        }
        let service = try await liveService()
        let inbox = try await service.inbox()
        XCTAssertNil(inbox)
        let stub = StubRequests()
        stub.onInbox = { nil }
        let model = InboxModel(service: stub)
        await model.load()
        XCTAssertEqual(model.availability, .unavailable)
        XCTAssertTrue(model.items.isEmpty)
    }

    func testComposerChecksMirrorTheServer() throws {
        let item = try PlugJSON.decoder.decode(ProviderInbox.self, from: fixture("providers.inbox", "success")).items[0]
        let now = item.notifiedAt
        var draft = OfferDraft(price: "28", start: now.addingTimeInterval(600))
        XCTAssertTrue(draft.errors(for: item, now: now).isEmpty)
        XCTAssertEqual(draft.body()?.priceCents, 2800)
        draft.price = "28.50"
        XCTAssertEqual(draft.priceCents, 2850)
        for price in ["", "abc", "4", "28.555", "-5"] {
            draft.price = price
            XCTAssertNotNil(draft.errors(for: item, now: now)[.price], price)
        }
        draft.price = "36"
        XCTAssertNotNil(draft.errors(for: item, now: now)[.price]) // over the $35 budget
        draft.price = "30"
        draft.start = now.addingTimeInterval(-3600)
        XCTAssertNotNil(draft.errors(for: item, now: now)[.start])
        draft.start = try XCTUnwrap(item.neededBy).addingTimeInterval(60)
        XCTAssertNotNil(draft.errors(for: item, now: now)[.start])
        let noDeadline = try PlugJSON.decoder.decode(ProviderInbox.self, from: fixture("providers.inbox", "success")).items[1]
        draft.start = now.addingTimeInterval(8 * 24 * 3600)
        XCTAssertNotNil(draft.errors(for: noDeadline, now: now)[.start])
        draft.start = now.addingTimeInterval(600)
        draft.note = String(repeating: "n", count: 141)
        XCTAssertNotNil(draft.errors(for: item, now: now)[.note])
        draft.note = "   "
        XCTAssertNil(draft.body()?.note)
    }

    func testOfferRetryReusesKeyAndServerErrorsBecomeInlineErrors() async throws {
        let service = StubRequests()
        let inbox = try PlugJSON.decoder.decode(ProviderInbox.self, from: fixture("providers.inbox", "success"))
        let offer = try PlugJSON.decoder.decode(ServiceOffer.self, from: fixture("requests.send-offer", "success"))
        service.onInbox = { inbox }
        var keys: [String] = []
        service.onSendOffer = { requestId, _, key in
            keys.append(key)
            XCTAssertEqual(requestId, inbox.items[0].requestId)
            switch keys.count {
            case 1: throw URLError(.networkConnectionLost)
            case 2: throw APIError(status: 400, body: try self.fixture("requests.send-offer", "contact-in-note"), requestID: nil)
            default: return offer
            }
        }
        let model = InboxModel(service: service)
        await model.load()
        let body = ProviderOfferCreate(priceCents: 2800, availableAt: Date().addingTimeInterval(600), note: "Call me")
        let first = await model.send(inbox.items[0], body: body)
        XCTAssertFalse(first)
        XCTAssertNotNil(model.errorMessage)
        let second = await model.send(inbox.items[0], body: body)
        XCTAssertFalse(second)
        XCTAssertEqual(keys[0], keys[1])
        XCTAssertNotNil(model.fieldErrors[.note])
        let third = await model.send(inbox.items[0], body: ProviderOfferCreate(priceCents: 2800, availableAt: body.availableAt))
        XCTAssertTrue(third)
        XCTAssertNotEqual(keys[2], keys[1])
    }

    func testDeclineAndReservationAnswersReplaceTheItemWithTheServers() async throws {
        let service = StubRequests()
        let inbox = try PlugJSON.decoder.decode(ProviderInbox.self, from: fixture("providers.inbox", "success"))
        service.onInbox = { inbox }
        let declined = try PlugJSON.decoder.decode(InboxItem.self, from: fixture("providers.decline", "success"))
        var reason: DeclineReason?
        service.onDecline = { _, value in reason = value; return declined }
        let model = InboxModel(service: service)
        await model.load()
        await model.decline(inbox.items[0], reason: .tooFar)
        XCTAssertEqual(reason, .tooFar)
        XCTAssertEqual(model.item(inbox.items[0].matchId)?.status, .declined)
        service.onAnswerReservation = { _, _ in
            throw APIError(status: 409, body: try self.fixture("providers.reservation", "reservation-closed"), requestID: nil)
        }
        await model.answer(declined, .confirm)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNotEqual(model.item(declined.matchId)?.status, .confirmed)
    }

    func testDeclineBodyCarriesOnlyTheOptionalReason() async throws {
        let data = try fixture("providers.decline", "success")
        var bodies: [String] = []
        TestTransport.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/providers/me/inbox/mat_01JA3P2B6D0F4H8K2M6P0R4T8V/decline")
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 256)
                let count = stream.read(&buffer, maxLength: 256)
                body = Data(buffer.prefix(max(count, 0)))
            }
            bodies.append(String(decoding: body, as: UTF8.self))
            return (try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])), data)
        }
        let service = try await liveService()
        _ = try await service.decline("mat_01JA3P2B6D0F4H8K2M6P0R4T8V", reason: .notMySkill)
        _ = try await service.decline("mat_01JA3P2B6D0F4H8K2M6P0R4T8V", reason: nil)
        XCTAssertEqual(bodies, ["{\"reason\":\"not_my_skill\"}", "{}"])
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

    var onSelect: ((String, String, String) async throws -> ServiceRequest)?
    var onInbox: (() async throws -> ProviderInbox?)?
    var onSendOffer: ((String, ProviderOfferCreate, String) async throws -> ServiceOffer)?
    var onDecline: ((String, DeclineReason?) async throws -> InboxItem)?
    var onAnswerReservation: ((String, ReservationAnswer) async throws -> InboxItem)?
    func select(_ id: String, offerId: String, key: String) async throws -> ServiceRequest {
        try await XCTUnwrap(onSelect)(id, offerId, key)
    }
    func inbox() async throws -> ProviderInbox? { try await XCTUnwrap(onInbox)() }
    func decline(_ matchId: String, reason: DeclineReason?) async throws -> InboxItem { try await XCTUnwrap(onDecline)(matchId, reason) }
    func sendOffer(_ requestId: String, _ body: ProviderOfferCreate, key: String) async throws -> ServiceOffer {
        try await XCTUnwrap(onSendOffer)(requestId, body, key)
    }
    func answerReservation(_ matchId: String, _ answer: ReservationAnswer) async throws -> InboxItem {
        try await XCTUnwrap(onAnswerReservation)(matchId, answer)
    }
}
