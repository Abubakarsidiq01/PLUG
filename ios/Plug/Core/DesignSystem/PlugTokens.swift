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

// The manual's type scale (§10.1, Figure 7) on Apple system typography. Each step scales
// with Dynamic Type relative to the closest text style, so token sizes are a base, not a cap.
enum PlugTextStyle {
    case title, title2, title3, body, bodySmall, action, label, caption, overline
    var size: CGFloat {
        switch self {
        case .title: return PlugTokens.TypeSize.title1
        case .title2: return PlugTokens.TypeSize.title2
        case .title3: return PlugTokens.TypeSize.title3
        case .body, .action: return PlugTokens.TypeSize.bodyLg
        case .bodySmall: return PlugTokens.TypeSize.body
        case .label: return PlugTokens.TypeSize.label
        case .caption: return PlugTokens.TypeSize.caption
        case .overline: return PlugTokens.TypeSize.overline
        }
    }
    var weight: Font.Weight {
        switch self {
        case .title, .title2, .overline: return .bold
        case .title3, .action, .label: return .semibold
        case .caption: return .medium
        case .body, .bodySmall: return .regular
        }
    }
    /// Figure 7 tracking, in points at the base size.
    var tracking: CGFloat {
        switch self {
        case .title: return -0.4
        case .title2: return -0.2
        case .caption: return 0.22
        case .overline: return 0.9
        default: return 0
        }
    }
    var relativeTo: Font.TextStyle {
        switch self {
        case .title: return .title
        case .title2: return .title2
        case .title3: return .headline
        case .body, .action: return .body
        case .bodySmall: return .subheadline
        case .label: return .footnote
        case .caption, .overline: return .caption
        }
    }
}

private struct PlugTextModifier: ViewModifier {
    let style: PlugTextStyle
    @ScaledMetric private var size: CGFloat
    init(style: PlugTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: style.weight))
            .tracking(style.tracking)
            .textCase(style == .overline ? .uppercase : nil)
    }
}

extension View {
    func plugText(_ style: PlugTextStyle) -> some View { modifier(PlugTextModifier(style: style)) }
}

// MARK: - Figure 8 components shared by request screens

/// §11.4: cards are flat, 1px line.200 border, radius.lg, no shadow.
struct PlugCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PlugTokens.Space.s4)
            .background(PlugTokens.Color.surface0, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.lg).strokeBorder(PlugTokens.Color.line200))
    }
}

extension View {
    func plugCard() -> some View { modifier(PlugCardModifier()) }
}

/// §11.4 filter chip: radius.sm; selected is brand.50 fill with a brand.600 border and label.
struct PlugChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .plugText(.label)
                .padding(.horizontal, PlugTokens.Space.s3)
                .frame(minHeight: PlugTokens.minTouchTarget)
                .foregroundStyle(selected ? PlugTokens.Color.brand600 : PlugTokens.Color.ink900)
                .background(selected ? PlugTokens.Color.brand50 : PlugTokens.Color.surface0,
                            in: RoundedRectangle(cornerRadius: PlugTokens.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.sm)
                    .strokeBorder(selected ? PlugTokens.Color.brand600 : PlugTokens.Color.line300,
                                  lineWidth: selected ? 1.5 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Figure 8 destructive button: white fill, danger border and label; pressed fills danger.50.
struct PlugDestructiveStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .plugText(.action)
            .multilineTextAlignment(.center)
            .padding(.horizontal, PlugTokens.Space.s4)
            .padding(.vertical, PlugTokens.Space.s3)
            .frame(maxWidth: .infinity, minHeight: PlugTokens.minTouchTarget)
            .foregroundStyle(PlugTokens.Color.danger600)
            .background(configuration.isPressed ? PlugTokens.Color.danger50 : PlugTokens.Color.surface0,
                        in: RoundedRectangle(cornerRadius: PlugTokens.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.md).strokeBorder(PlugTokens.Color.dangerBorder))
            .opacity(enabled ? 1 : 0.5)
    }
}

/// Wraps chips onto as many lines as the width and Dynamic Type size need.
struct PlugFlowLayout: Layout {
    var spacing: CGFloat = PlugTokens.Space.s2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, min(x - spacing, width))
        }
        return CGSize(width: widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
