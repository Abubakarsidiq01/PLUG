import Foundation

/// The last successful server snapshot is an account-scoped, memory-only cache. No query,
/// coordinates or offers are persisted to UserDefaults, logs, or shared URL caches.
@MainActor
final class RequestModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var request: ServiceRequest?
    /// Manual v4 §12A: one field, two kinds of ask. Exactly one of request, placeQuestion or
    /// askQuestion describes the current ask; the server decided which.
    @Published private(set) var askId: String?
    @Published private(set) var placeQuestion: PlaceQuestion?
    @Published private(set) var askQuestion: ServiceRequest.Clarification?
    var hasAsk: Bool { request != nil || placeQuestion != nil || askQuestion != nil }
    var hasActiveAsk: Bool { request?.status.canCancel == true || placeQuestion?.status == .asking }
    @Published private(set) var offers: [ServiceOffer] = []
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var correlationId: String?
    @Published private(set) var isCached = false
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var retryAfter: Date?
    private let service: RequestServing
    private let now: () -> Date
    private let sleep: (Int) async throws -> Void
    private var revision = UUID()
    private var polling: Task<Void, Never>?
    /// A retry resends the same body under the same key, so a slow network cannot create two asks.
    private var createAttempt: (body: AskBody, key: String)?
    private var answerAttempt: (id: String, value: String, key: String)?
    private var active = true
    static let placePollSeconds = 5

    init(service: RequestServing, now: @escaping () -> Date = Date.init,
         sleep: @escaping (Int) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.service = service
        self.now = now
        self.sleep = sleep
    }
    deinit { polling?.cancel() }

    var textError: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Type what you need, or tap an example." }
        if text.unicodeScalars.count > 500 { return "Keep it to 500 characters or fewer." }
        if text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" }) {
            return "Use plain text without control characters."
        }
        return nil
    }
    var canRetry: Bool { retryAfter.map { now() >= $0 } ?? true }

    func submit(location: RequestLocation) async {
        guard !isWorking, canRetry, !hasActiveAsk else { return }
        guard textError == nil, location.isValid else {
            errorMessage = textError ?? "Choose a valid search location."
            return
        }
        if let request, !request.status.canCancel { createAttempt = nil }
        let body = AskBody(text: text.trimmingCharacters(in: .whitespacesAndNewlines), location: location)
        if createAttempt?.body != body { createAttempt = (body, UUID().uuidString) }
        guard let attempt = createAttempt else { return }
        let token = begin()
        do {
            let result = try await service.ask(attempt.body, key: attempt.key)
            guard revision == token else { return }
            try await accept(result, token: token)
        } catch { fail(error, token: token, creating: true) }
        finish(token)
    }

    func answer(_ value: String) async {
        if let askId, let question = askQuestion {
            await answerAsk(askId, question: question, value: value)
            return
        }
        guard !isWorking, canRetry, let request, let question = request.clarification,
              question.options.contains(where: { $0.value == value }) else { return }
        if answerAttempt?.id != question.clarificationId || answerAttempt?.value != value {
            answerAttempt = (question.clarificationId, value, UUID().uuidString)
        }
        guard let attempt = answerAttempt else { return }
        let token = begin()
        do {
            let result = try await service.answer(request.requestId, clarificationId: attempt.id,
                                                  value: attempt.value, key: attempt.key)
            guard revision == token else { return }
            try await accept(result, token: token)
        } catch { fail(error, token: token) }
        finish(token)
    }

    private func answerAsk(_ id: String, question: ServiceRequest.Clarification, value: String) async {
        guard !isWorking, canRetry, question.options.contains(where: { $0.value == value }) else { return }
        if answerAttempt?.id != question.clarificationId || answerAttempt?.value != value {
            answerAttempt = (question.clarificationId, value, UUID().uuidString)
        }
        guard let attempt = answerAttempt else { return }
        let token = begin()
        do {
            let result = try await service.answerAsk(id, clarificationId: attempt.id, value: attempt.value, key: attempt.key)
            guard revision == token else { return }
            try await accept(result, token: token)
        } catch { fail(error, token: token) }
        finish(token)
    }

    func refresh() async {
        if request == nil, let askId, !isWorking, canRetry {
            let token = begin()
            do {
                let result = try await service.getAsk(askId)
                guard revision == token else { return }
                try await accept(result, token: token)
            } catch { fail(error, token: token) }
            finish(token)
            return
        }
        guard !isWorking, canRetry, let request else { return }
        let token = begin()
        do {
            let result = try await service.get(request.requestId)
            guard revision == token else { return }
            try await accept(result, token: token)
        } catch { fail(error, token: token) }
        finish(token)
    }

    /// Cancellation supersedes a GET already in flight. A late GET cannot replace the
    /// authoritative cancellation response, even if the transport ignores cancellation.
    func cancel() async {
        guard canRetry, let request, request.status.canCancel else { return }
        let token = begin()
        do {
            let result = try await service.cancel(request.requestId)
            guard revision == token else { return }
            try await accept(result, token: token)
        } catch { fail(error, token: token) }
        finish(token)
    }

    func startAgain() {
        guard !isWorking, !hasActiveAsk else { return }
        polling?.cancel()
        revision = UUID()
        request = nil
        askId = nil
        placeQuestion = nil
        askQuestion = nil
        offers = []
        errorMessage = nil
        correlationId = nil
        isCached = false
        refreshedAt = nil
        createAttempt = nil
        answerAttempt = nil
    }

    func setActive(_ active: Bool) {
        self.active = active
        polling?.cancel()
        if active { schedulePolling() }
        else if hasAsk { isCached = true }
    }

    private func begin() -> UUID {
        polling?.cancel()
        revision = UUID()
        isWorking = true
        errorMessage = nil
        correlationId = nil
        retryAfter = nil
        return revision
    }
    private func accept(_ result: AskResult, token: UUID) async throws {
        _ = try result.validated()
        askId = result.askId
        placeQuestion = result.placeQuestion
        askQuestion = result.clarification
        refreshedAt = now()
        isCached = !active
        if let request = result.request { try await accept(request, token: token) }
        else { request = nil; offers = [] }
    }
    private func accept(_ result: ServiceRequest, token: UUID) async throws {
        _ = try result.validated()
        if request?.requestId != result.requestId { offers = [] }
        request = result
        refreshedAt = now()
        isCached = !active
        if [.chooseOffer, .showResult, .awaitSupplierConfirmation].contains(result.nextAction)
            || (result.nextAction == .waitForOffers && result.progress.offersReady > 0) {
            let received = try await service.offers(result.requestId).validated(for: result.requestId)
            guard revision == token else { return }
            offers = received.offers
        } else {
            offers = []
        }
    }
    private func finish(_ token: UUID) {
        guard revision == token else { return }
        isWorking = false
        if errorMessage == nil { schedulePolling() }
    }
    private func schedulePolling() {
        guard active, !isWorking, errorMessage == nil else { return }
        let interval: Int
        if request?.nextAction == .waitForOffers, let serverInterval = request?.pollAfterSeconds {
            interval = serverInterval
        } else if request == nil, placeQuestion?.status == .asking {
            // Place questions carry no poll interval; check at the same cadence as requests.
            interval = Self.placePollSeconds
        } else { return }
        let token = revision
        let sleep = self.sleep
        polling = Task { [weak self] in
            do {
                try await sleep(interval)
                try Task.checkCancellation()
                guard let self, self.revision == token else { return }
                // The next refresh owns a new task; it must not cancel its own caller.
                self.polling = nil
                await self.refresh()
            } catch { /* Suspension and navigation never become user-facing failures. */ }
        }
    }
    private func fail(_ error: Error, token: UUID, creating: Bool = false) {
        guard revision == token else { return }
        isCached = hasAsk
        if let api = error as? APIError {
            correlationId = api.requestID
            if api.code == "rate_limited" {
                let delay = max(1, min(api.retryAfterSeconds ?? 60, 3600))
                retryAfter = now().addingTimeInterval(TimeInterval(delay))
                errorMessage = "Too many requests. Try again after \(delay) seconds."
            } else if api.code == "restricted_intent" {
                errorMessage = "PLUG cannot help with this request. Nobody was contacted."
            } else if api.fieldCode == "consent_required" {
                errorMessage = "Accept the current terms in your account before making a request. Nothing was created."
            } else if api.code == "unauthenticated" {
                // A revoked or switched account must never keep displaying the previous account's snapshot.
                request = nil
                askId = nil
                placeQuestion = nil
                askQuestion = nil
                offers = []
                isCached = false
                errorMessage = "Your session ended. Sign in again to continue."
            } else if api.code == "not_found" {
                request = nil
                askId = nil
                placeQuestion = nil
                askQuestion = nil
                offers = []
                isCached = false
                errorMessage = "This request is no longer available to your account."
            } else if api.code == "validation_failed" {
                errorMessage = api.fieldCode == "out_of_range"
                    ? "Budgets can be from $5 to $5,000 and distances up to about 30 miles. Nothing was created."
                    : "Check your request and location. Nothing was created."
            } else if api.code == "conflict" {
                errorMessage = "This request changed on the server. Refresh to see its current state."
            } else {
                errorMessage = creating
                    ? "We could not confirm whether your request was saved. Retry the same request safely."
                    : "We could not update this request. Refresh to check the server's current state."
            }
        } else {
            errorMessage = creating
                ? "Unable to connect. Your input is kept here. Retry the same request safely when you are online."
                : "Unable to connect. Showing the last server update. Refresh when you are online."
        }
    }
}
