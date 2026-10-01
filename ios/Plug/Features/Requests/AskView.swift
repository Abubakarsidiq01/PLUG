import SwiftUI

struct AskView: View {
    @StateObject private var model: RequestModel
    @StateObject private var location = RequestLocationModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showValidation = false

    init(service: RequestServing) { _model = StateObject(wrappedValue: RequestModel(service: service)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugSpacing.large) {
                    if let request = model.request { requestContent(request) }
                    else { composer }
                }
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(PlugSpacing.large)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PlugTokens.Color.surface0)
            .navigationTitle(model.request == nil ? "Ask PLUG" : "Your request")
            .toolbar {
                if model.request != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Refresh") { Task { await model.refresh() } }.disabled(model.isWorking)
                    }
                }
            }
            .task {
                model.setActive(true)
                if model.request != nil { await model.refresh() }
            }
            .onDisappear { model.setActive(false) }
            .onChange(of: scenePhase) { _, phase in
                model.setActive(phase == .active)
                if phase == .active, model.request != nil { Task { await model.refresh() } }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: PlugSpacing.large) {
            Text("What do you need?").plugText(.title)
            Text("Find a barber or beauty service near you. Tell us your budget and when you need it.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: PlugSpacing.small) {
                Text("Your request").plugText(.label)
                TextField("Barber under $35 in 30 minutes", text: $model.text, axis: .vertical)
                    .lineLimit(3...6).padding(PlugSpacing.medium)
                    .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.md).stroke(PlugTokens.Color.line300))
                    .accessibilityIdentifier("request-text").accessibilityLabel("Your request")
                    .disabled(model.isWorking)
                Text("\(model.text.unicodeScalars.count) / 500 characters").font(.caption).foregroundStyle(.secondary)
                if showValidation, let error = model.textError { errorText(error) }
            }
            VStack(alignment: .leading, spacing: PlugSpacing.medium) {
                Text("Where should we look?").font(.headline)
                Text("We use an approximate location only when you ask. You can also type an address.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Use my approximate location") { location.useDeviceLocation() }
                    .buttonStyle(AuthActionStyle()).disabled(location.isWorking || model.isWorking)
                PlugTextField(title: "Street address and city", text: $location.address)
                    .textContentType(.fullStreetAddress).disabled(model.isWorking)
                    .accessibilityIdentifier("request-address")
                Button(location.isWorking ? "Checking location…" : "Use this address") {
                    Task { await location.resolveAddress() }
                }
                .buttonStyle(AuthActionStyle()).disabled(location.isWorking || model.isWorking || location.address.isEmpty)
                if let error = location.errorMessage { errorText(error) }
                if let label = location.label, location.location != nil {
                    Label(label, systemImage: "mappin.circle.fill").foregroundStyle(PlugColor.brand)
                        .accessibilityIdentifier("request-location-ready")
                }
                if showValidation, location.location == nil, !location.isWorking {
                    errorText("Choose your current location or check an address before searching.")
                }
            }
            failure
            Button(model.isWorking ? "Sending your request…" : "Find options") {
                showValidation = true
                guard let coordinate = location.location else { return }
                Task { await model.submit(location: coordinate) }
            }
            .buttonStyle(AuthActionStyle(primary: true)).disabled(model.isWorking || location.isWorking)
            Text("Private preview: results use seeded supplier data. No suppliers are contacted and no booking is made.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func requestContent(_ request: ServiceRequest) -> some View {
        Text(request.text).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        if model.isCached {
            VStack(alignment: .leading, spacing: PlugSpacing.small) {
                Label("Cached result — refresh to check availability", systemImage: "clock.arrow.circlepath")
                if let refreshedAt = model.refreshedAt {
                    Text("Last updated \(refreshedAt.formatted(date: .abbreviated, time: .standard))").font(.caption)
                }
            }
            .foregroundStyle(.secondary).accessibilityIdentifier("request-cached")
        }
        constraints(request.constraints)
        failure
        switch request.nextAction {
        case .answerClarification:
            if let question = request.clarification {
                Text(question.question).font(.headline)
                ForEach(question.options, id: \.value) { option in
                    Button(option.label) { Task { await model.answer(option.value) } }
                        .buttonStyle(AuthActionStyle()).disabled(model.isWorking)
                }
            }
        case .waitForOffers:
            progress(request.progress)
            offerCards
        case .chooseOffer, .showResult:
            Text("Your options").font(.title2.bold())
            if model.isWorking { Text("Loading current offers…").foregroundStyle(.secondary) }
            else if model.offers.isEmpty {
                Text("No current offers are available. Refresh to check whether this request has expired.")
            }
            offerCards
        case .awaitSupplierConfirmation:
            Text("Waiting for supplier confirmation").font(.headline)
            Text("This is not a confirmed booking. Refresh to check the latest update.")
            offerCards
        case .showNoResult:
            Label("No matches this time", systemImage: "magnifyingglass").font(.title2.bold())
            Text(request.noResultReason?.explanation ?? "No current offers are available.")
        case .none:
            Label("Request canceled", systemImage: "checkmark.circle").font(.title2.bold())
            Text("The server confirmed cancellation. You can start a new request.")
        }
        if request.status.canCancel {
            Button("Cancel request", role: .destructive) { Task { await model.cancel() } }
                .buttonStyle(AuthActionStyle()).accessibilityIdentifier("request-cancel")
        } else {
            Button("Start a new request") { model.startAgain(); showValidation = false }
                .buttonStyle(AuthActionStyle(primary: true)).disabled(model.isWorking)
        }
        Text("Reference: \(request.requestId)").font(.caption).textSelection(.enabled).foregroundStyle(.secondary)
        Text("Seeded preview. No supplier outreach or booking takes place in this phase.")
            .font(.footnote).foregroundStyle(.secondary)
    }

    private func constraints(_ constraints: ServiceRequest.Constraints) -> some View {
        VStack(alignment: .leading, spacing: PlugSpacing.small) {
            valueRow("Budget", constraints.budgetCents.map { (Decimal($0) / 100).formatted(.currency(code: constraints.currency)) } ?? "Any price")
            valueRow("When", constraints.neededBy?.formatted(date: .abbreviated, time: .shortened) ?? "As soon as possible")
            valueRow("Search radius", "\(constraints.maxDistanceM) metres")
        }.font(.subheadline)
    }
    private func progress(_ progress: ServiceRequest.Progress) -> some View {
        VStack(alignment: .leading, spacing: PlugSpacing.medium) {
            Text("Checking participating suppliers").font(.headline)
            Text("\(progress.contacted) seeded suppliers checked; \(progress.replied) responded.")
            ProgressView(value: Double(progress.replied), total: Double(max(progress.contacted, 1)))
                .accessibilityLabel("Supplier responses")
                .accessibilityValue("\(progress.replied) of \(progress.contacted) responded")
            Text("\(progress.offersReady) offers ready").font(.subheadline.weight(.semibold))
        }.accessibilityIdentifier("request-progress")
    }
    private var offerCards: some View {
        ForEach(model.offers) { offer in
            NavigationLink {
                OfferDetailView(offer: offer, cached: model.isCached)
            } label: {
                VStack(alignment: .leading, spacing: PlugSpacing.medium) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top) { Text(offer.place.name).font(.headline); Spacer(); truthBadge(offer) }
                        VStack(alignment: .leading) { Text(offer.place.name).font(.headline); truthBadge(offer) }
                    }
                    Text(offer.serviceName).foregroundStyle(.secondary)
                    valueRow("Price", offer.price)
                    valueRow("Available", offer.availableAt.formatted(date: .abbreviated, time: .shortened))
                    valueRow("Distance", "\(offer.place.distanceM) metres")
                    Text("View details").foregroundStyle(PlugColor.brand).font(.subheadline.weight(.semibold))
                }
                .padding(PlugSpacing.medium)
                .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.md).stroke(PlugTokens.Color.line300))
            }
            .buttonStyle(.plain)
        }
    }
    @ViewBuilder private var failure: some View {
        if let message = model.errorMessage {
            VStack(alignment: .leading, spacing: PlugSpacing.small) {
                errorText(message)
                if let correlation = model.correlationId {
                    Text("Support reference: \(correlation)").font(.caption).textSelection(.enabled)
                }
                if model.request != nil {
                    Button("Retry update") { Task { await model.refresh() } }.frame(minHeight: 44)
                        .disabled(model.isWorking)
                }
            }.accessibilityIdentifier("request-error")
        }
    }
    private func errorText(_ value: String) -> some View {
        Label(value, systemImage: "exclamationmark.circle").font(.footnote)
            .foregroundStyle(PlugTokens.Color.ink900).fixedSize(horizontal: false, vertical: true)
    }
}

private func truthBadge(_ offer: ServiceOffer) -> some View {
    Text(offer.truthLabel.title).font(.caption.weight(.semibold))
        .padding(PlugSpacing.small)
        .foregroundStyle(offer.truthLabel.foreground)
        .background(offer.truthLabel.surface, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.sm).stroke(offer.truthLabel.foreground.opacity(0.35)))
        .accessibilityLabel(offer.truthLabel.explanation)
}

private func valueRow(_ label: String, _ value: String) -> some View {
    ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }
        VStack(alignment: .leading, spacing: 4) { Text(label).foregroundStyle(.secondary); Text(value) }
    }.accessibilityElement(children: .combine).fixedSize(horizontal: false, vertical: true)
}

private struct OfferDetailView: View {
    let offer: ServiceOffer
    let cached: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlugSpacing.large) {
                Text(offer.place.name).font(.title.bold())
                truthBadge(offer)
                Text(offer.truthLabel.explanation)
                if cached || offer.expiresAt <= Date() {
                    Label("This saved offer needs a fresh server check. Return to your request and refresh.", systemImage: "clock.arrow.circlepath")
                }
                if offer.source == .seed {
                    Text("Seeded demonstration data. This is not a real supplier offer or a confirmed booking.")
                        .font(.headline)
                }
                Text(offer.place.address).textSelection(.enabled)
                valueRow("Service", offer.serviceName)
                valueRow("Price", offer.price)
                valueRow("Available", offer.availableAt.formatted(date: .abbreviated, time: .shortened))
                valueRow("Distance", "\(offer.place.distanceM) metres")
                valueRow("Evidence recorded", offer.observedAt.formatted(date: .abbreviated, time: .shortened))
                valueRow("Offer expires", offer.expiresAt.formatted(date: .abbreviated, time: .shortened))
                Text("Booking and live supplier confirmation will be available in a later phase.").foregroundStyle(.secondary)
            }.frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity).padding(PlugSpacing.large)
        }.navigationTitle("Offer details").navigationBarTitleDisplayMode(.inline)
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
