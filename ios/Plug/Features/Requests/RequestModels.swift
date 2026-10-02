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

/// Structured controls for the composer (§9.1: chips first, typing is the fallback).
/// `.fromRequest` sends nothing, so PLUG reads that constraint from the person's words.
struct RequestFilters: Equatable {
    enum Budget: Int, CaseIterable, Identifiable {
        case fromRequest = 0, under25 = 2500, under50 = 5000, under100 = 10000, under250 = 25000
        var id: Int { rawValue }
        var cents: Int? { self == .fromRequest ? nil : rawValue }
        var title: String {
            switch self {
            case .fromRequest: return "From my words"
            default: return "Under " + (Decimal(rawValue) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0)))
            }
        }
    }
    enum Time: String, CaseIterable, Identifiable {
        case fromRequest, withinHour, today, tomorrow
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fromRequest: return "From my words"
            case .withinHour: return "Within 1 hour"
            case .today: return "Today"
            case .tomorrow: return "Tomorrow"
            }
        }
        /// The latest acceptable time, in the person's calendar. Today means by 11:59 PM.
        func deadline(now: Date, calendar: Calendar = .current) -> Date? {
            switch self {
            case .fromRequest: return nil
            case .withinHour: return now.addingTimeInterval(3600)
            case .today, .tomorrow:
                let day = calendar.startOfDay(for: now).addingTimeInterval(self == .today ? 0 : 86_400)
                return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day)
            }
        }
    }
    enum Distance: Int, CaseIterable, Identifiable {
        case fromRequest = 0, mile1 = 1609, miles3 = 4828, miles10 = 16093, miles25 = 40234
        var id: Int { rawValue }
        var metres: Int? { self == .fromRequest ? nil : rawValue }
        var title: String {
            switch self {
            case .fromRequest: return "From my words"
            case .mile1: return "1 mi"
            case .miles3: return "3 mi"
            case .miles10: return "10 mi"
            case .miles25: return "25 mi"
            }
        }
    }
    var budget = Budget.fromRequest
    var time = Time.fromRequest
    var distance = Distance.fromRequest
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
            case .noCoverage: return "No participating PLUG suppliers cover this service near you yet."
            case .noOffers: return "No current offers meet this request. Your request has expired."
            case .clarificationUnanswered: return "This request expired before the clarifying question was answered."
            }
        }
    }
    struct Constraints: Decodable, Equatable {
        let category: String?
        let serviceName: String?
        let searchTerms: [String]
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
              (constraints.category == nil) == constraints.searchTerms.isEmpty, constraints.searchTerms.count <= 5,
              (0...50).contains(progress.contacted), (0...progress.contacted).contains(progress.replied),
              (0...min(progress.replied, 20)).contains(progress.offersReady),
              (nextAction == .answerClarification) == (clarification != nil),
              (nextAction == .showNoResult) == (noResultReason != nil),
              (nextAction == .waitForOffers) == (pollAfterSeconds != nil),
              pollAfterSeconds.map({ (1...30).contains($0) }) ?? true,
              constraints.category != nil || status == .draft || status == .canceled || noResultReason == .clarificationUnanswered
        else { throw APIError.contractViolation(requestID: nil) }
        if let clarification {
            guard clarification.field == "category", !clarification.question.isEmpty,
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
    var id: String { offerId }
    struct Place: Decodable, Equatable {
        let placeId: String
        let name: String
        let address: String
        let distanceM: Int
    }
    enum TruthLabel: String, Decodable {
        case confirmed, recent, estimated, unknown
        var title: String { rawValue.capitalized }
        var explanation: String {
            switch self {
            case .confirmed: return "Confirmed. Verified by the supplier."
            case .recent: return "Recent. Based on recent verification."
            case .estimated: return "Estimated. Availability and price are not confirmed."
            case .unknown: return "Unknown. No recent verification is available."
            }
        }
    }
    enum Source: String, Decodable { case seed, sms, portal }
    var isValid: Bool {
        !offerId.isEmpty && !place.name.isEmpty && !place.address.isEmpty && !serviceName.isEmpty
        && (500...50_000).contains(priceCents) && currency == "USD"
        && (0...50_000).contains(place.distanceM) && expiresAt > availableAt
        && (source != .seed || [.estimated, .unknown].contains(truthLabel))
    }
    var price: String { (Decimal(priceCents) / 100).formatted(.currency(code: currency)) }
}
