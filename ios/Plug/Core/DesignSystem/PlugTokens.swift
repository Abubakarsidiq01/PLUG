import CoreText
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

/// Espresso editorial geometry (design/tokens.json): photos and panels nearly square, controls
/// 8pt, sheets 16pt. Lines are 1pt hairlines; nothing has an outline, a shadow or an offset edge.
enum PlugShape {
    static let tile = PlugTokens.Radius.card
    static let control = PlugTokens.Radius.control
    static let sheet = PlugTokens.Radius.sheet
    static let rule: CGFloat = 1
    static let buttonHeight: CGFloat = 52
}

// MARK: - Type

/// Newsreader, the display serif. It ships as one variable font, so weight and optical size
/// are set on its axes directly; that holds on every iOS version we support.
enum PlugFont {
    private static let weightAxis = 0x7767_6874 // 'wght', 200 to 800
    private static let opticalAxis = 0x6F70_737A // 'opsz', 6 to 72

    static func display(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        Font(uiFont(size, weight: weight) as CTFont)
    }

    static func uiFont(_ size: CGFloat, weight: CGFloat) -> UIFont {
        let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: PlugTokens.TypeFamily.display,
            variation: [weightAxis: weight, opticalAxis: min(max(size, 6), 72)]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Display sizes get a little negative tracking; text sizes keep the face's own spacing.
    static func tracking(_ size: CGFloat) -> CGFloat { size >= 28 ? -size * 0.015 : 0 }
}

private struct PlugDisplayModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let base: CGFloat
    let weight: CGFloat
    let limit: CGFloat

    init(size: CGFloat, weight: CGFloat, relativeTo: Font.TextStyle, limit: CGFloat) {
        base = size
        self.weight = weight
        self.limit = limit
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
    }

    func body(content: Content) -> some View {
        // Large display lines stop growing before they stop fitting; the words still wrap.
        let scaled = min(size, base * limit)
        content.font(PlugFont.display(scaled, weight: weight))
            .tracking(PlugFont.tracking(scaled))
    }
}

extension View {
    /// Newsreader at any size, regular (400) or medium (500), scaling with Dynamic Type.
    func plugDisplay(_ size: CGFloat, weight: CGFloat = 400, relativeTo: Font.TextStyle = .largeTitle,
                     limit: CGFloat? = nil) -> some View {
        modifier(PlugDisplayModifier(size: size, weight: weight, relativeTo: relativeTo,
                                     limit: limit ?? (size >= 32 ? 1.5 : 3)))
    }
}

/// The type scale. Hero, display and titles are Newsreader; everything a person reads or taps
/// (body, labels, buttons) is SF Pro so it reads like the rest of iOS. Every step scales with
/// Dynamic Type.
enum PlugTextStyle {
    case hero, display, title, title2, title3, body, bodySmall, action, label, caption
    var size: CGFloat {
        switch self {
        case .hero: return PlugTokens.TypeSize.hero
        case .display: return PlugTokens.TypeSize.display
        case .title: return PlugTokens.TypeSize.title1
        case .title2: return PlugTokens.TypeSize.title2
        case .title3, .action: return PlugTokens.TypeSize.title3
        case .body: return PlugTokens.TypeSize.bodyLg
        case .bodySmall: return PlugTokens.TypeSize.body
        case .label: return PlugTokens.TypeSize.label
        case .caption: return PlugTokens.TypeSize.caption + 1
        }
    }
    /// The Newsreader weight, or nil for SF Pro text.
    var serifWeight: CGFloat? {
        switch self {
        case .hero, .display: return 400
        case .title, .title2: return 500
        default: return nil
        }
    }
    var weight: Font.Weight {
        switch self {
        case .title3: return .semibold
        case .action, .label: return .medium
        default: return .regular
        }
    }
    var relativeTo: Font.TextStyle {
        switch self {
        case .hero, .display: return .largeTitle
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
        if let weight = style.serifWeight {
            let scaled = style.size >= 32 ? min(size, style.size * 1.5) : size
            content.font(PlugFont.display(scaled, weight: weight))
                .tracking(PlugFont.tracking(scaled))
        } else {
            // No extra line spacing: the accessibility audit reports text with added leading as
            // clipped. SF Pro's own leading at these sizes is already open.
            content.font(.system(size: size, weight: style.weight))
        }
    }
}

extension View {
    func plugText(_ style: PlugTextStyle) -> some View { modifier(PlugTextModifier(style: style)) }
}

// MARK: - The mark

/// The PLUG logotype, the same drawn artwork as the website (design/brand), set in espresso.
/// A fixed-size brand lockup: `size` is its height, and content around it scales instead.
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

/// The mark with its dot, still. `dot` colours the dot (you) so it can read on any surface.
struct PlugMark: View {
    var ink: Color = PlugTokens.Color.ink900
    var dot: Color = PlugTokens.Color.ink900

    var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width, geometry.size.height) / 256
            ZStack(alignment: .topLeading) {
                PlugMarkShape().fill(ink, style: FillStyle(eoFill: true))
                Circle().fill(dot).frame(width: 42 * unit, height: 42 * unit)
                    .position(x: 134 * unit, y: 104 * unit)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Motion

extension Animation {
    /// The press spring, or nothing under Reduce Motion.
    static func plug(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: PlugTokens.Motion.springKeyResponse,
                                     dampingFraction: PlugTokens.Motion.springKeyDamping)
    }
    /// Sheets and content arriving; a short cross-fade under Reduce Motion.
    static func plugSheet(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: PlugTokens.Motion.fast)
            : .spring(response: PlugTokens.Motion.springSheetResponse, dampingFraction: PlugTokens.Motion.springSheetDamping)
    }
}

/// Content that fades up 8pt into place the first time it appears, `index` steps later than the
/// first. It appears in place under Reduce Motion.
struct Arrival: ViewModifier {
    var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                guard !shown, !reduceMotion else { return }
                withAnimation(.easeOut(duration: PlugTokens.Motion.base).delay(Double(min(index, 6)) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func plugArrival(_ index: Int = 0) -> some View { modifier(Arrival(index: index)) }
}

// MARK: - Buttons

/// The one button. Primary is a forest-green fill with a cream label; secondary and outline are
/// a 1pt espresso hairline; destructive is the same in alert red; tertiary is an underlined
/// green text link. Pressing darkens the fill and settles it to 0.98; under Reduce Motion only the colour
/// changes. Only the primary press gives a light tap.
struct PlugButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, outline, destructive, tertiary }
    var kind: Kind = .outline
    var fullWidth = true
    /// A square 44pt control holding one glyph.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PlugButtonBody(configuration: configuration, kind: kind, fullWidth: fullWidth, compact: compact)
    }
}

struct PlugButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PlugButtonStyle.Kind
    let fullWidth: Bool
    var compact = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        if kind == .tertiary {
            configuration.label
                .plugText(.action)
                .underline(true, color: PlugTokens.Color.brandGreen.opacity(pressed ? 1 : 0.45))
                .multilineTextAlignment(.leading)
                .foregroundStyle(enabled ? (pressed ? PlugTokens.Color.brandGreenPressed : PlugTokens.Color.brandGreen) : PlugTokens.Color.ink600)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: PlugTokens.minTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
        } else {
            control(pressed)
        }
    }

    private func control(_ pressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous)
        return configuration.label
            .plugText(.action)
            .multilineTextAlignment(fullWidth ? .center : .leading)
            .padding(.horizontal, compact ? 0 : PlugTokens.Space.s6)
            .padding(.vertical, compact ? 0 : PlugTokens.Space.s3)
            .frame(maxWidth: fullWidth ? .infinity : nil,
                   minHeight: compact ? PlugTokens.minTouchTarget : PlugShape.buttonHeight)
            .frame(minWidth: PlugTokens.minTouchTarget)
            .foregroundStyle(labelColor)
            .background(fillColor(pressed), in: shape)
            .overlay {
                if kind != .primary {
                    shape.strokeBorder(borderColor, lineWidth: PlugShape.rule)
                }
            }
            .contentShape(shape)
            .scaleEffect(pressed && enabled && !reduceMotion ? 0.98 : 1)
            .animation(.plug(reduceMotion: reduceMotion), value: pressed)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, now in now && kind == .primary }
    }

    private var labelColor: Color {
        guard enabled else { return PlugTokens.Color.ink600 }
        switch kind {
        case .primary: return PlugTokens.Color.paper
        case .secondary, .outline, .tertiary: return PlugTokens.Color.ink900
        case .destructive: return PlugTokens.Color.alert600
        }
    }

    private func fillColor(_ pressed: Bool) -> Color {
        guard enabled else { return PlugTokens.Color.sunk }
        switch kind {
        case .primary: return pressed ? PlugTokens.Color.brandGreenPressed : PlugTokens.Color.brandGreen
        case .secondary, .outline: return pressed ? PlugTokens.Color.sunk : .clear
        case .destructive: return pressed ? PlugTokens.Color.alert50 : .clear
        case .tertiary: return .clear
        }
    }

    private var borderColor: Color {
        guard enabled else { return PlugTokens.Color.rule300 }
        return kind == .destructive ? PlugTokens.Color.alert600 : PlugTokens.Color.ink900
    }
}

// The earlier style names, kept so their call sites read the same; all draw PlugButtonStyle.
struct AuthActionStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        PlugButtonBody(configuration: configuration, kind: primary ? .primary : .outline, fullWidth: true)
    }
}

struct FlowActionStyle: ButtonStyle {
    var primary = false
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        PlugButtonBody(configuration: configuration,
                       kind: destructive ? .destructive : primary ? .primary : .outline, fullWidth: true)
    }
}

/// Secondary actions inside a section: a text link, or a compact destructive control.
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

/// A photo tile or feature that settles to 0.98 when pressed; it dims a little instead under
/// Reduce Motion.
struct PlugPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlugPressBody(configuration: configuration)
    }
}

private struct PlugPressBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(.plug(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// One trailing navigation-bar action drawn flat: a 44pt symbol with no background. On iOS 26
/// the bar's shared glass circle is turned off for it.
struct FlatToolbarButton: ViewModifier {
    let systemImage: String
    let label: String
    var disabled = false
    var color: Color = PlugTokens.Color.ink900
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
            Image(systemName: systemImage).font(.system(size: min(glyph, PlugTokens.Layout.iconMax), weight: .regular))
                .foregroundStyle(color.opacity(disabled ? 0.5 : 1))
                .frame(width: PlugTokens.minTouchTarget, height: PlugTokens.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(disabled)
    }
}

// MARK: - Fields, chips, dividers

/// A permanent label above, a hairline box that turns forest green when focused, and the error
/// below.
struct PlugTextField: View {
    let title: String
    @Binding var text: String
    var error: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s2) {
            Text(title).plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
            TextField("", text: $text)
                .plugText(.body)
                .padding(.horizontal, PlugTokens.Space.s3)
                .frame(minHeight: PlugTokens.minTouchTarget + 4)
                .background(PlugTokens.Color.card, in: RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous)
                    .strokeBorder(error != nil && !focused ? PlugTokens.Color.alert600
                                  : focused ? PlugTokens.Color.brandGreen : PlugTokens.Color.ruleControl,
                                  lineWidth: focused ? 1.5 : PlugShape.rule))
                .focused($focused)
                .accessibilityLabel(title)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .plugText(.bodySmall).foregroundStyle(PlugTokens.Color.alert600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A 1pt hairline between rows or sections.
struct PlugDivider: View {
    var body: some View {
        PlugTokens.Color.rule200.frame(height: PlugShape.rule).accessibilityHidden(true)
    }
}

/// The one chip: an 8pt hairline control. Selected is the forest-green fill with a check.
struct PlugChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .footnote) private var checkGlyph: CGFloat = PlugTokens.TypeSize.label

    var body: some View {
        Button(action: action) {
            HStack(spacing: PlugTokens.Space.s1 + 2) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: checkGlyph, weight: .semibold)).accessibilityHidden(true)
                }
                Text(title)
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
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous)
        let pressed = configuration.isPressed
        configuration.label
            .plugText(.bodySmall).fontWeight(.medium)
            .padding(.horizontal, PlugTokens.Space.s4).padding(.vertical, PlugTokens.Space.s2)
            .frame(minHeight: PlugTokens.minTouchTarget)
            .foregroundStyle(!enabled ? PlugTokens.Color.ink600 : selected ? PlugTokens.Color.paper : PlugTokens.Color.ink900)
            .background(selected ? PlugTokens.Color.brandGreen : (pressed ? PlugTokens.Color.sunk : .clear), in: shape)
            .overlay { if !selected { shape.strokeBorder(PlugTokens.Color.ruleControl, lineWidth: PlugShape.rule) } }
            .contentShape(shape)
            .animation(reduceMotion ? nil : .easeOut(duration: PlugTokens.Motion.fast), value: selected)
            .sensoryFeedback(.selection, trigger: selected)
    }
}

/// When an open request or question stops taking replies; the time is the server's.
struct PlugDeadlineTag: View {
    let until: Date
    var body: some View {
        Label("Open until \(until.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
            .plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Truth labels

/// The glyph for each truth label, so the label reads without colour: a solid check, a clock,
/// a tilde over a line, a dashed circle with a question mark, and a globe.
struct TruthGlyph: View {
    let label: ServiceOffer.TruthLabel
    let size: CGFloat

    var body: some View {
        Group {
            switch label {
            case .confirmed: Image(systemName: "checkmark.circle.fill").resizable().scaledToFit()
            case .recent: Image(systemName: "clock").resizable().scaledToFit()
            case .estimated: EstimateGlyph().stroke(style: StrokeStyle(lineWidth: max(1.2, size / 11), lineCap: .round))
            case .unknown:
                ZStack {
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: max(1, size / 14), dash: [size / 7, size / 9]))
                    Text("?").font(.system(size: size * 0.58, weight: .semibold))
                }
            case .notVerified: Image(systemName: "globe").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A tilde over a straight line: roughly this, not exactly.
struct EstimateGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: point(0.1, 0.48))
        path.addCurve(to: point(0.5, 0.42), control1: point(0.22, 0.2), control2: point(0.36, 0.22))
        path.addCurve(to: point(0.9, 0.36), control1: point(0.64, 0.62), control2: point(0.78, 0.64))
        path.move(to: point(0.1, 0.76))
        path.addLine(to: point(0.9, 0.76))
        return path
    }
}

/// Icon and word, small, in the label's own colour. A human-checked label is filled; Unknown is
/// filled with a dashed hairline; Not verified (the web) is a dashed hairline with no fill. The
/// truth colours appear nowhere else.
struct TruthBadge: View {
    let label: ServiceOffer.TruthLabel
    var large = false
    @ScaledMetric(relativeTo: .footnote) private var glyph: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var word: CGFloat = 13

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlugTokens.Radius.badge, style: .continuous)
        let dashed = label == .unknown || label == .notVerified
        HStack(spacing: PlugTokens.Space.s1 + 1) {
            TruthGlyph(label: label, size: large ? glyph * 1.2 : glyph)
            Text(label.title).font(.system(size: large ? word * 15 / 13 : word, weight: .semibold))
        }
        .padding(.horizontal, PlugTokens.Space.s2)
        .padding(.vertical, large ? PlugTokens.Space.s1 + 2 : PlugTokens.Space.s1)
        .foregroundStyle(label.foreground)
        .background(label == .notVerified ? Color.clear : label.surface, in: shape)
        .overlay { if dashed { shape.strokeBorder(label.border, style: StrokeStyle(lineWidth: PlugShape.rule, dash: [3, 2])) } }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.explanation)
    }
}

extension ServiceOffer.TruthLabel {
    var foreground: Color {
        switch self {
        case .confirmed: return PlugTokens.Color.truthConfirmed
        case .recent: return PlugTokens.Color.truthRecent
        case .estimated: return PlugTokens.Color.truthEstimated
        case .unknown: return PlugTokens.Color.truthUnknown
        case .notVerified: return PlugTokens.Color.ink600
        }
    }
    var surface: Color {
        switch self {
        case .confirmed: return PlugTokens.Color.truthSurfaceConfirmed
        case .recent: return PlugTokens.Color.truthSurfaceRecent
        case .estimated: return PlugTokens.Color.truthSurfaceEstimated
        case .unknown, .notVerified: return PlugTokens.Color.truthSurfaceUnknown
        }
    }
    var border: Color {
        switch self {
        case .confirmed: return PlugTokens.Color.truthBorderConfirmed
        case .recent: return PlugTokens.Color.truthBorderRecent
        case .estimated: return PlugTokens.Color.truthBorderEstimated
        case .unknown: return PlugTokens.Color.truthBorderUnknown
        case .notVerified: return PlugTokens.Color.ruleControl
        }
    }
}

// MARK: - Test mode, details and toasts

/// The test-mode marker: a small hairline tag in espresso text. A tap opens the full
/// disclosure, so the sentences that used to repeat on every screen are one tap away.
struct TestModeTab: View {
    let lines: [String]
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Text("Test mode").plugText(.label).foregroundStyle(PlugTokens.Color.ink900)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, PlugTokens.Space.s2).padding(.vertical, PlugTokens.Space.s1)
                .overlay(RoundedRectangle(cornerRadius: PlugTokens.Radius.badge, style: .continuous)
                    .strokeBorder(PlugTokens.Color.ruleControl, lineWidth: PlugShape.rule))
                .frame(minHeight: PlugTokens.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityLabel("Test mode")
        .accessibilityHint("Explains what is a test in this build")
        .sheet(isPresented: $open) { InfoSheet(title: "Test mode", lines: lines) }
    }
}

/// The sentences or reference codes behind a tap, in a short sheet.
struct InfoSheet: View {
    let title: String
    var lines: [String] = []
    var rows: [(String, String)] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlugTokens.Space.s4) {
                Text(title).plugText(.display).foregroundStyle(PlugTokens.Color.ink900).accessibilityAddTraits(.isHeader)
                ForEach(lines, id: \.self) { line in
                    Text(line).plugText(.body).foregroundStyle(PlugTokens.Color.ink900)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        PlugDivider()
                        ForEach(rows.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                                Text(rows[index].0).plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
                                Text(rows[index].1).font(.system(.body, design: .monospaced)).foregroundStyle(PlugTokens.Color.ink900)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, PlugTokens.Space.s3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            PlugDivider()
                        }
                    }
                }
                Button("Close") { dismiss() }.buttonStyle(PlugButtonStyle(kind: .secondary))
                    .padding(.top, PlugTokens.Space.s2)
            }
            .padding(PlugTokens.Space.s6)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(PlugTokens.Color.paper)
        .presentationCornerRadius(PlugShape.sheet)
    }
}

/// "Details": reference codes live behind this, never on the main screen.
struct DetailsButton: View {
    let rows: [(String, String)]
    @State private var open = false

    var body: some View {
        Button { open = true } label: { Text("Details") }
            .buttonStyle(PlugButtonStyle(kind: .tertiary, fullWidth: false))
            .accessibilityIdentifier("details")
            .sheet(isPresented: $open) { InfoSheet(title: "Details", rows: rows) }
    }
}

/// A short confirmation that fades down from the top and leaves by itself. VoiceOver hears it
/// as an announcement.
private struct PlugToastModifier: ViewModifier {
    @Binding var message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    HStack(spacing: PlugTokens.Space.s2) {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(message).plugText(.bodySmall).fontWeight(.medium)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(PlugTokens.Color.paper)
                    .padding(.vertical, PlugTokens.Space.s3).padding(.horizontal, PlugTokens.Space.s4)
                    .background(PlugTokens.Color.brandGreen, in: RoundedRectangle(cornerRadius: PlugShape.control, style: .continuous))
                    .padding(.horizontal, PlugTokens.Space.s4)
                    .padding(.top, PlugTokens.Space.s2)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)))
                    .task(id: message) {
                        AccessibilityNotification.Announcement(message).post()
                        try? await Task.sleep(for: .seconds(2.2))
                        self.message = nil
                    }
                    .allowsHitTesting(false)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: PlugTokens.Motion.fast) : .easeOut(duration: PlugTokens.Motion.base), value: message)
            .sensoryFeedback(.success, trigger: message) { _, now in now != nil }
    }
}

extension View {
    func plugToast(_ message: Binding<String?>) -> some View { modifier(PlugToastModifier(message: message)) }
}

// MARK: - States

/// One named state: an optional title (with the Unknown badge when nobody could answer), what
/// happened, an optional detail line and at most one action. Unknown is a calm sand panel with
/// a dashed hairline; an alert carries an icon and the word "Error".
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
    /// Reference codes, behind "Details".
    var references: [(String, String)] = []
    var action: () -> Void = {}

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlugShape.tile, style: .continuous)
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            if tone == .alert {
                Label("Error", systemImage: "exclamationmark.triangle")
                    .plugText(.title3).foregroundStyle(PlugTokens.Color.alert600)
            }
            if let title {
                if unknown {
                    TruthBadge(label: .unknown)
                    Text(title).plugText(.display).foregroundStyle(PlugTokens.Color.ink900)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(title).plugText(.title2).foregroundStyle(PlugTokens.Color.ink900)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let subject { Text(subject).plugText(.title3).foregroundStyle(PlugTokens.Color.ink900) }
            Text(message).plugText(.body)
                .foregroundStyle(tone == .alert ? PlugTokens.Color.alert600 : PlugTokens.Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(PlugButtonStyle(kind: .outline))
                    .disabled(actionDisabled)
            }
            if !references.isEmpty { DetailsButton(rows: references) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PlugTokens.Space.s6 - 4)
        .background(tone == .alert ? PlugTokens.Color.alert50 : PlugTokens.Color.sunk, in: shape)
        .overlay {
            if tone == .alert {
                shape.strokeBorder(PlugTokens.Color.alertBorder, lineWidth: PlugShape.rule)
            } else if unknown {
                shape.strokeBorder(PlugTokens.Color.ruleControl, style: StrokeStyle(lineWidth: PlugShape.rule, dash: [4, 3]))
            }
        }
    }
}

/// One quiet dot per person the server says was contacted: a hollow hairline ring while they
/// have not replied, filled green once they have. Always paired with the server's own count
/// sentence. VoiceOver reads "Notified N" then the rest of the counts; the screenshot test waits
/// on that label's number. A dot only fills when a server update says so.
struct PeopleProgress: View {
    let contacted: Int
    let replied: Int
    /// The server-count sentence; defaults to the request wording.
    var summary: String? = nil
    /// The counts after "Notified N", spoken as the value; defaults to the replies.
    var spokenCounts: String? = nil
    /// A line under the counts.
    var note: String? = nil
    @ScaledMetric(relativeTo: .body) private var dot: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let shownLimit = 12

    var body: some View {
        VStack(alignment: .leading, spacing: PlugTokens.Space.s3) {
            if contacted > 0 {
                PlugFlowLayout(spacing: PlugTokens.Space.s2) {
                    ForEach(0..<min(contacted, Self.shownLimit), id: \.self) { index in
                        let done = index < replied
                        Circle()
                            .fill(done ? PlugTokens.Color.brandGreen : Color.clear)
                            .overlay(Circle().strokeBorder(done ? PlugTokens.Color.brandGreen : PlugTokens.Color.ink400, lineWidth: PlugShape.rule))
                            .frame(width: dot, height: dot)
                    }
                    // The exact number is in the sentence; no count is derived here.
                    if contacted > Self.shownLimit {
                        Text("and more").plugText(.caption).foregroundStyle(PlugTokens.Color.ink600)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: PlugTokens.Motion.base), value: replied)
            }
            VStack(alignment: .leading, spacing: PlugTokens.Space.s1) {
                Text(summary ?? "\(contacted) notified, \(replied) replied")
                    .plugText(.body).fontWeight(.medium).monospacedDigit()
                    .foregroundStyle(PlugTokens.Color.ink900)
                if let note {
                    Text(note).plugText(.bodySmall).foregroundStyle(PlugTokens.Color.ink600)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notified \(contacted)")
        .accessibilityValue(spokenCounts ?? "\(replied) replied")
    }
}

// MARK: - Panels and layout

/// A panel: the slightly lighter card surface with a 1pt hairline, nearly square corners and
/// generous padding. No shadow and no edge.
struct PlugCardModifier: ViewModifier {
    var fill: Color = PlugTokens.Color.card

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PlugShape.tile, style: .continuous)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PlugTokens.Space.s6 - 4)
            .background(fill, in: shape)
            .overlay { if fill != PlugTokens.Color.sunk { shape.strokeBorder(PlugTokens.Color.rule200, lineWidth: PlugShape.rule) } }
    }
}

extension View {
    func plugCard(_ fill: Color = PlugTokens.Color.card) -> some View {
        modifier(PlugCardModifier(fill: fill))
    }
}

/// A real photograph (sources in docs/design/photo-credits.md) cropped to fill a fixed height.
/// Decorative, so VoiceOver skips it. Never used as a provider's own work or on an offer.
struct PlugPhoto: View {
    let name: String
    var height: CGFloat
    /// Which part of the photo stays in frame when it is cropped.
    var focus: Alignment = .center

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(alignment: focus) { Image(name).resizable().scaledToFill() }
            .clipped()
            .accessibilityHidden(true)
    }
}

extension View {
    /// A photo's frame: square by default, or the 4pt tile corner. Never a border.
    func photoFrame(radius: CGFloat = 0) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
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

/// A small label above a section, in SF Pro, sentence case.
struct Overline: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).plugText(.label).foregroundStyle(PlugTokens.Color.ink600)
    }
}
