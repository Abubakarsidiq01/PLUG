import SwiftUI

/// The provider's side of a request (manual v4 Figure A2, P3.S16): what was matched, the offer
/// they send, and the confirmation they owe once chosen. Every state comes from the server; the
/// app never moves a match or a reservation by itself.
@MainActor
final class InboxModel: ObservableObject {
    enum Availability { case unknown, unavailable, available }
    @Published private(set) var availability = Availability.unknown
    @Published private(set) var items: [InboxItem] = []
    @Published private(set) var notificationsPerHour: Int?
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    /// Inline composer errors from the server's 400 details.
    @Published private(set) var fieldErrors: [OfferDraft.Field: String] = [:]
    private let service: RequestServing
    /// One key per offer: a retry of the same offer after a lost response replays it.
    private var offerAttempt: (matchId: String, body: ProviderOfferCreate, key: String)?

    init(service: RequestServing) { self.service = service }

    func item(_ matchId: String) -> InboxItem? { items.first { $0.matchId == matchId } }

    func load() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        await reload()
    }

    private func reload() async {
        do {
            if let inbox = try await service.inbox() {
                items = inbox.items
                notificationsPerHour = inbox.notificationsPerHour
                availability = .available
            } else {
                items = []
                notificationsPerHour = nil
                availability = .unavailable
            }
            errorMessage = nil
        } catch {
            errorMessage = message(for: error, action: "load your inbox")
        }
    }

    func clearFieldError(_ field: OfferDraft.Field) { fieldErrors[field] = nil }

    /// True when the server accepted the offer; the inbox is then reloaded so the item reads offered.
    @discardableResult
    func send(_ item: InboxItem, body: ProviderOfferCreate) async -> Bool {
        guard !isWorking, item.status == .open else { return false }
        if offerAttempt?.matchId != item.matchId || offerAttempt?.body != body {
            offerAttempt = (item.matchId, body, UUID().uuidString)
        }
        guard let attempt = offerAttempt else { return false }
        isWorking = true
        errorMessage = nil
        fieldErrors = [:]
        defer { isWorking = false }
        do {
            _ = try await service.sendOffer(item.requestId, attempt.body, key: attempt.key)
            offerAttempt = nil
            await reload()
            return true
        } catch let api as APIError where api.code == "validation_failed" {
            offerAttempt = nil
            switch api.fieldCode {
            case "over_budget": fieldErrors[.price] = "That is over their budget. Offer their budget or less."
            case "outside_window": fieldErrors[.start] = "Choose a time from now until they need it, within 7 days."
            case "contact_in_note": fieldErrors[.note] = "Leave out phone numbers, emails and links. Contact happens after they confirm."
            default: errorMessage = "Check the price, time and note, then send again. Nothing was sent."
            }
        } catch let api as APIError where api.code == "conflict" {
            offerAttempt = nil
            await reload()
            errorMessage = api.fieldCode == "already_offered" ? "You already sent an offer for this request."
                : "This request has closed. This is where it stands now."
        } catch {
            errorMessage = message(for: error, action: "confirm whether your offer was sent. Send again safely")
        }
        return false
    }

    func decline(_ item: InboxItem, reason: DeclineReason?) async {
        await change(item) { try await self.service.decline(item.matchId, reason: reason) }
    }

    func answer(_ item: InboxItem, _ answer: ReservationAnswer) async {
        await change(item) { try await self.service.answerReservation(item.matchId, answer) }
    }

    private func change(_ item: InboxItem, _ call: () async throws -> InboxItem) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let updated = try await call()
            if let index = items.firstIndex(where: { $0.matchId == updated.matchId }) { items[index] = updated }
        } catch let api as APIError where api.code == "conflict" {
            await reload()
            errorMessage = api.fieldCode == "reservation_closed" || api.fieldCode == "no_reservation"
                ? "This booking can no longer be answered. This is where it stands now."
                : "This request has closed. This is where it stands now."
        } catch {
            errorMessage = message(for: error, action: "confirm your answer. Try again")
        }
    }

    private func message(for error: Error, action: String) -> String {
        if let api = error as? APIError {
            switch api.code {
            case "rate_limited": return "Too many tries. Wait a minute and try again."
            case "unauthenticated": return "Your session ended. Sign in again to continue."
            case "forbidden": return "Your provider account can't do this right now."
            default: break
            }
        }
        return "We could not \(action)."
    }
}

/// The provider's Inbox (manual v4 §2.3). It shows only when this account has a provider
/// profile. While the server's inbox is off it says so plainly instead of showing invented requests.
struct InboxView: View {
    let service: RequestServing
    let profile: ProviderProfile
    let onChange: (ProviderProfile) -> Void
    @StateObject private var location = RequestLocationModel()
    @StateObject private var inbox: InboxModel
    @State private var editing = false
    @Environment(\.scenePhase) private var scenePhase

    init(service: RequestServing, profile: ProviderProfile, onChange: @escaping (ProviderProfile) -> Void) {
        self.service = service
        self.profile = profile
        self.onChange = onChange
        _inbox = StateObject(wrappedValue: InboxModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                        PageTitle(title: "Inbox")
                        Label(profile.accepting ? "Your provider profile is saved." : "Your provider profile is paused.",
                              systemImage: profile.accepting ? "checkmark.circle.fill" : "pause.circle.fill")
                            .plugText(.body).fontWeight(.semibold).foregroundStyle(PlugTokens.Color.ink900)
                    }
                    if let error = inbox.errorMessage {
                        PlugNotice(message: error, tone: .alert, actionTitle: "Try again", actionDisabled: inbox.isWorking) {
                            Task { await inbox.load() }
                        }
                    }
                    switch inbox.availability {
                    case .available where !inbox.items.isEmpty: list
                    case .available: emptyState(title: "No requests here yet", line: emptyLine)
                    case .unavailable:
                        emptyState(title: "No requests here yet",
                                   line: "Your skills and hours are saved. Receiving and replying to requests here is coming in a future update.")
                    case .unknown:
                        if inbox.errorMessage == nil {
                            ProgressView("Checking your inbox").plugText(.bodySmall).tint(PlugTokens.Color.ink600)
                                .foregroundStyle(PlugTokens.Color.ink600)
                        }
                    }
                    profileCard
                }
                .foregroundStyle(PlugTokens.Color.ink900)
                .frame(maxWidth: PlugTokens.Layout.measure, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, PlugTokens.Space.s6).padding(.vertical, PlugTokens.Space.s4)
            }
            .background(PlugTokens.Color.paper)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await inbox.load() }
            .navigationDestination(for: String.self) { matchId in InboxItemView(model: inbox, matchId: matchId) }
            .sheet(isPresented: $editing) {
                ProviderOnboardingView(service: service, location: location, current: profile,
                                       inboxAvailable: inbox.availability == .available) { saved in
                    editing = false
                    onChange(saved)
                }
            }
        }
        .task { await inbox.load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await inbox.load() } } }
    }

    private var emptyLine: String {
        let cap = inbox.notificationsPerHour.map { " PLUG sends you at most \($0) an hour." } ?? ""
        return "When someone nearby asks for what you offer, the request shows up here with the time you have to reply.\(cap)"
    }

    private func emptyState(title: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
            IllustrationTile(name: "IllInbox", size: 88)
            Text(title).plugText(.title)
            Text(line).plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(PlugTokens.Color.ink900)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-empty")
    }

    /// Items that need an answer first, then the rest, each in the server's order.
    private var list: some View {
        let waiting = inbox.items.filter { [.open, .selected].contains($0.status) }
        let earlier = inbox.items.filter { ![.open, .selected].contains($0.status) }
        return VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
            if !waiting.isEmpty { section("Needs your answer", waiting) }
            if !earlier.isEmpty { section("Earlier", earlier) }
            if let cap = inbox.notificationsPerHour {
                caption("PLUG sends you at most \(cap) requests an hour.")
            }
        }
        .accessibilityIdentifier("inbox-list")
    }

    private func section(_ title: String, _ items: [InboxItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).plugText(.title2).accessibilityAddTraits(.isHeader).padding(.bottom, PlugTokens.Space.s3)
            PlugDivider()
            ForEach(items) { item in
                NavigationLink(value: item.matchId) { InboxRow(item: item) }
                    .buttonStyle(PlugPressStyle())
                    .accessibilityIdentifier("inbox-item-\(item.status.rawValue)")
                PlugDivider()
            }
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            BusinessIdentity(name: profile.business?.name ?? "Your business", business: profile.business, score: profile.score)
            if let about = profile.business?.about { Text(about).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600) }
            if let links = profile.business?.links { BusinessLinks(links: links) }
            Text("What you offer").plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
            PlugFlowLayout {
                ForEach(profile.skills) { skill in
                    SkillKey(title: skill.display, fill: PlugTokens.Color.sunk)
                }
                ForEach(profile.customSkills ?? [], id: \.self) { label in
                    SkillKey(title: label, fill: PlugTokens.Color.card)
                        .accessibilityLabel("\(label), your own skill")
                }
            }
            FlowMetrics(items: [("Travel area", distance(profile.travelRadiusM), "location"),
                                ("Licence", profile.licenceOnFile ? "On file" : "None given", "doc.text")], compact: true)
            VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                Text("Your hours").plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
                Text(profile.availability.map(\.summary).joined(separator: "\n")).plugText(.body)
            }
            Button("Edit business & services") { editing = true }
                .buttonStyle(FlowActionStyle(primary: true))
                .accessibilityIdentifier("provider-edit")
        }
        .marketCard()
    }
}

// MARK: - Shared pieces

extension InboxItem {
    var budgetText: String { budgetCents.map { "Up to \(money($0, currency))" } ?? "No budget set" }
    var neededText: String { neededBy.map { "Needed by \(clock($0))" } ?? "As soon as possible" }
    var statusTitle: String {
        switch status {
        case .open: return "New"
        case .offered: return "Offer sent"
        case .declined: return "Declined"
        case .expired: return "Missed"
        case .selected: return "Chosen"
        case .confirmed: return "Confirmed"
        case .notChosen: return "Not chosen"
        case .closed: return "Closed"
        }
    }
}

/// The clock alone today, the day too otherwise.
private func clock(_ date: Date) -> String {
    Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened)
        : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}

/// A small hairline tag; filled green only for the two states that need the provider.
private struct StatusTag: View {
    let item: InboxItem
    var body: some View {
        let strong = [.open, .selected].contains(item.status)
        let shape = RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous)
        Text(item.statusTitle).plugText(.label)
            .foregroundStyle(strong ? PlugTokens.Color.paper : PlugTokens.Color.ink900)
            .padding(.horizontal, PlugTokens.Space.s2).padding(.vertical, PlugTokens.Space.s1)
            .background(strong ? PlugTokens.Color.brandGreen : Color.clear, in: shape)
            .overlay { if !strong { shape.strokeBorder(PlugTokens.Color.ruleControl, lineWidth: PlugShape.rule) } }
            .fixedSize()
    }
}

/// The server's deadline, counted down each second; it disappears once the time has passed.
/// VoiceOver hears the clock time once, not a number changing every second.
private struct Countdown: View {
    let until: Date
    let verb: String
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = until.timeIntervalSince(context.date)
            if left > 0 {
                Label("\(Duration.seconds(Int(left.rounded(.up))).formatted(.time(pattern: .minuteSecond))) left to \(verb)",
                      systemImage: "timer")
                    .plugText(.bodySmall).fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(PlugTokens.Color.brandGreen)
                    .accessibilityLabel("\(verb.capitalized) by \(until.formatted(date: .omitted, time: .shortened))")
            }
        }
    }
}

private struct InboxRow: View {
    let item: InboxItem
    var body: some View {
        HStack(alignment: .center, spacing: PlugTokens.Space.s3) {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                HStack(alignment: .firstTextBaseline, spacing: PlugTokens.Space.s3) {
                    // Untrusted display text: a plain String, never markup.
                    Text(verbatim: item.serviceName).plugText(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    StatusTag(item: item)
                }
                Text("\(item.budgetText) · \(item.neededText) · \(distance(item.distanceM)) away")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                    .fixedSize(horizontal: false, vertical: true)
                if item.status == .open { Countdown(until: item.respondBy, verb: "reply") }
                if item.status == .selected, let reservation = item.reservation {
                    Countdown(until: reservation.confirmBy, verb: "confirm")
                }
            }
            .multilineTextAlignment(.leading)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .medium))
                .foregroundStyle(PlugTokens.Color.brandGreen).accessibilityHidden(true)
        }
        .foregroundStyle(PlugTokens.Color.ink900)
        .padding(.vertical, PlugTokens.Space.s4)
        .frame(minHeight: PlugTokens.minTouchTarget)
        .contentShape(Rectangle())
    }
}

// MARK: - One matched request

struct InboxItemView: View {
    @ObservedObject var model: InboxModel
    let matchId: String
    @State private var draft = OfferDraft(start: Date())
    @State private var showErrors = false
    @State private var prepared = false
    @State private var declining = false
    @State private var releasing = false
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                if let item = model.item(matchId) {
                    header(item)
                    if let error = model.errorMessage { PlugNotice(message: error, tone: .alert) }
                    state(item)
                } else {
                    PlugNotice(title: "Not in your inbox", message: "This request is no longer in your inbox. Go back and refresh.")
                }
            }
            .foregroundStyle(PlugTokens.Color.ink900)
            .frame(maxWidth: PlugTokens.Layout.measure, alignment: .leading).frame(maxWidth: .infinity)
            .padding(.horizontal, PlugTokens.Space.s6).padding(.vertical, PlugTokens.Space.s4)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PlugTokens.Color.paper)
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PlugTokens.Color.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .refreshable { await model.load() }
        .plugToast($toast)
        .tint(PlugTokens.Color.ink900)
        .onAppear(perform: prepare)
    }

    private func prepare() {
        guard !prepared, let item = model.item(matchId) else { return }
        prepared = true
        // Half an hour out on a five-minute mark, never past what the server accepts.
        let now = Date()
        let soon = now.addingTimeInterval(30 * 60)
        let rounded = Date(timeIntervalSinceReferenceDate: (soon.timeIntervalSinceReferenceDate / 300).rounded(.up) * 300)
        draft.start = max(now, min(rounded, OfferDraft.latestStart(neededBy: item.neededBy, now: now)))
    }

    private func header(_ item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            HStack { Overline("A request near you"); Spacer(minLength: 0); StatusTag(item: item) }
            Text(verbatim: item.serviceName).plugText(.display)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if item.status == .open { Countdown(until: item.respondBy, verb: "reply") }
            VStack(spacing: 0) {
                PlugDivider()
                valueRow("Budget", item.budgetCents.map { money($0, item.currency) } ?? "No budget set")
                valueRow("When", item.neededBy.map { "By \(clock($0))" } ?? "As soon as possible")
                valueRow("Distance", "\(distance(item.distanceM)) from your base")
                valueRow("Sent to you", clock(item.notifiedAt), last: true)
            }
            caption("You see what they need, never who they are or where they are.")
        }
    }

    @ViewBuilder private func state(_ item: InboxItem) -> some View {
        switch item.status {
        case .open: composer(item); declineSection(item)
        case .offered:
            if let offer = item.offer { sentOffer(offer, title: "Offer sent",
                line: "They see your offer next to any others. If they choose it, you confirm it here.") }
        case .declined:
            PlugNotice(title: "You declined", message: "Declining is free. It never counts against you.")
        case .expired:
            PlugNotice(title: "Reply time passed", message: "The time to reply ran out before you answered.")
        case .selected: selected(item)
        case .confirmed:
            if let reservation = item.reservation { booking(reservation, confirmed: true) }
            if let offer = item.offer { sentOffer(offer, title: "Your offer", line: nil) }
        case .notChosen:
            PlugNotice(title: "Not chosen", message: notChosenLine(item))
            if let offer = item.offer { sentOffer(offer, title: "Your offer", line: nil) }
        case .closed:
            PlugNotice(title: "Closed", message: item.reservation?.status == .canceled
                       ? "They canceled the request. Nothing is booked."
                       : "The request was canceled or ended before it was settled. This doesn't count against you.")
        }
    }

    private func notChosenLine(_ item: InboxItem) -> String {
        switch item.reservation?.status {
        case .released: return "You said you couldn't make it. Nothing is booked."
        case .timedOut: return "The time to confirm ran out. Nothing is booked."
        default: return "They chose another offer, or your offer ended."
        }
    }

    // MARK: Composer

    private func composer(_ item: InboxItem) -> some View {
        let now = Date()
        let latest = OfferDraft.latestStart(neededBy: item.neededBy, now: now)
        let errors = showErrors ? draft.errors(for: item, now: now).merging(model.fieldErrors) { local, _ in local }
            : model.fieldErrors
        return VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
            Text("Send an offer").plugText(.title)
            PlugTextField(title: "Your price in dollars", text: $draft.price, error: errors[.price])
                .keyboardType(.decimalPad)
                .onChange(of: draft.price) { _, _ in model.clearFieldError(.price) }
                .accessibilityIdentifier("offer-price")
            if latest > now {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                    DatePicker("Start time", selection: $draft.start, in: now...latest,
                               displayedComponents: [.date, .hourAndMinute])
                        .plugText(.body).tint(PlugTokens.Color.brandGreen)
                        .frame(minHeight: PlugTokens.minTouchTarget)
                        .onChange(of: draft.start) { _, _ in model.clearFieldError(.start) }
                        .accessibilityIdentifier("offer-start")
                    if let error = errors[.start] { fieldError(error) }
                }
            } else {
                fieldError("Their time has passed, so a start time can't be offered.")
            }
            noteField(errors[.note])
            Button(model.isWorking ? "Sending…" : "Send offer") {
                showErrors = true
                guard draft.errors(for: item, now: Date()).isEmpty, let body = draft.body() else { return }
                Task { if await model.send(item, body: body) { toast = "Offer sent" } }
            }
            .buttonStyle(PlugButtonStyle(kind: .primary))
            .disabled(model.isWorking || latest <= now)
            .accessibilityIdentifier("offer-send")
            caption("They see your price, time and note. Contact details are shared only after they confirm.")
        }
        .plugCard()
    }

    private func noteField(_ error: String?) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            HStack {
                Text("Note (optional)").plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
                Spacer()
                Text("\(draft.note.count)/\(OfferDraft.noteLimit)").plugText(.label).monospacedDigit()
                    .foregroundStyle(PlugTokens.Color.ink600)
                    .accessibilityLabel("\(OfferDraft.noteLimit - draft.note.count) characters left")
            }
            TextField("", text: $draft.note, axis: .vertical)
                .plugText(.body).lineLimit(2...4)
                .padding(PlugTokens.Space.s3)
                .frame(minHeight: PlugTokens.minTouchTarget)
                .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous)
                    .strokeBorder(error != nil ? PlugTokens.Color.alert600 : PlugTokens.Color.ruleControl, lineWidth: PlugShape.rule))
                .onChange(of: draft.note) { _, value in
                    if value.count > OfferDraft.noteLimit { draft.note = String(value.prefix(OfferDraft.noteLimit)) }
                    model.clearFieldError(.note)
                }
                .accessibilityLabel("Note (optional)")
                .accessibilityIdentifier("offer-note")
            if let error { fieldError(error) }
        }
    }

    private func declineSection(_ item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            Button("Decline this request") { declining = true }
                .buttonStyle(PlugButtonStyle(kind: .outline))
                .disabled(model.isWorking)
                .accessibilityIdentifier("inbox-decline")
            caption("Declining is free and never counts against you. Not replying does.")
        }
        .confirmationDialog("Decline this request?", isPresented: $declining, titleVisibility: .visible) {
            ForEach(DeclineReason.allCases) { reason in
                Button(reason.title) { Task { await model.decline(item, reason: reason) } }
            }
            Button("Decline without a reason") { Task { await model.decline(item, reason: nil) } }
            Button("Keep it", role: .cancel) { }
        } message: {
            Text("A reason is optional. It helps matching and is never shown to the person who asked.")
        }
    }

    // MARK: Offer and booking

    private func sentOffer(_ offer: ServiceOffer, title: String, line: String?) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text(title).plugText(.title2)
            Text(money(offer.priceCents, offer.currency)).plugDisplay(40, weight: 500).monospacedDigit()
            VStack(spacing: 0) {
                PlugDivider()
                valueRow("Start", clock(offer.availableAt))
                valueRow("Offer ends", clock(offer.expiresAt), last: offer.note == nil)
            }
            if let note = offer.note {
                Text(verbatim: note).plugText(.body).fixedSize(horizontal: false, vertical: true)
            }
            if let line { caption(line) }
        }
        .plugCard()
        .accessibilityIdentifier("inbox-offer-sent")
    }

    private func booking(_ reservation: Reservation, confirmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
            if confirmed {
                Label("You confirmed", systemImage: "checkmark.circle.fill")
                    .plugText(.title3).foregroundStyle(PlugTokens.Color.brandGreen)
                Text("Booked").plugText(.display)
            } else {
                Overline("They chose your offer")
                Text("Can you make it?").plugText(.display)
            }
            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                Text("Booking reference").plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
                Text(reservation.bookingRef).plugDisplay(40, weight: 500).monospaced().kerning(4)
                    .accessibilityLabel(reservation.bookingRef.map(String.init).joined(separator: " "))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("booking-ref")
            if confirmed {
                caption("Both of you can quote this reference.")
            } else {
                VStack(spacing: 0) {
                    PlugDivider()
                    valueRow("Confirm by", reservation.confirmBy.formatted(date: .omitted, time: .shortened), last: true)
                }
                Countdown(until: reservation.confirmBy, verb: "confirm")
                Text("Nothing is booked until you confirm.").plugText(.body).fontWeight(.medium)
            }
        }
        .plugCard()
    }

    private func selected(_ item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
            if let reservation = item.reservation { booking(reservation, confirmed: false) }
            Button(model.isWorking ? "Confirming…" : "Confirm") { Task { await model.answer(item, .confirm) } }
                .buttonStyle(PlugButtonStyle(kind: .primary))
                .disabled(model.isWorking)
                .accessibilityIdentifier("inbox-confirm")
            Button("Can't make it") { releasing = true }
                .buttonStyle(PlugButtonStyle(kind: .outline))
                .disabled(model.isWorking)
                .accessibilityIdentifier("inbox-release")
                .confirmationDialog("Release this booking?", isPresented: $releasing, titleVisibility: .visible) {
                    Button("I can't make it", role: .destructive) { Task { await model.answer(item, .release) } }
                    Button("Keep it", role: .cancel) { }
                } message: {
                    Text("They can choose another offer, if one is left.")
                }
            if let offer = item.offer { sentOffer(offer, title: "Your offer", line: nil) }
        }
    }

    private func fieldError(_ value: String) -> some View {
        Label(value, systemImage: "exclamationmark.triangle")
            .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.alert600)
            .fixedSize(horizontal: false, vertical: true)
    }
}
