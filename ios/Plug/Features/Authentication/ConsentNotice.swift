import SwiftUI

/// The consent copy and its two links, shown on every screen that creates an account.
/// Continuing is the act of agreeing, so the sentence that says so has to be next to the
/// button that does it rather than on a screen the person already left.
struct ConsentNotice: View {
    let environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: PlugSpacing.small) {
            Text("By continuing you agree to the PLUG Terms and Privacy Policy.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: PlugSpacing.medium) {
                consentLink("Terms", url: PlugConsent.termsURL(environment))
                consentLink("Privacy Policy", url: PlugConsent.privacyURL(environment))
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// A link with nowhere to go is shown as plain text rather than as a control that does
    /// nothing. An unconfigured web address is a build problem, not something to hide.
    @ViewBuilder
    private func consentLink(_ title: String, url: URL?) -> some View {
        if let url {
            Link(title, destination: url)
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityHint("Opens \(title.lowercased()) in your browser")
        } else {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .accessibilityHint("This build has no web address configured, so the link cannot open")
        }
    }
}
