import SwiftUI

/// Entering the code from the message, and the two ways that goes wrong. A wrong code and
/// an expired one look different here because the person can do different things about
/// them: try again, or ask for a new code.
struct CodeEntryView: View {
    let challengeID: String
    let expiresAt: Date?
    let attemptsRemaining: Int?
    let problem: AuthenticationState.CodeRejection?
    let environment: AppEnvironment
    let onSubmit: (String) -> Void
    let onStartOver: () -> Void
    let onResend: () -> Void

    @State private var code = ""
    @State private var canResend = false

    var body: some View {
        VStack(alignment: .leading, spacing: PlugSpacing.medium) {
            Text("Enter the code we sent you")
                .font(.headline)
            if let expiresAt {
                Text("It expires \(expiresAt.formatted(date: .omitted, time: .shortened)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            PlugTextField(title: "Six-digit code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .onChange(of: code) { _, value in code = String(value.filter { "0123456789".contains($0) }.prefix(6)) }

            if let problem {
                StateMessage(title: title(for: problem), detail: detail(for: problem),
                             systemImage: "exclamationmark.circle")
            } else if let attemptsRemaining {
                Text("You have \(attemptsRemaining) attempts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if code.count != 6 && problem != .expired {
                Text("Enter all six digits to continue.")
                    .font(.footnote).foregroundStyle(PlugTokens.Color.ink600)
            }

            if problem == .expired {
                PlugPrimaryButton(title: "Request a new code", action: onResend)
            } else {
                PlugPrimaryButton(title: "Continue") { onSubmit(code) }
                    .disabled(code.count != 6)
            }

            if problem != .expired {
                Button("Resend code", action: onResend)
                    .disabled(!canResend)
                    .buttonStyle(AuthActionStyle())
                if !canResend {
                    Text("You can request another code after 30 seconds.")
                        .font(.footnote).foregroundStyle(PlugTokens.Color.ink600)
                }
            }
            Button("Change phone number", action: onStartOver)
                .buttonStyle(AuthActionStyle())

        }
        .accessibilityElement(children: .contain)
        .task {
            do {
                try await Task.sleep(for: .seconds(30))
                canResend = true
            } catch { /* Leaving this screen cancels the cooldown. */ }
        }
    }

    private func title(for problem: AuthenticationState.CodeRejection) -> String {
        switch problem {
        case .invalid: return "That code is not correct"
        case .expired: return "That code has expired"
        }
    }

    private func detail(for problem: AuthenticationState.CodeRejection) -> String {
        switch problem {
        case .invalid: return "Check the message and enter the six digits again."
        case .expired: return "Codes are only good for a few minutes. Ask for a new one."
        }
    }
}
