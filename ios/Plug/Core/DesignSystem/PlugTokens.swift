import SwiftUI
import UIKit

// Compatibility names for the generated shared tokens; values have one source.
enum PlugColor {
    static let brand = PlugTokens.Color.brand600
}

enum PlugSpacing {
    static let small = PlugTokens.Space.s2
    static let medium = PlugTokens.Space.s4
    static let large = PlugTokens.Space.s6
}

enum AuthLayout {
    static let contentWidth = PlugTokens.Space.s12 * 9
}

/// The PLUG logotype, the same drawn artwork on the app and the website (design/brand). A
/// fixed-size brand lockup: `size` is its height, and content around it scales instead.
struct PlugLogotype: View {
    var size: CGFloat = PlugTokens.Layout.mark

    var body: some View {
        Image("PlugLogotype").resizable().scaledToFit()
            .frame(height: size)
            .accessibilityLabel("PLUG")
    }
}

struct PlugWordmark: View {
    var body: some View { PlugLogotype(size: PlugTokens.Layout.logo) }
}

// MARK: - The mark, drawn

/// design/brand/plug-mark.svg on its 256 grid: a stem joined to a bowl, with the counter cut
/// out (even-odd fill). The dot inside the counter is drawn separately: it is you.
struct PlugMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 256
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        path.move(to: point(50, 32))
        path.addLine(to: point(134, 32))
        // Top of the bowl, round the right side, to the bottom of the bowl.
        path.addRelativeArc(center: point(134, 104), radius: 72 * unit,
                            startAngle: .degrees(-90), delta: .degrees(180))
        path.addLine(to: point(96, 176))
        path.addLine(to: point(96, 224))
        path.addLine(to: point(50, 224))
        path.closeSubpath()
        path.addEllipse(in: CGRect(origin: point(90, 60), size: CGSize(width: 88 * unit, height: 88 * unit)))
        return path
    }
}

/// The launch reveal, under Motion.reveal: the dot (you) appears, a ring of people nearby
/// forms around it and fades, then the P closes around both. Under Reduce Motion it is the
/// final frame from the start.
struct PlugMarkAnimated: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dot: CGFloat = 0
    @State private var ring: Double = 0
    // 0.86 start scale: an interaction constant with no token yet.
    @State private var markScale: CGFloat = 0.86
    @State private var markOpacity: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width, geometry.size.height) / 256
            ZStack(alignment: .topLeading) {
                PlugMarkShape()
                    .fill(PlugTokens.Color.ink900, style: FillStyle(eoFill: true))
                    .scaleEffect(markScale, anchor: UnitPoint(x: 134.0 / 256, y: 104.0 / 256))
                    .opacity(markOpacity)
                MarkRing(progress: ring, unit: unit)
                Circle().fill(PlugTokens.Color.ink900)
                    .frame(width: 42 * unit, height: 42 * unit)
                    .scaleEffect(dot)
                    .position(x: 134 * unit, y: 104 * unit)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear(perform: play)
    }

    private func play() {
        guard !reduceMotion else {
            dot = 1; ring = 1; markScale = 1; markOpacity = 1
            return
        }
        typealias Mark = PlugTokens.Motion.Mark
        let damping = PlugTokens.Motion.springDamping
        withAnimation(.spring(response: Mark.dot, dampingFraction: damping)) { dot = 1 }
        withAnimation(.easeOut(duration: Mark.ring).delay(Mark.ringDelay)) { ring = 1 }
        withAnimation(.spring(response: Mark.body, dampingFraction: damping).delay(Mark.bodyDelay)) { markScale = 1 }
        withAnimation(.easeOut(duration: Mark.body).delay(Mark.bodyDelay)) { markOpacity = 1 }
    }
}

/// The ring of people around you: grows from the dot's edge to the counter's edge and fades.
private struct MarkRing: View, Animatable {
    var progress: Double
    let unit: CGFloat
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let radius = (21 + 23 * progress) * unit
        Circle().stroke(PlugTokens.Color.ink900, lineWidth: 3 * unit)
            .frame(width: radius * 2, height: radius * 2)
            .position(x: 134 * unit, y: 104 * unit)
            .opacity(progress > 0 ? 1 - progress : 0)
    }
}

// MARK: - Buttons

/// The one button style. Primary is the ink-filled action; secondary is a card with a control
/// border; destructive is alert text on a card; tertiary is text only. Pressing changes the
/// fill or the label colour and scales to 0.98, never the opacity (manual §11.1). Disabled
/// reads as ink600 on a sunk fill and is always explained by text beside it.
struct PlugButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, tertiary }
    var kind: Kind = .secondary
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        PlugButtonBody(configuration: configuration, kind: kind, fullWidth: fullWidth)
    }
}

struct PlugButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PlugButtonStyle.Kind
    let fullWidth: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        let boxed = kind != .tertiary
        configuration.label
            .plugText(.action)
            .multilineTextAlignment(fullWidth ? .center : .leading)
            .padding(.horizontal, boxed ? PlugTokens.Space.s4 : 0)
            .padding(.vertical, boxed ? PlugTokens.Space.s3 : 0)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: PlugTokens.minTouchTarget,
                   alignment: fullWidth ? .center : .leading)
            .foregroundStyle(labelColor(pressed))
            .background(fillColor(pressed), in: RoundedRectangle(cornerRadius: PlugTokens.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.control).strokeBorder(borderColor, lineWidth: 1))
            .contentShape(Rectangle())
            // 0.98 press scale: an interaction constant with no token yet.
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(.plug(reduceMotion: reduceMotion), value: pressed)
    }

    private func labelColor(_ pressed: Bool) -> Color {
        guard enabled else { return PlugTokens.Color.ink600 }
        switch kind {
        case .primary: return pressed ? PlugTokens.Color.sunk : PlugTokens.Color.card
        case .secondary: return PlugTokens.Color.ink900
        case .destructive: return PlugTokens.Color.alert600
        case .tertiary: return pressed ? PlugTokens.Color.ink600 : PlugTokens.Color.ink900
        }
    }

    private func fillColor(_ pressed: Bool) -> Color {
        if kind == .tertiary { return .clear }
        guard enabled else { return PlugTokens.Color.sunk }
        switch kind {
        case .primary: return PlugTokens.Color.ink900
        case .secondary: return pressed ? PlugTokens.Color.sunk : PlugTokens.Color.card
        case .destructive: return pressed ? PlugTokens.Color.alert50 : PlugTokens.Color.card
        case .tertiary: return .clear
        }
    }

    private var borderColor: Color {
        switch kind {
        case .tertiary: return .clear
        case .primary: return enabled ? .clear : PlugTokens.Color.ruleControl
        case .secondary: return PlugTokens.Color.ruleControl
        case .destructive: return enabled ? PlugTokens.Color.alertBorder : PlugTokens.Color.ruleControl
        }
    }
}

// The earlier style names, kept so their call sites read the same; all draw PlugButtonStyle.
struct AuthActionStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        PlugButtonBody(configuration: configuration, kind: primary ? .primary : .secondary, fullWidth: true)
    }
}

struct FlowActionStyle: ButtonStyle {
    var primary = false
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        PlugButtonBody(configuration: configuration,
                       kind: destructive ? .destructive : primary ? .primary : .secondary, fullWidth: true)
    }
}

/// Secondary actions inside a card: text only, or a compact destructive control.
struct RequestTextActionStyle: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        PlugButtonBody(configuration: configuration, kind: destructive ? .destructive : .tertiary, fullWidth: false)
    }
}

struct PlugPrimaryButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(PlugButtonStyle(kind: .primary))
            .disabled(isBusy)
    }
}

/// One trailing navigation-bar action drawn flat: a 44pt ink symbol with no background. On
/// iOS 26 the bar's shared glass circle is turned off for it.
struct FlatToolbarButton: ViewModifier {
    let systemImage: String
    let label: String
    var disabled = false
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = PlugTokens.TypeSize.title3

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.toolbar {
                ToolbarItem(placement: .topBarTrailing) { button }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content.toolbar {
                ToolbarItem(placement: .topBarTrailing) { button }
            }
        }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: min(glyph, PlugTokens.Layout.iconMax), weight: .medium))
                .foregroundStyle(disabled ? PlugTokens.Color.ink400 : PlugTokens.Color.ink900)
                .frame(width: PlugTokens.minTouchTarget, height: PlugTokens.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(disabled)
    }
}

// MARK: - Fields, chips, dividers

/// A permanent label above, a control border at 3:1, 2pt ink when focused, and the error below.
struct PlugTextField: View {
    let title: String
    @Binding var text: String
    var error: String? = nil
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            Text(title).plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
            TextField("", text: $text)
                .plugText(.body)
                .padding(PlugTokens.Space.s3)
                .frame(minHeight: PlugTokens.minTouchTarget)
                .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: PlugTokens.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.control)
                    .strokeBorder(focused ? PlugTokens.Color.ink900 : error != nil ? PlugTokens.Color.alert600 : PlugTokens.Color.ruleControl,
                                  lineWidth: focused ? 2 : 1))
                .focused($focused)
                .accessibilityLabel(title)
                .animation(.plug(reduceMotion: reduceMotion), value: focused)
            if let error {
                Text(error).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.alert600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A 1pt hairline between rows of one card.
struct PlugDivider: View {
    var body: some View {
        PlugTokens.Color.rule200.frame(height: 1).accessibilityHidden(true)
    }
}

/// The one chip: a choice among a few. Selected is a sunk fill with an ink border and a check;
/// never ink-filled, so the primary action stays the only filled control.
struct PlugChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .footnote) private var checkGlyph: CGFloat = PlugTokens.TypeSize.label

    var body: some View {
        Button(action: action) {
            HStack(spacing: PlugTokens.Space.s1) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: checkGlyph, weight: .bold)).accessibilityHidden(true)
                }
                Text(title).plugText(.label)
            }
        }
        .buttonStyle(PlugChipStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PlugChipStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        PlugChipBody(configuration: configuration, selected: selected)
    }
}

struct PlugChipBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .padding(.horizontal, PlugTokens.Space.s4).padding(.vertical, PlugTokens.Space.s2)
            .frame(minHeight: PlugTokens.minTouchTarget)
            .foregroundStyle(PlugTokens.Color.ink900)
            .background(selected ? (pressed ? PlugTokens.Color.rule200 : PlugTokens.Color.sunk)
                                 : (pressed ? PlugTokens.Color.sunk : PlugTokens.Color.card),
                        in: RoundedRectangle(cornerRadius: PlugTokens.Radius.badge))
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.badge)
                .strokeBorder(selected ? PlugTokens.Color.ink900 : PlugTokens.Color.ruleControl, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
            // 0.98 press scale: an interaction constant with no token yet.
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(.plug(reduceMotion: reduceMotion), value: pressed)
            .animation(.plug(reduceMotion: reduceMotion), value: selected)
    }
}

/// When an open request or question stops taking replies; the time is the server's.
struct PlugDeadlineTag: View {
    let until: Date
    var body: some View {
        Text("Open until \(until.formatted(date: .omitted, time: .shortened))")
            .plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
            .padding(.horizontal, PlugTokens.Space.s2).padding(.vertical, PlugTokens.Space.s1)
            .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.badge).strokeBorder(PlugTokens.Color.rule300))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - States

/// One named state: an optional title (with the Unknown badge when nobody could answer), what
/// happened, an optional detail line and at most one action. Neutral sits on a card; alert
/// says what failed on the alert surface (§11.3).
struct PlugNotice: View {
    enum Tone { case neutral, alert }
    var title: String? = nil
    var unknown = false
    var subject: String? = nil
    let message: String
    var detail: String? = nil
    var tone: Tone = .neutral
    var actionTitle: String? = nil
    var actionDisabled = false
    var action: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            if let title {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: PlugTokens.Space.s3) {
                        heading(title).fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        unknownBadge
                    }
                    VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
                        heading(title).fixedSize(horizontal: false, vertical: true)
                        unknownBadge
                    }
                }
            }
            if let subject { Text(subject).plugText(.title3).foregroundStyle(PlugTokens.Color.ink900) }
            Text(message).plugText(.body)
                .foregroundStyle(tone == .alert ? PlugTokens.Color.alert600 : PlugTokens.Color.ink600)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(PlugButtonStyle(kind: .secondary))
                    .disabled(actionDisabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PlugTokens.Space.s4)
        .background(tone == .alert ? PlugTokens.Color.alert50 : PlugTokens.Color.card,
                    in: RoundedRectangle(cornerRadius: PlugTokens.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.card)
            .strokeBorder(tone == .alert ? PlugTokens.Color.alertBorder : PlugTokens.Color.rule200))
    }

    private func heading(_ text: String) -> some View {
        Text(text).plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
    }

    @ViewBuilder private var unknownBadge: some View {
        if unknown { TruthBadge(label: .unknown) }
    }
}

/// One circle per person the server says was contacted: filled once that person replied,
/// outlined until then. Always paired with the server's own count sentence. VoiceOver reads
/// "Notified N" then the rest of the counts; the screenshot test waits on that label's
/// number. A circle only fills when a server update says so.
struct PeopleProgress: View {
    let contacted: Int
    let replied: Int
    /// The server-count sentence; defaults to the request wording.
    var summary: String? = nil
    /// The counts after "Notified N", spoken as the value; defaults to the replies.
    var spokenCounts: String? = nil
    // Layout.dot at the default size, scaling with the sentence beside it.
    @ScaledMetric(relativeTo: .body) private var dot: CGFloat = PlugTokens.Layout.dot
    private static let shownLimit = 12

    var body: some View {
        let sentence = summary ?? "\(contacted) notified, \(replied) replied"
        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            if contacted > 0 {
                PlugFlowLayout(spacing: PlugTokens.Space.s2) {
                    ForEach(0..<min(contacted, Self.shownLimit), id: \.self) { index in
                        PersonDot(filled: index < replied, size: dot)
                    }
                    // The exact number is in the sentence below; no count is derived here.
                    if contacted > Self.shownLimit {
                        Text("and more").plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
                    }
                }
            }
            Text(sentence).plugText(.bodySmall).monospacedDigit().foregroundStyle(PlugTokens.Color.ink600)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notified \(contacted)")
        .accessibilityValue(spokenCounts ?? "\(replied) replied")
    }
}

private struct PersonDot: View {
    let filled: Bool
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1

    var body: some View {
        Circle().fill(filled ? PlugTokens.Color.ink900 : Color.clear)
            .overlay(Circle().strokeBorder(filled ? PlugTokens.Color.ink900 : PlugTokens.Color.ruleControl, lineWidth: 1))
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .onChange(of: filled) { _, nowFilled in
                // A reply the server just reported settles into place; nothing else moves.
                guard nowFilled, !reduceMotion else { return }
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { scale = 0.6 }
                DispatchQueue.main.async {
                    withAnimation(.plug(reduceMotion: false)) { scale = 1 }
                }
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
/// reported. One token spring (response 0.35, damping 0.82), and none under Reduce Motion.
extension Animation {
    static func plug(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: PlugTokens.Motion.springResponse,
                                     dampingFraction: PlugTokens.Motion.springDamping)
    }
}
