import SwiftUI

// These foundation values are provisional until the design handoff is reviewed.
enum PlugColor {
    static let brand = Color.blue
    static let surface = Color(uiColor: .secondarySystemBackground)
}

enum PlugSpacing {
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
}

struct PlugCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(PlugSpacing.medium)
            .background(PlugColor.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PlugStatusBadge: View {
    let label: String
    var body: some View {
        Text(label).font(.caption.weight(.semibold)).padding(PlugSpacing.small)
            .background(PlugColor.surface, in: Capsule())
    }
}

struct PlugPrimaryButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void
    var body: some View {
        Button(title, action: action).buttonStyle(.borderedProminent)
            .frame(minHeight: 44).disabled(isBusy)
    }
}

struct PlugTextField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        TextField(title, text: $text).textFieldStyle(.roundedBorder)
            .frame(minHeight: 44).accessibilityLabel(title)
    }
}
