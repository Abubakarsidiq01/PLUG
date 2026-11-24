import AVFoundation
import MapKit
import Speech
import SwiftUI

/// The Ask screen: the ask box first, one field for both kinds of ask, example asks as a small
/// service catalogue, and the answer states (working, offers, nobody answered, and the web answer).
/// The server decides the ask type, the counts, the labels and every value; this view renders.
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
    @State private var offerOrder = OfferOrder.suggested
    @State private var selectedOffer: ServiceOffer?
    @State private var toast: String?
    @State private var confirmingCancel = false
    private enum OfferOrder: String, CaseIterable { case suggested = "For you", price = "Lowest price", distance = "Closest" }
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var clearGlyph: CGFloat = PlugTokens.Layout.iconSmall
    @ScaledMetric(relativeTo: .footnote) private var sourceMark: CGFloat = PlugTokens.Space.s8 + 4
    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 60
    /// Thumbnails grow with the text a little, never past 88pt.
    private var thumbnail: CGFloat { min(thumbnailSize, 88) }
    /// The answer is a pushed page, so the system back button and edge swipe both return home.
    @State private var path: [Page] = []
    private enum Page: Hashable { case answer }
    private let service: RequestServing
    private let onProviderChange: (ProviderProfile) -> Void
    /// The one disclosure left from the preview: shown only where example (seed) offers appear.
    static let exampleNote = "Example offers for preview. Booking isn’t available yet."
    @State private var tileTaps = 0
    /// Know before you go, or one category's example asks. A sheet sends its ask itself; nothing
    /// is put in the home field for the person to notice.
    @State private var sheet: AskSheet?
    @State private var pendingAsk: String?
    private enum AskSheet: Identifiable {
        case knowBefore, examples(title: String, asks: [String])
        var id: String { if case .examples(let title, _) = self { return title }; return "know-before" }
    }

    init(service: RequestServing, onProviderChange: @escaping (ProviderProfile) -> Void = { _ in }) {
        self.service = service
        self.onProviderChange = onProviderChange
        _model = StateObject(wrappedValue: RequestModel(service: service))
    }

    var body: some View {
        NavigationStack(path: $path) {
            home
            .navigationDestination(for: Page.self) { _ in answerScreen }
            .onChange(of: model.hasAsk) { _, hasAsk in
                if hasAsk, path.isEmpty { path = [.answer] }
                if hasAsk { toast = "Ask sent" }
                if !hasAsk { path = [] }
            }
            .onChange(of: model.askId) { _, id in
                if id != nil, path.isEmpty { path = [.answer] }
            }
            .onChange(of: path) { _, pages in
                // Back from the answer. Anything finished is cleared; a request still asking
                // people keeps running and stays one tap away, never silently abandoned.
                guard pages.isEmpty, model.hasAsk, !model.hasActiveAsk else { return }
                model.startAgain()
                showValidation = false
            }
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
            .sheet(item: $sheet, onDismiss: sendPendingAsk) { shown in
                switch shown {
                case .knowBefore:
                    KnowBeforeSheet(location: location) { pendingAsk = $0 }
                case .examples(let title, let asks):
                    ExampleAskSheet(title: title, asks: asks) { pendingAsk = $0 }
                }
            }
            .sheet(isPresented: $offeringService) {
                ProviderOnboardingView(service: service, location: location) { profile in
                    offeringService = false
                    onProviderChange(profile)
                    toast = "Your provider profile is saved."
                }
            }
        }
        .tint(PlugTokens.Color.ink900)
        .plugToast($toast)
        // Active means the Ask tab is on screen; attached to the stack, not a page in it.
        .task {
            model.setActive(true)
            if model.hasAsk { await model.refresh() }
        }
        .onDisappear { model.setActive(false); voice.stop() }
    }

    // MARK: 1. Ask

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s8) {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    masthead
                    homeTitle
                    // The street sits between the question and the ask box, road edge down.
                    StreetHero(asking: stillAsking)
                        .padding(.top, PlugTokens.Space.s4)
                        .background(PlugTokens.Color.sunk, in: RoundedRectangle(cornerRadius: PlugShape.illustration, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: PlugShape.illustration, style: .continuous))
                    if !stillAsking { composer }
                    failure
                }
                if model.hasAsk { resumeCard }
                discovery
            }
            .padding(.horizontal, PlugTokens.Space.s6)
            .padding(.bottom, PlugTokens.Space.s8)
            .frame(maxWidth: PlugTokens.Layout.measure, alignment: .leading)
            .frame(maxWidth: .infinity)
            .foregroundStyle(PlugTokens.Color.ink900)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PlugTokens.Color.paper)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { textFocused = false }
            }
        }
    }

    /// PLUG on cream.
    private var masthead: some View {
        HStack(alignment: .center) {
            // One logotype everywhere, the app and the website (owner decision, 2026-10-08).
            PlugLogotype(size: PlugTokens.Layout.mark)
            Spacer()
        }
        .padding(.top, PlugTokens.Space.s1)
    }

    private var homeTitle: some View {
        Text(stillAsking ? "Your ask is still open." : "What do you need nearby?")
            .plugText(.hero)
            .foregroundStyle(PlugTokens.Color.ink900)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("ask-home-title")
    }

    /// The ask box: a sand field with dictation at its end, then the one green action under it.
    private var composer: some View {
        let shape = RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous)
        return VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            HStack(alignment: .center, spacing: PlugTokens.Space.s1) {
                ZStack(alignment: .topLeading) {
                    // This placeholder wraps at large sizes and meets the contrast floor.
                    if model.text.isEmpty {
                        Text("Tell us what you need…").plugText(.body)
                            .foregroundStyle(PlugTokens.Color.ink600)
                            .fixedSize(horizontal: false, vertical: true)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    TextField("", text: $model.text, axis: .vertical)
                        .plugText(.body)
                        .lineLimit(1...5).focused($textFocused)
                        .tint(PlugTokens.Color.brandGreen)
                }
                .padding(.vertical, PlugTokens.Space.s4)
                .frame(maxWidth: .infinity, minHeight: PlugShape.buttonHeight + 12, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if !model.isWorking { textFocused = true } }
                .accessibilityLabel("What do you need?")
                .accessibilityIdentifier("request-text")
                .disabled(model.isWorking)
                // Earlier words stay after "Ask something else"; one tap starts fresh.
                if !model.text.isEmpty && !model.isWorking {
                    Button { voice.stop(); model.text = ""; textFocused = true } label: {
                        Image(systemName: "xmark").font(.system(size: min(clearGlyph, PlugTokens.Layout.iconMax) - 4, weight: .medium))
                            .foregroundStyle(PlugTokens.Color.ink600)
                            .frame(minWidth: PlugTokens.minTouchTarget, minHeight: PlugTokens.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Clear")
                    .accessibilityIdentifier("request-clear")
                }
                voiceButton
            }
            .padding(.leading, PlugTokens.Space.s4)
            .padding(.trailing, PlugTokens.Space.s2)
            .background(PlugTokens.Color.sunk, in: shape)
            .opacity(sending ? 0.55 : 1)
            .scaleEffect(sending && !reduceMotion ? 0.98 : 1, anchor: .bottom)
            .animation(.plugSheet(reduceMotion: reduceMotion), value: sending)
            .overlay(shape.strokeBorder(textFocused ? PlugTokens.Color.brandGreen : .clear, lineWidth: 1.5))
            .animation(reduceMotion ? nil : .easeOut(duration: PlugTokens.Motion.fast), value: textFocused)
            Button { ask() } label: {
                // The words give way to a small progress while the ask goes out.
                ZStack {
                    Text("Ask people nearby").opacity(sending ? 0 : 1)
                    if sending {
                        HStack(spacing: PlugTokens.Space.s2) {
                            ProgressView().tint(PlugTokens.Color.paper).controlSize(.small)
                            Text("Sending")
                        }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                    }
                }
                .animation(.plugSheet(reduceMotion: reduceMotion), value: sending)
            }
                .buttonStyle(PlugButtonStyle(kind: .primary))
                .accessibilityIdentifier("ask-submit")
                .accessibilityLabel(sending ? "Sending" : "Ask people nearby")
                .disabled((model.isWorking || location.isWorking) && !sending)
                .allowsHitTesting(!sending)
                .sensoryFeedback(.impact(weight: .medium), trigger: sending) { _, now in now }
            if let note = voice.message { caption(note) }
            if showValidation, let error = model.textError { fieldError(error) }
            locationNote
        }
    }

    /// The examples while nothing is being asked; offering a service is always here.
    private var discovery: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s8) {
            if !stillAsking {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    // (title, illustration, its example asks, test identifier). No asks: Know before you go.
                    let categories = [("Hair & beauty", "IllHairBeauty", Example.hairBeauty, "ask-example-barber"),
                                      ("Home help", "IllHomeHelp", Example.homeHelp, "ask-example-home"),
                                      ("Tech", "IllTech", Example.tech, "ask-example-tech"),
                                      ("Places", "IllPlaces", [], "ask-example-places")]
                    // The frame hugs the serif's cap height; the audit sampled clipped descenders as low contrast.
                    Text("Start with an example").plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
                        .padding(.vertical, 3).accessibilityAddTraits(.isHeader)
                    // Four across, two at accessibility sizes. Not a lazy grid: a lazy one drops tiles
                    // out of view, and the tests find them by id.
                    let columns = typeSize.isAccessibilitySize ? 2 : 4
                    Grid(alignment: .topLeading, horizontalSpacing: PlugTokens.Space.s3, verticalSpacing: PlugTokens.Space.s4) {
                        ForEach(0..<(categories.count / columns), id: \.self) { row in
                            GridRow {
                                ForEach(0..<columns, id: \.self) { column in categoryTile(categories[row * columns + column]) }
                            }
                        }
                    }
                }
            }
            VStack(spacing: 0) {
                PlugDivider()
                if !stillAsking {
                    featureRow(art: "IllKnowBefore", title: "Know before you go",
                               line: "Pick a place, choose what to check, and ask people there.", id: "ask-example-place",
                               hint: "Opens a place search. Nothing is sent until you ask.") {
                        sheet = .knowBefore
                    }
                    PlugDivider()
                }
                featureRow(art: "IllOfferService", title: "Do you offer a service?",
                           line: "Add your skills, hours and how far you travel.", id: "offer-service",
                           label: "Offer a service") {
                    offeringService = true
                }
                PlugDivider()
            }
        }
        .foregroundStyle(PlugTokens.Color.ink900)
    }

    /// (title, illustration, example asks, identifier): an illustration on a sand tile with its
    /// label below, like a service catalogue. A tap opens that category's asks in a sheet; a press
    /// settles to 0.97 with a light tap.
    private func categoryTile(_ category: (String, String, [String], String)) -> some View {
        let open = {
            guard !model.isWorking else { return }
            tileTaps += 1
            voice.stop()
            sheet = category.2.isEmpty ? .knowBefore : .examples(title: category.0, asks: category.2)
        }
        // The label sits outside the button and repeats its name, so the accessibility audit
        // reads the text against the cream, not against the art above it.
        return VStack(spacing: PlugTokens.Space.s2) {
            Button(action: open) {
                IllustrationTile(name: category.1)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlugPressStyle(scale: 0.97))
            .sensoryFeedback(.impact(weight: .light), trigger: tileTaps)
            .disabled(model.isWorking)
            .accessibilityLabel(category.0)
            .accessibilityIdentifier(category.3)
            .accessibilityHint("Opens example asks. Nothing is sent until you ask.")
            Text(category.0).plugText(.label)
                .foregroundStyle(PlugTokens.Color.ink900)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture(perform: open)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    /// A compact row: a small illustration tile, a serif title, one line, and a chevron. The
    /// tile sits beside the button, so the audit reads the words against the cream.
    private func featureRow(art: String, title: String, line: String, id: String,
                            label: String? = nil, hint: String = "",
                            action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: PlugTokens.Space.s4) {
            IllustrationTile(name: art, size: thumbnail)
                .onTapGesture { if !model.isWorking { action() } }
            Button(action: action) {
                HStack(alignment: .center, spacing: PlugTokens.Space.s3) {
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                        Text(title).plugText(.title2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(line).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PlugTokens.Color.brandGreen)
                        .accessibilityHidden(true)
                }
                .multilineTextAlignment(.leading)
                .foregroundStyle(PlugTokens.Color.ink900)
                .frame(minHeight: thumbnail)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlugPressStyle())
            .disabled(model.isWorking)
            .accessibilityLabel(label ?? title)
            .accessibilityIdentifier(id)
            .accessibilityHint(hint)
        }
        .padding(.vertical, PlugTokens.Space.s4)
    }

    /// A sheet's ask goes out once the sheet has gone, through the same path as the home field:
    /// the same checks, the same approximate-location request and notice.
    private func sendPendingAsk() {
        guard let text = pendingAsk else { return }
        pendingAsk = nil
        voice.stop()
        model.text = text
        ask()
    }

    private var stillAsking: Bool { model.hasActiveAsk }
    /// The ask is on its way: submitting, or waiting for the location it needs first.
    private var sending: Bool { (model.isWorking && !model.hasAsk) || askWhenLocated }

    /// Shown after swiping back from a request that is still asking people.
    private var resumeCard: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text(stillAsking ? "Still asking" : model.request?.status == .canceled ? "Ask stopped" : "Your last ask")
                .plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
            Text(askedText).plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
            if let progress = model.request?.progress {
                PeopleProgress(contacted: progress.contacted, replied: progress.replied)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PlugTokens.Space.s4) {
                    resumeAction.fixedSize(horizontal: true, vertical: false)
                    stopAction.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: PlugTokens.Space.s2) { resumeAction; stopAction }
            }
            if model.request?.status == .canceled { caption("Stopped. You're free to ask again.") }
        }
        .plugCard()
    }

    private var resumeAction: some View {
        Button { path = [.answer] } label: {
            Text("Open this ask")
        }
        .buttonStyle(PlugButtonStyle(kind: .secondary, fullWidth: false))
        .accessibilityIdentifier("ask-resume")
    }

    @ViewBuilder private var stopAction: some View {
        if model.request?.status.canCancel == true {
            Button(model.isWorking ? "Stopping…" : "Stop asking") { Task { await model.cancel() } }
                .buttonStyle(PlugButtonStyle(kind: .destructive, fullWidth: false))
                .disabled(model.isWorking)
                .accessibilityIdentifier("ask-stop")
        }
    }

    private var voiceButton: some View {
        Button { voice.toggle() } label: {
            Image(systemName: voice.isListening ? "mic.fill" : "mic")
                .font(.system(size: 18, weight: .regular))
                .frame(width: PlugTokens.minTouchTarget, height: PlugTokens.minTouchTarget)
                .symbolEffect(.pulse, isActive: voice.isListening && !reduceMotion)
        }
        .buttonStyle(PlugButtonStyle(kind: voice.isListening ? .primary : .outline, fullWidth: false, compact: true))
        .disabled(model.isWorking || !voice.isAvailable)
        .accessibilityLabel(voice.isListening ? "Stop dictation" : "Ask by voice")
        .sensoryFeedback(.start, trigger: voice.isListening) { _, listening in listening }
    }

    private func ask() {
        guard !sending else { return }
        showValidation = true
        voice.stop()
        textFocused = false
        guard model.textError == nil else { return }
        // A fix taken earlier (in Know before you go, or a past ask) is renewed once it is stale.
        if let located = location.location, !location.isStale() {
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
            Label("Asking near: \(label)", systemImage: "location.fill")
                .plugText(.caption).foregroundStyle(PlugTokens.Color.ink900)
                .accessibilityIdentifier("request-location-ready")
        } else if location.errorMessage != nil {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
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
                    : "PLUG sends your approximate location only when you ask.")
        }
    }

    // MARK: 2 to 4. The answer

    private var answerScreen: some View {
        answerChrome(answerScroll)
            .sheet(item: $selectedOffer) { offer in
                OfferDetailView(offer: offer, cached: model.isCached,
                                choice: model.request?.status == .ranked && offer.source != .seed
                                    ? (model.bookingUnavailable ? .unavailable : .available) : .none,
                                choosing: model.isWorking, error: model.errorMessage) {
                    Task { await model.select(offer) }
                }
                    // Full height: at the medium detent the sheet edge cut through text, which the
                    // accessibility audit reports as clipped.
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(PlugTokens.Color.paper)
                    .presentationCornerRadius(PlugShape.sheet)
            }
            // Chosen: the sheet gives way to the pending reservation the server returned.
            .onChange(of: model.request?.status) { _, status in
                if status != .ranked { selectedOffer = nil }
            }
    }

    private var answerScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                answerBand
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
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
                    // Offers fade up row by row (offerList); the rest of a server change lands in place.
                    actions
                    if let request = model.request, model.askQuestion == nil {
                        DetailsButton { RequestDetails(request: request) }
                    } else if let place = model.placeQuestion {
                        DetailsButton { PlaceDetails(place: place) }
                    }
                }
                .padding(.horizontal, PlugTokens.Space.s6)
                .padding(.vertical, PlugTokens.Space.s6)
                .frame(maxWidth: PlugTokens.Layout.measure, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(PlugTokens.Color.ink900)
        }
    }

    private func answerChrome<Content: View>(_ content: Content) -> some View {
        content
        .background(PlugTokens.Color.paper)
        .navigationTitle("Your ask")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PlugTokens.Color.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .refreshable { await model.refresh() }
        .sensoryFeedback(.success, trigger: model.offers.count) { (old: Int, new: Int) -> Bool in old == 0 && new > 0 }
        .sensoryFeedback(.error, trigger: model.errorMessage) { (_: String?, new: String?) -> Bool in new != nil }
        .modifier(FlatToolbarButton(systemImage: "arrow.clockwise", label: "Refresh", disabled: model.isWorking) {
            Task { await model.refresh() }
        })
    }

    /// The ask itself in the serif, the status in plain words, and the live count of people
    /// being asked between hairlines.
    private var answerBand: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Overline("Your request")
            Text(askedText).plugText(.display).foregroundStyle(PlugTokens.Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let status = bandStatus {
                HStack(alignment: .firstTextBaseline, spacing: PlugTokens.Space.s2) {
                    AskingPulse()
                    Text(status).plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.isCached {
                Label("Saved result. Refresh to check it is still current.", systemImage: "clock.arrow.circlepath")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink900)
                    .accessibilityIdentifier("request-cached")
            }
            // Lands in place: a moving layout under the counts read as a moving target.
            progressCard
        }
        .padding(.horizontal, PlugTokens.Space.s6)
        .padding(.top, PlugTokens.Space.s2)
        .frame(maxWidth: PlugTokens.Layout.measure, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var bandStatus: String? {
        if model.askQuestion == nil, let request = model.request, request.nextAction == .waitForOffers {
            return "Asking \(request.constraints.serviceName?.lowercased() ?? "providers") nearby"
        }
        if model.askQuestion == nil, model.request?.nextAction == .awaitSupplierConfirmation {
            return "Waiting for the provider to confirm"
        }
        if let place = model.placeQuestion, place.status == .asking {
            return "Asking people near \(place.placeName ?? "this place")"
        }
        return nil
    }

    /// Reply counts come from the server; the visual never implies elapsed-time progress.
    @ViewBuilder private var progressCard: some View {
        if model.askQuestion == nil, let request = model.request, request.nextAction == .waitForOffers {
            progressBox(deadline: request.expiresAt) {
                PeopleProgress(contacted: request.progress.contacted, replied: request.progress.replied,
                               note: "Offers from people nearby show up here.")
            }
            .accessibilityIdentifier("request-progress")
        } else if let place = model.placeQuestion, place.status == .asking {
            progressBox(deadline: place.expiresAt) {
                PeopleProgress(contacted: place.progress.notified, replied: place.progress.answered,
                               summary: "\(place.progress.notified) notified, \(place.progress.opened) opened, \(place.progress.answered) answered",
                               spokenCounts: "\(place.progress.opened) opened, \(place.progress.answered) answered",
                               note: "Checking with people nearby.")
            }
            .accessibilityIdentifier("place-progress")
        }
    }

    private func progressBox<Content: View>(deadline: Date, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            PlugDivider()
            content()
            PlugDeadlineTag(until: deadline)
            PlugDivider()
        }
        .padding(.top, PlugTokens.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var askedText: String {
        model.request?.text ?? model.placeQuestion?.text ?? model.text
    }

    private func questionCard(_ question: ServiceRequest.Clarification) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                Text(question.question).plugText(.display).fixedSize(horizontal: false, vertical: true)
                Text("One quick detail to find the right help.").plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
            }
            ForEach(question.options, id: \.value) { option in
                Button { Task { await model.answer(option.value) } } label: {
                    HStack {
                        Text(option.label).multilineTextAlignment(.leading)
                        Spacer(minLength: PlugTokens.Space.s3)
                        Image(systemName: "arrow.right").fontWeight(.medium).accessibilityHidden(true)
                    }
                }.buttonStyle(PlugButtonStyle(kind: .outline)).disabled(model.isWorking)
            }
        }.foregroundStyle(PlugTokens.Color.ink900)
    }

    @ViewBuilder private func serviceAnswer(_ request: ServiceRequest) -> some View {
        switch request.nextAction {
        case .answerClarification:
            if let question = request.clarification { questionCard(question) }
        case .waitForOffers:
            offerList(request)
        case .awaitSupplierConfirmation:
            if let reservation = request.reservation { bookingCard(reservation) }
        case .showResult where request.reservation?.status == .confirmed:
            if let reservation = request.reservation { bookingCard(reservation) }
        case .chooseOffer, .showResult:
            if request.isRecovering, !model.offers.isEmpty {
                PlugNotice(title: "They couldn't confirm", message: "They couldn't confirm. Here are your other offers.",
                           detail: "Nothing was booked. Choose another offer below.")
                    .accessibilityIdentifier("booking-recovery")
            }
            offerList(request)
            if model.offers.isEmpty, !model.isWorking {
                nobody("No current offers", "Refresh to check whether this request is still open.", request.progress.contacted)
            }
        case .showNoResult:
            nobody(request.noResultReason == .notConfirmed ? "Not confirmed" : "No offers",
                   request.noResultReason?.explanation ?? "No current offers are available.", request.progress.contacted)
            if request.noResultReason == .noCoverage { offerTheGap(request) }
        case .none:
            if request.reservation?.status == .canceled {
                PlugNotice(title: "You canceled this request", message: "Nothing is booked, and nobody else will be contacted.")
            } else {
                PlugNotice(title: "You stopped asking", message: "This request is closed. Nobody else will be contacted.")
            }
        }
    }

    /// The reservation, pending or confirmed. "Booked" appears only when the server says confirmed.
    private func bookingCard(_ reservation: Reservation) -> some View {
        let offer = model.offers.first { $0.offerId == reservation.offerId }
        let name = offer?.businessName ?? "the provider"
        let confirmed = reservation.status == .confirmed
        return VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
            if confirmed {
                Label("Confirmed by the provider", systemImage: "checkmark.circle.fill")
                    .plugText(.title3).foregroundStyle(PlugTokens.Color.brandGreen)
            } else {
                Overline("Waiting for confirmation")
            }
            Text(confirmed ? "Booked with \(name)" : "Waiting for \(name) to confirm")
                .plugText(.display).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                Text("Booking reference").plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
                Text(reservation.bookingRef).plugDisplay(40, weight: 500).monospaced().kerning(4)
                    .accessibilityLabel(reservation.bookingRef.map(String.init).joined(separator: " "))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("booking-ref")
            VStack(spacing: 0) {
                PlugDivider()
                if let offer {
                    valueRow("Price", money(offer.priceCents, offer.currency))
                    valueRow("Starts", offer.availableAt.formatted(date: .omitted, time: .shortened))
                    if let place = offer.place { valueRow("Where", place.address) }
                }
                if confirmed, let at = reservation.confirmedAt {
                    valueRow("Confirmed at", at.formatted(date: .omitted, time: .shortened), last: true)
                } else {
                    valueRow("They confirm by", reservation.confirmBy.formatted(date: .omitted, time: .shortened), last: true)
                }
            }
            Text(confirmed ? "Both of you can quote this reference." : "Nothing is booked until they confirm.")
                .plugText(.body).fontWeight(confirmed ? .regular : .medium)
                .fixedSize(horizontal: false, vertical: true)
            if !confirmed {
                caption("If they can't make it, you can choose from your other offers.")
            }
        }
        .plugCard()
        .accessibilityIdentifier(confirmed ? "booking-confirmed" : "booking-pending")
    }

    private var orderedOffers: [ServiceOffer] {
        switch offerOrder {
        case .suggested: return model.offers
        case .price: return model.offers.enumerated().sorted {
            $0.element.priceCents == $1.element.priceCents ? $0.offset < $1.offset : $0.element.priceCents < $1.element.priceCents
        }.map(\.element)
        case .distance: return model.offers.enumerated().sorted {
            $0.element.distanceM == $1.element.distanceM ? $0.offset < $1.offset : $0.element.distanceM < $1.element.distanceM
        }.map(\.element)
        }
    }

    @ViewBuilder private func offerList(_ request: ServiceRequest) -> some View {
        if !model.offers.isEmpty {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                // The headline is the result itself, not a sentence about it.
                Text("\(model.offers.count) \(model.offers.count == 1 ? "offer" : "offers")")
                    .plugText(.hero).monospacedDigit()
                Text(offersTitle(request)).plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                if model.offers.contains(where: { $0.source == .seed }) { caption(Self.exampleNote) }
            }
            if model.offers.count > 1 {
                PlugFlowLayout(spacing: PlugTokens.Space.s2) {
                    ForEach(OfferOrder.allCases, id: \.self) { order in
                        PlugChip(title: order.rawValue, selected: offerOrder == order) {
                            withAnimation(.plugSheet(reduceMotion: reduceMotion)) { offerOrder = order }
                        }
                        .accessibilityIdentifier("offers-sort-" + String(describing: order))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                PlugDivider()
                ForEach(Array(orderedOffers.enumerated()), id: \.element.id) { index, offer in
                    VStack(spacing: 0) {
                        offerRow(offer).padding(.vertical, PlugTokens.Space.s6 - 4)
                        PlugDivider()
                    }
                    .plugArrival(index)
                }
            }
        }
    }

    /// An offer as a row between hairlines: the name in the serif, and the price, larger, opposite.
    private func offerRow(_ offer: ServiceOffer) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: PlugTokens.Space.s3) {
                    offerName(offer)
                    Spacer(minLength: 0)
                    price(offer).fixedSize()
                }
                VStack(alignment: .leading, spacing: PlugTokens.Space.s2) { offerName(offer); price(offer) }
            }
            HStack(alignment: .center, spacing: PlugTokens.Space.s3) {
                PlugFlowLayout(spacing: PlugTokens.Space.s3) {
                    TruthBadge(label: offer.truthLabel)
                    Label(offer.availableAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink900)
                        .frame(minHeight: 26)
                        .accessibilityLabel("Earliest \(offer.availableAt.formatted(date: .omitted, time: .shortened))")
                }
                Spacer(minLength: 0)
                Button { selectedOffer = offer } label: {
                    Image(systemName: "chevron.right").font(.system(size: 16, weight: .medium))
                        .frame(width: PlugTokens.minTouchTarget, height: PlugTokens.minTouchTarget)
                }
                .buttonStyle(PlugButtonStyle(kind: .outline, fullWidth: false, compact: true))
                .accessibilityLabel("View details")
            }
            caption("Offer ends " + offer.expiresAt.formatted(date: .omitted, time: .shortened))
        }
    }

    private func offerName(_ offer: ServiceOffer) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
            Text(offer.businessName).plugText(.title)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(offer.serviceName) · \(distance(offer.distanceM))").plugText(.bodySmall)
                .foregroundStyle(PlugTokens.Color.ink600)
            if let line = scoreText(offer.providerScore) {
                Text(line).plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
            }
        }
    }

    private func price(_ offer: ServiceOffer) -> some View {
        Text(money(offer.priceCents, offer.currency)).plugDisplay(34, weight: 500).monospacedDigit()
    }

    private func offersTitle(_ request: ServiceRequest) -> String {
        let service = request.constraints.serviceName ?? "Offers"
        guard let budget = request.constraints.budgetCents else { return service }
        return "\(service) under \(money(budget, request.constraints.currency))"
    }

    /// A place question: the human answer, the designed Unknown, and the web answer below them.
    @ViewBuilder private func placeAnswer(_ place: PlaceQuestion) -> some View {
        if place.status == .asking {
            EmptyView()
        } else if place.status == .answered, let answer = place.answer {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                Text(place.placeName ?? "From nearby").plugText(.title3)
                ResultHeadline(value: answer.value, label: answer.truthLabel)
                Text(answer.summary).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                if !answer.sources.isEmpty {
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                        PlugDivider()
                        Text("Who answered").plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
                        PlugFlowLayout(spacing: PlugTokens.Space.s4) {
                            ForEach(Array(answer.sources.enumerated()), id: \.offset) { _, source in
                                // Each source is a person, so their initials sit in a circle.
                                HStack(spacing: PlugTokens.Space.s2) {
                                    Text(source.initials).plugText(.label).foregroundStyle(PlugTokens.Color.paper)
                                        .frame(minWidth: sourceMark, minHeight: sourceMark)
                                        .background(PlugTokens.Color.ink900, in: Circle())
                                    caption(source.answeredAt.formatted(.relative(presentation: .named)))
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .accessibilityIdentifier("place-answer-sources")
                }
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

    private func nobody(_ title: String, _ detail: String, _ notified: Int, subject: String? = nil) -> some View {
        PlugNotice(title: title, unknown: true, subject: subject, message: detail,
                   detail: notified == 0 ? "Nobody was notified" : "\(notified) people notified")
            .accessibilityIdentifier("request-unknown")
    }

    /// Nobody nearby offers this yet. PLUG fills gaps with people, so the honest next step is an
    /// invitation to offer it, not a dead end. Nothing is implied about who else might.
    private func offerTheGap(_ request: ServiceRequest) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Is this something you do?").plugText(.title)
                .foregroundStyle(PlugTokens.Color.ink900)
            Text("Nobody nearby offers \(request.constraints.serviceName?.lowercased() ?? "this") on PLUG yet. Add it as a skill and you will be matched with the next person who asks.")
                .plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
            Button("Offer this service") { offeringService = true }
                .buttonStyle(PlugButtonStyle(kind: .secondary, fullWidth: false))
                .accessibilityIdentifier("offer-the-gap")
        }
        .plugCard()
    }

    @ViewBuilder private var actions: some View {
        if let request = model.request, request.status.canCancel {
            Button(request.status == .confirmed ? "Cancel booking" : request.status == .userSelected ? "Cancel request" : "Stop asking") {
                if request.status == .confirmed { confirmingCancel = true } else { Task { await model.cancel() } }
            }
                .buttonStyle(FlowActionStyle(destructive: true))
                .disabled(model.isWorking)
                .accessibilityIdentifier("request-cancel")
                .confirmationDialog("Cancel this booking?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                    Button("Cancel booking", role: .destructive) { Task { await model.cancel() } }
                    Button("Keep booking", role: .cancel) { }
                } message: {
                    Text("The provider will see that it is canceled.")
                }
        } else if model.placeQuestion?.status != .asking {
            // While the one question is open, answering it is the task; starting over is secondary.
            Button("Ask something else") { model.startAgain(); showValidation = false }
                .buttonStyle(FlowActionStyle(primary: model.askQuestion == nil && model.request?.clarification == nil))
                .disabled(model.isWorking)
        }
    }

    // MARK: Shared

    /// Says what failed and whether anything was saved.
    @ViewBuilder private var failure: some View {
        if let message = model.errorMessage {
            PlugNotice(message: message,
                       tone: .alert,
                       actionTitle: model.hasAsk ? "Retry update" : nil,
                       actionDisabled: model.isWorking) { Task { await model.refresh() } }
                .accessibilityIdentifier("request-error")
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
        }
    }
    private func fieldError(_ value: String) -> some View {
        Label(value, systemImage: "exclamationmark.triangle.fill")
            .plugText(.bodySmall).fontWeight(.semibold).foregroundStyle(PlugTokens.Color.alert600)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Ready-made asks for each category tile, from skills in contracts/skills.yaml. The first is
/// the one shown in the sheet's box when it opens.
private enum Example {
    static let hairBeauty = ["Someone to do knotless braids, $120 max", "Barber under $35 in the next hour",
                             "Nails done this afternoon", "Brows shaped today"]
    static let homeHelp = ["Fix a leaking sink today", "Mount a TV this weekend",
                           "Assemble a bed frame tomorrow", "House cleaning on Saturday morning"]
    static let tech = ["I need help repairing my laptop", "Fix a cracked phone screen today",
                       "Replace my phone battery this week"]
}

/// The server's score wording, or nil when it sent a scored state without a value: no number
/// is ever filled in on the phone.
func scoreText(_ score: ProviderScore) -> String? {
    switch score.state {
    case .new: return score.completedJobs == 0 ? "New provider" : "New provider, \(score.completedJobs) jobs"
    case .scored:
        guard let value = score.value else { return nil }
        return "Score \(value) from \(score.completedJobs) jobs"
    }
}

func caption(_ text: String) -> some View {
    Text(text).plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
        .fixedSize(horizontal: false, vertical: true)
}

/// Values right-aligned in a key/value column so they scan vertically.
func valueRow(_ label: String, _ value: String, last: Bool = false) -> some View {
    VStack(spacing: 0) {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: PlugTokens.Space.s2)
                Text(value).plugText(.title3).monospacedDigit().foregroundStyle(PlugTokens.Color.ink900)
                    .fixedSize(horizontal: true, vertical: false)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                Text(label).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                Text(value).plugText(.title3).monospacedDigit().foregroundStyle(PlugTokens.Color.ink900)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, PlugTokens.Space.s2)
        if !last { PlugDivider() }
    }
    .accessibilityElement(children: .combine)
}

func distance(_ metres: Int) -> String {
    Measurement(value: Double(metres), unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
}

func money(_ cents: Int, _ currency: String) -> String {
    (Decimal(cents) / 100).formatted(.currency(code: currency).precision(.fractionLength(cents % 100 == 0 ? 0 : 2)))
}

/// Keep the value dominant; move the evidence below it when large text needs room.
private struct ResultHeadline: View {
    let value: String
    let label: ServiceOffer.TruthLabel
    var size: CGFloat = 42
    var color: Color = PlugTokens.Color.ink900
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes always stacked, so the value keeps the full width over the badge.
        if typeSize.isAccessibilitySize {
            stacked
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: PlugTokens.Space.s3) {
                    title.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    TruthBadge(label: label, large: true)
                }
                stacked
            }
        }
    }
    private var stacked: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            title.fixedSize(horizontal: false, vertical: true)
            TruthBadge(label: label, large: true)
        }
    }
    private var title: some View {
        Text(value).plugDisplay(size, weight: 500).monospacedDigit().foregroundStyle(color)
    }
}

/// What the web says: a dashed hairline, labelled Not verified, and set smaller and quieter than
/// any human answer above it. Never a human answer.
struct WebAnswerCard: View {
    let answer: WebAnswer
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlugShape.tile, style: .continuous)
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            HStack {
                TruthBadge(label: .notVerified)
                Spacer(minLength: 0)
            }
            Text(answer.headline).plugText(.title2)
                .foregroundStyle(PlugTokens.Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
            Label("From the web", systemImage: "globe").plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
            Text(answer.summary).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                .fixedSize(horizontal: false, vertical: true)
            PlugDivider()
            Text("Where this came from").plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
            Text("\(answer.sourceName), read \(answer.retrievedAt.formatted(.relative(presentation: .named)))")
                .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink900)
            caption("No person checked this. It is a pattern, not what is happening now.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PlugTokens.Space.s6 - 4)
        .overlay(shape.strokeBorder(PlugTokens.Color.ruleControl, style: StrokeStyle(lineWidth: PlugShape.rule, dash: [4, 3])))
    }
}

/// The offer in full, as a sheet over the results. Choosing asks the provider to confirm; it
/// never books by itself.
private struct OfferDetailView: View {
    enum Choice { case none, available, unavailable }
    let offer: ServiceOffer
    let cached: Bool
    var choice: Choice = .none
    var choosing = false
    var error: String? = nil
    var onChoose: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                        Text(offer.businessName).plugText(.display)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(offer.serviceName).plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                        if offer.source == .seed { caption("Example offer for preview. Nothing is booked.") }
                        if let line = scoreText(offer.providerScore) {
                            Text(line).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                        }
                    }
                    if cached || offer.expiresAt <= Date() {
                        PlugNotice(message: "This saved offer needs a fresh check. Go back and refresh.")
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom, spacing: PlugTokens.Space.s3) {
                            priceText.fixedSize()
                            Spacer(minLength: 0)
                            TruthBadge(label: offer.truthLabel, large: true).padding(.bottom, PlugTokens.Space.s3)
                        }
                        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                            priceText
                            TruthBadge(label: offer.truthLabel, large: true)
                        }
                    }
                    facts
                    explanation
                    chooseSection
                    if let about = offer.business?.about {
                        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                            BusinessIdentity(name: offer.businessName, business: offer.business, score: offer.providerScore)
                            Text(about).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let links = offer.business?.links, !links.isEmpty {
                        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                            Text("See their work").plugText(.title2)
                            BusinessLinks(links: links)
                        }
                        .padding(.top, PlugTokens.Space.s2)
                    }
                    HStack {
                        DetailsButton { OfferDetails(offer: offer) }
                        Spacer()
                    }
                }
                .foregroundStyle(PlugTokens.Color.ink900)
                .padding(.horizontal, PlugTokens.Space.s6)
                .padding(.top, PlugTokens.Space.s2)
                .padding(.bottom, PlugTokens.Space.s8)
            }
            .background(PlugTokens.Color.paper)
            .navigationTitle("Offer").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PlugTokens.Color.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .tint(PlugTokens.Color.ink900)
    }

    private var live: Bool { !cached && offer.expiresAt > Date() }

    @ViewBuilder private var chooseSection: some View {
        switch choice {
        case .available where live:
            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                Button { onChoose() } label: {
                    ZStack {
                        Text("Choose this offer").opacity(choosing ? 0 : 1)
                        if choosing {
                            HStack(spacing: PlugTokens.Space.s2) {
                                ProgressView().tint(PlugTokens.Color.paper).controlSize(.small)
                                Text("Asking them to confirm")
                            }
                        }
                    }
                }
                .buttonStyle(PlugButtonStyle(kind: .primary))
                .disabled(choosing)
                .accessibilityIdentifier("offer-choose")
                .accessibilityHint("Asks the provider to confirm. Nothing is booked until they do.")
                caption("We ask them to confirm. Nothing is booked until they do.")
                if let error { PlugNotice(message: error, tone: .alert) }
            }
        case .unavailable:
            caption("Booking isn’t available yet. Nothing was booked.")
                .accessibilityIdentifier("offer-booking-unavailable")
        default:
            EmptyView()
        }
    }

    private var priceText: some View {
        Text(money(offer.priceCents, offer.currency)).plugDisplay(64, weight: 500, limit: 1.2).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    private var facts: some View {
        var items = [("Away", distance(offer.distanceM)),
                     ("Earliest", offer.availableAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))]
        if let place = offer.place { items.append(("Where to find them", place.address)) }
        items.append(("Offer ends", offer.expiresAt.formatted(date: .abbreviated, time: .shortened)))
        let columns = Array(repeating: GridItem(.flexible(), spacing: PlugTokens.Space.s3, alignment: .top),
                            count: typeSize.isAccessibilitySize ? 1 : 2)
        return VStack(alignment: .leading, spacing: 0) {
            PlugDivider()
            LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                        Text(items[index].0).plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
                        Text(items[index].1).plugText(.title3).fontWeight(.medium).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, PlugTokens.Space.s4)
                    // Every cell in a row is as tall as the tallest, so the hairlines line up.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .overlay(alignment: .bottom) { PlugDivider() }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// What the label means for this offer, in its own colour and edge.
    private var explanation: some View {
        let label = offer.truthLabel
        let shape = RoundedRectangle(cornerRadius: PlugShape.tile, style: .continuous)
        let dashed = ![ServiceOffer.TruthLabel.confirmed, .recent].contains(label)
        return HStack(alignment: .top, spacing: PlugTokens.Space.s3) {
            TruthGlyph(label: label, size: 18).foregroundStyle(label.foreground)
            Text(label.explanation).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PlugTokens.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(label.surface, in: shape)
        .overlay { if dashed { shape.strokeBorder(label.border, style: StrokeStyle(lineWidth: PlugShape.rule, dash: [4, 3])) } }
        .accessibilityElement(children: .combine)
    }
}

/// A monogram on sand when a business has chosen not to share a photo.
struct BusinessPortrait: View {
    let name: String
    let photo: String?
    var size: CGFloat = PlugTokens.Layout.portrait
    private var picture: UIImage? {
        guard let photo, photo.count <= 65536, let data = Data(base64Encoded: photo) else { return nil }
        return UIImage(data: data)
    }
    var body: some View {
        Group {
            if let picture {
                Image(uiImage: picture).resizable().scaledToFill()
            } else {
                Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
                    .font(PlugFont.display(initialsSize, weight: 500))
                    .foregroundStyle(PlugTokens.Color.ink900)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PlugTokens.Color.sunk)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    /// Initials sized to the fixed portrait; the portrait is hidden from VoiceOver and the name
    /// beside it carries the text, which does scale.
    private var initialsSize: CGFloat {
        if size >= PlugTokens.Layout.portraitLarge { return PlugTokens.TypeSize.display }
        if size >= PlugTokens.Layout.portrait { return PlugTokens.TypeSize.title1 }
        return PlugTokens.TypeSize.title3
    }
}

struct BusinessIdentity: View {
    let name: String
    let business: BusinessProfile?
    let score: ProviderScore
    var prominent = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: PlugTokens.Space.s3))
            : AnyLayout(HStackLayout(alignment: .center, spacing: PlugTokens.Space.s4))
        layout {
            BusinessPortrait(name: name, photo: business?.photoBase64,
                             size: prominent ? PlugTokens.Layout.portraitLarge : PlugTokens.Layout.portraitSmall)
            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                Text(name).plugText(prominent ? .title : .title3).foregroundStyle(PlugTokens.Color.ink900)
                if let line = scoreText(score) {
                    Text(line).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BusinessLinks: View {
    let links: [BusinessLink]
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = PlugTokens.Layout.icon
    var body: some View {
        ForEach(Array(links.enumerated()), id: \.offset) { _, link in
            if let url = link.destination {
                Link(destination: url) {
                    HStack(alignment: .center, spacing: PlugTokens.Space.s3) {
                        Image(systemName: link.label.lowercased().contains("instagram") ? "camera.fill" : "globe")
                            .font(.system(size: min(glyph, PlugTokens.Layout.iconMax), weight: .regular))
                            .frame(width: PlugTokens.minTouchTarget, height: PlugTokens.minTouchTarget)
                            .overlay(RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous).strokeBorder(PlugTokens.Color.rule300, lineWidth: PlugShape.rule))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                            Text(link.label).plugText(.action)
                            Text(url.host() ?? "").plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").fontWeight(.medium).accessibilityHidden(true)
                    }
                    .foregroundStyle(PlugTokens.Color.ink900)
                    .padding(.vertical, PlugTokens.Space.s1)
                    .frame(minHeight: PlugTokens.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .accessibilityHint("Opens the business's external website")
            }
        }
    }
}

extension View {
    /// One card style; the name stays for its call sites.
    func marketCard() -> some View { plugCard() }
}

struct FlowMetrics: View {
    let items: [(String, String, String)]
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        // One row when every label fits whole; otherwise a column, so "Answered" never breaks.
        if typeSize.isAccessibilitySize {
            cells(AnyLayout(VStackLayout(alignment: .leading, spacing: PlugTokens.Space.s3)), whole: false)
        } else {
            ViewThatFits(in: .horizontal) {
                cells(AnyLayout(HStackLayout(alignment: .top, spacing: PlugTokens.Space.s3)), whole: true)
                cells(AnyLayout(VStackLayout(alignment: .leading, spacing: PlugTokens.Space.s3)), whole: false)
            }
        }
    }
    private func cells(_ layout: AnyLayout, whole: Bool) -> some View {
        layout {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                    Text(item.0).plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
                        .fixedSize(horizontal: whole, vertical: false)
                    Text(item.1).plugText(compact ? .title3 : .title2)
                        .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
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

/// A small green dot with one ring breathing out of it, beside "Asking ... nearby". The only
/// looping motion in the app; still under Reduce Motion.
private struct AskingPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var out = false
    var body: some View {
        Circle().fill(PlugTokens.Color.brandGreen).frame(width: 8, height: 8)
            .background {
                Circle().stroke(PlugTokens.Color.brandGreen, lineWidth: 1)
                    .scaleEffect(out ? 2.6 : 1).opacity(out ? 0 : 0.7)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { out = true }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Details

/// A time the server sent: the clock alone today, the day too otherwise.
private func moment(_ date: Date) -> String {
    Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened)
        : date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
}

private func detailSection<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
        Text(title).plugText(.title2).foregroundStyle(PlugTokens.Color.ink900).accessibilityAddTraits(.isHeader)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

/// The illustrated stand-in when there is no position to show: no coordinates were sent.
private struct DetailsArt: View {
    let art: String
    let title: String
    let line: String
    var body: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Image(art).resizable().scaledToFit().frame(height: 120)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PlugTokens.Space.s4)
                .background(PlugTokens.Color.sunk, in: RoundedRectangle(cornerRadius: PlugShape.illustration, style: .continuous))
                .accessibilityHidden(true)
            Text(title).plugText(.title).fixedSize(horizontal: false, vertical: true)
            caption(line)
        }
    }
}

/// The search area of a service request: the approximate point the request carries, with a soft
/// circle for its distance limit. No pin, so it never reads as a precise position.
private struct SearchAreaMap: View {
    let location: RequestLocation
    let radius: Int
    var body: some View {
        let centre = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        let span = Double(radius) * 2.8
        let shape = RoundedRectangle(cornerRadius: PlugShape.illustration, style: .continuous)
        Map(initialPosition: .region(MKCoordinateRegion(center: centre, latitudinalMeters: span, longitudinalMeters: span)),
            interactionModes: []) {
            MapCircle(center: centre, radius: CLLocationDistance(radius))
                .foregroundStyle(PlugTokens.Color.brandGreen.opacity(0.12))
                .stroke(PlugTokens.Color.brandGreen, lineWidth: 1.5)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls { }
        .frame(height: 220)
        .clipShape(shape)
        .overlay(shape.strokeBorder(PlugTokens.Color.rule300, lineWidth: PlugShape.rule))
        .accessibilityElement()
        .accessibilityLabel("Map of the approximate search area, \(distance(radius)) around where you asked")
        .accessibilityIdentifier("details-map")
    }
}

/// Your ask: where PLUG is looking, what has happened so far, and what comes next.
struct RequestDetails: View {
    let request: ServiceRequest

    var body: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s8) {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                SearchAreaMap(location: request.constraints.location, radius: request.constraints.maxDistanceM)
                caption("Searching within \(distance(request.constraints.maxDistanceM)) of where you asked. The map shows the area, not your exact spot.")
            }
            detailSection("So far") { DetailTimeline(steps: steps) }
            detailSection("What happens next") {
                Text(next).plugText(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var steps: [DetailTimeline.Step] {
        let progress = request.progress
        let open = request.status.canCancel
        var steps = [DetailTimeline.Step(title: "Asked", value: moment(request.createdAt))]
        steps.append(.init(title: "People nearby",
                           value: progress.contacted == 0 ? "Nobody notified yet"
                               : "\(progress.contacted) notified, \(progress.replied) replied",
                           done: progress.contacted > 0))
        if progress.offersReady > 0 {
            steps.append(.init(title: "Offers", value: "\(progress.offersReady) \(progress.offersReady == 1 ? "offer" : "offers") ready"))
        }
        steps.append(.init(title: open ? "Offers stop" : "Closed", value: open ? moment(request.expiresAt) : status,
                           done: !open))
        return steps
    }

    private var status: String {
        switch request.status {
        case .expired: return "Ended at \(moment(request.expiresAt))"
        case .canceled: return "You stopped asking"
        case .blocked: return "Not sent"
        case .confirmed: return "Confirmed by the provider"
        case .completed: return "Completed"
        default: return "Closed"
        }
    }

    private var next: String {
        switch request.nextAction {
        case .answerClarification: return "Answer the question on your ask so PLUG knows who to ask."
        case .waitForOffers: return "People nearby who offer this see your ask and can send an offer. Offers show up on your ask."
        case .chooseOffer: return "Compare the offers by price, time and distance. Nothing is booked until a provider confirms."
        case .awaitSupplierConfirmation: return "The provider has been asked to confirm. Nothing is booked until they do."
        case .showResult: return "This request is finished."
        case .showNoResult: return request.noResultReason?.explanation ?? "No current offers are available."
        case .none: return "This request is closed. Nobody else will be contacted."
        }
    }
}

/// A place question: who was asked, what came back and how long it holds.
struct PlaceDetails: View {
    let place: PlaceQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s8) {
            DetailsArt(art: "IllPlaces", title: place.placeName ?? "Your question",
                       line: "Answered by people nearby, never by PLUG itself.")
            detailSection("So far") { DetailTimeline(steps: steps) }
            if let web = place.webAnswer {
                detailSection("From the web") {
                    HStack { TruthBadge(label: .notVerified); Spacer(minLength: 0) }
                    caption("\(web.sourceName), read \(web.retrievedAt.formatted(.relative(presentation: .named))). No person checked this.")
                }
            }
            detailSection("What happens next") {
                Text(next).plugText(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var steps: [DetailTimeline.Step] {
        let progress = place.progress
        var steps = [DetailTimeline.Step(title: "Asked", value: moment(place.createdAt)),
                     .init(title: "People nearby",
                           value: progress.notified == 0 ? "Nobody notified"
                               : "\(progress.notified) notified, \(progress.opened) opened, \(progress.answered) answered",
                           done: progress.notified > 0)]
        switch place.status {
        case .asking:
            steps.append(.init(title: "Question open until", value: moment(place.expiresAt), done: false))
        case .answered:
            if let answer = place.answer {
                steps.append(.init(title: "Answer", value: answer.value))
                steps.append(.init(title: "Current until", value: moment(answer.expiresAt), done: answer.expiresAt <= Date()))
            }
        case .unknown:
            steps.append(.init(title: "Answer", value: "Unknown. No one nearby could check."))
        }
        return steps
    }

    private var next: String {
        switch place.status {
        case .asking: return "People nearby can see your question and answer it. Answers show up on your ask."
        case .answered: return "After the time above, this answer is no longer current. Ask again for a fresh one."
        case .unknown: return "Nobody could check this time. You can ask again later."
        }
    }
}

/// An offer: how far, when, and how choosing works today.
private struct OfferDetails: View {
    let offer: ServiceOffer

    var body: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s8) {
            if let place = offer.place {
                DetailsArt(art: "IllPlaces", title: "\(distance(offer.distanceM)) away",
                           line: "\(place.name), \(place.address)")
            } else {
                DetailsArt(art: "IllHomeHelp", title: "\(distance(offer.distanceM)) away",
                           line: "This provider works through PLUG and has no public address.")
            }
            detailSection("Timing") {
                DetailTimeline(steps: [
                    .init(title: "Information recorded", value: moment(offer.observedAt)),
                    .init(title: "Earliest", value: moment(offer.availableAt), done: offer.availableAt <= Date()),
                    .init(title: "Offer ends", value: moment(offer.expiresAt), done: offer.expiresAt <= Date())
                ])
            }
            detailSection("How choosing works") {
                Text(offer.source == .seed
                     ? "This is an example offer for preview. Nothing is booked."
                     : "Choosing an offer asks the provider to confirm it. Nothing is booked until they do. If they can't, your other offers stay open.")
                    .plugText(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
