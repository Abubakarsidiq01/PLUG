import SwiftUI
import PhotosUI
import ImageIO

/// Manual v4 Figure A2: becoming a provider is adding a capability to this same account. The
/// person can enter skills directly or ask for suggestions. Listed skills retain their
/// matching and licence rules; new skills use the own-words matching path (ADR-011).
struct ProviderOnboardingView: View {
    let service: RequestServing
    @ObservedObject var location: RequestLocationModel
    var current: ProviderProfile? = nil
    let onSaved: (ProviderProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingBusiness = false
    @State private var businessName = ""
    @State private var about = ""
    @State private var photo: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoLoading = false
    @State private var photoError: String?
    @State private var links: [BusinessLinkDraft] = ["Website", "Instagram", "Facebook"].map { BusinessLinkDraft(label: $0) }
    @State private var description = ""
    @State private var proposed: [SkillTag] = []
    @State private var chosen: Set<String> = []
    @State private var unmatched: [String] = []
    /// Skills in the provider's own words that PLUG does not list (ADR-011), up to five.
    @State private var ownSkills: [String] = []
    @State private var radius = Radius.miles3
    @State private var days = AvailabilityWindow.Days.everyDay
    @State private var slots: Set<Slot> = [.afternoons]
    @State private var licence = ""
    @State private var licenceRequested = false
    @State private var accepting = true
    @State private var radiusChanged = false
    @State private var availabilityChanged = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var toast: String?
    @FocusState private var describing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    // The sheet's name is in the navigation bar, so it stays visible however far the
                    // sheet is scrolled; at the largest sizes a header title went under Cancel.
                    Text("Tell people nearby what you do.")
                        .plugText(.display).foregroundStyle(PlugTokens.Color.ink900)
                        .fixedSize(horizontal: false, vertical: true)
                    describeStep.marketCard()
                    if !proposed.isEmpty || !unmatched.isEmpty || !ownSkills.isEmpty { skillsStep }
                    if hasSkills {
                        DisclosureGroup(isExpanded: $showingBusiness) {
                            businessStep.padding(.top, PlugTokens.Space.s4)
                        } label: {
                            HStack(spacing: PlugTokens.Space.s3) {
                                BusinessPortrait(name: optional(businessName) ?? "Your business", photo: photo, size: PlugTokens.Layout.portraitMedium)
                                VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                                    Text("Business profile").plugText(.title3)
                                        .accessibilityIdentifier("provider-business-section")
                                    Text("Photo, about and links. Optional.").plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
                                }
                                .multilineTextAlignment(.leading)
                            }
                        }.marketCard()
                        radiusStep.marketCard()
                        availabilityStep.marketCard()
                        if needsLicence { licenceStep }
                        baseStep.marketCard()
                        if current != nil {
                            Toggle("Receive matching requests", isOn: $accepting)
                                .plugText(.title3).tint(PlugTokens.Color.brandGreen)
                                .frame(minHeight: PlugTokens.minTouchTarget)
                        }
                    }
                    if let errorMessage {
                        PlugNotice(message: errorMessage, tone: .alert)
                    }
                    if hasSkills {
                        Button(isWorking ? "Saving…" : saveTitle) { Task { await save() } }
                            .buttonStyle(FlowActionStyle(primary: true))
                            .disabled(isWorking || photoLoading || location.location == nil || slots.isEmpty || (needsLicence && !licenceValid))
                            .accessibilityIdentifier("provider-save")
                        caption("Private test. Your settings are saved for matching. Inbox delivery and booking are not available yet.")
                    }
                }
                .foregroundStyle(PlugTokens.Color.ink900)
                .disabled(isWorking)
                .frame(maxWidth: PlugTokens.Layout.measure, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, PlugTokens.Space.s4).padding(.vertical, PlugTokens.Space.s6)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PlugTokens.Color.paper)
            .animation(.plugSheet(reduceMotion: reduceMotion), value: hasSkills)
            .animation(.plugSheet(reduceMotion: reduceMotion), value: proposed.count + ownSkills.count + unmatched.count)
            // A paper bar, so scrolled text never runs under Cancel at large text sizes.
            .navigationTitle(current == nil ? "Offer a service" : "What you offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PlugTokens.Color.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.fontWeight(.semibold).disabled(isWorking) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { describing = false } }
            }
        }
        .interactiveDismissDisabled(isWorking)
        .tint(PlugTokens.Color.ink900)
        .plugToast($toast)
        .presentationBackground(PlugTokens.Color.paper)
        .presentationCornerRadius(PlugShape.sheet)
        .sensoryFeedback(.selection, trigger: chosen)
        .sensoryFeedback(.selection, trigger: ownSkills)
        .sensoryFeedback(.selection, trigger: radius)
        .sensoryFeedback(.selection, trigger: slots)
        .sensoryFeedback(.success, trigger: proposed.count) { old, new in new > old }
        .onAppear(perform: prefill)
        .task(id: selectedPhoto) { await loadPhoto() }
    }

    // MARK: Steps

    private func optional(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var businessStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                Text("Show people your work").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
                Text("Share only what you want customers to see.")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            }
            HStack(alignment: .center, spacing: PlugTokens.Space.s4) {
                BusinessPortrait(name: optional(businessName) ?? "Your business", photo: photo, size: PlugTokens.Layout.portraitLarge)
                VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Text(photoLoading ? "Preparing photo…" : photo == nil ? "Add business photo" : "Change photo")
                    }
                    .buttonStyle(PlugButtonStyle(kind: .secondary, fullWidth: false))
                    .disabled(photoLoading)
                    if photo != nil {
                        Button("Remove photo") { photo = nil; selectedPhoto = nil }
                            .buttonStyle(PlugButtonStyle(kind: .tertiary, fullWidth: false))
                    }
                }
                .foregroundStyle(PlugTokens.Color.ink900)
            }
            if let photoError { Text(photoError).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.alert600) }
            PlugTextField(title: "Business name (optional)", text: $businessName)
                .onChange(of: businessName) { _, value in businessName = String(value.prefix(80)) }
                .accessibilityIdentifier("provider-business-name")
            PlugTextField(title: "About your work (optional)", text: $about)
                .onChange(of: about) { _, value in about = String(value.prefix(300)) }
            Text("Where can people see your work?").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            ForEach($links) { $link in
                VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                    if !["Website", "Instagram", "Facebook"].contains(link.label) {
                        PlugTextField(title: "Link name", text: $link.label)
                    }
                    PlugTextField(title: "\(link.label.isEmpty ? "Link" : link.label) URL (optional)", text: $link.url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !link.url.isEmpty {
                        Button("Remove \(link.label.isEmpty ? "link" : link.label)") { link.url = "" }
                            .buttonStyle(PlugButtonStyle(kind: .tertiary, fullWidth: false))
                    }
                }
            }
            if links.count < 5 {
                Button("Add another link") { links.append(BusinessLinkDraft(label: "")) }
                    .buttonStyle(PlugButtonStyle(kind: .tertiary, fullWidth: false))
            }
            caption("Use a full https:// link. Clear any field to stop sharing it.")
        }
    }

    private func loadPhoto() async {
        guard let selectedPhoto else { return }
        photoLoading = true
        photoError = nil
        defer { photoLoading = false }
        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self),
                  data.count <= 50_000_000,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256
                  ] as CFDictionary),
                  let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.75), jpeg.count <= 49_152
            else { photoError = "That photo couldn't be prepared. Try a different image."; return }
            try Task.checkCancellation()
            photo = jpeg.base64EncodedString()
        } catch {
            if !Task.isCancelled { photoError = "The photo couldn't be opened. Try again." }
        }
    }

    private var describeStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("What do you do?").plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
            ZStack(alignment: .topLeading) {
                // Wraps at large sizes and meets the contrast floor, unlike the system placeholder.
                if description.isEmpty {
                    Text("For example: Wig install").plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                TextField("", text: $description, axis: .vertical)
                    .plugText(.body).lineLimit(2...5).focused($describing)
            }
                .padding(PlugTokens.Space.s3)
                .frame(minHeight: PlugTokens.minTouchTarget)
                .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous)
                    .strokeBorder(describing ? PlugTokens.Color.brandGreen : PlugTokens.Color.ruleControl,
                                  lineWidth: describing ? 1.5 : PlugShape.rule))
                .accessibilityLabel("What do you do?")
                .accessibilityIdentifier("provider-description")
            Button("Add skill") {
                let label = description.trimmingCharacters(in: .whitespacesAndNewlines)
                guard (3...40).contains(label.count), ownSkills.count < 5 else { return }
                if !ownSkills.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
                    ownSkills.append(label)
                    toast = "Added \(label)"
                }
                description = ""
                describing = false
                errorMessage = nil
            }
            .buttonStyle(PlugButtonStyle(kind: .secondary))
            .disabled(isWorking || !(3...40).contains(description.trimmingCharacters(in: .whitespacesAndNewlines).count) || ownSkills.count >= 5)
            .accessibilityIdentifier("provider-add-skill")
            caption("Add one skill at a time, 3 to 40 characters.")
            Button(isWorking && proposed.isEmpty ? "Reading…" : "Find my skills") { Task { await propose() } }
                .buttonStyle(RequestTextActionStyle())
                .disabled(isWorking || description.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
        }
    }

    private var skillsStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Your skills").plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
            if !proposed.isEmpty {
                Text("Keep the skills you offer. Tap to remove any others.")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                PlugFlowLayout {
                    ForEach(proposed) { skill in
                        ProviderChoice(title: skill.requiresLicence ? "\(skill.display), licence" : skill.display,
                                 selected: chosen.contains(skill.tag)) {
                            if chosen.contains(skill.tag) { chosen.remove(skill.tag) } else { chosen.insert(skill.tag) }
                        }
                    }
                }
            }
            ownSkillsSection
        }
        .marketCard()
    }

    /// Direct entries and suggestion candidates. The server resolves listed skills on save.
    private var ownSkillsSection: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            if !proposed.isEmpty && !ownSkillCandidates.isEmpty {
                PlugDivider()
                Text("Added by you").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            }
            if !ownSkillCandidates.isEmpty {
                PlugFlowLayout {
                    ForEach(ownSkillCandidates, id: \.self) { label in
                        ProviderChoice(title: label, selected: ownSkills.contains(label)) { toggleOwn(label) }
                            .accessibilityHint(ownSkills.contains(label) ? "Removes this skill" : "Keeps this as your own skill")
                    }
                }
            }
            if ownSkills.count >= 5 { caption("You can keep up to five skills entered in your own words.") }
        }
    }

    /// Unmatched words from the description first, then anything already kept or typed.
    private var ownSkillCandidates: [String] {
        var labels = unmatched
        for label in ownSkills where !labels.contains(label) { labels.append(label) }
        return labels
    }

    private func toggleOwn(_ label: String) {
        if let index = ownSkills.firstIndex(of: label) { ownSkills.remove(at: index) }
        else if ownSkills.count < 5 { ownSkills.append(label) }
    }

    private var radiusStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("How far will you go?").plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
            PlugFlowLayout {
                ForEach(Radius.allCases) { option in
                    ProviderChoice(title: option.title, selected: selectedRadius == option.rawValue) {
                        radius = option
                        radiusChanged = true
                    }
                }
            }
            if let current, !radiusChanged { caption("Current radius: \(distance(current.travelRadiusM)). Kept unless you choose a new distance.") }
            caption("You only receive requests from people inside this distance.")
        }
    }

    private var availabilityStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("When are you usually free?").plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
            PlugFlowLayout {
                ForEach([AvailabilityWindow.Days.weekdays, .weekends, .everyDay], id: \.self) { option in
                    ProviderChoice(title: option.title, selected: days == option) { days = option; availabilityChanged = true }
                }
            }
            PlugFlowLayout {
                ForEach(Slot.allCases) { slot in
                    ProviderChoice(title: slot.title, selected: slots.contains(slot)) {
                        availabilityChanged = true
                        if slots.contains(slot) { slots.remove(slot) } else { slots.insert(slot) }
                    }
                }
            }
            if let current, !availabilityChanged {
                caption("Current hours: \(current.availability.map(\.summary).joined(separator: "; ")). Kept unless you choose new hours.")
            }
            caption("Times are in \(current?.timeZone ?? TimeZone.current.identifier).")
            if slots.isEmpty { Text("Choose at least one time.").plugText(.bodySmall).foregroundStyle(PlugTokens.Color.alert600) }
        }
    }

    private var licenceStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Licence").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            Text("\(licensedNames.isEmpty ? "This work" : licensedNames) needs a licence. Licensed requests are matched only to providers who give one.")
                .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            PlugTextField(title: "Licence number", text: $licence,
                          error: !licence.isEmpty && !licenceValid
                              ? "Use 3 to 64 letters, numbers, spaces, dots, slashes or dashes." : nil)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
        }
        .marketCard()
    }

    private var baseStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Where do you work from?").plugText(.title).foregroundStyle(PlugTokens.Color.ink900)
            if let label = location.label, location.location != nil {
                valueRow("Base", label, last: true)
                // Set already: the way to change it steps back so the save action leads.
                Button(location.isWorking ? "Finding location…" : "Update location") { location.useDeviceLocation() }
                    .buttonStyle(PlugButtonStyle(kind: .tertiary, fullWidth: false))
                    .disabled(location.isWorking)
            } else {
                caption("Approximate only. People who ask never see your address.")
                Button(location.isWorking ? "Finding location…" : "Use my approximate location") { location.useDeviceLocation() }
                    .buttonStyle(FlowActionStyle()).disabled(location.isWorking)
            }
            if let error = location.errorMessage {
                Text(error).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.alert600)
                PlugTextField(title: "Street address and city", text: $location.address)
                    .textContentType(.fullStreetAddress)
                Button("Use this address") { Task { await location.resolveAddress() } }
                    .buttonStyle(FlowActionStyle()).disabled(location.isWorking || location.address.isEmpty)
            }
        }
    }

    // MARK: Behaviour

    private var selectedRadius: Int { radiusChanged ? radius.rawValue : (current?.travelRadiusM ?? radius.rawValue) }
    private var hasSkills: Bool { !chosen.isEmpty || !ownSkills.isEmpty }
    private var needsLicence: Bool { licenceRequested || proposed.contains { chosen.contains($0.tag) && $0.requiresLicence } }
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
        ownSkills = current.customSkills ?? []
        radius = Radius.nearest(current.travelRadiusM)
        accepting = current.accepting
        businessName = current.business?.name ?? ""
        about = current.business?.about ?? ""
        photo = current.business?.photoBase64
        if let savedLinks = current.business?.links, !savedLinks.isEmpty {
            links = savedLinks.map { BusinessLinkDraft(label: $0.label, url: $0.url) }
        }
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
            proposed = result.skills
            chosen = Set(result.skills.map(\.tag))
            unmatched = result.unmatched
        } catch {
            errorMessage = message(for: error, saving: false)
        }
    }

    private func save() async {
        guard let base = location.location, !photoLoading else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let windows = Slot.allCases.filter(slots.contains).map { AvailabilityWindow(days: days, from: $0.from, to: $0.to) }
        var setup = ProviderSetup(skillTags: proposed.map(\.tag).filter(chosen.contains),
                                  travelRadiusM: radiusChanged ? radius.rawValue : (current?.travelRadiusM ?? radius.rawValue),
                                  baseLocation: base,
                                  availability: availabilityChanged ? windows : (current?.availability ?? windows))
        setup.timeZone = current?.timeZone ?? TimeZone.current.identifier
        if needsLicence { setup.licenceRef = licence.trimmingCharacters(in: .whitespaces) }
        setup.accepting = accepting
        setup.customSkills = ownSkills
        setup.business = BusinessProfile(name: optional(businessName), about: optional(about), photoBase64: photo,
                                         links: links.filter { optional($0.url) != nil }.map {
            BusinessLink(label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines),
                         url: $0.url.trimmingCharacters(in: .whitespacesAndNewlines))
        })
        do {
            onSaved(try await service.setProvider(setup))
            dismiss()
        } catch {
            if let api = error as? APIError, api.fieldCode == "licence_required" { licenceRequested = true }
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
        return saving ? "We could not confirm whether your changes were saved. Retry these same settings when you are connected."
                      : "Suggestions are unavailable. You can still add each skill directly above."
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
            case .any: return "50 mi"
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
        var from: String {
            switch self {
            case .mornings: return "08:00"
            case .afternoons: return "12:00"
            case .evenings: return "17:00"
            }
        }
        var to: String {
            switch self {
            case .mornings: return "12:00"
            case .afternoons: return "17:00"
            case .evenings: return "21:00"
            }
        }
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
                        PageTitle(title: "Inbox")
                        Label(profile.accepting ? "Your provider profile is saved." : "Your provider profile is paused.",
                              systemImage: profile.accepting ? "checkmark.circle.fill" : "pause.circle.fill")
                            .plugText(.body).fontWeight(.semibold).foregroundStyle(PlugTokens.Color.ink900)
                    }
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
                        IllustrationTile(name: "IllInbox", size: 88)
                        Text("No requests here yet")
                            .plugText(.title)
                        Text("Your skills and hours are saved. Receiving and replying to requests here is coming in a future update.")
                            .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(PlugTokens.Color.ink900)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("inbox-empty")
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
                .foregroundStyle(PlugTokens.Color.ink900)
                .frame(maxWidth: PlugTokens.Layout.measure, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, PlugTokens.Space.s6).padding(.vertical, PlugTokens.Space.s4)
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

private struct BusinessLinkDraft: Identifiable {
    let id = UUID()
    var label: String
    var url = ""
}

/// A skill shown, not chosen: a small tag that does not press. Listed skills sit on sand; skills
/// in the provider's own words carry a hairline instead.
private struct SkillKey: View {
    let title: String
    let fill: Color
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous)
        Text(title).plugText(.bodySmall).fontWeight(.medium).foregroundStyle(PlugTokens.Color.ink900)
            .padding(.horizontal, PlugTokens.Space.s3).frame(minHeight: PlugTokens.minTouchTarget - 8)
            .background(fill, in: shape)
            .overlay { if fill != PlugTokens.Color.sunk { shape.strokeBorder(PlugTokens.Color.ruleControl, lineWidth: PlugShape.rule) } }
    }
}

/// The shared chip; the name stays for its call sites.
private struct ProviderChoice: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View { PlugChip(title: title, selected: selected, action: action) }
}
