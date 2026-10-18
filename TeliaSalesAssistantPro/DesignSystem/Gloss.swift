import SwiftUI

// MARK: - Gloss system (DS 2.2, Update 1.3)
//
// The app's glossy surface language, layered on top of the DS 2.0 card
// system. Principles:
//
// - RESTRAINT: gloss marks hierarchy, not decoration. `.animated` is for hero
//   cards only (Dagens fokus, Kampanj header). `.subtle` is for select
//   content cards. Everything else keeps the plain DS 2.0 card. Never a
//   rainbow, never a gaming rig — one slow, low-opacity light pass.
// - READABILITY: sheen and sweep stay well under content contrast limits;
//   text sits on solid/inset surfaces first.
// - ACCESSIBILITY: with Reduce Motion on, the animated sweep is replaced by
//   the static sheen (light without movement). The sweep also stops by itself
//   when the view leaves the hierarchy.
// - PERFORMANCE: no blend modes, no per-frame TimelineView. One repeating
//   position animation on a small gradient stripe — GPU-composited, zero
//   layout invalidation. Sheen/edges are plain static gradients.
// - iOS 16: uses only APIs available on iOS 16 (no PhaseAnimator,
//   symbolEffect or scroll transitions).

// MARK: Level

enum GlossLevel {
    /// Plain DS 2.0 card — no gloss.
    case none
    /// Static specular sheen + refined edge light + soft depth. Cheap.
    case subtle
    /// Subtle plus a slow diagonal reflection sweep (Reduce Motion → subtle).
    case animated
}

// MARK: Specular sheen (static)

/// A top-down specular highlight — the "glass catch light". Static, so it is
/// always available as the Reduce Motion alternative.
struct GlossSheen: View {
    var cornerRadius: CGFloat
    var opacity: Double = 0.16

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(opacity), location: 0),
                        .init(color: Color.white.opacity(opacity * 0.35), location: 0.28),
                        .init(color: .clear, location: 0.55),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
    }
}

// MARK: Reflection sweep (animated)

/// A single soft diagonal band of light that slowly travels across the card —
/// the "living glass" moment. Low opacity, slow period, one stripe.
struct GlossSweep: View {
    var cornerRadius: CGFloat
    var tint: Color = .white
    var intensity: Double = 0.12
    var period: TimeInterval = 9

    /// Stripe travel, from off-left to off-right.
    @State private var travel: CGFloat = -0.6

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            LinearGradient(
                colors: [.clear, tint.opacity(intensity), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: max(60, width * 0.34))
            .rotationEffect(.degrees(-22))
            .offset(x: travel * width)
            .frame(width: width, height: geo.size.height, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                travel = 1.6
            }
        }
    }
}

// MARK: Edge light

/// A vertical white gradient stroke — brighter along the top edge, fading
/// out — that gives glossy cards their lit rim. Stronger than the DS 2.0
/// hairline, which keeps card edges visible over dark photo backgrounds.
struct GlossEdge: View {
    var cornerRadius: CGFloat
    var topOpacity: Double = 0.28
    var bottomOpacity: Double = 0.06

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(topOpacity), location: 0),
                        .init(color: Color.white.opacity(bottomOpacity), location: 0.45),
                        .init(color: Color.clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }
}

// MARK: Glossy card modifier

/// Glossy translucent card surface (DS 2.2). Use INSTEAD of `.card()`:
/// same padding contract, upgraded treatment.
struct GlossBackground: ViewModifier {
    var level: GlossLevel
    var tinted: Bool = false
    var cornerRadius: CGFloat = DS.Radius.card
    var padding: CGFloat = DS.Space.l

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background(
                shape.fill(
                    tinted ? AnyShapeStyle(DS.Surface.tintGradient) : AnyShapeStyle(DS.Surface.card)
                )
            )
            .overlay(GlossSheen(cornerRadius: cornerRadius))
            .overlay(
                Group {
                    if level == .animated && !reduceMotion {
                        GlossSweep(cornerRadius: cornerRadius)
                    }
                }
            )
            .overlay(GlossEdge(cornerRadius: cornerRadius))
            .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
    }
}

// MARK: Hero gloss (dark translucent hero cards)

/// The hero treatment: DS 2.0 hero gradient + warm corner glow + sheen +
/// slow sweep (Reduce Motion aware) + lit rim with an orange accent edge.
struct HeroGlossBackground: ViewModifier {
    var padding: CGFloat = DS.Space.l

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous)
        content
            .padding(padding)
            .background(shape.fill(DS.Surface.heroGradient))
            .background(
                // Warm orange catch light in the top-trailing corner.
                shape.fill(
                    LinearGradient(
                        colors: [DS.Orange.light.opacity(0.16), .clear],
                        startPoint: .topTrailing,
                        endPoint: .center
                    )
                )
            )
            .overlay(GlossSheen(cornerRadius: DS.Radius.hero, opacity: 0.20))
            .overlay(
                Group {
                    if !reduceMotion {
                        GlossSweep(
                            cornerRadius: DS.Radius.hero,
                            tint: DS.Orange.light,
                            intensity: 0.10,
                            period: 11
                        )
                    }
                }
            )
            .overlay(GlossEdge(cornerRadius: DS.Radius.hero, topOpacity: 0.34))
            .overlay(
                // Restrained orange accent along the leading edge.
                shape.trim(from: 0.08, to: 0.42)
                    .stroke(DS.Orange.base.opacity(0.55), lineWidth: 1.5)
            )
            .shadow(color: DS.Purple.ink.opacity(0.35), radius: 18, y: 8)
    }
}

// MARK: Selection glow

/// Selected-state treatment for tiles and swatches: gradient ring + a soft
/// purple glow. Deselected keeps the quiet DS hairline.
struct GlossSelection: ViewModifier {
    var selected: Bool
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: selected
                            ? [DS.Orange.light, DS.Purple.base]
                            : [Color.primary.opacity(0.08), Color.primary.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: selected ? 2.5 : 1
                )
            )
            .shadow(
                color: selected ? DS.Purple.base.opacity(0.35) : .clear,
                radius: selected ? 8 : 0,
                y: 2
            )
            .animation(.easeInOut(duration: DS.Motion.reveal), value: selected)
    }
}

// MARK: Press feedback

/// Button press feedback with a glossy feel: slight scale + brightness lift.
struct GlossPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - View extensions

extension View {
    /// Glossy card surface (DS 2.2). See `GlossLevel` for restraint guidance.
    func gloss(
        _ level: GlossLevel = .subtle,
        tinted: Bool = false,
        cornerRadius: CGFloat = DS.Radius.card,
        padding: CGFloat = DS.Space.l
    ) -> some View {
        modifier(GlossBackground(level: level, tinted: tinted, cornerRadius: cornerRadius, padding: padding))
    }

    /// Premium glossy hero card — always pair with white foreground text.
    /// Includes the slow reflection sweep unless Reduce Motion is on.
    func heroGloss(padding: CGFloat = DS.Space.l) -> some View {
        modifier(HeroGlossBackground(padding: padding))
    }

    /// Selection ring + glow for selectable tiles and swatches.
    func glossSelection(_ selected: Bool, cornerRadius: CGFloat = 12) -> some View {
        modifier(GlossSelection(selected: selected, cornerRadius: cornerRadius))
    }
}
