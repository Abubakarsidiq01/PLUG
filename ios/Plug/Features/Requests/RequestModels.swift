import Foundation

struct RequestLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let precision: Precision
    enum Precision: String, Codable { case coarse, fine }
    var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}

struct CreateServiceRequest: Encodable, Equatable {
    let text: String
    let location: RequestLocation
    /// The person's IANA zone, so "tomorrow" means their tomorrow (ADR-009).
    var timeZone: String = TimeZone.current.identifier
    // Chip choices are sent as exact values and win over the words (§9.1). Nil is omitted,
    // never sent as null, so the server reads that constraint from the text instead.
    var budgetCents: Int? = nil
    var currency: String? = nil
    var neededBy: Date? = nil
    var maxDistanceM: Int? = nil
}

struct ServiceRequest: Decodable, Equatable {
    let requestId: String
    let status: Status
    let nextAction: NextAction
    let text: String
    let constraints: Constraints
    let progress: Progress
    let clarification: Clarification?
    let noResultReason: NoResultReason?
    let pollAfterSeconds: Int?
    let createdAt: Date
    let updatedAt: Date
    let expiresAt: Date

    enum Status: String, Decodable {
        case draft, submitted, routed, awaitingResponses = "awaiting_responses", ranked
        case userSelected = "user_selected", confirmed, completed, expired, canceled, blocked
        var canCancel: Bool { ![.completed, .expired, .canceled, .blocked].contains(self) }
    }
    enum NextAction: String, Decodable {
        case answerClarification = "answer_clarification", waitForOffers = "wait_for_offers"
        case chooseOffer = "choose_offer", awaitSupplierConfirmation = "await_supplier_confirmation"
        case showResult = "show_result", showNoResult = "show_no_result", none
    }
    /// Any lawful service (ADR-009). A snake_case identifier; display `serviceName` instead.
    static func isServiceIdentifier(_ value: String) -> Bool {
        value.range(of: "^[a-z][a-z0-9_]{1,39}$", options: .regularExpression) != nil
    }
    enum NoResultReason: String, Decodable {
        case noCoverage = "no_coverage", noOffers = "no_offers", clarificationUnanswered = "clarification_unanswered"
        var explanation: String {
            switch self {
            case .noCoverage: return "Nobody on PLUG offers this near you yet."
            case .noOffers: return "No current offers meet this request. Your request has expired."
            case .clarificationUnanswered: return "This request expired before the clarifying question was answered."
            }
        }
    }
    struct Constraints: Decodable, Equatable {
        let category: String?
        let serviceName: String?
        /// Vocabulary tags from contracts/skills.yaml, primary first (manual v4 §12B.3).
        let skillTags: [String]
        let licenceRequired: Bool
        let budgetCents: Int?
        let currency: String
        let neededBy: Date?
        let maxDistanceM: Int
        let location: RequestLocation
    }
    struct Progress: Decodable, Equatable {
        let contacted: Int
        let replied: Int
        let offersReady: Int
    }
    struct Clarification: Decodable, Equatable {
        let clarificationId: String
        let field: String
        let question: String
        let options: [Option]
        struct Option: Decodable, Equatable { let value: String; let label: String }
    }

    /// Semantic checks supplement decoding; malformed server state must never invent a UI state.
    func validated() throws -> Self {
        let mapping: [Status: NextAction] = [.draft: .answerClarification, .submitted: .waitForOffers,
            .routed: .waitForOffers, .awaitingResponses: .waitForOffers, .ranked: .chooseOffer,
            .userSelected: .awaitSupplierConfirmation, .confirmed: .showResult, .completed: .showResult,
            .expired: .showNoResult, .canceled: .none]
        guard requestId.range(of: "^req_[A-Za-z0-9-]+$", options: .regularExpression) != nil,
              mapping[status] == nextAction, text.unicodeScalars.count <= 500,
              constraints.location.isValid, constraints.currency == "USD",
              (100...50_000).contains(constraints.maxDistanceM),
              constraints.budgetCents.map({ (500...500_000).contains($0) }) ?? true,
              constraints.category.map(ServiceRequest.isServiceIdentifier) ?? true,
              (constraints.category == nil) == (constraints.serviceName == nil),
              (constraints.category == nil) == constraints.skillTags.isEmpty, constraints.skillTags.count <= 5,
              constraints.category == constraints.skillTags.first,
              (0...50).contains(progress.contacted), (0...progress.contacted).contains(progress.replied),
              (0...min(progress.replied, 20)).contains(progress.offersReady),
              (nextAction == .answerClarification) == (clarification != nil),
              (nextAction == .showNoResult) == (noResultReason != nil),
              (nextAction == .waitForOffers) == (pollAfterSeconds != nil),
              pollAfterSeconds.map({ (1...30).contains($0) }) ?? true,
              constraints.category != nil || status == .draft || status == .canceled || noResultReason == .clarificationUnanswered
        else { throw APIError.contractViolation(requestID: nil) }
        if let clarification {
            guard ["category", "ask"].contains(clarification.field), !clarification.question.isEmpty,
                  (1...8).contains(clarification.options.count),
                  Set(clarification.options.map(\.value)).count == clarification.options.count,
                  clarification.options.allSatisfy({ ServiceRequest.isServiceIdentifier($0.value) && !$0.label.isEmpty })
            else { throw APIError.contractViolation(requestID: nil) }
        }
        return self
    }
}

struct ServiceOfferList: Decodable, Equatable {
    let requestId: String
    let offers: [ServiceOffer]
    func validated(for requestId: String) throws -> Self {
        guard self.requestId == requestId, offers.count <= 20,
              Set(offers.map(\.offerId)).count == offers.count,
              offers.allSatisfy(\.isValid) else { throw APIError.contractViolation(requestID: nil) }
        return self
    }
}

struct ServiceOffer: Decodable, Equatable, Identifiable {
    let offerId: String
    let place: Place
    let serviceName: String
    let priceCents: Int
    let currency: String
    let availableAt: Date
    let expiresAt: Date
    let observedAt: Date
    let truthLabel: TruthLabel
    let source: Source
    let providerScore: ProviderScore
    var business: BusinessProfile? = nil
    var businessName: String { business?.name ?? place.name }
    var id: String { offerId }
    struct Place: Decodable, Equatable {
        let placeId: String
        let name: String
        let address: String
        let distanceM: Int
    }
    enum TruthLabel: String, Decodable {
        case confirmed, recent, estimated, unknown
        /// Web-sourced (manual v4 §11.2): dashed, never filled, never on an offer.
        case notVerified = "not_verified"
        var title: String { self == .notVerified ? "Not verified" : rawValue.capitalized }
        var explanation: String {
            switch self {
            case .confirmed: return "Confirmed. Verified by the provider."
            case .recent: return "Recent. Based on recent verification."
            case .estimated: return "Estimated. Availability and price are not confirmed."
            case .unknown: return "Unknown. No recent information. You can keep asking."
            case .notVerified: return "Not verified. This came from the web and nobody checked it."
            }
        }
    }
    enum Source: String, Decodable { case seed, sms, portal }
    var isValid: Bool {
        !offerId.isEmpty && !place.name.isEmpty && !place.address.isEmpty && !serviceName.isEmpty
        && (500...50_000).contains(priceCents) && currency == "USD"
        && (0...50_000).contains(place.distanceM) && expiresAt > availableAt
        && (source != .seed || [.estimated, .unknown].contains(truthLabel)) && truthLabel != .notVerified
        && providerScore.isValid
    }
    var price: String { (Decimal(priceCents) / 100).formatted(.currency(code: currency)) }
}

/// Manual v4 §12C: fewer than three completed jobs is New, never a zero.
struct ProviderScore: Decodable, Equatable {
    enum State: String, Decodable { case new, scored }
    let state: State
    let value: Int?
    let completedJobs: Int
    var isValid: Bool {
        (state == .scored) == (value != nil) && (value.map { (0...100).contains($0) } ?? true) && completedJobs >= 0
            && (completedJobs >= 3 || state == .new)
    }
}

// MARK: - The single ask entry point (manual v4 §12A, contract 0.5.0)

struct AskBody: Encodable, Equatable {
    let text: String
    let location: RequestLocation
    var timeZone: String = TimeZone.current.identifier
}

struct AskResult: Decodable, Equatable {
    enum AskType: String, Decodable { case serviceRequest = "service_request", placeQuestion = "place_question" }
    let askId: String
    let askType: AskType?
    let request: ServiceRequest?
    let placeQuestion: PlaceQuestion?
    let clarification: ServiceRequest.Clarification?
    let createdAt: Date

    /// Exactly one of the three, matching ask_type. Anything else is a contract violation.
    func validated() throws -> Self {
        guard askId.range(of: "^ask_[A-Za-z0-9-]+$", options: .regularExpression) != nil else {
            throw APIError.contractViolation(requestID: nil)
        }
        switch askType {
        case .serviceRequest:
            guard let request, placeQuestion == nil, clarification == nil else { throw APIError.contractViolation(requestID: nil) }
            _ = try request.validated()
        case .placeQuestion:
            guard let placeQuestion, request == nil, clarification == nil, placeQuestion.isValid else {
                throw APIError.contractViolation(requestID: nil)
            }
        case nil:
            guard let clarification, request == nil, placeQuestion == nil, clarification.field == "ask",
                  (1...8).contains(clarification.options.count) else { throw APIError.contractViolation(requestID: nil) }
        }
        return self
    }
}

struct PlaceQuestion: Decodable, Equatable {
    enum Status: String, Decodable { case asking, answered, unknown }
    struct Progress: Decodable, Equatable { let notified: Int; let opened: Int; let answered: Int }
    let questionId: String
    let text: String
    let placeName: String?
    let status: Status
    let progress: Progress
    let answer: PlaceAnswer?
    let webAnswer: WebAnswer?
    let createdAt: Date
    let expiresAt: Date
    var isValid: Bool {
        progress.notified >= 0 && progress.opened >= 0 && progress.answered >= 0
            && progress.opened <= progress.notified && progress.answered <= progress.notified
            && (status == .answered) == (answer != nil) && expiresAt > createdAt
            && (webAnswer?.truthLabel ?? .notVerified) == .notVerified
    }
}

/// Synthesised only from what people said (Phase 4). The value is the headline.
struct PlaceAnswer: Decodable, Equatable {
    struct Source: Decodable, Equatable { let initials: String; let answeredAt: Date }
    let value: String
    let summary: String
    let truthLabel: ServiceOffer.TruthLabel
    let sources: [Source]
    let expiresAt: Date
}

/// What the web says, behind a dashed outline. Never a human answer.
struct WebAnswer: Decodable, Equatable {
    let headline: String
    let summary: String
    let sourceName: String
    let retrievedAt: Date
    let truthLabel: ServiceOffer.TruthLabel
}

// MARK: - Provider capability on the same account (manual v4 §2.3, §12B)

struct SkillTag: Codable, Equatable, Hashable, Identifiable {
    let tag: String
    let display: String
    let requiresLicence: Bool
    var id: String { tag }
}

struct SkillProposal: Decodable, Equatable {
    let skills: [SkillTag]
    let unmatched: [String]
}

struct AvailabilityWindow: Codable, Equatable {
    enum Days: String, Codable { case weekdays, weekends, everyDay = "every_day" }
    let days: Days
    let from: String
    let to: String
}

struct ProviderSetup: Encodable, Equatable {
    let skillTags: [String]
    let travelRadiusM: Int
    let baseLocation: RequestLocation
    let availability: [AvailabilityWindow]
    var timeZone: String = TimeZone.current.identifier
    var licenceRef: String? = nil
    var accepting: Bool = true
    var business: BusinessProfile? = nil
    /// Skills in the provider's own words (ADR-011). nil keeps what is stored; [] removes it.
    var customSkills: [String]? = nil
}

struct ProviderProfile: Decodable, Equatable {
    let userId: String
    let skills: [SkillTag]
    let travelRadiusM: Int
    let availability: [AvailabilityWindow]
    let timeZone: String
    let accepting: Bool
    let licenceOnFile: Bool
    let score: ProviderScore
    let createdAt: Date
    var business: BusinessProfile? = nil
    var customSkills: [String]? = nil
}

/// All public details are optional and supplied by the business itself.
struct BusinessProfile: Codable, Equatable {
    var name: String? = nil
    var about: String? = nil
    var photoBase64: String? = nil
    var links: [BusinessLink]? = nil
}

struct BusinessLink: Codable, Equatable, Identifiable {
    let label: String
    let url: String
    var id: String { label + url }
    var destination: URL? {
        guard let value = URL(string: url), value.scheme == "https", value.host != nil,
              value.user == nil, value.password == nil else { return nil }
        return value
    }
}
