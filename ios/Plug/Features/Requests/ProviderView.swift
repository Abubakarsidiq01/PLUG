import SwiftUI

/// Manual v4 Figure A2: becoming a provider is adding a capability to this same account. The
/// person describes what they do in plain words, the server maps it onto the controlled
/// vocabulary, and the chips it returns are the only skills that can be saved. Terms that
/// matched nothing are shown, never matched on (§19A.2).
struct ProviderOnboardingView: View {
    let service: RequestServing
    @ObservedObject var location: RequestLocationModel
    var current: ProviderProfile? = nil
    let onSaved: (ProviderProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var proposed: [SkillTag] = []
    @State private var chosen: Set<String> = []
    @State private var unmatched: [String] = []
    @State private var radius = Radius.miles3
    @State private var days = AvailabilityWindow.Days.everyDay
    @State private var slots: Set<Slot> = [.afternoons]
    @State private var licence = ""
    @State private var accepting = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var describing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                        Text(current == nil ? "Offer a service" : "What you offer").plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
                        Text("Same account. You keep asking as normal and also receive requests that match what you do.")
                            .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                    }
                    describeStep
                    if !proposed.isEmpty || !unmatched.isEmpty { skillsStep }
                    if !chosen.isEmpty {
                        radiusStep
                        availabilityStep
                        if needsLicence { licenceStep }
                        baseStep
                        if current != nil {
                            Toggle("Receive matching requests", isOn: $accepting)
                                .plugText(.body).tint(PlugTokens.Color.ink900)
                                .frame(minHeight: PlugTokens.minTouchTarget)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).plugText(.body).foregroundStyle(PlugTokens.Color.alert600)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(PlugTokens.Space.s4)
                            .background(PlugTokens.Color.alert50, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.control))
                            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.control).strokeBorder(PlugTokens.Color.alertBorder))
                    }
                    if !chosen.isEmpty {
                        Button(isWorking ? "Saving…" : saveTitle) { Task { await save() } }
                            .buttonStyle(AuthActionStyle(primary: true))
                            .disabled(isWorking || location.location == nil || slots.isEmpty || (needsLicence && !licenceValid))
                            .accessibilityIdentifier("provider-save")
                        caption("Private test. Requests you receive here come from other testers, and nothing is booked.")
                    }
                }
                .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, PlugTokens.Space.s4).padding(.vertical, PlugTokens.Space.s6)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PlugTokens.Color.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { describing = false } }
            }
        }
        .tint(PlugTokens.Color.ink900)
        .sensoryFeedback(.selection, trigger: chosen)
        .sensoryFeedback(.selection, trigger: radius)
        .sensoryFeedback(.selection, trigger: slots)
        .sensoryFeedback(.success, trigger: proposed.count) { old, new in new > old }
        .onAppear(perform: prefill)
    }

    // MARK: Steps

    private var describeStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("What do you do?").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            TextField("For example: I do knotless braids and wig installs", text: $description, axis: .vertical)
                .plugText(.body).lineLimit(2...5).focused($describing)
                .padding(PlugTokens.Space.s3)
                .frame(minHeight: PlugTokens.minTouchTarget)
                .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.control)
                    .strokeBorder(describing ? PlugTokens.Color.ink900 : PlugTokens.Color.rule300, lineWidth: describing ? 2 : 1))
                .accessibilityLabel("What do you do?")
                .accessibilityIdentifier("provider-description")
            Button(isWorking && proposed.isEmpty ? "Reading…" : "Find my skills") { Task { await propose() } }
                .buttonStyle(AuthActionStyle(primary: chosen.isEmpty))
                .disabled(isWorking || description.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
        }
        .plugCard()
    }

    private var skillsStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Your skills").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            if proposed.isEmpty {
                Text("None of that matched a skill PLUG can route yet. Try other words.")
                    .plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
            } else {
                Text("Tap to remove any that are wrong. You can only be matched on these.")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                PlugFlowLayout {
                    ForEach(proposed) { skill in
                        PlugChip(title: skill.requiresLicence ? "\(skill.display), licence" : skill.display,
                                 selected: chosen.contains(skill.tag)) {
                            if chosen.contains(skill.tag) { chosen.remove(skill.tag) } else { chosen.insert(skill.tag) }
                        }
                    }
                }
            }
            if !unmatched.isEmpty {
                Rectangle().fill(PlugTokens.Color.rule200).frame(height: 1)
                Text("Not matched yet: \(unmatched.joined(separator: ", "))")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink900)
                caption("PLUG keeps a list of these for review. Nobody is matched on them.")
            }
        }
        .plugCard()
    }

    private var radiusStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("How far will you go?").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            PlugFlowLayout {
                ForEach(Radius.allCases) { option in
                    PlugChip(title: option.title, selected: radius == option) { radius = option }
                }
            }
            caption("You only receive requests from people inside this distance.")
        }
        .plugCard()
    }

    private var availabilityStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("When are you usually free?").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            PlugFlowLayout {
                ForEach([AvailabilityWindow.Days.weekdays, .weekends, .everyDay], id: \.self) { option in
                    PlugChip(title: option.title, selected: days == option) { days = option }
                }
            }
            PlugFlowLayout {
                ForEach(Slot.allCases) { slot in
                    PlugChip(title: slot.title, selected: slots.contains(slot)) {
                        if slots.contains(slot) { slots.remove(slot) } else { slots.insert(slot) }
                    }
                }
            }
            if slots.isEmpty { Text("Choose at least one time.").plugText(.bodySmall).foregroundStyle(PlugTokens.Color.alert600) }
        }
        .plugCard()
    }

    private var licenceStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Licence").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            Text("\(licensedNames) needs a licence. Licensed requests are matched only to providers who give one.")
                .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            PlugTextField(title: "Licence number", text: $licence)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            if !licence.isEmpty, !licenceValid {
                Text("Use 3 to 64 letters, numbers, spaces, dots, slashes or dashes.")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.alert600)
            }
        }
        .plugCard()
    }

    private var baseStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Where do you work from?").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            if let label = location.label, location.location != nil {
                valueRow("Base", label, last: true)
                // Set already: the way to change it steps back so the save action leads.
                Button(location.isWorking ? "Finding location…" : "Update location") { location.useDeviceLocation() }
                    .plugText(.action).foregroundStyle(PlugTokens.Color.ink900).underline()
                    .frame(minHeight: PlugTokens.minTouchTarget)
                    .disabled(location.isWorking)
            } else {
                caption("Approximate only. People who ask never see your address.")
                Button(location.isWorking ? "Finding location…" : "Use my approximate location") { location.useDeviceLocation() }
                    .buttonStyle(AuthActionStyle()).disabled(location.isWorking)
            }
            if let error = location.errorMessage {
                Text(error).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.alert600)
                PlugTextField(title: "Street address and city", text: $location.address)
                    .textContentType(.fullStreetAddress)
                Button("Use this address") { Task { await location.resolveAddress() } }
                    .buttonStyle(AuthActionStyle()).disabled(location.isWorking || location.address.isEmpty)
            }
        }
        .plugCard()
    }

    // MARK: Behaviour

    private var needsLicence: Bool { proposed.contains { chosen.contains($0.tag) && $0.requiresLicence } }
    private var licensedNames: String {
        proposed.filter { chosen.contains($0.tag) && $0.requiresLicence }.map(\.display).joined(separator: " and ")
    }
    private var licenceValid: Bool {
        licence.trimmingCharacters(in: .whitespaces).range(of: "^[A-Za-z0-9 ./-]{3,64}$", options: .regularExpression) != nil
    }
    private var saveTitle: String {
        if current == nil { return "Start receiving requests" }
        return accepting ? "Save changes" : "Stop receiving requests"
    }

    private func prefill() {
        guard let current, proposed.isEmpty else { return }
        proposed = current.skills
        chosen = Set(current.skills.map(\.tag))
        radius = Radius.nearest(current.travelRadiusM)
        accepting = current.accepting
        if let first = current.availability.first { days = first.days }
        let saved = Set(Slot.allCases.filter { slot in current.availability.contains { $0.from == slot.from && $0.to == slot.to } })
        if !saved.isEmpty { slots = saved }
    }

    private func propose() async {
        describing = false
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await service.proposeSkills(description.trimmingCharacters(in: .whitespacesAndNewlines))
            var merged = proposed.filter { chosen.contains($0.tag) }
            for skill in result.skills where !merged.contains(skill) { merged.append(skill) }
            proposed = merged
            chosen.formUnion(result.skills.map(\.tag))
            unmatched = result.unmatched
        } catch {
            errorMessage = message(for: error, saving: false)
        }
    }

    private func save() async {
        guard let base = location.location else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let windows = Slot.allCases.filter(slots.contains).map { AvailabilityWindow(days: days, from: $0.from, to: $0.to) }
        var setup = ProviderSetup(skillTags: proposed.map(\.tag).filter(chosen.contains), travelRadiusM: radius.rawValue,
                                  baseLocation: base, availability: windows)
        if needsLicence { setup.licenceRef = licence.trimmingCharacters(in: .whitespaces) }
        setup.accepting = accepting
        do {
            onSaved(try await service.setProvider(setup))
            dismiss()
        } catch {
            errorMessage = message(for: error, saving: true)
        }
    }

    private func message(for error: Error, saving: Bool) -> String {
        if let api = error as? APIError {
            switch api.code {
            case "restricted_intent": return "PLUG cannot route that kind of work. Nothing was saved."
            case "validation_failed" where api.fieldCode == "licence_required": return "Add your licence number for licensed work."
            case "validation_failed": return api.message
            case "rate_limited": return "Too many tries. Wait a minute and try again. Nothing was saved."
            case "unauthenticated": return "Your session ended. Sign in again to continue."
            default: break
            }
        }
        return saving ? "Your skills were not saved. Check your connection and try again."
                      : "Your description could not be read. Nothing was saved; try again."
    }

    enum Radius: Int, CaseIterable, Identifiable {
        case mile1 = 1609, miles3 = 4828, miles10 = 16093, miles25 = 40234, any = 80000
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .mile1: return "1 mi"
            case .miles3: return "3 mi"
            case .miles10: return "10 mi"
            case .miles25: return "25 mi"
            case .any: return "Any (50 mi)"
            }
        }
        static func nearest(_ metres: Int) -> Radius {
            allCases.min { abs($0.rawValue - metres) < abs($1.rawValue - metres) } ?? .miles3
        }
    }

    enum Slot: String, CaseIterable, Identifiable {
        case mornings, afternoons, evenings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .mornings: return "Mornings, 8 to 12"
            case .afternoons: return "Afternoons, 12 to 5"
            case .evenings: return "Evenings, 5 to 9"
            }
        }
        var from: String { ["mornings": "08:00", "afternoons": "12:00", "evenings": "17:00"][rawValue]! }
        var to: String { ["mornings": "12:00", "afternoons": "17:00", "evenings": "21:00"][rawValue]! }
    }
}

extension AvailabilityWindow.Days {
    var title: String {
        switch self {
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        case .everyDay: return "Every day"
        }
    }
}

/// The provider's Inbox (manual v4 §2.3). It shows only when this account has a provider
/// profile. Until requests are delivered to providers in the app, it says so plainly
/// instead of showing invented requests.
struct InboxView: View {
    let service: RequestServing
    let profile: ProviderProfile
    let onChange: (ProviderProfile) -> Void
    @StateObject private var location = RequestLocationModel()
    @State private var editing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                        Text("Inbox").plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
                        Text(profile.accepting ? "Matching requests near you arrive here."
                                               : "You are not receiving requests right now.")
                            .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                    }
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                        HStack(alignment: .top) {
                            Text("No requests yet").plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
                            Spacer(minLength: PlugTokens.Space.s2)
                            TruthBadge(label: .unknown)
                        }
                        Text("Nobody nearby has asked for what you offer since you joined. When someone does, you will see their ask, the price they named and when they need it.")
                            .plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                    }
                    .plugCard()
                    .accessibilityIdentifier("inbox-empty")
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                        Text("What you offer").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
                        PlugFlowLayout {
                            ForEach(profile.skills) { skill in
                                Text(skill.display).plugText(.label).foregroundStyle(PlugTokens.Color.ink900)
                                    .padding(.horizontal, PlugTokens.Space.s3).padding(.vertical, PlugTokens.Space.s2)
                                    .background(PlugTokens.Color.sunk, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.badge))
                            }
                        }
                        VStack(spacing: 0) {
                            valueRow("Travel", distance(profile.travelRadiusM))
                            valueRow("Free", profile.availability.map(\.summary).joined(separator: "\n"))
                            valueRow("Licence", profile.licenceOnFile ? "On file" : "None given")
                            valueRow("Score", scoreText(profile.score), last: true)
                        }
                        Button(profile.accepting ? "Change skills or stop receiving" : "Start receiving again") { editing = true }
                            .buttonStyle(AuthActionStyle())
                            .accessibilityIdentifier("provider-edit")
                    }
                    .plugCard()
                }
                .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, PlugTokens.Space.s4).padding(.vertical, PlugTokens.Space.s6)
            }
            .background(PlugTokens.Color.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $editing) {
                ProviderOnboardingView(service: service, location: location, current: profile) { saved in
                    editing = false
                    onChange(saved)
                }
            }
        }
    }
}

extension AvailabilityWindow {
    /// "Every day, 12 PM to 5 PM" in the person's own clock style, from the server's HH:mm.
    var summary: String { "\(days.title), \(Self.clock(from)) to \(Self.clock(to))" }

    private static func clock(_ value: String) -> String {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return value }
        if parts[0] == 24 { return "midnight" }
        var components = DateComponents()
        components.hour = parts[0]
        components.minute = parts[1]
        guard let date = Calendar.current.date(from: components) else { return value }
        return parts[1] == 0 ? date.formatted(.dateTime.hour()) : date.formatted(.dateTime.hour().minute())
    }
}
