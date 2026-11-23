import CoreLocation
import MapKit
import SwiftUI

/// The exact words a "Know before you go" ask sends. The phone only phrases the question; people
/// near the place answer it, and the server says Unknown when nobody can.
enum KnowBefore {
    enum Topic: String, CaseIterable, Identifiable {
        case busy, line, open, parking, other
        var id: Self { self }
        var title: String {
            switch self {
            case .busy: return "How busy is it right now?"
            case .line: return "How long is the line?"
            case .open: return "Is it open right now?"
            case .parking: return "Is parking easy?"
            case .other: return "Something else"
            }
        }
    }

    /// The place name and the free text together stay under the 500-character ask limit.
    static let maxPlace = 120
    static let maxOther = 360

    static func question(_ topic: Topic, place: String, other: String = "") -> String? {
        let place = String(place.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxPlace))
        guard !place.isEmpty else { return nil }
        switch topic {
        case .busy: return "How busy is \(place) right now?"
        case .line: return "How long is the line at \(place) right now?"
        case .open: return "Is \(place) open right now?"
        case .parking: return "Is parking easy at \(place) right now?"
        case .other:
            let words = String(other.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxOther))
            return words.isEmpty ? nil : "At \(place): \(words)"
        }
    }

    /// "H-E-B on South Congress Avenue": the street tells people which branch is meant.
    static func placeName(_ name: String, street: String?) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let street = street?.trimmingCharacters(in: .whitespacesAndNewlines), !street.isEmpty,
              !name.localizedCaseInsensitiveContains(street) else { return String(name.prefix(maxPlace)) }
        return String("\(name) on \(street)".prefix(maxPlace))
    }
}

/// A place from Apple Maps. The distance is worked out on the phone and is never sent.
struct NearbyPlace: Hashable {
    let name: String
    let label: String
    let category: String?
    let street: String?
    let metres: Double?
}

/// Places around the approximate location the Ask screen already holds, or a name search
/// anywhere when there is none. Results stay on the phone; only the question the person
/// chooses to send leaves it.
@MainActor
final class PlaceSearch: ObservableObject {
    @Published private(set) var places: [NearbyPlace] = []
    @Published private(set) var isSearching = false
    @Published private(set) var failed = false
    private var generation = 0

    /// (category, one place, the filter's name), in the order the filters show.
    static let categories: [(MKPointOfInterestCategory, String, String)] = [
        (.cafe, "Cafe", "Cafes"), (.restaurant, "Restaurant", "Restaurants"), (.foodMarket, "Grocery", "Grocery"),
        (.pharmacy, "Pharmacy", "Pharmacies"), (.gasStation, "Gas station", "Gas"), (.fitnessCenter, "Gym", "Gyms"),
        (.bank, "Bank", "Banks"), (.postOffice, "Post office", "Post offices")
    ]
    static func name(_ category: MKPointOfInterestCategory?) -> String? {
        categories.first { $0.0 == category }?.1
    }

    func load(_ query: String, near: RequestLocation?, only: MKPointOfInterestCategory? = nil) async {
        generation += 1
        let current = generation
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let centre = near.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let search: MKLocalSearch
        if !text.isEmpty {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.resultTypes = .pointOfInterest
            if let centre {
                request.region = MKCoordinateRegion(center: centre.coordinate, latitudinalMeters: 10_000, longitudinalMeters: 10_000)
            }
            search = MKLocalSearch(request: request)
        } else if let centre {
            let request = MKLocalPointsOfInterestRequest(center: centre.coordinate, radius: 2_000)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: only.map { [$0] } ?? Self.categories.map(\.0))
            search = MKLocalSearch(request: request)
        } else {
            places = []
            failed = false
            return
        }
        isSearching = true
        do {
            let items = try await search.start().mapItems
            guard current == generation else { return }
            places = items.compactMap { item in
                guard let name = item.name, !name.isEmpty else { return nil }
                let street = item.placemark.thoroughfare
                return NearbyPlace(name: name, label: KnowBefore.placeName(name, street: street),
                                   category: Self.name(item.pointOfInterestCategory),
                                   street: street,
                                   metres: centre.flatMap { centre in item.placemark.location.map { $0.distance(from: centre) } })
            }
            .sorted { ($0.metres ?? .greatestFiniteMagnitude) < ($1.metres ?? .greatestFiniteMagnitude) }
            .prefix(20).map { $0 }
            failed = false
        } catch {
            guard current == generation else { return }
            places = []
            failed = (error as? MKError)?.code != .placemarkNotFound
        }
        isSearching = false
    }
}

/// "Know before you go": choose a place, choose what to check, see the exact question, and send
/// it through the same ask as the home field. Nothing is placed in the home field.
struct KnowBeforeSheet: View {
    @ObservedObject var location: RequestLocationModel
    let onSend: (String) -> Void
    @StateObject private var search = PlaceSearch()
    @State private var query = ""
    @State private var place: String?
    @State private var kind: MKPointOfInterestCategory?
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 14
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                        Text("Where are you going?").plugText(.display)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(KnowBeforeCopy.howItWorks).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    searchField
                    if !trimmedQuery.isEmpty { typedPlace }
                    nearby
                }
                .foregroundStyle(PlugTokens.Color.ink900)
                .padding(.horizontal, PlugTokens.Space.s6)
                .padding(.top, PlugTokens.Space.s2)
                .padding(.bottom, PlugTokens.Space.s8)
                .frame(maxWidth: PlugTokens.Layout.measure, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PlugTokens.Color.paper)
            .knowBeforeChrome("Know before you go") { dismiss() }
            .navigationDestination(item: $place) { chosen in
                KnowBeforeQuestion(place: chosen) { question in onSend(question); dismiss() }
            }
            .task(id: searchKey) {
                // A short pause so each typed letter is not its own Apple Maps search.
                if !trimmedQuery.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
                guard !Task.isCancelled else { return }
                await search.load(query, near: location.location, only: kind)
            }
        }
        .tint(PlugTokens.Color.ink900)
        .knowBeforePresentation()
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searchKey: String {
        "\(trimmedQuery)|\(kind?.rawValue ?? "all")|\(location.location.map { "\($0.latitude),\($0.longitude)" } ?? "-")"
    }

    private var searchField: some View {
        let shape = RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous)
        return HStack(spacing: PlugTokens.Space.s3) {
            Image(systemName: "magnifyingglass").foregroundStyle(PlugTokens.Color.ink600).accessibilityHidden(true)
            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text("Search a place, or type its name").plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                TextField("", text: $query)
                    .plugText(.body)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .tint(PlugTokens.Color.brandGreen)
                    .accessibilityLabel("Search a place, or type its name")
                    .accessibilityIdentifier("kbg-search")
                    .onChange(of: query) { _, value in
                        if value.count > KnowBefore.maxPlace { query = String(value.prefix(KnowBefore.maxPlace)) }
                    }
            }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark").font(.system(size: min(glyph, PlugTokens.Layout.iconMax), weight: .medium))
                        .foregroundStyle(PlugTokens.Color.ink600)
                        .frame(width: PlugTokens.minTouchTarget, height: PlugTokens.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, PlugTokens.Space.s4)
        .frame(minHeight: PlugShape.buttonHeight)
        .background(PlugTokens.Color.sunk, in: shape)
    }

    /// The plain fallback: the name exactly as typed, for when Apple Maps has no match.
    private var typedPlace: some View {
        Button { place = trimmedQuery } label: {
            HStack(spacing: PlugTokens.Space.s3) {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                    Text("Ask about \u{201C}\(trimmedQuery)\u{201D}").plugText(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Use the name as you typed it").plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                chevron
            }
            .multilineTextAlignment(.leading)
            .padding(PlugTokens.Space.s4)
            .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous)
                .strokeBorder(PlugTokens.Color.rule300, lineWidth: PlugShape.rule))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlugPressStyle())
        .foregroundStyle(PlugTokens.Color.ink900)
        .accessibilityIdentifier("kbg-typed-place")
    }

    @ViewBuilder private var nearby: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Overline(trimmedQuery.isEmpty ? "Near you" : "From Apple Maps")
                Spacer()
                if search.isSearching { ProgressView().controlSize(.small).tint(PlugTokens.Color.ink600) }
            }
            if location.location == nil && trimmedQuery.isEmpty {
                locationPrompt
            } else {
                if trimmedQuery.isEmpty { filters }
                if search.failed {
                    caption("Apple Maps could not load places. Type the place name above instead.")
                } else if search.places.isEmpty && !search.isSearching {
                    caption(trimmedQuery.isEmpty ? "No places of this kind found nearby. Type the place name above."
                            : "No match on Apple Maps. Use the name as you typed it.")
                }
            }
            if !search.places.isEmpty {
                VStack(spacing: 0) {
                    PlugDivider()
                    ForEach(Array(search.places.enumerated()), id: \.offset) { index, item in
                        placeRow(item).accessibilityIdentifier("kbg-place-\(index)")
                        PlugDivider()
                    }
                }
            }
        }
        .animation(.plugSheet(reduceMotion: reduceMotion), value: search.places.count)
    }

    /// One kind of place at a time, so a pharmacy or a gas station is not buried under cafes.
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PlugTokens.Space.s2) {
                PlugChip(title: "All", selected: kind == nil) { kind = nil }
                    .accessibilityIdentifier("kbg-kind-all")
                ForEach(PlaceSearch.categories, id: \.0) { category in
                    PlugChip(title: category.2, selected: kind == category.0) { kind = category.0 }
                        .accessibilityIdentifier("kbg-kind-\(category.0.rawValue)")
                }
            }
            .padding(.vertical, PlugTokens.Space.s1)
        }
        // Edge to edge, so chips scroll under the sheet's sides, not under the page margin.
        .contentMargins(.horizontal, PlugTokens.Space.s6, for: .scrollContent)
        .padding(.horizontal, -PlugTokens.Space.s6)
    }

    /// Nearby places need the approximate location the ask itself uses; it is asked for only on
    /// a tap, the same permission, and the search field works without it.
    @ViewBuilder private var locationPrompt: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            if let error = location.errorMessage {
                caption(error.contains("off") ? "Location is off. Search by name above, or type the place name."
                        : "Your location is unavailable. Search by name above, or type the place name.")
            } else {
                caption("Search by name above, or list places near your approximate location. PLUG sends nothing until you ask.")
                Button(location.isWorking ? "Finding places near you\u{2026}" : "Show places near me") {
                    location.useDeviceLocation()
                }
                .buttonStyle(PlugButtonStyle(kind: .secondary, fullWidth: false))
                .disabled(location.isWorking)
                .accessibilityIdentifier("kbg-use-location")
            }
        }
        .padding(.top, PlugTokens.Space.s1)
    }

    private func placeRow(_ item: NearbyPlace) -> some View {
        Button { place = item.label } label: {
            HStack(alignment: .center, spacing: PlugTokens.Space.s3) {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                    Text(item.name).plugText(.title2).fixedSize(horizontal: false, vertical: true)
                    let facts = [item.category, item.metres.map { distance(Int($0)) }, item.street].compactMap { $0 }
                    if !facts.isEmpty {
                        Text(facts.joined(separator: " \u{00B7} ")).plugText(.bodySmall)
                            .foregroundStyle(PlugTokens.Color.ink600).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                chevron
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, PlugTokens.Space.s4)
            .frame(minHeight: PlugTokens.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlugPressStyle())
        .foregroundStyle(PlugTokens.Color.ink900)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: min(glyph, PlugTokens.Layout.iconMax), weight: .medium))
            .foregroundStyle(PlugTokens.Color.brandGreen).accessibilityHidden(true)
    }
}

/// Step 2: what to check, the exact question, and the one green action.
private struct KnowBeforeQuestion: View {
    let place: String
    let onSend: (String) -> Void
    @State private var topic: KnowBefore.Topic?
    @State private var other = ""
    @FocusState private var otherFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var back

    private var question: String? { topic.flatMap { KnowBefore.question($0, place: place, other: other) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                    Overline(place)
                    Text("What do you want to know?").plugText(.display)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(spacing: PlugTokens.Space.s3) {
                    ForEach(KnowBefore.Topic.allCases) { choice in
                        ChoiceRow(title: choice.title, selected: topic == choice) {
                            withAnimation(.plugSheet(reduceMotion: reduceMotion)) { topic = choice }
                            otherFocused = choice == .other
                        }
                        .accessibilityIdentifier("kbg-topic-\(choice.rawValue)")
                    }
                }
                if topic == .other {
                    AskTextBox(text: $other, limit: KnowBefore.maxOther, placeholder: "What do you want to check there?",
                               focus: $otherFocused, label: "Your question", id: "kbg-other-text")
                        .transition(.opacity)
                }
                QuestionPreview(question: question, empty: "Choose one above to see your question.")
                    .accessibilityIdentifier("kbg-preview")
                VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                    Button { if let question { onSend(question) } } label: { Text("Ask people nearby") }
                        .buttonStyle(PlugButtonStyle(kind: .primary))
                        .disabled(question == nil)
                        .accessibilityIdentifier("kbg-send")
                    caption(KnowBeforeCopy.howItWorks)
                    caption(KnowBeforeCopy.location)
                }
            }
            .foregroundStyle(PlugTokens.Color.ink900)
            .padding(.horizontal, PlugTokens.Space.s6)
            .padding(.top, PlugTokens.Space.s2)
            .padding(.bottom, PlugTokens.Space.s8)
            .frame(maxWidth: PlugTokens.Layout.measure, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PlugTokens.Color.paper)
        .navigationTitle("Your question")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PlugTokens.Color.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // A plain text Back, not the system's round glass one; the sheet still swipes down.
        .navigationBarBackButtonHidden(true)
        .modifier(SheetBarButton(title: "Back", back: true, id: "kbg-back") { back() })
        .sensoryFeedback(.selection, trigger: topic)
    }
}

/// A category's ready-made asks: tap one to see it in the box, change any words, then send.
struct ExampleAskSheet: View {
    let title: String
    let asks: [String]
    let onSend: (String) -> Void
    @State private var text: String
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: String, asks: [String], onSend: @escaping (String) -> Void) {
        self.title = title
        self.asks = asks
        self.onSend = onSend
        _text = State(initialValue: asks.first ?? "")
    }

    private var ready: String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                        Text("Start from an example").plugText(.display)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Tap one, change any words, then ask people nearby.").plugText(.bodySmall)
                            .foregroundStyle(PlugTokens.Color.ink600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: PlugTokens.Space.s3) {
                        ForEach(Array(asks.enumerated()), id: \.offset) { index, ask in
                            ChoiceRow(title: ask, selected: text == ask) { text = ask }
                                .accessibilityIdentifier("example-ask-\(index)")
                        }
                    }
                    AskTextBox(text: $text, limit: 500, placeholder: "Tell us what you need\u{2026}",
                               focus: $focused, label: "Your ask", id: "example-ask-text")
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                        Button { if let ready { onSend(ready); dismiss() } } label: { Text("Ask people nearby") }
                            .buttonStyle(PlugButtonStyle(kind: .primary))
                            .disabled(ready == nil)
                            .accessibilityIdentifier("example-ask-send")
                        caption(KnowBeforeCopy.location)
                    }
                }
                .foregroundStyle(PlugTokens.Color.ink900)
                .padding(.horizontal, PlugTokens.Space.s6)
                .padding(.top, PlugTokens.Space.s2)
                .padding(.bottom, PlugTokens.Space.s8)
                .frame(maxWidth: PlugTokens.Layout.measure, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PlugTokens.Color.paper)
            .knowBeforeChrome(title) { dismiss() }
        }
        .tint(PlugTokens.Color.ink900)
        .knowBeforePresentation()
        .sensoryFeedback(.selection, trigger: text) { old, new in asks.contains(new) && old != new }
    }
}

private enum KnowBeforeCopy {
    static let howItWorks = "People near the place answer. If nobody can, PLUG says Unknown."
    static let location = "PLUG sends your approximate location only when you ask."
}

/// A large choice: the words on the left, an open or filled green circle on the right.
private struct ChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous)
        Button(action: action) {
            HStack(alignment: .center, spacing: PlugTokens.Space.s3) {
                Text(title).plugText(.body).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: min(glyph, PlugTokens.Layout.iconMax), weight: .regular))
                    .foregroundStyle(selected ? PlugTokens.Color.brandGreen : PlugTokens.Color.ruleControl)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PlugTokens.Space.s4)
            .padding(.vertical, PlugTokens.Space.s4)
            .frame(maxWidth: .infinity, minHeight: PlugShape.choiceHeight, alignment: .leading)
            .background(selected ? PlugTokens.Color.card : .clear, in: shape)
            .overlay(shape.strokeBorder(selected ? PlugTokens.Color.brandGreen : PlugTokens.Color.rule300,
                                        lineWidth: selected ? PlugShape.focusRule : PlugShape.rule))
            .contentShape(shape)
        }
        .buttonStyle(PlugPressStyle())
        .foregroundStyle(PlugTokens.Color.ink900)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The exact words that will be sent, in the serif, on sand.
private struct QuestionPreview: View {
    let question: String?
    let empty: String
    var body: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            Text("You will ask").plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
            if let question {
                Text(question).plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            } else {
                Text(empty).plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(PlugTokens.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PlugTokens.Color.sunk, in: RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A sand box like the home field, with a label above and a character count once it is long.
private struct AskTextBox: View {
    @Binding var text: String
    let limit: Int
    let placeholder: String
    var focus: FocusState<Bool>.Binding
    let label: String
    let id: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous)
        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            Text(label).plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                TextField("", text: $text, axis: .vertical)
                    .plugText(.body)
                    .lineLimit(2...6)
                    .focused(focus)
                    .tint(PlugTokens.Color.brandGreen)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier(id)
                    .onChange(of: text) { _, value in
                        if value.count > limit { text = String(value.prefix(limit)) }
                    }
            }
            .padding(PlugTokens.Space.s4)
            .background(PlugTokens.Color.sunk, in: shape)
            .overlay(shape.strokeBorder(focus.wrappedValue ? PlugTokens.Color.brandGreen : .clear, lineWidth: PlugShape.focusRule))
            if text.count > limit - 60 {
                caption("\(text.count) of \(limit) characters")
            }
        }
    }
}

private extension View {
    func knowBeforeChrome(_ title: String, close: @escaping () -> Void) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PlugTokens.Color.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .modifier(SheetBarButton(title: "Close", id: "sheet-close", action: close))
    }

    func knowBeforePresentation() -> some View {
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(PlugTokens.Color.paper)
            .presentationCornerRadius(PlugShape.sheet)
    }
}

/// A bar action as plain espresso text, never the round glass button iOS 26 puts behind toolbar
/// items. CI builds with Xcode 16 (iOS 18 SDK), which has no sharedBackgroundVisibility.
private struct SheetBarButton: ViewModifier {
    let title: String
    var back = false
    let id: String
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 16

    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            content.toolbar { ToolbarItem(placement: .topBarLeading) { button }.sharedBackgroundVisibility(.hidden) }
        } else {
            content.toolbar { ToolbarItem(placement: .topBarLeading) { button } }
        }
        #else
        content.toolbar { ToolbarItem(placement: .topBarLeading) { button } }
        #endif
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: PlugTokens.Space.s1) {
                if back {
                    Image(systemName: "chevron.left")
                        .font(.system(size: min(glyph, PlugTokens.Layout.iconMax), weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(title).plugText(.action).lineLimit(1)
            }
            // The bar proposes a narrow width; the label keeps its own so it never wraps.
            .fixedSize()
            .foregroundStyle(PlugTokens.Color.ink900)
            .frame(minHeight: PlugTokens.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}
