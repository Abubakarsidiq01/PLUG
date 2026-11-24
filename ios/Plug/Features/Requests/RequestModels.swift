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
    /// Contract 0.7.0: present once an offer was chosen, then always the latest reservation.
    var reservation: Reservation? = nil

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
        /// Contract 0.7.0: the chosen provider did not confirm and no other offer was left.
        case notConfirmed = "not_confirmed"
        var explanation: String {
            switch self {
            case .noCoverage: return "Nobody on PLUG offers this near you yet."
            case .noOffers: return "No current offers meet this request. Your request has expired."
            case .clarificationUnanswered: return "This request expired before the clarifying question was answered."
            case .notConfirmed: return "The provider didn't confirm, and no other offer was left. Nothing was booked."
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
              [.waitForOffers, .awaitSupplierConfirmation].contains(nextAction) == (pollAfterSeconds != nil),
              pollAfterSeconds.map({ (1...30).contains($0) }) ?? true,
              constraints.category != nil || status == .draft || status == .canceled || noResultReason == .clarificationUnanswered
        else { throw APIError.contractViolation(requestID: nil) }
        guard reservation.map(\.isValid) ?? true, reservationMatchesStatus else { throw APIError.contractViolation(requestID: nil) }
        if let clarification {
            guard ["category", "ask"].contains(clarification.field), !clarification.question.isEmpty,
                  (1...8).contains(clarification.options.count),
                  Set(clarification.options.map(\.value)).count == clarification.options.count,
                  clarification.options.allSatisfy({ ServiceRequest.isServiceIdentifier($0.value) && !$0.label.isEmpty })
            else { throw APIError.contractViolation(requestID: nil) }
        }
        return self
    }

    /// Only the pairs the contract allows; anything else is a contract violation, never a state.
    private var reservationMatchesStatus: Bool {
        let ended: [Reservation.Status] = [.released, .timedOut]
        switch status {
        case .userSelected: return reservation?.status == .pending
        case .confirmed, .completed: return reservation?.status == .confirmed
        case .ranked: return reservation.map { ended.contains($0.status) } ?? true
        case .expired:
            guard noResultReason == .notConfirmed else { return reservation == nil }
            return reservation.map { ended.contains($0.status) } ?? false
        case .canceled: return reservation.map { $0.status == .canceled } ?? true
        case .draft, .submitted, .routed, .awaitingResponses, .blocked: return reservation == nil
        }
    }

    /// The provider released the reservation or let it lapse, and other live offers remain.
    var isRecovering: Bool {
        status == .ranked && [.released, .timedOut].contains(reservation?.status)
    }
}

/// The asker's choice, waiting for the provider (manual §19.6). Only a provider event confirms it.
struct Reservation: Decodable, Equatable {
    enum Status: String, Decodable { case pending, confirmed, released, timedOut = "timed_out", canceled }
    let reservationId: String
    let offerId: String
    let status: Status
    /// Four characters without 0, O, 1 or I, quoted by both sides. Not a secret.
    let bookingRef: String
    let confirmBy: Date
    var confirmedAt: Date? = nil
    var endedAt: Date? = nil
    let createdAt: Date

    var isValid: Bool {
        reservationId.range(of: "^rsv_[A-Za-z0-9-]{1,60}$", options: .regularExpression) != nil
            && offerId.range(of: "^off_[A-Za-z0-9-]{1,60}$", options: .regularExpression) != nil
            && bookingRef.range(of: "^[2-9A-HJ-NP-Z]{4}$", options: .regularExpression) != nil
            && confirmBy > createdAt
            && (confirmedAt != nil) == (status == .confirmed)
            && (endedAt != nil) == [.released, .timedOut, .canceled].contains(status)
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
    /// Contract 0.7.0: present only for seed and SMS offers. An in-app provider's offer has
    /// no public place, so distance lives on the offer itself.
    let place: Place?
    let distanceM: Int
    var note: String? = nil
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
    var businessName: String { business?.name ?? place?.name ?? "A provider nearby" }
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
        !offerId.isEmpty && !serviceName.isEmpty
        && (place == nil) == (source == .portal) && (note == nil || source == .portal)
        && place.map({ !$0.name.isEmpty && !$0.address.isEmpty && $0.distanceM == distanceM }) ?? true
        && (500...50_000).contains(priceCents) && currency == "USD"
        && (0...80_000).contains(distanceM) && expiresAt > availableAt
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

// MARK: - The provider inbox (contract 0.7.0, P3.S10 to P3.S12)

struct ProviderInbox: Decodable, Equatable {
    let items: [InboxItem]
    let notificationsPerHour: Int
    func validated() throws -> Self {
        guard items.count <= 50, (1...10).contains(notificationsPerHour), Set(items.map(\.matchId)).count == items.count,
              items.allSatisfy(\.isValid) else { throw APIError.contractViolation(requestID: nil) }
        return self
    }
}

/// One matched request as the provider sees it: never the asker's words, place or identity.
struct InboxItem: Decodable, Equatable, Identifiable {
    enum Status: String, Decodable {
        case open, offered, declined, expired, selected, confirmed, notChosen = "not_chosen", closed
    }
    let matchId: String
    let requestId: String
    let status: Status
    /// Untrusted display text (0.7.2): rendered as plain text only.
    let serviceName: String
    let skillTags: [String]
    let budgetCents: Int?
    let currency: String
    let neededBy: Date?
    let distanceM: Int
    let respondBy: Date
    let notifiedAt: Date
    var offer: ServiceOffer? = nil
    var reservation: Reservation? = nil
    var id: String { matchId }

    var isValid: Bool {
        guard matchId.range(of: "^mat_[A-Za-z0-9-]{1,60}$", options: .regularExpression) != nil,
              requestId.range(of: "^req_[A-Za-z0-9-]{1,60}$", options: .regularExpression) != nil,
              (1...80).contains(serviceName.count), (1...5).contains(skillTags.count),
              skillTags.allSatisfy(ServiceRequest.isServiceIdentifier), currency == "USD",
              budgetCents.map({ (500...500_000).contains($0) }) ?? true,
              (0...80_000).contains(distanceM), distanceM % 100 == 0, respondBy > notifiedAt,
              offer.map({ $0.isValid && $0.source == .portal }) ?? true,
              reservation.map(\.isValid) ?? true,
              reservation == nil || reservation?.offerId == offer?.offerId else { return false }
        switch status {
        case .open, .declined, .expired: return offer == nil && reservation == nil
        case .offered: return offer != nil && reservation == nil
        case .selected: return offer != nil && reservation?.status == .pending
        case .confirmed: return offer != nil && reservation?.status == .confirmed
        case .notChosen, .closed: return true
        }
    }
}

enum DeclineReason: String, Encodable, CaseIterable, Identifiable {
    case busy, tooFar = "too_far", price, notMySkill = "not_my_skill", other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .busy: return "I'm busy then"
        case .tooFar: return "Too far"
        case .price: return "The budget doesn't work"
        case .notMySkill: return "Not something I do"
        case .other: return "Something else"
        }
    }
}

enum ReservationAnswer: String, Encodable { case confirm, release }

/// An in-app offer. Expiry, label and observed time are the server's.
struct ProviderOfferCreate: Encodable, Equatable {
    let priceCents: Int
    var currency = "USD"
    let availableAt: Date
    var note: String? = nil
}

/// The composer's input and its checks, which mirror the server's (contract ProviderOfferCreate).
/// The server still decides; these only save a round trip and say what to fix.
struct OfferDraft: Equatable {
    var price = ""
    var start: Date
    var note = ""
    static let noteLimit = 140

    enum Field: Hashable { case price, start, note }

    var priceCents: Int? {
        let text = price.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
        guard text.range(of: "^[0-9]{1,4}(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }
    var trimmedNote: String? {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    /// The latest start the server accepts: the asker's needed-by time, and never more than 7 days out.
    static func latestStart(neededBy: Date?, now: Date) -> Date {
        min(neededBy ?? .distantFuture, now.addingTimeInterval(7 * 24 * 3600))
    }

    func errors(for item: InboxItem, now: Date) -> [Field: String] {
        var errors: [Field: String] = [:]
        if let cents = priceCents {
            if !(500...50_000).contains(cents) { errors[.price] = "Offers can be from $5 to $500." }
            else if let budget = item.budgetCents, cents > budget {
                errors[.price] = "Their budget is \(money(budget, item.currency)). Offer that or less."
            }
        } else {
            errors[.price] = "Enter a price in dollars, for example 30."
        }
        let latest = Self.latestStart(neededBy: item.neededBy, now: now)
        if start < now.addingTimeInterval(-60) { errors[.start] = "Choose a start time that is not in the past." }
        else if start > latest {
            let beforeNeeded = item.neededBy.map { $0 < now.addingTimeInterval(7 * 24 * 3600) } ?? false
            errors[.start] = beforeNeeded ? "Choose a time before they need it." : "Choose a time in the next 7 days."
        }
        if note.count > Self.noteLimit { errors[.note] = "Keep the note to \(Self.noteLimit) characters." }
        return errors
    }

    func body() -> ProviderOfferCreate? {
        guard let cents = priceCents else { return nil }
        return ProviderOfferCreate(priceCents: cents, availableAt: start, note: trimmedNote)
    }
}
