//
//  GlassStyle.swift
//  iPhoneUse
//
//  Liquid Glass on iOS 26, frosted material on iOS 17.4.
//  Restrained by design: at most two tints per screen, low opacity, so the glass
//  reads as glass and the color is only seasoning.
//

import SwiftUI

/// The tints allowed on glass. Each is a system color at low opacity, because the
/// glass supplies most of the color on iOS 26 and the material does on older systems.
enum GlassTint {
    /// Primary interaction: the composer, the main settings group.
    static let blue = Color.blue.opacity(0.22)
    /// Output and state: agent replies, the phone-connection group.
    static let teal = Color.teal.opacity(0.20)
    /// Starter prompts and the setup/reminder group.
    static let orange = Color.orange.opacity(0.18)
}

extension View {
    /// A rounded Liquid Glass surface behind the view.
    ///
    /// iOS 26: `glassEffect(.regular[.tint(tint)][.interactive()], in: .rect(cornerRadius:))`.
    /// Before: `.ultraThinMaterial` over the same low-opacity tint, plus a hairline edge,
    /// so the fallback still looks like a surface instead of flat grey.
    func glassSurface(_ tint: Color? = nil, cornerRadius: CGFloat = 22, interactive: Bool = false) -> some View {
        modifier(GlassSurface(tint: tint, cornerRadius: cornerRadius, interactive: interactive))
    }

    /// Capsule glass for pills, chips and floating round buttons.
    func glassPill(_ tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassPill(tint: tint, interactive: interactive))
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

private struct GlassSurface: ViewModifier {
    let tint: Color?
    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(LiquidGlass.make(tint: tint, interactive: interactive),
                                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(tint ?? Color.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

private struct GlassPill: ViewModifier {
    let tint: Color?
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(LiquidGlass.make(tint: tint, interactive: interactive), in: Capsule())
        } else {
            content
                .background(tint ?? Color.clear, in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

/// Builds the `Glass` value in one place: `Glass.tint` takes a non-optional color,
/// so the tint has to be applied conditionally.
@available(iOS 26, *)
private enum LiquidGlass {
    static func make(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
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
