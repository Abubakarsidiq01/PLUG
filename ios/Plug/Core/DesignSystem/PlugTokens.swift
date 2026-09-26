import SwiftUI

// Compatibility names for the generated shared tokens; values have one source.
enum PlugColor {
    static let brand = PlugTokens.Color.brand600
    static let surface = PlugTokens.Color.surface50
}

enum PlugSpacing {
    static let small = PlugTokens.Space.s2
    static let medium = PlugTokens.Space.s4
    static let large = PlugTokens.Space.s6
}

struct PlugCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(PlugSpacing.medium)
            .background(PlugColor.surface, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.lg))
    }
}

struct PlugStatusBadge: View {
    let label: String
    var body: some View {
        Text(label).font(.caption.weight(.semibold)).padding(PlugSpacing.small)
            .background(PlugColor.surface, in: Capsule())
    }
}

enum AuthLayout {
    static let contentWidth = PlugTokens.Space.s12 * 9
}

struct PlugWordmark: View {
    var body: some View {
        HStack(spacing: PlugTokens.Space.s2) {
            Image("PlugMark").resizable().scaledToFit()
                .frame(width: PlugTokens.Space.s6, height: PlugTokens.Space.s8)
            Text("PLUG").font(.title2.weight(.bold))
                .dynamicTypeSize(.large) // Fixed brand lockup; content still follows Dynamic Type.
                .foregroundStyle(PlugTokens.Color.ink900)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PLUG")
    }
}

struct AuthActionStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .plugText(.action)
            .multilineTextAlignment(.center)
            .padding(.horizontal, PlugTokens.Space.s4)
            .padding(.vertical, PlugTokens.Space.s3)
            .frame(maxWidth: .infinity, minHeight: PlugTokens.minTouchTarget)
            .foregroundStyle(primary ? PlugTokens.Color.surface0 : PlugTokens.Color.ink900)
            .background(background(pressed: configuration.isPressed),
                        in: RoundedRectangle(cornerRadius: PlugTokens.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.md)
                .strokeBorder(primary ? Color.clear : PlugTokens.Color.line300))
            .opacity(enabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : .easeOut(duration: PlugTokens.Motion.fast),
                       value: configuration.isPressed)
    }

    private func background(pressed: Bool) -> Color {
        if primary { return pressed ? PlugTokens.Color.brand700 : PlugTokens.Color.brand600 }
        return pressed ? PlugTokens.Color.surface50 : PlugTokens.Color.surface0
    }
}

struct PlugPrimaryButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(AuthActionStyle(primary: true))
            .disabled(isBusy)
    }
}

struct PlugTextField: View {
    let title: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            Text(title).plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
            TextField("", text: $text)
            .plugText(.body)
            .padding(PlugTokens.Space.s3)
            .frame(minHeight: PlugTokens.minTouchTarget)
            .background(PlugTokens.Color.surface0)
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.md)
                .strokeBorder(focused ? PlugTokens.Color.brand600 : PlugTokens.Color.line300,
                              lineWidth: focused ? 2 : 1))
            .focused($focused)
            .accessibilityLabel(title)
        }
    }
}

// Base sizes come from the manual's shared type scale; Dynamic Type remains native.
enum PlugTextStyle {
    case title, body, action, label
    var size: CGFloat {
        switch self {
        case .title: return PlugTokens.TypeSize.title1
        case .body, .action: return PlugTokens.TypeSize.bodyLg
        case .label: return PlugTokens.TypeSize.label
        }
    }
    var weight: Font.Weight {
        switch self {
        case .title: return .bold
        case .action, .label: return .semibold
        case .body: return .regular
        }
    }
}

private struct PlugTextModifier: ViewModifier {
    let style: PlugTextStyle
    @ScaledMetric private var size: CGFloat
    init(style: PlugTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style == .title ? .title : .body)
    }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: style.weight))
    }
}

extension View {
    func plugText(_ style: PlugTextStyle) -> some View { modifier(PlugTextModifier(style: style)) }
}
