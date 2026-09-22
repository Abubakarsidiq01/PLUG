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

    @State private var code = ""

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

            if let problem {
                StateMessage(title: title(for: problem), detail: detail(for: problem),
                             systemImage: "exclamationmark.circle")
            } else if let attemptsRemaining {
                Text("You have \(attemptsRemaining) attempts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if problem == .expired {
                PlugPrimaryButton(title: "Send me a new code", action: onStartOver)
            } else {
                PlugPrimaryButton(title: "Continue") { onSubmit(code) }
                    .disabled(code.count != 6)
                Button("Start over", action: onStartOver)
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }

            ConsentNotice(environment: environment)
        }
        .accessibilityElement(children: .contain)
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
