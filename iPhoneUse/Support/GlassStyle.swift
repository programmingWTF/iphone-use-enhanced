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
    static let purple = Color.purple.opacity(0.32)
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

extension View {
    /// A rounded Liquid Glass surface behind the view.
    ///
    /// Tinted surfaces keep the real thing (`Glass.regular.tint(…)`, or the tint plus a
    /// full material before iOS 26), because the colour is the message there.
    ///
    /// Plain surfaces are meant to be almost nothing: `Glass.clear` is the clearest glass
    /// iOS 26 ships, and it still reads as a film, so plain surfaces skip `glassEffect`
    /// entirely and keep only a 1pt rim. Before iOS 26 the rim is joined by a 3% white
    /// wash and a 30% material, which is enough to see the view behind through the card.
    func glassSurface(_ tint: Color? = nil, cornerRadius: CGFloat = 22, interactive: Bool = false) -> some View {
        glassSurface(tint,
                     in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                     interactive: interactive)
    }

    /// The same surface clipped to a shape — `Capsule()` for a one-line row.
    func glassSurface<S: InsettableShape>(_ tint: Color? = nil, in shape: S, interactive: Bool = false) -> some View {
        modifier(GlassSurface(tint: tint, shape: shape, interactive: interactive))
    }

    /// Capsule glass for pills, chips and floating round buttons.
    func glassPill(_ tint: Color? = nil, interactive: Bool = false) -> some View {
        glassSurface(tint, in: Capsule(), interactive: interactive)
    }

    /// A perfect circle: a fixed square hit area around a circle-shaped surface.
    ///
    /// Every single-icon glass control goes through this, so the circles all have the
    /// same diameter and none of them turn into a rounded square on iOS 26, where a
    /// toolbar item would otherwise be shaped by the system's own button border.
    func glassCircle(_ tint: Color? = nil,
                     size: CGFloat = GlassMetrics.circle,
                     interactive: Bool = true) -> some View {
        frame(width: size, height: size)
            .contentShape(Circle())
            .glassSurface(tint, in: Circle(), interactive: interactive)
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
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if let tint = tint {
                content.glassEffect(LiquidGlass.tinted(tint, interactive: interactive), in: shape)
            } else {
                // 普通玻璃再透一档：Glass.clear 已是 iOS 26 最透的一档，索性不铺玻璃，
                // 只留一圈 1pt 描边，背后的内容整块透出来，靠边框和文字辨认。
                content.overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            }
        } else {
            // 回退：几乎不放底色，材质压到 0.3，靠更明显的 1pt 边框认形状。
            content
                .background(tint ?? Color.white.opacity(0.03), in: shape)
                .background { shape.fill(.ultraThinMaterial).opacity(tint == nil ? 0.30 : 1) }
                .overlay(shape.strokeBorder(Color.primary.opacity(tint == nil ? 0.20 : 0.10), lineWidth: 1))
        }
    }
}

/// Builds the tinted `Glass` value in one place: `Glass.tint` takes a non-optional color,
/// so the tint has to be applied conditionally.
@available(iOS 26, *)
private enum LiquidGlass {
    static func tinted(_ tint: Color, interactive: Bool) -> Glass {
        var glass: Glass = .regular.tint(tint)
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// A card of content on a glass surface.
struct GlassCard<Content: View>: View {
    private let tint: Color?
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let content: Content

    init(tint: Color? = nil, cornerRadius: CGFloat = 22, padding: CGFloat = 16,
         @ViewBuilder content: () -> Content) {
        self.tint = tint
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
        .glassSurface(tint, cornerRadius: cornerRadius)
    }
}

/// A form-like group: an optional title, a glass card of rows, and a footer.
struct GlassSection<Content: View, Footer: View>: View {
    private let title: String?
    private let tint: Color?
    private let content: Content
    private let footer: Footer

    init(_ title: String? = nil, tint: Color? = nil,
         @ViewBuilder content: () -> Content,
         @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.tint = tint
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
            GlassCard(tint: tint, padding: 0) { content }
            footer
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

extension GlassSection where Footer == EmptyView {
    init(_ title: String? = nil, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, tint: tint, content: content, footer: { EmptyView() })
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

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

/// The leading SF Symbol of a settings row.
///
/// One fixed column width keeps every title on the same baseline, and the symbol stays
/// `.secondary`: icons say what a row is, they never add a colour of their own.
struct GlassRowIcon: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: 22)
    }
}
