import SwiftUI

/// Legal notices are bundled so they remain readable before sign-in and while offline.
struct ConsentNotice: View {
    let environment: AppEnvironment
    @State private var document: LegalDocument?

    var body: some View {
        VStack(spacing: PlugTokens.Space.s1) {
            Text("Private testing · Review the notices before continuing.")
                .font(.caption).foregroundStyle(PlugTokens.Color.ink600)
                .multilineTextAlignment(.center)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PlugTokens.Space.s6) { documentLinks }
                VStack(spacing: 0) { documentLinks }
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(item: $document) { LegalDocumentView(document: $0) }
    }

    private var documentLinks: some View {
        Group {
            documentButton("Terms", .terms)
            documentButton("Privacy Policy", .privacy)
            documentButton("Help", .help)
        }
        .fixedSize()
    }

    private func documentButton(_ title: String, _ value: LegalDocument) -> some View {
        Button { document = value } label: { Text(title).underline() }
            .buttonStyle(.plain).font(.footnote.weight(.medium))
            .foregroundStyle(.primary)
            .frame(minHeight: PlugTokens.minTouchTarget)
    }
}

enum LegalDocument: String, Identifiable {
    case terms, privacy, help
    var id: String { rawValue }
    var title: String {
        switch self {
        case .terms: return "Terms of Service"
        case .privacy: return "Privacy Policy"
        case .help: return "Help with PLUG"
        }
    }

    // These explain the private test build. They must not be presented as an approved
    // public policy or a substitute for the operator's reviewed launch documents.
    var sections: [(String, String)] {
        switch self {
        case .terms:
            return [
                ("Private testing notice", "PLUG is currently a private test build. These notices describe that test. Public Terms of Service have not yet been approved, and this is not a published public-use agreement."),
                ("What you can test", "You can create an account, sign in, and explore the available screens. Some features are still being developed. Availability and test data may change or be reset. Do not rely on this build for urgent or essential services."),
                ("Your account", "Use an account you control. Google and Apple manage their own sign-in credentials; PLUG does not ask for those passwords. A guest session is tied to this device. Sign in with an available provider to keep the same guest account."),
                ("Responsible use", "Use only test information you are comfortable sharing with the project team. Do not submit another person’s private information or attempt to access other accounts."),
                ("Questions or stopping participation", "You can sign out from Profile and stop using the test at any time. Contact the person who invited you to test PLUG with account or data-removal requests. A public support contact will be provided before launch.")
            ]
        case .privacy:
            return [
                ("Private testing notice", "This describes the current private test build. A public Privacy Policy, including the operator’s contact details and retention schedule, is still awaiting approval."),
                ("Account information", "PLUG creates an internal user ID and records your sign-in method, account status, sessions and notice acknowledgements. Verified provider identifiers and phone numbers are stored as keyed hashes for account matching. Session credentials are stored in the iPhone Keychain; the server stores token hashes."),
                ("Sign-in providers", "When you choose Google or Apple, that provider handles authentication and returns an identity token. PLUG verifies the token to create or restore your account. PLUG does not receive your provider password. Phone verification, when enabled, shares the destination number and code with the SMS provider to deliver the message."),
                ("Requests and diagnostics", "Information you submit to PLUG is sent to its server. Request IDs and operational logs help diagnose failures and prevent abuse. Network providers process connection information to deliver requests. Do not include sensitive personal information in test submissions."),
                ("Development code testing", "In explicitly enabled local development mode, phone codes and numbers are written to a file on the developer’s Mac instead of being sent by SMS. This mode is for test data only."),
                ("Your choices and questions", "You can sign out from Profile. Contact the person who invited you for access or data-removal requests. Signing out or deleting the app does not itself delete server records. Do not assume test data has a guaranteed retention period.")
            ]
        case .help:
            return [
                ("Signing in", "Use the same method you used when creating your account. Complete the Google or Apple account sheet, then return to PLUG. Only configured methods are offered in this build."),
                ("Connection problems", "Keep an internet connection available. If PLUG cannot connect, ask the person running the test to check its development server and tunnel. Trying again will not reset your saved account."),
                ("Phone and password recovery", "Phone sign-in uses a one-time code rather than a password. Google and Apple manage password recovery on their own account recovery pages, available under Trouble signing in."),
                ("Report a problem", "Contact the person who invited you. Include the action, time, and any request ID from the diagnostic log. Do not send passwords, one-time codes or session tokens.")
            ]
        }
    }
}

private struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlugTokens.Space.s6) {
                    ForEach(document.sections.indices, id: \.self) { index in
                        let section = document.sections[index]
                        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
                            Text(section.0).font(.headline)
                            Text(section.1).font(.body).foregroundStyle(PlugTokens.Color.ink600)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(PlugTokens.Space.s6).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
