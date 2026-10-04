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
    @FocusState private var describing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 28, weight: .regular))
                                .frame(width: 60, height: 60)
                                .background(PlugTokens.Color.sunk, in: RoundedRectangle(cornerRadius: 20))
                            Text(current == nil ? "Offer a service" : "What you offer")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                        }.foregroundStyle(PlugTokens.Color.ink900)
                        Text("Turn what you do into a local connection.")
                            .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                    }
                    describeStep.marketCard()
                    if !proposed.isEmpty || !unmatched.isEmpty || !ownSkills.isEmpty { skillsStep }
                    if hasSkills {
                        DisclosureGroup(isExpanded: $showingBusiness) {
                            businessStep.padding(.top, PlugTokens.Space.s4)
                        } label: {
                            HStack(spacing: PlugTokens.Space.s3) {
                                BusinessPortrait(name: optional(businessName) ?? "Your business", photo: photo, size: 48)
                                VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                                    Text("Business profile").plugText(.title3)
                                        .accessibilityIdentifier("provider-business-section")
                                    Text("Photo, about & links · Optional").plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
                                }
                                .multilineTextAlignment(.leading)
                            }
                            .padding(.vertical, PlugTokens.Space.s2)
                        }.marketCard()
                        radiusStep.marketCard()
                        availabilityStep.marketCard()
                        if needsLicence { licenceStep }
                        baseStep.marketCard()
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
                    if hasSkills {
                        Button(isWorking ? "Saving…" : saveTitle) { Task { await save() } }
                            .buttonStyle(FlowActionStyle(primary: true))
                            .disabled(isWorking || photoLoading || location.location == nil || slots.isEmpty || (needsLicence && !licenceValid))
                            .accessibilityIdentifier("provider-save")
                        caption("Private test. Your settings are saved for matching. Inbox delivery and booking are not available yet.")
                    }
                }
                .disabled(isWorking)
                .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, PlugTokens.Space.s4).padding(.vertical, PlugTokens.Space.s6)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PlugTokens.Color.paper)
            // A paper bar, so scrolled text never runs under Cancel at large text sizes.
            .toolbarBackground(PlugTokens.Color.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isWorking) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { describing = false } }
            }
        }
        .interactiveDismissDisabled(isWorking)
        .tint(PlugTokens.Color.ink900)
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
                BusinessPortrait(name: optional(businessName) ?? "Your business", photo: photo, size: 88)
                VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Text(photoLoading ? "Preparing photo…" : photo == nil ? "Add business photo" : "Change photo")
                            .plugText(.action).underline().frame(minHeight: PlugTokens.minTouchTarget)
                    }
                    .disabled(photoLoading)
                    if photo != nil {
                        Button("Remove photo") { photo = nil; selectedPhoto = nil }
                            .plugText(.bodySmall).frame(minHeight: PlugTokens.minTouchTarget)
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
                            .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                            .frame(minHeight: PlugTokens.minTouchTarget)
                    }
                }
            }
            if links.count < 5 {
                Button("Add another link") { links.append(BusinessLinkDraft(label: "")) }
                    .plugText(.action).foregroundStyle(PlugTokens.Color.ink900)
                    .frame(minHeight: PlugTokens.minTouchTarget)
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
            Text("What do you do?").plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
            TextField("For example: Wig install", text: $description, axis: .vertical)
                .plugText(.body).lineLimit(2...5).focused($describing)
                .padding(PlugTokens.Space.s3)
                .frame(minHeight: PlugTokens.minTouchTarget)
                .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.control)
                    .strokeBorder(describing ? PlugTokens.Color.ink900 : PlugTokens.Color.rule300, lineWidth: describing ? 2 : 1))
                .accessibilityLabel("What do you do?")
                .accessibilityIdentifier("provider-description")
            Button("Add skill") {
                let label = description.trimmingCharacters(in: .whitespacesAndNewlines)
                guard (3...40).contains(label.count), ownSkills.count < 5 else { return }
                if !ownSkills.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
                    ownSkills.append(label)
                }
                description = ""
                describing = false
                errorMessage = nil
            }
            .buttonStyle(FlowActionStyle(primary: true))
            .disabled(isWorking || !(3...40).contains(description.trimmingCharacters(in: .whitespacesAndNewlines).count) || ownSkills.count >= 5)
            .accessibilityIdentifier("provider-add-skill")
            caption("Add one skill at a time · 3–40 characters.")
            Button(isWorking && proposed.isEmpty ? "Reading…" : "Find my skills") { Task { await propose() } }
                .buttonStyle(RequestTextActionStyle())
                .disabled(isWorking || description.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
        }
    }

    private var skillsStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Your skills").plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
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
                Rectangle().fill(PlugTokens.Color.rule200).frame(height: 1)
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
            Text("How far will you go?").plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
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
        .padding(.vertical, PlugTokens.Space.s2)
    }

    private var availabilityStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("When are you usually free?").plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
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
        .padding(.vertical, PlugTokens.Space.s2)
    }

    private var licenceStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Licence").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
            Text("\(licensedNames.isEmpty ? "This work" : licensedNames) needs a licence. Licensed requests are matched only to providers who give one.")
                .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
            PlugTextField(title: "Licence number", text: $licence)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            if !licence.isEmpty, !licenceValid {
                Text("Use 3 to 64 letters, numbers, spaces, dots, slashes or dashes.")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.alert600)
            }
        }
        .marketCard()
    }

    private var baseStep: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            Text("Where do you work from?").plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
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
        .padding(.vertical, PlugTokens.Space.s2)
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
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Inbox").font(.system(.largeTitle, design: .rounded, weight: .bold))
                            Text(profile.accepting ? "Your provider profile is saved." : "Your provider profile is paused.")
                                .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                        }
                        Spacer(minLength: 0)
                        FlowEmblem(symbol: "tray", size: 56)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        FlowEmblem(symbol: "bubble.left.and.bubble.right", size: 76)
                        Text("A place for your next connection")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("Your skills and hours are saved. Receiving and replying to requests here is coming in a future update.")
                            .plugText(.body).foregroundStyle(PlugTokens.Color.ink600)
                    }.marketCard().accessibilityIdentifier("inbox-empty")
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                        BusinessIdentity(name: profile.business?.name ?? "Your business", business: profile.business, score: profile.score)
                        if let about = profile.business?.about { Text(about).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600) }
                        if let links = profile.business?.links { BusinessLinks(links: links) }
                        Text("What you offer").plugText(.title3).foregroundStyle(PlugTokens.Color.ink900)
                        PlugFlowLayout {
                            ForEach(profile.skills) { skill in
                                Text(skill.display).plugText(.label).foregroundStyle(PlugTokens.Color.ink900)
                                    .padding(.horizontal, PlugTokens.Space.s3).padding(.vertical, PlugTokens.Space.s2)
                                    .background(PlugTokens.Color.sunk, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.badge))
                            }
                            ForEach(profile.customSkills ?? [], id: \.self) { label in
                                Text(label).plugText(.label).foregroundStyle(PlugTokens.Color.ink900)
                                    .padding(.horizontal, PlugTokens.Space.s3).padding(.vertical, PlugTokens.Space.s2)
                                    .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.badge).strokeBorder(PlugTokens.Color.rule300))
                                    .accessibilityLabel("\(label), your own skill")
                            }
                        }
                        FlowMetrics(items: [("Travel area", distance(profile.travelRadiusM), "location"),
                                            ("Licence", profile.licenceOnFile ? "On file" : "None given", "doc.text")], compact: true)
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your hours", systemImage: "calendar").plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
                            Text(profile.availability.map(\.summary).joined(separator: "\n")).plugText(.body)
                        }
                        Button("Edit business & services") { editing = true }
                            .buttonStyle(FlowActionStyle(primary: true))
                            .accessibilityIdentifier("provider-edit")
                    }
                    .marketCard()
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


private struct BusinessLinkDraft: Identifiable {
    let id = UUID()
    var label: String
    var url = ""
}

private struct ProviderChoice: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).plugText(.label)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 44)
                .foregroundStyle(selected ? PlugTokens.Color.card : PlugTokens.Color.ink900)
                .background(selected ? PlugTokens.Color.ink900 : PlugTokens.Color.paper, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
