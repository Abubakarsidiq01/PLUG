import MapKit
import SwiftUI

/// The Ask flow from manual Figure 10: home prompt, query composer, searching, results and
/// request detail. Colours, type, spacing and radii come only from the Figure 7 tokens and
/// components follow Figure 8: flat cards, one truth badge per card, right-aligned values,
/// 6px chips and exactly one primary action per screen. Every value shown came from the
/// server, or for nearby businesses from Apple Maps with price and availability Unknown.
struct AskView: View {
    @StateObject private var model: RequestModel
    @StateObject private var location = RequestLocationModel()
    @StateObject private var nearby = NearbyBusinessesModel()
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var textFocused: Bool
    @State private var composing = false
    @State private var filters = RequestFilters()
    @State private var showValidation = false

    init(service: RequestServing) { _model = StateObject(wrappedValue: RequestModel(service: service)) }

    var body: some View {
        NavigationStack {
            Group {
                if let request = model.request { requestScreen(request) } else { home }
            }
            .navigationDestination(isPresented: $composing) { composer }
            .toolbarBackground(PlugTokens.Color.surface0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onChange(of: scenePhase) { _, phase in
                model.setActive(phase == .active)
                if phase == .active, model.request != nil { Task { await model.refresh() } }
            }
            .onChange(of: model.request?.requestId) { _, id in
                nearby.reset()
                if id != nil { composing = false }
            }
        }
        .tint(PlugTokens.Color.brand600)
        // Active means the Ask tab is on screen. Attached to the stack, not its root page, so
        // pushing "New request" does not mark a request it is about to create as stale.
        .task {
            model.setActive(true)
            if model.request != nil { await model.refresh() }
        }
        .onDisappear { model.setActive(false) }
    }

    // MARK: Home prompt (Figure 10, screen 4)

    private var home: some View {
        page {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
                Text("What do you need?").plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
                Text("Ask for any local service in your own words. PLUG finds who can help near you.")
                    .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                Button { composing = true } label: {
                    HStack(spacing: PlugTokens.Space.s2) {
                        Image(systemName: "magnifyingglass").accessibilityHidden(true)
                        Text("e.g. shoe repair, barber, plumber")
                        Spacer(minLength: 0)
                    }
                    .plugText(.body)
                    .foregroundStyle(PlugTokens.Color.ink400)
                    .padding(.horizontal, PlugTokens.Space.s4)
                    .frame(minHeight: PlugTokens.minTouchTarget)
                    .background(PlugTokens.Color.surface0, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.md).strokeBorder(PlugTokens.Color.line300))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start a new request")
                .accessibilityIdentifier("request-start")
            }
            .plugCard()

            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                Text("Popular examples").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
                ForEach(Example.all) { example in
                    Button {
                        model.text = example.prompt
                        composing = true
                    } label: {
                        HStack(spacing: PlugTokens.Space.s3) {
                            Image(systemName: example.symbol)
                                .foregroundStyle(PlugTokens.Color.brand600)
                                .frame(width: PlugTokens.Space.s6)
                                .accessibilityHidden(true)
                            Text(example.prompt).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: PlugTokens.Space.s2)
                            Image(systemName: "chevron.right").foregroundStyle(PlugTokens.Color.ink400)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: PlugTokens.minTouchTarget)
                        .plugCard()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Starts a request with this text")
                }
            }
            privateTestNote
        }
        .navigationTitle("Ask")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Query composer (Figure 10, screen 5)

    private var composer: some View {
        page {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                Text("What do you need?").plugText(.label).foregroundStyle(PlugTokens.Color.ink900)
                TextField("Fix my shoe for $45 tomorrow", text: $model.text, axis: .vertical)
                    .plugText(.body)
                    .lineLimit(2...5)
                    .focused($textFocused)
                    .padding(PlugTokens.Space.s3)
                    .frame(minHeight: PlugTokens.minTouchTarget)
                    .background(PlugTokens.Color.surface0, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.md)
                        .strokeBorder(textFocused ? PlugTokens.Color.brand600 : PlugTokens.Color.line300,
                                      lineWidth: textFocused ? 2 : 1))
                    .accessibilityIdentifier("request-text")
                    .accessibilityLabel("What do you need?")
                    .disabled(model.isWorking)
                HStack(alignment: .firstTextBaseline) {
                    Text("Say the service, and if you like your budget, when and how far.")
                        .plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
                    Spacer(minLength: PlugTokens.Space.s2)
                    Text("\(model.text.unicodeScalars.count)/500").plugText(.caption)
                        .foregroundStyle(PlugTokens.Color.ink400).monospacedDigit()
                }
                if showValidation, let error = model.textError { fieldError(error) }
            }

            chipGroup("Budget", options: RequestFilters.Budget.allCases, title: \.title, selection: $filters.budget)
            chipGroup("Time", options: RequestFilters.Time.allCases, title: \.title, selection: $filters.time)
            chipGroup("Max distance", options: RequestFilters.Distance.allCases, title: \.title, selection: $filters.distance)

            locationSection
            failure
            Button(model.isWorking ? "Sending your request…" : "Find options") {
                showValidation = true
                guard let coordinate = location.location else { return }
                textFocused = false
                Task { await model.submit(location: coordinate, filters: filters) }
            }
            .buttonStyle(AuthActionStyle(primary: true))
            .disabled(model.isWorking || location.isWorking)
            privateTestNote
        }
        .navigationTitle("New request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A multi-line field has no return-to-dismiss; this keeps the location controls reachable.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { textFocused = false }
            }
        }
        .toolbarBackground(PlugTokens.Color.surface0, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func chipGroup<Option: Identifiable & Equatable>(_ label: String, options: [Option],
                                                              title: KeyPath<Option, String>,
                                                              selection: Binding<Option>) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            Text(label).plugText(.label).foregroundStyle(PlugTokens.Color.ink900)
            PlugFlowLayout {
                ForEach(options) { option in
                    PlugChip(title: option[keyPath: title], selected: selection.wrappedValue == option) {
                        selection.wrappedValue = option
                    }
                    .disabled(model.isWorking)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Where").plugText(.label).foregroundStyle(PlugTokens.Color.ink900)
            if let label = location.label, location.location != nil {
                Label(label, systemImage: "mappin.circle.fill")
                    .plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                    .accessibilityIdentifier("request-location-ready")
            } else {
                Text("We use an approximate location only when you ask, or you can type an address.")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            }
            Button("Use my approximate location") { location.useDeviceLocation() }
                .buttonStyle(AuthActionStyle())
                .disabled(location.isWorking || model.isWorking)
            PlugTextField(title: "Street address and city", text: $location.address)
                .textContentType(.fullStreetAddress).disabled(model.isWorking)
                .accessibilityIdentifier("request-address")
            Button(location.isWorking ? "Checking address…" : "Use this address") {
                Task { await location.resolveAddress() }
            }
            .buttonStyle(AuthActionStyle())
            .disabled(location.isWorking || model.isWorking || location.address.isEmpty)
            if location.address.isEmpty {
                Text("Type an address to use it instead.").plugText(.caption).foregroundStyle(PlugTokens.Color.ink400)
            }
            if let error = location.errorMessage { fieldError(error) }
            if showValidation, location.location == nil, !location.isWorking {
                fieldError("Choose your approximate location or check an address before searching.")
            }
        }
    }

    // MARK: Request (Figure 10, screens 6 to 8)

    private func requestScreen(_ request: ServiceRequest) -> some View {
        page {
            summary(request)
            if model.isCached {
                Label("Cached result. Refresh to check availability.", systemImage: "clock.arrow.circlepath")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                    .accessibilityIdentifier("request-cached")
                if let refreshedAt = model.refreshedAt {
                    Text("Last updated \(refreshedAt.formatted(date: .abbreviated, time: .standard))")
                        .plugText(.caption).foregroundStyle(PlugTokens.Color.ink400)
                }
            }
            failure
            switch request.nextAction {
            case .answerClarification:
                if let question = request.clarification { clarification(question) }
            case .waitForOffers:
                searching(request)
                offerCards
            case .chooseOffer, .showResult:
                if model.isWorking, model.offers.isEmpty {
                    Text("Loading current offers…").plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                } else if model.offers.isEmpty {
                    emptyState("No current offers", "Refresh to check whether this request has expired.")
                }
                offerCards
            case .awaitSupplierConfirmation:
                emptyState("Waiting for supplier confirmation", "This is not a confirmed booking. Refresh to check the latest update.")
                offerCards
            case .showNoResult:
                emptyState("No matches this time", request.noResultReason?.explanation ?? "No current offers are available.")
                if request.noResultReason != .clarificationUnanswered, !request.constraints.searchTerms.isEmpty {
                    nearbySection(request)
                }
            case .none:
                emptyState("Request canceled", "PLUG confirmed the cancellation. Nobody will be contacted for this request.")
            }
            if request.status.canCancel {
                Button("Cancel request") { Task { await model.cancel() } }
                    .buttonStyle(PlugDestructiveStyle())
                    .accessibilityIdentifier("request-cancel")
            } else {
                Button("Start a new request") { model.startAgain(); filters = RequestFilters(); showValidation = false }
                    .buttonStyle(AuthActionStyle(primary: true)).disabled(model.isWorking)
            }
            Text("Reference \(request.requestId)")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(PlugTokens.Color.ink400)
                .textSelection(.enabled)
            privateTestNote
        }
        .navigationTitle(title(for: request))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") { Task { await model.refresh() } }.disabled(model.isWorking)
            }
        }
    }

    private func title(for request: ServiceRequest) -> String {
        switch request.nextAction {
        case .answerClarification: return "One question"
        case .waitForOffers: return "Finding options"
        case .chooseOffer, .showResult: return "Top options"
        default: return "Your request"
        }
    }

    private func summary(_ request: ServiceRequest) -> some View {
        let c = request.constraints
        let parts = [
            c.budgetCents.map { "Under " + money($0, c.currency) } ?? "Any price",
            c.neededBy.map { "By " + when($0) } ?? "As soon as possible",
            "Within " + distance(c.maxDistanceM),
        ]
        return VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            Text(c.serviceName ?? "Choosing a service").plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
            Text(request.text).plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
            Text(parts.joined(separator: " · ")).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
        }
        .accessibilityElement(children: .combine)
    }

    private func clarification(_ question: ServiceRequest.Clarification) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text(question.question).plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            Text("Choose one. PLUG asks at most one question.").plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            ForEach(question.options, id: \.value) { option in
                Button(option.label) { Task { await model.answer(option.value) } }
                    .buttonStyle(AuthActionStyle()).disabled(model.isWorking)
            }
        }
        .plugCard()
    }

    /// Figure 10 screen 6 driven only by server status and counts, never by elapsed time.
    private func searching(_ request: ServiceRequest) -> some View {
        let p = request.progress
        let stage: Int = switch request.status {
        case .submitted, .routed: 1
        case .awaitingResponses: 2
        default: 3
        }
        let steps = ["Understanding your request", "Checking participating providers", "Waiting for replies", "Preparing results"]
        return VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                Text("Checking participating providers").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
                Text("\(p.contacted) contacted · \(p.replied) replied · \(p.offersReady) \(p.offersReady == 1 ? "offer" : "offers") ready")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            }
            ProgressView(value: Double(p.replied), total: Double(max(p.contacted, 1)))
                .tint(PlugTokens.Color.brand600)
                .accessibilityLabel("Replies received")
                .accessibilityValue("\(p.replied) of \(p.contacted)")
            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: PlugTokens.Space.s3) {
                        Image(systemName: index < stage ? "checkmark.circle.fill" : index == stage ? "circle.inset.filled" : "circle")
                            .foregroundStyle(index <= stage ? PlugTokens.Color.brand600 : PlugTokens.Color.ink400)
                            .accessibilityHidden(true)
                        Text(step).plugText(.body)
                            .foregroundStyle(index == stage ? PlugTokens.Color.brand600 : index < stage ? PlugTokens.Color.ink900 : PlugTokens.Color.ink400)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(index < stage ? "Done" : index == stage ? "In progress" : "Not started")
                }
            }
        }
        .plugCard()
        .accessibilityIdentifier("request-progress")
    }

    private var offerCards: some View {
        ForEach(model.offers) { offer in
            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: PlugTokens.Space.s2) { offerTitle(offer); Spacer(minLength: 0); TruthBadge(label: offer.truthLabel) }
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s2) { offerTitle(offer); TruthBadge(label: offer.truthLabel) }
                }
                VStack(spacing: 0) {
                    valueRow("Price", offer.price)
                    valueRow("Earliest", offer.availableAt.formatted(date: .omitted, time: .shortened))
                    valueRow("Offer expires", offer.expiresAt.formatted(date: .omitted, time: .shortened), last: true)
                }
                NavigationLink { OfferDetailView(offer: offer, cached: model.isCached) } label: { Text("View details") }
                    .buttonStyle(AuthActionStyle())
            }
            .plugCard()
        }
    }

    private func offerTitle(_ offer: ServiceOffer) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
            Text(offer.place.name).plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            Text("\(distance(offer.place.distanceM)) · \(offer.place.address)").plugText(.caption)
                .foregroundStyle(PlugTokens.Color.ink600)
        }
    }

    // MARK: Nearby businesses from Apple Maps (ADR-009)

    private func nearbySection(_ request: ServiceRequest) -> some View {
        let c = request.constraints
        return VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Nearby businesses").plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
            Text("From Apple Maps. PLUG has not contacted these businesses, so price and availability are unknown. Call or get directions to check.")
                .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            switch nearby.phase {
            case .idle, .searching:
                HStack(spacing: PlugTokens.Space.s2) {
                    ProgressView()
                    Text("Searching Apple Maps for \((c.serviceName ?? "this service").lowercased()) within \(distance(c.maxDistanceM))…")
                        .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                }
            case .empty:
                emptyState("No businesses found", "Apple Maps found nothing matching within \(distance(c.maxDistanceM)). Start a new request with a wider distance.")
            case .failed:
                emptyState("Apple Maps did not respond", "Check your connection, then search again.")
                Button("Search again") {
                    Task { await nearby.search(terms: c.searchTerms, around: c.location, radiusM: c.maxDistanceM, force: true) }
                }
                .buttonStyle(AuthActionStyle())
            case .loaded:
                ForEach(nearby.businesses) { business in businessCard(business) }
            }
        }
        .accessibilityIdentifier("request-nearby")
        .task(id: request.requestId) {
            await nearby.search(terms: c.searchTerms, around: c.location, radiusM: c.maxDistanceM)
        }
    }

    private func businessCard(_ business: NearbyBusiness) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: PlugTokens.Space.s2) { businessTitle(business); Spacer(minLength: 0); TruthBadge(label: .unknown) }
                VStack(alignment: .leading, spacing: PlugTokens.Space.s2) { businessTitle(business); TruthBadge(label: .unknown) }
            }
            VStack(spacing: 0) {
                valueRow("Price", "Unknown")
                valueRow("Availability", "Unknown", last: business.phone == nil)
                if let phone = business.phone, let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                    HStack {
                        Text("Phone").plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                        Spacer(minLength: PlugTokens.Space.s2)
                        Link(phone, destination: url).plugText(.bodySmall)
                    }
                    .frame(minHeight: PlugTokens.minTouchTarget)
                }
            }
            Button("Get directions") { business.mapItem.openInMaps() }.buttonStyle(AuthActionStyle())
        }
        .plugCard()
    }

    private func businessTitle(_ business: NearbyBusiness) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
            Text(business.name).plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            Text([distance(business.distanceM), business.address].compactMap { $0 }.joined(separator: " · "))
                .plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
        }
    }

    // MARK: Shared

    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s6) { content() }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, PlugTokens.Space.s4)
                .padding(.vertical, PlugTokens.Space.s6)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PlugTokens.Color.surface0)
    }

    private func emptyState(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            Text(title).plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            Text(detail).plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
        }
        .plugCard()
    }

    private var privateTestNote: some View {
        Text("Private test. Participating suppliers are demo data and nearby businesses come from Apple Maps. Nobody is contacted and nothing is booked.")
            .plugText(.caption).foregroundStyle(PlugTokens.Color.ink400)
    }

    /// §11.3 form-level error: says what failed and whether anything was saved.
    @ViewBuilder private var failure: some View {
        if let message = model.errorMessage {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                Text(message).plugText(.body).foregroundStyle(PlugTokens.Color.danger600)
                if let correlation = model.correlationId {
                    Text("Support reference \(correlation)").font(.system(.caption, design: .monospaced))
                        .foregroundStyle(PlugTokens.Color.ink600).textSelection(.enabled)
                }
                if model.request != nil {
                    Button("Retry update") { Task { await model.refresh() } }
                        .plugText(.label).frame(minHeight: PlugTokens.minTouchTarget).disabled(model.isWorking)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PlugTokens.Space.s4)
            .background(PlugTokens.Color.danger50, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.md).strokeBorder(PlugTokens.Color.dangerBorder))
            .accessibilityIdentifier("request-error")
        }
    }

    /// §11.3 field-level error beneath the field, in words.
    private func fieldError(_ value: String) -> some View {
        Text(value).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.danger600)
    }
}

/// Figure 10 "Popular examples". They only fill the text; the server decides the service.
private struct Example: Identifiable {
    let prompt: String
    let symbol: String
    var id: String { prompt }
    static let all = [
        Example(prompt: "Fix my shoes for $45 tomorrow", symbol: "shoe"),
        Example(prompt: "Barber under $35 in 30 minutes", symbol: "scissors"),
        Example(prompt: "Plumber for a leaking sink today", symbol: "wrench.and.screwdriver"),
    ]
}

/// §11.2: the one place truth colours appear. The server sets the label; the app never computes it.
private struct TruthBadge: View {
    let label: ServiceOffer.TruthLabel
    var body: some View {
        Text(label.title)
            .plugText(.overline)
            .padding(.horizontal, PlugTokens.Space.s2)
            .padding(.vertical, PlugTokens.Space.s1)
            .foregroundStyle(label.foreground)
            .background(label.surface, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.sm).strokeBorder(label.foreground.opacity(0.35)))
            .fixedSize()
            .accessibilityLabel(label.explanation)
    }
}

/// §11.4: values right-aligned in a key/value column so they scan vertically.
private func valueRow(_ label: String, _ value: String, last: Bool = false) -> some View {
    VStack(spacing: 0) {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                Spacer(minLength: PlugTokens.Space.s2)
                Text(value).plugText(.body).fontWeight(.semibold).foregroundStyle(PlugTokens.Color.ink900)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                Text(label).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                Text(value).plugText(.body).fontWeight(.semibold).foregroundStyle(PlugTokens.Color.ink900)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, PlugTokens.Space.s2)
        if !last { Rectangle().fill(PlugTokens.Color.line200).frame(height: 1) }
    }
    .accessibilityElement(children: .combine)
}

private func distance(_ metres: Int) -> String {
    Measurement(value: Double(metres), unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
}

/// Figure 10 style: "3:30 PM today", "11:59 PM tomorrow", otherwise a short weekday date.
private func when(_ date: Date, calendar: Calendar = .current) -> String {
    let time = date.formatted(date: .omitted, time: .shortened)
    if calendar.isDateInToday(date) { return "\(time) today" }
    if calendar.isDateInTomorrow(date) { return "\(time) tomorrow" }
    return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
}

private func money(_ cents: Int, _ currency: String) -> String {
    (Decimal(cents) / 100).formatted(.currency(code: currency))
}

/// Figure 10 screen 8, without booking: that arrives with supplier confirmation in Phase 3.
private struct OfferDetailView: View {
    let offer: ServiceOffer
    let cached: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                    TruthBadge(label: offer.truthLabel)
                    Text(offer.place.name).plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
                    Text(offer.place.address).plugText(.body).foregroundStyle(PlugTokens.Color.ink600).textSelection(.enabled)
                    Text(offer.truthLabel.explanation).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                }
                if cached || offer.expiresAt <= Date() {
                    Label("This saved offer needs a fresh check. Go back and refresh your request.", systemImage: "clock.arrow.circlepath")
                        .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink900)
                }
                VStack(spacing: 0) {
                    valueRow("Service", offer.serviceName)
                    valueRow("Price", offer.price)
                    valueRow("Available", when(offer.availableAt))
                    valueRow("Distance", distance(offer.place.distanceM))
                    valueRow("Evidence recorded", when(offer.observedAt))
                    valueRow("Offer expires", when(offer.expiresAt), last: true)
                }
                .plugCard()
                if offer.source == .seed {
                    Text("Demo data for private testing. This is not a real supplier offer and nothing is booked.")
                        .plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                }
                Text("Booking opens when suppliers can confirm offers in a later phase.")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            }
            .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            .padding(.horizontal, PlugTokens.Space.s4).padding(.vertical, PlugTokens.Space.s6)
        }
        .background(PlugTokens.Color.surface0)
        .navigationTitle("Offer details").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PlugTokens.Color.surface0, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private extension ServiceOffer.TruthLabel {
    var foreground: Color {
        switch self {
        case .confirmed: return PlugTokens.Color.truthConfirmed
        case .recent: return PlugTokens.Color.truthRecent
        case .estimated: return PlugTokens.Color.truthEstimated
        case .unknown: return PlugTokens.Color.truthUnknown
        }
    }
    var surface: Color {
        switch self {
        case .confirmed: return PlugTokens.Color.truthSurfaceConfirmed
        case .recent: return PlugTokens.Color.truthSurfaceRecent
        case .estimated: return PlugTokens.Color.truthSurfaceEstimated
        case .unknown: return PlugTokens.Color.truthSurfaceUnknown
        }
    }
}
