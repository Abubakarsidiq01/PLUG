import SwiftUI
import UIKit

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

/// The PLUG logotype, the same on the app and the website: the designed P is the letter P,
/// followed by "LUG", all in ink. The mark's bowl sits on the cap height and its tail drops
/// below the baseline like a descender. A fixed-size brand lockup; content around it scales.
struct PlugLogotype: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.03) {
            Image("PlugMark").renderingMode(.template).resizable().scaledToFit()
                .frame(width: markHeight * 64 / 80, height: markHeight)
                // In the mark's 80-unit box the bowl spans 4…52; 52 is the baseline.
                .alignmentGuide(.firstTextBaseline) { dimensions in dimensions.height * 52 / 80 }
            Text("LUG").font(.system(size: size, weight: .heavy, design: .rounded)).tracking(size * 0.02)
        }
        .foregroundStyle(PlugTokens.Color.ink900)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PLUG")
    }

    /// The bowl (48 of the mark's 80 units) matches the capital letters' height.
    private var markHeight: CGFloat {
        let capHeight = UIFont.systemFont(ofSize: size, weight: .heavy).capHeight
        return capHeight * 80 / 48
    }
}

struct PlugWordmark: View {
    var body: some View { PlugLogotype(size: 22) }
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

// The manual v4 type scale (§10.1, Figure 7) on Apple system typography, sentence case only:
// v4 bans tracked-out capital labels. Each step scales with Dynamic Type from its base size.
enum PlugTextStyle {
    case display, title, title2, title3, body, bodySmall, action, label, caption
    var size: CGFloat {
        switch self {
        case .display: return PlugTokens.TypeSize.display
        case .title: return PlugTokens.TypeSize.title1
        case .title2: return PlugTokens.TypeSize.title2
        case .title3: return PlugTokens.TypeSize.title3
        case .body, .action: return PlugTokens.TypeSize.bodyLg
        case .bodySmall: return PlugTokens.TypeSize.body
        case .label: return PlugTokens.TypeSize.label
        case .caption: return PlugTokens.TypeSize.caption
        }
    }
    var weight: Font.Weight {
        switch self {
        case .display, .title, .title2, .title3, .label: return .bold
        case .action: return .semibold
        case .caption: return .medium
        case .body, .bodySmall: return .regular
        }
    }
    /// Figure 7 tracking, in points at the base size.
    var tracking: CGFloat {
        switch self {
        case .display: return -0.8
        case .title: return -0.6
        case .title2: return -0.45
        case .title3: return -0.25
        default: return 0
        }
    }
    var relativeTo: Font.TextStyle {
        switch self {
        case .display: return .largeTitle
        case .title: return .title
        case .title2: return .title2
        case .title3: return .headline
        case .body, .action: return .body
        case .bodySmall: return .subheadline
        case .label: return .footnote
        case .caption: return .caption
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
    }
}

extension View {
    func plugText(_ style: PlugTextStyle) -> some View { modifier(PlugTextModifier(style: style)) }
}

// MARK: - Figure 8 components shared by request screens

/// Manual v4 §10: a card is brighter than the paper page, with a 1px rule border, radius.card
/// and no shadow. Elevation is brightness.
struct PlugCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PlugTokens.Space.s4)
            .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.card).strokeBorder(PlugTokens.Color.rule200))
    }
}

extension View {
    func plugCard() -> some View { modifier(PlugCardModifier()) }
}

/// Manual v4 Figure A2 chip: radius.badge; selected is an ink fill with a card label, the
/// way the approved screens draw a chosen skill or radius. Colour stays out of it.
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
                .foregroundStyle(selected ? PlugTokens.Color.card : PlugTokens.Color.ink900)
                .background(selected ? PlugTokens.Color.ink900 : PlugTokens.Color.card,
                            in: RoundedRectangle(cornerRadius: PlugTokens.Radius.badge))
                .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.badge)
                    .strokeBorder(selected ? PlugTokens.Color.ink900 : PlugTokens.Color.rule300))
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
            .foregroundStyle(PlugTokens.Color.alert600)
            .background(configuration.isPressed ? PlugTokens.Color.alert50 : PlugTokens.Color.card,
                        in: RoundedRectangle(cornerRadius: PlugTokens.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.control).strokeBorder(PlugTokens.Color.alertBorder))
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

/// Manual v4 §10.1 and §16.3: motion only explains a change the person caused or the server
/// reported, uses the token durations and easing, and resolves to none under Reduce Motion.
extension Animation {
    static func plug(_ duration: Double = PlugTokens.Motion.base, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.2, 0, 0, 1, duration: duration)
    }
}
