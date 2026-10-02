import AVFoundation
import Speech
import SwiftUI

/// The Ask screen from manual v4 Figure A1: one field for both kinds of ask, examples grouped
/// by the two things PLUG does, and the four answer states (working, answered, nobody
/// answered, and the dashed web answer). Ink on paper, colour only for evidence (§10). The
/// server decides the ask type, the counts, the labels and every value; this view renders.
struct AskView: View {
    @StateObject private var model: RequestModel
    @StateObject private var location = RequestLocationModel()
    @StateObject private var voice = VoiceDictation()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var textFocused: Bool
    @State private var askWhenLocated = false
    @State private var showValidation = false
    @State private var offeringService = false
    /// The answer is a pushed page, so the system back button and edge swipe both return home.
    @State private var path: [Page] = []
    private enum Page: Hashable { case answer }
    private let service: RequestServing
    private let onProviderChange: (ProviderProfile) -> Void

    init(service: RequestServing, onProviderChange: @escaping (ProviderProfile) -> Void = { _ in }) {
        self.service = service
        self.onProviderChange = onProviderChange
        _model = StateObject(wrappedValue: RequestModel(service: service))
    }

    var body: some View {
        NavigationStack(path: $path) {
            home
            .navigationDestination(for: Page.self) { _ in
                answerScreen
                    .background(PlugTokens.Color.paper)
                    .toolbarBackground(PlugTokens.Color.paper, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
            .onChange(of: model.hasAsk) { _, hasAsk in
                if hasAsk, path.isEmpty { path = [.answer] }
                if !hasAsk { path = [] }
            }
            .onChange(of: model.askId) { _, id in
                if id != nil, path.isEmpty { path = [.answer] }
            }
            .onChange(of: path) { _, pages in
                // Back from the answer. Anything finished is cleared; a request still asking
                // people keeps running and stays one tap away, never silently abandoned.
                guard pages.isEmpty, model.hasAsk, model.request?.status.canCancel != true else { return }
                model.startAgain()
                showValidation = false
            }
            .background(PlugTokens.Color.paper)
            .toolbarBackground(PlugTokens.Color.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onChange(of: scenePhase) { _, phase in
                model.setActive(phase == .active)
                if phase == .active, model.hasAsk { Task { await model.refresh() } }
            }
            .onChange(of: location.location) { _, located in
                guard askWhenLocated, let located else { return }
                askWhenLocated = false
                Task { await model.submit(location: located) }
            }
            .onChange(of: voice.transcript) { _, words in if !words.isEmpty { model.text = words } }
            .sheet(isPresented: $offeringService) {
                ProviderOnboardingView(service: service, location: location) { profile in
                    offeringService = false
                    onProviderChange(profile)
                }
            }
        }
        .tint(PlugTokens.Color.ink900)
        // Active means the Ask tab is on screen; attached to the stack, not a page in it.
        .task {
            model.setActive(true)
            if model.hasAsk { await model.refresh() }
        }
        .onDisappear { model.setActive(false) }
    }

    // MARK: 1. Ask

    private var home: some View {
        page {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                Text("What do you need to know?").plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
                Text("Ask for a service, or ask what's happening at a place. Real people nearby answer.")
                    .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
            }
            if model.hasAsk { resumeCard }
            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                ZStack(alignment: .topLeading) {
                    // A wrapping placeholder: the system one truncates at large text sizes.
                    if model.text.isEmpty {
                        Text("Type anything, or tap an example").plugText(.body)
                            .foregroundStyle(PlugTokens.Color.ink600)
                            .padding(PlugTokens.Space.s3)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    TextField("", text: $model.text, axis: .vertical)
                        .plugText(.body)
                        .lineLimit(1...5)
                        .focused($textFocused)
                        .padding(PlugTokens.Space.s3)
                        .accessibilityLabel("What do you need to know?")
                        .accessibilityIdentifier("request-text")
                        .disabled(model.isWorking)
                }
                .frame(minHeight: PlugTokens.minTouchTarget)
                .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.control)
                    .strokeBorder(textFocused || voice.isListening ? PlugTokens.Color.ink900 : PlugTokens.Color.rule300,
                                  lineWidth: textFocused || voice.isListening ? 2 : 1))
                .animation(.plug(PlugTokens.Motion.fast, reduceMotion: reduceMotion), value: textFocused)
                // Side by side while they fit; stacked at the largest text sizes instead of breaking words.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PlugTokens.Space.s2) { askButton; voiceButton.fixedSize(horizontal: true, vertical: false) }
                    VStack(spacing: PlugTokens.Space.s2) { askButton; voiceButton }
                }
                if let note = voice.message { caption(note) }
                if showValidation, let error = model.textError { fieldError(error) }
                locationNote
            }
            .plugCard()
            failure
            examples("Find me something", Example.services)
            examples("Tell me what's happening", Example.places)
            VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                Text("Do you do something people ask for?").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
                Text("Add a skill to this account and receive matching requests near you. You stay a normal user too.")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                Button("Offer a service") { offeringService = true }
                    .buttonStyle(AuthActionStyle())
                    .accessibilityIdentifier("offer-service")
            }
            caption("Private test. Nobody is contacted and nothing is booked.")
        }
        .toolbar(.hidden, for: .navigationBar)
        // No bar on home, so give the status bar a paper backing that scrolled text passes under.
        .overlay {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    PlugTokens.Color.paper.frame(height: geometry.safeAreaInsets.top)
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { textFocused = false }
            }
        }
    }

    private var stillAsking: Bool { model.request?.status.canCancel == true }

    /// Shown after swiping back from a request that is still asking people.
    private var resumeCard: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text(stillAsking ? "Still asking" : "Your last ask").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            Text(askedText).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
            if let progress = model.request?.progress {
                Text("\(progress.contacted) notified, \(progress.replied) replied")
                    .plugText(.bodySmall).monospacedDigit().foregroundStyle(PlugTokens.Color.ink600)
            }
            Button("Open this ask") { path = [.answer] }
                .buttonStyle(AuthActionStyle())
                .accessibilityIdentifier("ask-resume")
            if stillAsking { caption("Stop it or let it finish before asking something new.") }
        }
        .plugCard()
    }

    private var askButton: some View {
        Button(model.isWorking ? "Asking…" : "Ask") { ask() }
            .buttonStyle(AuthActionStyle(primary: true))
            .disabled(model.isWorking || location.isWorking || stillAsking)
            .accessibilityIdentifier("ask-submit")
    }

    private var voiceButton: some View {
        Button { voice.toggle() } label: {
            Label(voice.isListening ? "Listening… Stop" : "Voice",
                  systemImage: voice.isListening ? "mic.fill" : "mic")
        }
        .buttonStyle(AuthActionStyle())
        .disabled(model.isWorking || !voice.isAvailable)
        .accessibilityLabel(voice.isListening ? "Stop dictation" : "Ask by voice")
        .sensoryFeedback(.start, trigger: voice.isListening) { _, listening in listening }
    }

    private func ask() {
        showValidation = true
        textFocused = false
        guard model.textError == nil else { return }
        if let located = location.location {
            Task { await model.submit(location: located) }
        } else {
            askWhenLocated = true
            location.useDeviceLocation()
        }
    }

    /// The approximate location is taken only when the person asks. If it is denied or
    /// unavailable, typing an address keeps the product usable (§12.2 permission denied).
    @ViewBuilder private var locationNote: some View {
        if let label = location.label, location.location != nil {
            caption("Asking near: \(label)").accessibilityIdentifier("request-location-ready")
        } else if location.errorMessage != nil {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                if let error = location.errorMessage { fieldError(error) }
                PlugTextField(title: "Street address and city", text: $location.address)
                    .textContentType(.fullStreetAddress).disabled(model.isWorking)
                    .accessibilityIdentifier("request-address")
                Button(location.isWorking ? "Checking address…" : "Use this address") {
                    askWhenLocated = true
                    Task { await location.resolveAddress() }
                }
                .buttonStyle(AuthActionStyle())
                .disabled(location.isWorking || model.isWorking || location.address.isEmpty)
            }
        } else {
            caption(location.isWorking ? "Finding your approximate location…"
                    : "PLUG uses your approximate location when you ask, never before.")
        }
    }

    private func examples(_ heading: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            Text(heading).plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            ForEach(items, id: \.self) { example in
                Button { model.text = example } label: {
                    Text(example).plugText(.body).fontWeight(.semibold).foregroundStyle(PlugTokens.Color.ink900)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: PlugTokens.minTouchTarget, alignment: .leading)
                        .padding(.horizontal, PlugTokens.Space.s4)
                        .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.card).strokeBorder(PlugTokens.Color.rule200))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Puts this example in the field")
            }
        }
    }

    // MARK: 2 to 4. The answer

    private var answerScreen: some View {
        page {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                Text("You asked").plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                Text(askedText).plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            }
            .accessibilityElement(children: .combine)
            if model.isCached {
                Label("Saved result. Refresh to check it is still current.", systemImage: "clock.arrow.circlepath")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                    .accessibilityIdentifier("request-cached")
            }
            failure
            Group {
                if let question = model.askQuestion {
                    questionCard(question)
                } else if let place = model.placeQuestion {
                    placeAnswer(place)
                } else if let request = model.request {
                    serviceAnswer(request)
                }
            }
            // Motion explains a change the server reported (§16.3); none on first render or scroll.
            .transition(.opacity)
            .animation(.plug(reduceMotion: reduceMotion), value: answerState)
            actions
            if let reference = model.request?.requestId ?? model.askId {
                Text("Reference \(reference)").plugText(.caption)
                    .foregroundStyle(PlugTokens.Color.ink600).textSelection(.enabled)
            }
        }
        .navigationTitle("Your ask")
        .refreshable { await model.refresh() }
        .sensoryFeedback(.success, trigger: model.offers.count) { old, new in new > old }
        .sensoryFeedback(.error, trigger: model.errorMessage) { _, new in new != nil }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") { Task { await model.refresh() } }.disabled(model.isWorking)
            }
        }
    }

    /// Which answer is on screen, so a server-reported change animates and nothing else does.
    private var answerState: String {
        if let question = model.askQuestion { return "question-\(question.clarificationId)" }
        if let place = model.placeQuestion { return "place-\(place.status.rawValue)" }
        if let request = model.request { return "request-\(request.nextAction.rawValue)-\(model.offers.count)" }
        return "none"
    }

    private var askedText: String {
        model.request?.text ?? model.placeQuestion?.text ?? model.text
    }

    private func questionCard(_ question: ServiceRequest.Clarification) -> some View {
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

    @ViewBuilder private func serviceAnswer(_ request: ServiceRequest) -> some View {
        switch request.nextAction {
        case .answerClarification:
            if let question = request.clarification { questionCard(question) }
        case .waitForOffers:
            working(request)
            offerList(request)
        case .chooseOffer, .showResult, .awaitSupplierConfirmation:
            offerList(request)
            if model.offers.isEmpty, !model.isWorking {
                nobody("No current offers", "Refresh to check whether this request is still open.", request.progress.contacted)
            }
        case .showNoResult:
            nobody("No offers", request.noResultReason?.explanation ?? "No current offers are available.", request.progress.contacted)
        case .none:
            VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                Text("You stopped asking").plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
                Text("PLUG confirmed it. Nobody will be contacted for this request.")
                    .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
            }
            .plugCard()
        }
    }

    /// Figure A1 screen 2. Counts from the server; the bar tracks replies, never time.
    private func working(_ request: ServiceRequest) -> some View {
        let p = request.progress
        return VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { workingTitle(request); Spacer(minLength: PlugTokens.Space.s2); deadline(request) }
                VStack(alignment: .leading, spacing: PlugTokens.Space.s2) { workingTitle(request); deadline(request) }
            }
            ProgressView(value: Double(p.replied), total: Double(max(p.contacted, 1)))
                .tint(PlugTokens.Color.ink900)
                .animation(.plug(PlugTokens.Motion.slow, reduceMotion: reduceMotion), value: p.replied)
                .accessibilityLabel("Replies received")
                .accessibilityValue("\(p.replied) of \(p.contacted)")
            VStack(spacing: 0) {
                valueRow("Providers notified", "\(p.contacted)")
                valueRow("Replied", "\(p.replied)")
                valueRow("Offers ready", "\(p.offersReady)", last: true)
            }
            .contentTransition(.numericText())
            .animation(.plug(reduceMotion: reduceMotion), value: p)
            caption("Counts are real. We never guess, and we never run a timer and call it progress.")
        }
        .plugCard()
        .accessibilityIdentifier("request-progress")
    }
    private func workingTitle(_ request: ServiceRequest) -> some View {
        Text("Asking \(request.constraints.serviceName?.lowercased() ?? "providers") nearby")
            .plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
    }
    private func deadline(_ request: ServiceRequest) -> some View {
        Text("Open until \(request.expiresAt.formatted(date: .omitted, time: .shortened))")
            .plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
            .padding(.horizontal, PlugTokens.Space.s2).padding(.vertical, PlugTokens.Space.s1)
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.badge).strokeBorder(PlugTokens.Color.rule300))
            .fixedSize()
    }

    /// Figure A3: the price is the headline; the badge is the evidence; the provider is New, never 0.
    @ViewBuilder private func offerList(_ request: ServiceRequest) -> some View {
        if !model.offers.isEmpty {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                Text(model.offers.count == 1 ? "1 offer" : "\(model.offers.count) offers")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                Text(offersTitle(request)).plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
            }
            ForEach(model.offers) { offer in
                VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                    HStack(alignment: .top) {
                        Text(money(offer.priceCents, offer.currency)).plugText(.display).monospacedDigit().foregroundStyle(PlugTokens.Color.ink900)
                        Spacer(minLength: PlugTokens.Space.s2)
                        TruthBadge(label: offer.truthLabel)
                    }
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                        Text(offer.place.name).plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
                        Text(scoreText(offer.providerScore)).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                    }
                    VStack(spacing: 0) {
                        valueRow("Earliest", offer.availableAt.formatted(date: .omitted, time: .shortened))
                        valueRow("Distance", distance(offer.place.distanceM))
                        valueRow("Offer ends", offer.expiresAt.formatted(date: .omitted, time: .shortened), last: true)
                    }
                    NavigationLink { OfferDetailView(offer: offer, cached: model.isCached) } label: { Text("View details") }
                        .buttonStyle(AuthActionStyle())
                }
                .plugCard()
            }
        }
    }
    private func offersTitle(_ request: ServiceRequest) -> String {
        let service = request.constraints.serviceName ?? "Offers"
        guard let budget = request.constraints.budgetCents else { return service }
        return "\(service) under \(money(budget, request.constraints.currency))"
    }

    /// Figure A1 screen 4 for a place question. Unknown is designed, with real counts.
    @ViewBuilder private func placeAnswer(_ place: PlaceQuestion) -> some View {
        if place.status == .asking {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { placeTitle(place); Spacer(minLength: PlugTokens.Space.s2); placeDeadline(place) }
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s2) { placeTitle(place); placeDeadline(place) }
                }
                VStack(spacing: 0) {
                    valueRow("People notified", "\(place.progress.notified)")
                    valueRow("Opened", "\(place.progress.opened)")
                    valueRow("Answered", "\(place.progress.answered)", last: true)
                }
                caption("Counts are real. An answer appears only when a person nearby gives one.")
            }
            .plugCard()
            .accessibilityIdentifier("place-progress")
        } else if place.status == .answered, let answer = place.answer {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                HStack(alignment: .top) {
                    Text(answer.value).plugText(.display).foregroundStyle(PlugTokens.Color.ink900)
                    Spacer(minLength: PlugTokens.Space.s2)
                    TruthBadge(label: answer.truthLabel)
                }
                Text(answer.summary).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                caption("This answer stops being current at \(answer.expiresAt.formatted(date: .omitted, time: .shortened)).")
            }
            .plugCard()
        } else {
            nobody("No answers", place.progress.notified == 0
                   ? "Nobody near this place is answering questions on PLUG yet, so no one could check."
                   : "No one nearby was able to check.", place.progress.notified,
                   subject: place.placeName)
        }
        if let web = place.webAnswer { WebAnswerCard(answer: web) }
    }

    private func placeTitle(_ place: PlaceQuestion) -> some View {
        Text("Asking people near \(place.placeName ?? "this place")").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
    }
    private func placeDeadline(_ place: PlaceQuestion) -> some View {
        Text("Open until \(place.expiresAt.formatted(date: .omitted, time: .shortened))")
            .plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
            .padding(.horizontal, PlugTokens.Space.s2).padding(.vertical, PlugTokens.Space.s1)
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.badge).strokeBorder(PlugTokens.Color.rule300))
            .fixedSize()
    }

    private func nobody(_ title: String, _ detail: String, _ notified: Int, subject: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            HStack(alignment: .top) {
                Text(title).plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
                Spacer(minLength: PlugTokens.Space.s2)
                TruthBadge(label: .unknown)
            }
            if let subject { Text(subject).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600) }
            Text(notified == 0 ? "Nobody was notified." : "\(notified) notified, none replied.")
                .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            Rectangle().fill(PlugTokens.Color.rule200).frame(height: 1)
            Text(detail).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
        }
        .plugCard()
        .accessibilityIdentifier("request-unknown")
    }

    @ViewBuilder private var actions: some View {
        if let request = model.request, request.status.canCancel {
            Button("Stop asking") { Task { await model.cancel() } }
                .buttonStyle(PlugDestructiveStyle())
                .accessibilityIdentifier("request-cancel")
        } else {
            // While the one question is open, answering it is the task; starting over is secondary.
            Button("Ask something else") { model.startAgain(); showValidation = false }
                .buttonStyle(AuthActionStyle(primary: model.askQuestion == nil && model.request?.clarification == nil))
                .disabled(model.isWorking)
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
        .background(PlugTokens.Color.paper)
    }

    /// §11.3: says what failed and whether anything was saved.
    @ViewBuilder private var failure: some View {
        if let message = model.errorMessage {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                Text(message).plugText(.body).foregroundStyle(PlugTokens.Color.alert600)
                if let correlation = model.correlationId {
                    Text("Support reference \(correlation)").plugText(.caption)
                        .foregroundStyle(PlugTokens.Color.ink600).textSelection(.enabled)
                }
                if model.hasAsk {
                    Button("Retry update") { Task { await model.refresh() } }
                        .plugText(.label).frame(minHeight: PlugTokens.minTouchTarget).disabled(model.isWorking)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PlugTokens.Space.s4)
            .background(PlugTokens.Color.alert50, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.control).strokeBorder(PlugTokens.Color.alertBorder))
            .accessibilityIdentifier("request-error")
        }
    }
    private func fieldError(_ value: String) -> some View {
        Text(value).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.alert600)
    }
}

/// Figure A1 examples, grouped by the two things PLUG does. They only fill the field.
private enum Example {
    static let services = ["Barber under $35 in the next hour", "Someone to do knotless braids, $120 max",
                           "Fix a leaking sink today"]
    static let places = ["How long is the line at Walmart right now?", "Is the DMV busy right now?"]
}

func scoreText(_ score: ProviderScore) -> String {
    switch score.state {
    case .new: return score.completedJobs == 0 ? "New provider" : "New provider, \(score.completedJobs) jobs"
    case .scored: return "Score \(score.value ?? 0) from \(score.completedJobs) jobs"
    }
}

func caption(_ text: String) -> some View {
    Text(text).plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
}

/// §11.4: values right-aligned in a key/value column so they scan vertically.
func valueRow(_ label: String, _ value: String, last: Bool = false) -> some View {
    VStack(spacing: 0) {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                Spacer(minLength: PlugTokens.Space.s2)
                Text(value).plugText(.body).fontWeight(.bold).monospacedDigit().foregroundStyle(PlugTokens.Color.ink900)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                Text(label).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                Text(value).plugText(.body).fontWeight(.bold).monospacedDigit().foregroundStyle(PlugTokens.Color.ink900)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, PlugTokens.Space.s2)
        if !last { Rectangle().fill(PlugTokens.Color.rule200).frame(height: 1) }
    }
    .accessibilityElement(children: .combine)
}

func distance(_ metres: Int) -> String {
    Measurement(value: Double(metres), unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
}

func money(_ cents: Int, _ currency: String) -> String {
    (Decimal(cents) / 100).formatted(.currency(code: currency).precision(.fractionLength(cents % 100 == 0 ? 0 : 2)))
}

/// Manual v4 §11.2: the only place truth colours appear. Filled for human evidence, dashed for
/// the web, so the difference survives greyscale and sunlight.
struct TruthBadge: View {
    let label: ServiceOffer.TruthLabel
    var body: some View {
        Text(label.title)
            .plugText(.label)
            .padding(.horizontal, PlugTokens.Space.s2)
            .padding(.vertical, PlugTokens.Space.s1)
            .foregroundStyle(label.foreground)
            .background(label == .notVerified ? Color.clear : label.surface,
                        in: RoundedRectangle(cornerRadius: PlugTokens.Radius.badge))
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.badge)
                .strokeBorder(label.border, style: StrokeStyle(lineWidth: 1, dash: label == .notVerified ? [4, 3] : [])))
            .fixedSize()
            .accessibilityLabel(label.explanation)
    }
}

/// Figure A1 screen 4: what the web says, dashed, with its source and age. Never a human answer.
struct WebAnswerCard: View {
    let answer: WebAnswer
    var body: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            HStack(alignment: .top) {
                Text(answer.headline).plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
                Spacer(minLength: PlugTokens.Space.s2)
                TruthBadge(label: .notVerified)
            }
            Text(answer.summary).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
            Rectangle().fill(PlugTokens.Color.rule200).frame(height: 1)
            Text("Where this came from").plugText(.label).foregroundStyle(PlugTokens.Color.ink900)
            Text("\(answer.sourceName), read \(answer.retrievedAt.formatted(.relative(presentation: .named)))")
                .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            caption("No person checked this. It is a pattern, not what is happening now.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PlugTokens.Space.s4)
        .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.card)
            .strokeBorder(PlugTokens.Color.rule300, style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
    }
}

/// Figure A3: the offer in full. Booking needs supplier confirmation, which is Phase 3.
private struct OfferDetailView: View {
    let offer: ServiceOffer
    let cached: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                    HStack(alignment: .top) {
                        Text(money(offer.priceCents, offer.currency)).plugText(.display).monospacedDigit().foregroundStyle(PlugTokens.Color.ink900)
                        Spacer(minLength: PlugTokens.Space.s2)
                        TruthBadge(label: offer.truthLabel)
                    }
                    Text(offer.place.name).plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
                    Text(scoreText(offer.providerScore)).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                    Text(offer.truthLabel.explanation).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                }
                if cached || offer.expiresAt <= Date() {
                    Label("This saved offer needs a fresh check. Go back and refresh.", systemImage: "clock.arrow.circlepath")
                        .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink900)
                }
                VStack(spacing: 0) {
                    valueRow("Service", offer.serviceName)
                    valueRow("Address", offer.place.address)
                    valueRow("Distance", distance(offer.place.distanceM))
                    valueRow("Earliest", offer.availableAt.formatted(date: .abbreviated, time: .shortened))
                    valueRow("Offer ends", offer.expiresAt.formatted(date: .abbreviated, time: .shortened))
                    valueRow("Evidence recorded", offer.observedAt.formatted(date: .abbreviated, time: .shortened), last: true)
                }
                .plugCard()
                if offer.source == .seed {
                    Text("Demo data for private testing. This is not a real offer and nothing is booked.")
                        .plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                }
                caption("Choosing and booking open when providers can confirm offers.")
            }
            .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            .padding(.horizontal, PlugTokens.Space.s4).padding(.vertical, PlugTokens.Space.s6)
        }
        .background(PlugTokens.Color.paper)
        .navigationTitle("Offer").navigationBarTitleDisplayMode(.inline)
    }
}

extension ServiceOffer.TruthLabel {
    var foreground: Color {
        switch self {
        case .confirmed: return PlugTokens.Color.truthConfirmed
        case .recent: return PlugTokens.Color.truthRecent
        case .estimated: return PlugTokens.Color.truthEstimated
        case .unknown: return PlugTokens.Color.truthUnknown
        case .notVerified: return PlugTokens.Color.ink600
        }
    }
    var surface: Color {
        switch self {
        case .confirmed: return PlugTokens.Color.truthSurfaceConfirmed
        case .recent: return PlugTokens.Color.truthSurfaceRecent
        case .estimated: return PlugTokens.Color.truthSurfaceEstimated
        case .unknown, .notVerified: return PlugTokens.Color.truthSurfaceUnknown
        }
    }
    var border: Color {
        switch self {
        case .confirmed: return PlugTokens.Color.truthBorderConfirmed
        case .recent: return PlugTokens.Color.truthBorderRecent
        case .estimated: return PlugTokens.Color.truthBorderEstimated
        case .unknown: return PlugTokens.Color.truthBorderUnknown
        case .notVerified: return PlugTokens.Color.rule300
        }
    }
}

/// On-device dictation for the Voice button. Audio and transcripts never leave the phone except
/// as the text the person then chooses to ask.
@MainActor
final class VoiceDictation: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var message: String?
    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isAvailable: Bool { recognizer?.isAvailable == true }

    func toggle() { isListening ? stop() : start() }

    private func start() {
        message = nil
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.message = "Voice needs speech recognition permission. You can type instead."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        if granted { self.begin() }
                        else { self.message = "Voice needs microphone permission. You can type instead." }
                    }
                }
            }
        }
    }

    private func begin() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true { request.requiresOnDeviceRecognition = true }
            self.request = request
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isListening = true
            task = recognizer?.recognitionTask(with: request) { result, error in
                let text = result?.bestTranscription.formattedString
                let done = error != nil || result?.isFinal == true
                Task { @MainActor in
                    if let text { self.transcript = text }
                    if done { self.stop() }
                }
            }
        } catch {
            message = "Voice could not start. You can type instead."
            stop()
        }
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
