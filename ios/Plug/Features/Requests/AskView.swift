import AVFoundation
import Speech
import SwiftUI

/// The Ask screen from manual v4 Figure A1: one field for both kinds of ask, examples grouped
/// by the two things PLUG does, and the four answer states (working, answered, nobody
/// answered, and the dashed web answer). Owner-requested marketplace visual revision; the
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
    @State private var moreIdeas = false
    @State private var offerOrder = OfferOrder.suggested
    private enum OfferOrder: String, CaseIterable { case suggested = "For you", price = "Lowest price", distance = "Closest" }
    @Environment(\.dynamicTypeSize) private var typeSize
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
                guard pages.isEmpty, model.hasAsk, !model.hasActiveAsk else { return }
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
        .onDisappear { model.setActive(false); voice.stop() }
    }

    // MARK: 1. Ask

    private var home: some View {
        page {
            HStack {
                // One logotype everywhere, the app and the website (owner decision, 2026-10-08).
                PlugLogotype(size: 28)
                Spacer()
                Label("Around you", systemImage: "location")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(stillAsking ? "Let’s find your person." : "Who can help you today?")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("ask-home-title")
                if !stillAsking {
                    Text("Local skills. Real connections.")
                        .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                }
            }
            if model.hasAsk { resumeCard }
            if !stillAsking { composer }
            failure
            if !stillAsking { discovery }
            Button { offeringService = true } label: {
                stacked(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 26, weight: .regular))
                        .frame(width: 52, height: 56)
                        .background(PlugTokens.Color.card.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your skill. Someone’s solution.").plugText(.title3).fixedSize(horizontal: false, vertical: true)
                        Text("Offer a service").plugText(.bodySmall).opacity(0.8)
                    }
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 18, weight: .medium))
                    }
                }
                .foregroundStyle(PlugTokens.Color.card)
                .padding(20)
                .background(PlugTokens.Color.ink900, in: RoundedRectangle(cornerRadius: 24))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Offer a service")
            .accessibilityIdentifier("offer-service")
            caption("Private preview · Example offers. Booking isn’t available yet.")
        }
        .toolbar(.hidden, for: .navigationBar)
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

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(PlugTokens.Color.ink600).accessibilityHidden(true)
                ZStack(alignment: .leading) {
                    // The system placeholder truncates at large text sizes and is very light;
                    // this one wraps and meets the contrast floor.
                    if model.text.isEmpty {
                        Text("Tell us what you need…").plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                            .fixedSize(horizontal: false, vertical: true)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    TextField("", text: $model.text, axis: .vertical)
                        .plugText(.body).lineLimit(1...5).focused($textFocused)
                }
                    .frame(minHeight: PlugTokens.minTouchTarget, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityLabel("What do you need?")
                    .accessibilityIdentifier("request-text")
                    .disabled(model.isWorking)
                // Earlier words stay after "Ask something else"; one tap starts fresh.
                if !model.text.isEmpty && !model.isWorking {
                    Button { voice.stop(); model.text = ""; textFocused = true } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                            .foregroundStyle(PlugTokens.Color.ink400)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Clear")
                    .accessibilityIdentifier("request-clear")
                }
                Button { ask() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 20, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .foregroundStyle(PlugTokens.Color.card)
                        .background(PlugTokens.Color.ink900, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain).accessibilityLabel("Ask")
                .accessibilityIdentifier("ask-submit")
                .disabled(model.isWorking || location.isWorking)
            }
            .padding(12).padding(.leading, 4)
            // The whole box focuses the field, not just its single line of text.
            .contentShape(RoundedRectangle(cornerRadius: 24))
            .onTapGesture { if !model.isWorking { textFocused = true } }
            .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(textFocused ? PlugTokens.Color.ink900 : PlugTokens.Color.rule200))
            HStack {
                Text("A service or a question about a place").plugText(.caption)
                    .foregroundStyle(PlugTokens.Color.ink600)
                Spacer(minLength: 4)
                voiceButton
            }
            if let note = voice.message { caption(note) }
            if showValidation, let error = model.textError { fieldError(error) }
            if location.location != nil || location.errorMessage != nil || location.isWorking { locationNote }
        }
    }

    private var discovery: some View {
        VStack(alignment: .leading, spacing: 24) {
            let categories = [("Hair & beauty", "scissors", Example.services[1]),
                              ("Home help", "house", Example.services[2]),
                              ("Tech", "laptopcomputer", "I need help repairing my laptop"),
                              ("Places", "mappin.and.ellipse", Example.places[0])]
            let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 2 : 4)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(categories, id: \.0) { title, icon, example in
                    Button { fillExample(example) } label: {
                        VStack(spacing: 10) {
                            Image(systemName: icon).font(.system(size: 25, weight: .regular))
                                .frame(width: 62, height: 62)
                                .background(PlugTokens.Color.sunk, in: RoundedRectangle(cornerRadius: 22))
                            Text(title).plugText(.label).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("A little inspiration").font(.system(.title3, design: .rounded, weight: .bold))
                Button { fillExample(Example.services[1]) } label: {
                    ZStack(alignment: .bottomLeading) {
                        GeometryReader { geometry in
                            Image("ServiceConnection").resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        }
                        LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Look good. Feel like you.")
                                    .font(.system(.title2, design: .rounded, weight: .bold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Find your next stylist").plugText(.bodySmall)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right").font(.system(size: 18, weight: .semibold))
                                .frame(width: 42, height: 42).background(.white.opacity(0.18), in: Circle())
                        }
                        .foregroundStyle(.white).padding(20)
                    }
                    // At least the photo's height, taller when the title needs it, never clipped.
                    .frame(minHeight: typeSize.isAccessibilitySize ? 330 : 248)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask-example-barber")
                .accessibilityLabel("Find hair and beauty services")
                .accessibilityHint("Fills an example request. Nothing is sent yet.")
                Button { fillExample(Example.places[0]) } label: {
                    stacked(spacing: 16) {
                        Image("Neighbourhood").renderingMode(.template).resizable().scaledToFit()
                            .frame(width: 70, height: 70)
                            .padding(8).background(PlugTokens.Color.sunk, in: RoundedRectangle(cornerRadius: 20))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Know before you go").plugText(.title3)
                            Text("Ask what’s happening nearby.").plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !typeSize.isAccessibilitySize {
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                        }
                    }
                    .padding(16).background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: 24))
                }
                .buttonStyle(.plain).accessibilityIdentifier("ask-example-place")
                .accessibilityHint("Fills a question about a place. Nothing is sent yet.")
            }
            DisclosureGroup("More ideas", isExpanded: $moreIdeas) {
                VStack(alignment: .leading, spacing: 12) {
                    examples("Find help", Array(Example.services.dropFirst()))
                    examples("Ask nearby", Array(Example.places.dropFirst()))
                }.padding(.top, 12)
            }
            .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
        }
        .foregroundStyle(PlugTokens.Color.ink900)
        .disabled(model.isWorking)
    }

    private func fillExample(_ text: String) {
        voice.stop()
        model.text = text
        textFocused = true
        showValidation = false
    }

    private var stillAsking: Bool { model.hasActiveAsk }

    /// Shown after swiping back from a request that is still asking people.
    private var resumeCard: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text(stillAsking ? "Still asking" : model.request?.status == .canceled ? "Ask stopped" : "Your last ask").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            Text(askedText).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
            if let progress = model.request?.progress {
                Text("\(progress.contacted) notified, \(progress.replied) replied")
                    .plugText(.bodySmall).monospacedDigit().foregroundStyle(PlugTokens.Color.ink600)
            }
            Rectangle().fill(PlugTokens.Color.rule200).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PlugTokens.Space.s6) {
                    resumeAction.fixedSize(horizontal: true, vertical: false)
                    stopAction.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: PlugTokens.Space.s1) { resumeAction; stopAction }
            }
            if model.request?.status == .canceled { caption("Stopped. You're free to ask again.") }
        }
        .plugCard()
    }

    private var resumeAction: some View {
        Button { path = [.answer] } label: {
            HStack { Text("Open this ask"); Image(systemName: "chevron.right").imageScale(.small).accessibilityHidden(true) }
        }
        .buttonStyle(RequestTextActionStyle())
        .accessibilityIdentifier("ask-resume")
    }

    @ViewBuilder private var stopAction: some View {
        if model.request?.status.canCancel == true {
            Button(model.isWorking ? "Stopping…" : "Stop asking") { Task { await model.cancel() } }
                .buttonStyle(RequestTextActionStyle(destructive: true))
                .disabled(model.isWorking)
                .accessibilityIdentifier("ask-stop")
        }
    }

    private var voiceButton: some View {
        Button { voice.toggle() } label: {
            Label(voice.isListening ? "Listening… Stop" : "Voice",
                  systemImage: voice.isListening ? "mic.fill" : "mic")
        }
        .buttonStyle(RequestTextActionStyle())
        .disabled(model.isWorking || !voice.isAvailable)
        .accessibilityLabel(voice.isListening ? "Stop dictation" : "Ask by voice")
        .sensoryFeedback(.start, trigger: voice.isListening) { _, listening in listening }
    }

    private func ask() {
        showValidation = true
        voice.stop()
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
        VStack(alignment: .leading, spacing: 0) {
            Text(heading).plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
                .padding(.bottom, PlugTokens.Space.s2)
            ForEach(items, id: \.self) { example in
                Button {
                    voice.stop()
                    model.text = example
                    textFocused = true
                } label: {
                    Text(example).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: PlugTokens.minTouchTarget, alignment: .leading)
                        .padding(.vertical, PlugTokens.Space.s2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking || stillAsking)
                .accessibilityHint("Puts this example in the field")
                if example != items.last { Rectangle().fill(PlugTokens.Color.rule200).frame(height: 1) }
            }
        }
        .padding(.vertical, PlugTokens.Space.s1)
    }

    // MARK: 2 to 4. The answer

    private var answerScreen: some View {
        page {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.bubble").font(.system(size: 19, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(PlugTokens.Color.sunk, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your request").plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
                    Text(askedText).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                }
                Spacer(minLength: 0)
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
                DisclosureGroup("Request reference") {
                    Text(reference).plugText(.caption).textSelection(.enabled)
                }.plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
            }
        }
        .navigationTitle("Your ask")
        .refreshable { await model.refresh() }
        .sensoryFeedback(.success, trigger: model.offers.count) { old, new in new > old }
        .sensoryFeedback(.error, trigger: model.errorMessage) { _, new in new != nil }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 17, weight: .medium))
                }.accessibilityLabel("Refresh").disabled(model.isWorking)
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
        VStack(alignment: .leading, spacing: 20) {
            FlowEmblem(symbol: "bubble.left.and.text.bubble.right", size: 72)
            VStack(alignment: .leading, spacing: 8) {
                Text(question.question).font(.system(.title2, design: .rounded, weight: .bold))
                Text("One quick detail to find the right help.").plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
            }
            ForEach(question.options, id: \.value) { option in
                Button { Task { await model.answer(option.value) } } label: {
                    HStack {
                        Text(option.label).plugText(.action)
                        Spacer(minLength: 12)
                        Image(systemName: "arrow.right").font(.system(size: 16))
                    }
                    .padding(18).background(PlugTokens.Color.paper, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).disabled(model.isWorking)
            }
        }.foregroundStyle(PlugTokens.Color.ink900).marketCard()
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
            if request.noResultReason == .noCoverage { offerTheGap(request) }
        case .none:
            VStack(alignment: .leading, spacing: 18) {
                FlowEmblem(symbol: "checkmark", size: 72)
                Text("You stopped asking").font(.system(.title2, design: .rounded, weight: .bold))
                Text("This request is closed. Nobody else will be contacted.")
                    .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
            }.marketCard()
        }
    }

    /// Reply counts come from the server; the visual never implies elapsed-time progress.
    private func working(_ request: ServiceRequest) -> some View {
        let p = request.progress
        return VStack(alignment: .leading, spacing: 22) {
            stacked(alignment: .top, spacing: 16) {
                FlowEmblem(symbol: "paperplane", size: 64)
                VStack(alignment: .leading, spacing: 8) {
                    workingTitle(request)
                    Text("Your request is out there. Replies land here.")
                        .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                }
            }
            FlowMetrics(items: [("Notified", "\(p.contacted)", "person.2"),
                                ("Replied", "\(p.replied)", "bubble.left"),
                                ("Offers", "\(p.offersReady)", "tray")])
            ProgressView(value: Double(p.replied), total: Double(max(p.contacted, 1)))
                .tint(PlugTokens.Color.ink900)
                .accessibilityLabel("Replies received").accessibilityValue("\(p.replied) of \(p.contacted)")
            deadline(request)
        }
        .marketCard().accessibilityIdentifier("request-progress")
    }
    private func workingTitle(_ request: ServiceRequest) -> some View {
        Text("Asking \(request.constraints.serviceName?.lowercased() ?? "providers") nearby")
            .font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(PlugTokens.Color.ink900)
            .fixedSize(horizontal: false, vertical: true)
    }
    /// Side by side, or one above the other at accessibility text sizes, where a narrow column
    /// beside an icon would break words in the middle.
    private func stacked<Content: View>(alignment: VerticalAlignment = .center, spacing: CGFloat,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        // Full width either way, as every other card is; stacked content would otherwise hug its text.
        return layout(content).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func deadline(_ request: ServiceRequest) -> some View {
        Text("Open until \(request.expiresAt.formatted(date: .omitted, time: .shortened))")
            .plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
            .padding(.horizontal, PlugTokens.Space.s2).padding(.vertical, PlugTokens.Space.s1)
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.badge).strokeBorder(PlugTokens.Color.rule300))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var orderedOffers: [ServiceOffer] {
        switch offerOrder {
        case .suggested: return model.offers
        case .price: return model.offers.enumerated().sorted {
            $0.element.priceCents == $1.element.priceCents ? $0.offset < $1.offset : $0.element.priceCents < $1.element.priceCents
        }.map(\.element)
        case .distance: return model.offers.enumerated().sorted {
            $0.element.place.distanceM == $1.element.place.distanceM ? $0.offset < $1.offset : $0.element.place.distanceM < $1.element.place.distanceM
        }.map(\.element)
        }
    }

    @ViewBuilder private func offerList(_ request: ServiceRequest) -> some View {
        if !model.offers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // The headline is the result itself (design gate §16.8), not a sentence about it.
                Text("\(model.offers.count) \(model.offers.count == 1 ? "offer" : "offers")")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(offersTitle(request)).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            }
            if model.offers.count > 1 {
                PlugFlowLayout(spacing: 8) {
                    ForEach(OfferOrder.allCases, id: \.self) { order in
                        Button { offerOrder = order } label: {
                            HStack(spacing: 6) {
                                if offerOrder == order {
                                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).accessibilityHidden(true)
                                }
                                Text(order.rawValue).plugText(.label)
                            }
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .foregroundStyle(offerOrder == order ? PlugTokens.Color.ink900 : PlugTokens.Color.ink600)
                                .background(offerOrder == order ? PlugTokens.Color.card : PlugTokens.Color.sunk, in: Capsule())
                                .overlay(Capsule().strokeBorder(offerOrder == order ? PlugTokens.Color.ink900 : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain).accessibilityAddTraits(offerOrder == order ? .isSelected : [])
                        .accessibilityIdentifier("offers-sort-" + String(describing: order))
                    }
                }
            }
            ForEach(orderedOffers) { offer in
                VStack(alignment: .leading, spacing: 18) {
                    BusinessIdentity(name: offer.businessName, business: offer.business, score: offer.providerScore)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            comparisonPrice(offer)
                            Spacer(minLength: 0)
                            TruthBadge(label: offer.truthLabel)
                        }
                        VStack(alignment: .leading, spacing: 10) { comparisonPrice(offer); TruthBadge(label: offer.truthLabel) }
                    }
                    FlowMetrics(items: [("Earliest", offer.availableAt.formatted(date: .omitted, time: .shortened), "clock"),
                                        ("Away", distance(offer.place.distanceM), "location")], compact: true)
                    NavigationLink { OfferDetailView(offer: offer, cached: model.isCached) } label: {
                        HStack {
                            Text("View details").plugText(.action)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 17, weight: .medium))
                        }
                    }.buttonStyle(FlowActionStyle())
                    Text("Offer ends " + offer.expiresAt.formatted(date: .omitted, time: .shortened))
                        .plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
                }.marketCard()
            }
        }
    }
    private func comparisonPrice(_ offer: ServiceOffer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(offer.serviceName).plugText(.title3)
            Text(money(offer.priceCents, offer.currency))
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func offersTitle(_ request: ServiceRequest) -> String {
        let service = request.constraints.serviceName ?? "Offers"
        guard let budget = request.constraints.budgetCents else { return service }
        return "\(service) under \(money(budget, request.constraints.currency))"
    }

    /// Figure A1 screen 4 for a place question. Unknown is designed, with real counts.
    @ViewBuilder private func placeAnswer(_ place: PlaceQuestion) -> some View {
        if place.status == .asking {
            VStack(alignment: .leading, spacing: 22) {
                FlowEmblem(symbol: "mappin.and.ellipse", size: 72)
                placeTitle(place)
                Text("Checking with people nearby.").plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                FlowMetrics(items: [("Notified", "\(place.progress.notified)", "person.2"),
                                    ("Opened", "\(place.progress.opened)", "envelope.open"),
                                    ("Answered", "\(place.progress.answered)", "bubble.left")])
                placeDeadline(place)
            }.marketCard().accessibilityIdentifier("place-progress")
        } else if place.status == .answered, let answer = place.answer {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                HStack(spacing: 12) {
                    FlowEmblem(symbol: "bubble.left.and.bubble.right", size: 52)
                    Text(place.placeName ?? "From nearby").font(.system(.title3, design: .rounded, weight: .bold))
                }
                ResultHeadline(value: answer.value, label: answer.truthLabel)
                Text(answer.summary).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                if !answer.sources.isEmpty {
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                        Rectangle().fill(PlugTokens.Color.rule200).frame(height: 1)
                        Text("Who answered").plugText(.label).foregroundStyle(PlugTokens.Color.ink900)
                        PlugFlowLayout {
                            ForEach(Array(answer.sources.enumerated()), id: \.offset) { _, source in
                                VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                                    Text(source.initials).plugText(.label).foregroundStyle(PlugTokens.Color.ink900)
                                    caption(source.answeredAt.formatted(.relative(presentation: .named)))
                                }
                                .padding(PlugTokens.Space.s2)
                                .background(PlugTokens.Color.sunk, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.badge))
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .accessibilityIdentifier("place-answer-sources")
                }
                caption("This answer stops being current at \(answer.expiresAt.formatted(date: .omitted, time: .shortened)).")
            }
            .marketCard()
        } else {
            nobody("No answers", place.progress.notified == 0
                   ? "Nobody near this place is answering questions on PLUG yet, so no one could check."
                   : "No one nearby was able to check.", place.progress.notified,
                   subject: place.placeName)
        }
        if let web = place.webAnswer { WebAnswerCard(answer: web) }
    }

    private func placeTitle(_ place: PlaceQuestion) -> some View {
        Text("Asking people near \(place.placeName ?? "this place")").font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(PlugTokens.Color.ink900)
    }
    private func placeDeadline(_ place: PlaceQuestion) -> some View {
        Text("Open until \(place.expiresAt.formatted(date: .omitted, time: .shortened))")
            .plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
            .padding(.horizontal, PlugTokens.Space.s2).padding(.vertical, PlugTokens.Space.s1)
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.badge).strokeBorder(PlugTokens.Color.rule300))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func nobody(_ title: String, _ detail: String, _ notified: Int, subject: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            FlowEmblem(symbol: "bubble.left.and.exclamationmark.bubble.right", size: 80)
            ResultHeadline(value: title, label: .unknown, style: .title2)
            if let subject { Text(subject).plugText(.title3) }
            Text(detail).plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
            Label(notified == 0 ? "Nobody was notified" : "\(notified) people notified", systemImage: "person.2")
                .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
        }.marketCard().accessibilityIdentifier("request-unknown")
    }

    /// Nobody nearby offers this yet. PLUG fills gaps with people, so the honest next step is an
    /// invitation to offer it, not a dead end. Nothing is implied about who else might.
    private func offerTheGap(_ request: ServiceRequest) -> some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Is this something you do?").font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(PlugTokens.Color.ink900)
            Text("Nobody nearby offers \(request.constraints.serviceName?.lowercased() ?? "this") on PLUG yet. Add it as a skill and you will be matched with the next person who asks.")
                .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
            Button("Offer this service") { offeringService = true }
                .buttonStyle(FlowActionStyle())
                .accessibilityIdentifier("offer-the-gap")
        }
        .marketCard()
    }

    @ViewBuilder private var actions: some View {
        if let request = model.request, request.status.canCancel {
            Button("Stop asking") { Task { await model.cancel() } }
                .buttonStyle(FlowActionStyle(destructive: true))
                .disabled(model.isWorking)
                .accessibilityIdentifier("request-cancel")
        } else if model.placeQuestion?.status != .asking {
            // While the one question is open, answering it is the task; starting over is secondary.
            Button("Ask something else") { model.startAgain(); showValidation = false }
                .buttonStyle(FlowActionStyle(primary: model.askQuestion == nil && model.request?.clarification == nil))
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
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: PlugTokens.Space.s2)
                Text(value).plugText(.body).fontWeight(.bold).monospacedDigit().foregroundStyle(PlugTokens.Color.ink900)
                    .fixedSize(horizontal: true, vertical: false)
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

/// Keep the value dominant; move the evidence below it when large text needs room.
private struct ResultHeadline: View {
    let value: String
    let label: ServiceOffer.TruthLabel
    var style: PlugTextStyle = .display

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: PlugTokens.Space.s3) {
                title.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                TruthBadge(label: label)
            }
            VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                title.fixedSize(horizontal: false, vertical: true)
                TruthBadge(label: label)
            }
        }
    }
    private var title: some View {
        Text(value).plugText(style).monospacedDigit().foregroundStyle(PlugTokens.Color.ink900)
    }
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
            Label("From the web", systemImage: "globe").plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
            ResultHeadline(value: answer.headline, label: .notVerified, style: .title3)
            Text(answer.summary).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
            Rectangle().fill(PlugTokens.Color.rule200).frame(height: 1)
            Text("Where this came from").plugText(.label).foregroundStyle(PlugTokens.Color.ink900)
            Text("\(answer.sourceName), read \(answer.retrievedAt.formatted(.relative(presentation: .named)))")
                .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            caption("No person checked this. It is a pattern, not what is happening now.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PlugTokens.Space.s4)
        .overlay(RoundedRectangle(cornerRadius: 24)
            .strokeBorder(PlugTokens.Color.rule300, style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
    }
}

/// Figure A3: the offer in full. Booking needs supplier confirmation, which is Phase 3.
private struct OfferDetailView: View {
    let offer: ServiceOffer
    let cached: Bool
    @State private var showingEvidence = false
    private var hasPhoto: Bool {
        guard let photo = offer.business?.photoBase64, let data = Data(base64Encoded: photo) else { return false }
        return UIImage(data: data) != nil
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 0) {
                    BusinessImageBanner(photo: offer.business?.photoBase64, height: 220)
                    VStack(alignment: .leading, spacing: 14) {
                        if !hasPhoto {
                            BusinessPortrait(name: offer.businessName, photo: nil, size: 76)
                        }
                        Text(offer.businessName).font(.system(.title, design: .rounded, weight: .bold))
                        Label(scoreText(offer.providerScore), systemImage: "person.crop.circle")
                            .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                        if let about = offer.business?.about {
                            Text(about).plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                        }
                    }.padding(22)
                }
                .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: 28))
                .clipShape(RoundedRectangle(cornerRadius: 28))

                VStack(alignment: .leading, spacing: 18) {
                    Text(offer.serviceName).font(.system(.title2, design: .rounded, weight: .bold))
                    ResultHeadline(value: money(offer.priceCents, offer.currency), label: offer.truthLabel)
                    Text(offer.truthLabel.explanation).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                    FlowMetrics(items: [("Earliest", offer.availableAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()), "calendar"),
                                        ("Away", distance(offer.place.distanceM), "location")], compact: true)
                }.marketCard()

                if cached || offer.expiresAt <= Date() {
                    Label("This saved offer needs a fresh check. Go back and refresh.", systemImage: "clock.arrow.circlepath")
                        .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600).marketCard()
                }
                if let links = offer.business?.links, !links.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("See their work").font(.system(.title3, design: .rounded, weight: .bold))
                        BusinessLinks(links: links)
                    }.marketCard()
                }
                VStack(alignment: .leading, spacing: 16) {
                    Label("Where to find them", systemImage: "mappin.and.ellipse")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text(offer.place.address).plugText(.body)
                    Text("\(distance(offer.place.distanceM)) away").plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                }.marketCard()
                VStack(alignment: .leading, spacing: 14) {
                    Label("Offer ends \(offer.expiresAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                        .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                    DisclosureGroup("Offer information", isExpanded: $showingEvidence) {
                        VStack(alignment: .leading, spacing: 12) {
                            valueRow("Evidence recorded", offer.observedAt.formatted(date: .abbreviated, time: .shortened), last: true)
                            if offer.source == .seed {
                                Text("Demo data for private testing. This is not a real offer and nothing is booked.").plugText(.bodySmall)
                            }
                        }.padding(.top, 12)
                    }.plugText(.bodySmall)
                }.marketCard()
                Label(offer.source == .seed ? "Demo offer · Booking isn’t available yet." : "Booking opens when providers can confirm offers.", systemImage: "info.circle")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            }
            .foregroundStyle(PlugTokens.Color.ink900)
            .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            .padding(.horizontal, 16).padding(.vertical, 20)
        }
        .background(PlugTokens.Color.paper)
        .navigationTitle("Offer").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PlugTokens.Color.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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

/// A quiet monogram when a business has chosen not to share a photo.
struct BusinessPortrait: View {
    let name: String
    let photo: String?
    var size: CGFloat = 64
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
                    .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                    .foregroundStyle(PlugTokens.Color.ink600)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PlugTokens.Color.sunk)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct BusinessIdentity: View {
    let name: String
    let business: BusinessProfile?
    let score: ProviderScore
    var prominent = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        layout {
            BusinessPortrait(name: name, photo: business?.photoBase64, size: prominent ? 88 : 64)
            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                Text(name).font(.system(prominent ? .title2 : .headline, design: .rounded, weight: .bold)).foregroundStyle(PlugTokens.Color.ink900)
                Text(scoreText(score)).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OfferFact: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(PlugTokens.Color.paper, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct BusinessLinks: View {
    let links: [BusinessLink]
    var body: some View {
        ForEach(Array(links.enumerated()), id: \.offset) { _, link in
            if let url = link.destination {
                Link(destination: url) {
                    HStack(alignment: .center, spacing: PlugTokens.Space.s3) {
                        Image(systemName: link.label.lowercased().contains("instagram") ? "camera" : "globe")
                            .font(.system(size: 20, weight: .regular))
                            .frame(width: 44, height: 44)
                            .background(PlugTokens.Color.sunk, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                            Text(link.label).plugText(.action)
                            Text(url.host() ?? "").plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 17, weight: .medium)).accessibilityHidden(true)
                    }
                    .foregroundStyle(PlugTokens.Color.ink900)
                    .padding(.vertical, PlugTokens.Space.s2)
                    .frame(minHeight: PlugTokens.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .accessibilityHint("Opens the business's external website")
            }
        }
    }
}

/// Secondary actions read as actions, without another competing filled or outlined box.
struct RequestTextActionStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .plugText(.action)
            .foregroundStyle(destructive ? PlugTokens.Color.alert600 : PlugTokens.Color.ink900)
            .frame(minHeight: PlugTokens.minTouchTarget, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.6 : 1)
    }
}

/// Only imagery actually supplied by the business is shown on offers.
private struct BusinessImageBanner: View {
    let photo: String?
    let height: CGFloat
    var body: some View {
        if let photo, photo.count <= 65536, let data = Data(base64Encoded: photo), let image = UIImage(data: data) {
            GeometryReader { geometry in
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: height).clipped()
            }
            .frame(height: height).accessibilityHidden(true)
        }
    }
}

extension View {
    func marketCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

/// Visual status markers carry no invented people or progress.
struct FlowEmblem: View {
    let symbol: String
    var size: CGFloat = 64
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.38, weight: .light))
            .foregroundStyle(PlugTokens.Color.ink900)
            .frame(width: size, height: size)
            .background(PlugTokens.Color.sunk, in: RoundedRectangle(cornerRadius: size * 0.32))
            .accessibilityHidden(true)
    }
}

struct FlowMetrics: View {
    let items: [(String, String, String)]
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        // One row when every label fits whole; otherwise a column, so "Answered" never breaks.
        if typeSize.isAccessibilitySize {
            cells(AnyLayout(VStackLayout(alignment: .leading, spacing: 12)), whole: false)
        } else {
            ViewThatFits(in: .horizontal) {
                cells(AnyLayout(HStackLayout(alignment: .top, spacing: 10)), whole: true)
                cells(AnyLayout(VStackLayout(alignment: .leading, spacing: 12)), whole: false)
            }
        }
    }
    private func cells(_ layout: AnyLayout, whole: Bool) -> some View {
        layout {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 8) {
                    Label(item.0, systemImage: item.2).plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
                        .fixedSize(horizontal: whole, vertical: false)
                    Text(item.1).font(.system(compact ? .subheadline : .title2, design: .rounded, weight: .semibold))
                        .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(PlugTokens.Color.paper, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct FlowActionStyle: ButtonStyle {
    var primary = false
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.plugText(.action)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(16)
            // Disabled reads as text on a quiet fill, not a faded primary: white on mid-grey failed contrast.
            .foregroundStyle(!enabled ? PlugTokens.Color.ink600 : destructive ? PlugTokens.Color.alert600
                             : primary ? PlugTokens.Color.card : PlugTokens.Color.ink900)
            .background(!enabled ? PlugTokens.Color.sunk : primary ? PlugTokens.Color.ink900 : PlugTokens.Color.card,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(primary && enabled ? Color.clear : PlugTokens.Color.rule300))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
