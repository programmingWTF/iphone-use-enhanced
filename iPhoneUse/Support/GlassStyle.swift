//
//  GlassStyle.swift
//  iPhoneUse
//
//  Liquid Glass on iOS 26, frosted material on iOS 17.4.
//  Colour is an identity signal here, not decoration: purple is "from me" and "start
//  something new", blue is a connection in progress, and the vivid green/red sit on the
//  one card that reports a live connection state. Every other surface is plain,
//  untinted glass.
//

import SwiftUI

/// The tints allowed on glass. Each is a system color at low opacity, because the
/// glass supplies most of the color on iOS 26 and the material does on older systems.
enum GlassTint {
    /// The connection status card while a connection is being made.
    static let blue = Color.blue.opacity(0.22)
    /// "From me", and everything that starts a new session: the one hue that means you.
    /// Saturated on purpose: the three purple controls (toolbar circle, drawer pill,
    /// send) all use this same value, so nobody reads them as three different purples.
    static let purple = Color(uiColor: .systemPurple).opacity(0.62)
    /// A quieter purple for large surfaces (the chat bubble, the lifted history card):
    /// the buttons need to shout, a paragraph of text does not.
    static let purpleSoft = Color(uiColor: .systemPurple).opacity(0.34)
    /// The connection status card, connected.
    static let success = Color.green.opacity(0.34)
    /// The connection status card, failed or not connected yet.
    static let failure = Color.red.opacity(0.34)
}

/// Sizes shared by the floating controls, so nothing drifts apart.
enum GlassMetrics {
    /// Diameter of every single-icon glass button: toolbar, send, drawer gear, screenshot close.
    static let circle: CGFloat = 44
}

/// How much glass an untinted surface carries. Coloured surfaces ignore this: their
/// tint is the message, so they always keep the full material.
///
/// Two weights, both real: the chat keeps the film you can see the page through, while
/// the settings pages drop it to a rim so the rows stay the subject.
enum GlassWeight {
    /// The chat screen: `Glass.clear` on iOS 26, a 55% material before it.
    case standard
    /// The settings pages: a 1pt rim on iOS 26, a 3% wash and a 30% material before it.
    case light
}

extension View {
    /// A rounded Liquid Glass surface behind the view.
    ///
    /// Tinted surfaces keep the real thing (`Glass.regular.tint(…)`, or the tint plus a
    /// full material before iOS 26), because the colour is the message there.
    ///
    /// Plain surfaces come in two weights. `.standard` is `Glass.clear` on iOS 26 and a
    /// 55% material before it: a film you can see the page through. `.light` drops the
    /// film on iOS 26 and keeps only a 1pt rim, joined before iOS 26 by a 3% white wash
    /// and a 30% material.
    func glassSurface(_ tint: Color? = nil,
                      weight: GlassWeight = .standard,
                      cornerRadius: CGFloat = 22,
                      interactive: Bool = false) -> some View {
        glassSurface(tint,
                     in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                     weight: weight,
                     interactive: interactive)
    }

    /// The same surface clipped to a shape — `Capsule()` for a one-line row.
    func glassSurface<S: InsettableShape>(_ tint: Color? = nil,
                                          in shape: S,
                                          weight: GlassWeight = .standard,
                                          interactive: Bool = false) -> some View {
        modifier(GlassSurface(tint: tint, shape: shape, weight: weight, interactive: interactive))
    }

    /// The composer's surface: the thinnest glass the system will draw, with refraction.
    ///
    /// `Glass.regular` bends what is behind it instead of fogging it, and it stays
    /// see-through — the point of the field is that you can still read the page under it
    /// while typing. Before iOS 26 there is no glass API, so a thin material stands in.
    @ViewBuilder
    func composerGlass(cornerRadius: CGFloat = 26) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(shape.fill(.ultraThinMaterial))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }

    /// Capsule glass for pills, chips and floating round buttons.
    ///
    /// A coloured capsule gets the same solid base coat as `glassCircle`, so the drawer's
    /// "new chat" pill and the toolbar's round button are the same purple at the same
    /// weight — before this the pill leaned on the tint alone and read as a pale violet.
    func glassPill(_ tint: Color? = nil,
                   weight: GlassWeight = .standard,
                   interactive: Bool = false) -> some View {
        background {
            if let tint = tint {
                Capsule().fill(tint)
            }
        }
        .glassSurface(tint, in: Capsule(), weight: weight, interactive: interactive)
    }

    /// A perfect circle: a fixed square hit area around a circle-shaped surface.
    ///
    /// Every single-icon glass control goes through this, so the circles all have the
    /// same diameter and none of them turn into a rounded square on iOS 26, where a
    /// toolbar item would otherwise be shaped by the system's own button border.
    ///
    /// A coloured circle also gets a base coat of its own colour before the glass goes on,
    /// so the navigation bar's material cannot show through the semi-transparent tint. One
    /// coat is enough now that the toolbar hides its own shared glass (see
    /// `withoutSharedBackground`); a second coat only made the colour heavy.
    func glassCircle(_ tint: Color? = nil,
                     size: CGFloat = GlassMetrics.circle,
                     weight: GlassWeight = .standard,
                     interactive: Bool = true) -> some View {
        frame(width: size, height: size)
            .contentShape(Circle())
            .background {
                if let tint = tint {
                    Circle().fill(tint)
                }
            }
            .glassSurface(tint, in: Circle(), weight: weight, interactive: interactive)
    }

    /// One coloured glass rim, and nothing at all when `tint` is nil.
    ///
    /// Used by the history list: the rows themselves stay borderless, and only the copy
    /// that lifts under the finger (a context menu preview) carries the rim. The gradient
    /// catches the light at the top-left, then settles into the tint, which is what makes
    /// a thin line read as an edge instead of a drawn stroke.
    @ViewBuilder
    func glassOutline<S: InsettableShape>(_ tint: Color?, in shape: S, lineWidth: CGFloat = 1.5) -> some View {
        if let tint = tint {
            overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.55), tint, tint.opacity(0.40)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: lineWidth
                )
            }
        } else {
            self
        }
    }

    /// `.glass` / `.glassProminent` on iOS 26, bordered buttons before.
    /// Wrapped in `HapticButtonStyle` so every button still taps back, as the app expects.
    @ViewBuilder
    func glassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                buttonStyle(.haptic(.glassProminent)).tint(tint ?? .accentColor)
            } else {
                buttonStyle(.haptic(.glass))
            }
        } else if prominent {
            buttonStyle(.haptic(.borderedProminent)).tint(tint)
        } else {
            buttonStyle(.haptic(.bordered))
        }
    }

    /// Standard insets for one row inside a `GlassSection`'s card.
    func glassRow() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

private struct GlassSurface<S: InsettableShape>: ViewModifier {
    let tint: Color?
    let shape: S
    let weight: GlassWeight
    let interactive: Bool

    private var isLight: Bool {
        if case .light = weight { return true }
        return false
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if let tint = tint {
                content.glassEffect(LiquidGlass.tinted(tint, interactive: interactive), in: shape)
            } else if isLight {
                // 轻档：Glass.clear 已是 iOS 26 最透的一档，设置页索性不铺玻璃，
                // 只留一圈 1pt 描边，背后的内容整块透出来，靠边框和文字辨认。
                content.overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            } else {
                content.glassEffect(LiquidGlass.plain(interactive: interactive), in: shape)
            }
        } else {
            // 回退：普通档是淡淡的底色 + 55% 材质；轻档几乎不放底色，材质压到 0.3。
            content
                .background(tint ?? Color.white.opacity(isLight ? 0.03 : 0.04), in: shape)
                .background { shape.fill(.ultraThinMaterial).opacity(tint == nil ? (isLight ? 0.30 : 0.55) : 1) }
                .overlay(shape.strokeBorder(Color.primary.opacity(tint == nil ? (isLight ? 0.20 : 0.18) : 0.10), lineWidth: 1))
        }
    }
}

/// Builds the `Glass` values in one place: `Glass.tint` takes a non-optional color, so
/// the tint has to be applied conditionally.
@available(iOS 26, *)
private enum LiquidGlass {
    static func tinted(_ tint: Color, interactive: Bool) -> Glass {
        var glass: Glass = .regular.tint(tint)
        if interactive { glass = glass.interactive() }
        return glass
    }

    static func plain(interactive: Bool) -> Glass {
        var glass: Glass = .clear
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// A card of content on a glass surface.
struct GlassCard<Content: View>: View {
    private let tint: Color?
    private let weight: GlassWeight
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let content: Content

    init(tint: Color? = nil, weight: GlassWeight = .standard, cornerRadius: CGFloat = 22,
         padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.weight = weight
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(tint, weight: weight, cornerRadius: cornerRadius)
    }
}

/// A form-like group: an optional title, a glass card of rows, and a footer.
struct GlassSection<Content: View, Footer: View>: View {
    private let title: String?
    private let tint: Color?
    private let weight: GlassWeight
    private let content: Content
    private let footer: Footer

    init(_ title: String? = nil, tint: Color? = nil, weight: GlassWeight = .standard,
         @ViewBuilder content: () -> Content,
         @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.tint = tint
        self.weight = weight
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            GlassCard(tint: tint, weight: weight, padding: 0) { content }
            footer
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

extension GlassSection where Footer == EmptyView {
    init(_ title: String? = nil, tint: Color? = nil, weight: GlassWeight = .standard,
         @ViewBuilder content: () -> Content) {
        self.init(title, tint: tint, weight: weight, content: content, footer: { EmptyView() })
    }
}

/// Hairline between the rows of a `GlassSection`'s card.
struct GlassRowDivider: View {
    var body: some View {
        Divider().padding(.leading, 16)
    }
}

/// Row label with a trailing chevron, for a `NavigationLink` in a `GlassSection`.
/// A plain `NavigationLink` only draws its disclosure indicator inside a `Form`/`List`,
/// so outside one the row would look inert.
struct GlassDisclosureLabel<Content: View>: View {
    private let content: Content
    private let chevron: Color

    /// `chevron` defaults to the secondary label colour; a section that keeps its rows in
    /// the plain label colour (white on a dark theme) passes `.primary` so the arrow matches.
    init(chevron: Color = .secondary, @ViewBuilder content: () -> Content) {
        self.chevron = chevron
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(chevron)
        }
    }
}

/// The leading SF Symbol of a settings row.
///
/// One fixed column width keeps every title on the same baseline, and the symbol normally
/// stays `.secondary`: icons say what a row is, they never add a colour of their own. The
/// one exception is a row that is itself about a colour (`tint`), which passes it in.
struct GlassRowIcon: View {
    let name: String
    var tint: Color?

    init(name: String, tint: Color? = nil) {
        self.name = name
        self.tint = tint
    }

    var body: some View {
        Image(systemName: name)
            .font(.body)
            .foregroundStyle(tint ?? Color.secondary)
            .frame(width: 22)
    }
}

/// Keeps a toolbar item out of the system's shared Liquid Glass capsule.
///
/// On iOS 26 the navigation bar puts toolbar items from the same logical group into one
/// shared glass background. Our round purple button lives inside that group, so the
/// capsule showed as a grey rim around the circle — which read as "plain glass under
/// coloured glass". iOS 26 can hide the shared background; before that there is none to
/// hide, so this returns the item untouched.
extension ToolbarContent {
    @ToolbarContentBuilder
    func withoutSharedBackground() -> some ToolbarContent {
        if #available(iOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
