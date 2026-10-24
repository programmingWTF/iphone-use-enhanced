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

extension View {
    /// A rounded Liquid Glass surface behind the view.
    ///
    /// iOS 26: `glassEffect(.clear/.regular[.tint(tint)][.interactive()], in: …)`.
    /// Plain surfaces take the clear variant, because regular reads as a grey slab and a
    /// plain surface should be a film you recognise by its rim; tinted ones stay regular
    /// so their colour keeps its weight.
    /// Before iOS 26: a barely-there fill and the thinnest material, held by a 1pt edge,
    /// so the fallback stays translucent instead of turning into flat grey.
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

    /// A round toolbar button whose tint rides the system's own glass.
    ///
    /// The toolbar draws glass behind its items on iOS 26, so a `glassEffect` behind the
    /// item stacked a second, grey surface under the tint — glass inside glass. Sending
    /// the tint through the button style leaves exactly one layer. Before iOS 26 nothing
    /// draws a surface there, so the tinted pill is it.
    @ViewBuilder
    func glassToolbarButton(_ tint: Color) -> some View {
        if #available(iOS 26, *) {
            buttonBorderShape(.circle)
                .buttonStyle(.haptic(.glassProminent))
                .tint(tint)
        } else {
            buttonStyle(.haptic(.plain))
                .glassPill(tint, interactive: true)
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

    private var isPlain: Bool { tint == nil }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(LiquidGlass.make(tint: tint, interactive: interactive), in: shape)
        } else {
            // Plain: almost nothing inside, so the 1pt edge is what defines the surface.
            // Tinted: the colour and a full material keep the accent solid.
            content
                .background(tint ?? Color.white.opacity(0.04), in: shape)
                .background { shape.fill(.ultraThinMaterial).opacity(isPlain ? 0.55 : 1) }
                .overlay(shape.strokeBorder(Color.primary.opacity(isPlain ? 0.18 : 0.10), lineWidth: 1))
        }
    }
}

/// Builds the `Glass` value in one place: `Glass.tint` takes a non-optional color,
/// so the tint has to be applied conditionally.
@available(iOS 26, *)
private enum LiquidGlass {
    static func make(tint: Color?, interactive: Bool) -> Glass {
        var glass: Glass = tint == nil ? .clear : .regular
        if let tint { glass = glass.tint(tint) }
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
