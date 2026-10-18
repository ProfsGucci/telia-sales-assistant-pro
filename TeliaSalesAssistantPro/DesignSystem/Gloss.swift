import SwiftUI

// MARK: - Gloss system (DS 2.3, Update 1.4) — VISIBLE gloss
//
// 1.3's gloss was real code but visually imperceptible. Diagnosis (see
// docs/DEBUG-REPORT-1.4.md): white overlays at 0.12–0.16 opacity on a WHITE
// card are invisible (white over white); on dark cards they were a faint
// haze. Real gloss reads through CONTRAST: a bright band with a crisp
// falloff edge, a lit rim, and a base that isn't already pure white.
//
// 1.4 therefore reworks the optics:
// - Light surfaces get a tinted glass base (white → faint lavender) so
//   white highlights have something to contrast against.
// - The sheen is a pronounced top band with a HARD falloff edge (the
//   "light line" the eye catches), not a smooth invisible fade.
// - The sweep runs at visible opacity (0.26–0.32) with a wide soft band.
// - SectionCards are glossed by default (static — cheap); only hero cards
//   animate (battery/restraint), and never under Reduce Motion.
//
// Principles kept from 1.3: no blend modes, no per-frame TimelineView, iOS
// 16 APIs only, sweep off with Reduce Motion, text sits above the sheen.

// MARK: Level

enum GlossLevel {
    /// Plain DS 2.0 card — no gloss.
    case none
    /// Static glass: tinted base + bright top band + lit rim + depth.
    case subtle
    /// Subtle plus a slow diagonal reflection sweep (Reduce Motion → subtle).
    case animated
}

// MARK: Adaptive optics

/// Contrast values tuned per color scheme so highlights are actually VISIBLE.
struct GlossOptics {
    let sheenTop: Double
    let edgeTop: Double
    let sweepIntensity: Double
    let sweepTint: Color

    static func forScheme(_ scheme: ColorScheme, hero: Bool = false) -> GlossOptics {
        if hero {
            return GlossOptics(
                sheenTop: scheme == .dark ? 0.34 : 0.30,
                edgeTop: scheme == .dark ? 0.55 : 0.45,
                sweepIntensity: scheme == .dark ? 0.24 : 0.22,
                sweepTint: DS.Orange.light.opacity(0.5)
            )
        }
        return GlossOptics(
            sheenTop: scheme == .dark ? 0.32 : 0.55,
            edgeTop: scheme == .dark ? 0.50 : 0.65,
            sweepIntensity: scheme == .dark ? 0.26 : 0.30,
            sweepTint: DS.Purple.light.opacity(0.45)
        )
    }
}

// MARK: Specular sheen (static, the visible "glass catch light")

/// A bright top band with a CRISP falloff edge at ~22% height. The hard stop
/// is what makes it read as gloss — smooth fades vanish, edges don't.
/// Static, so it doubles as the Reduce Motion alternative.
struct GlossSheen: View {
    var cornerRadius: CGFloat
    var optics: GlossOptics

    var body: some View {
        ZStack {
            // The specular band itself.
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(optics.sheenTop), location: 0),
                    .init(color: Color.white.opacity(optics.sheenTop * 0.9), location: 0.08),
                    .init(color: Color.white.opacity(optics.sheenTop * 0.30), location: 0.20),
                    .init(color: .clear, location: 0.36),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Bottom depth: faint darkening that gives the surface thickness.
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.07), location: 0),
                    .init(color: .clear, location: 0.18),
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }
}

// MARK: Reflection sweep (animated)

/// A single soft, WIDE band of light that slowly travels across the card.
/// Visible: 0.22–0.30 opacity with a white core and tinted fringes.
struct GlossSweep: View {
    var cornerRadius: CGFloat
    var optics: GlossOptics
    var period: TimeInterval = 8

    /// Stripe travel, from off-left to off-right.
    @State private var travel: CGFloat = -0.7

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: optics.sweepTint.opacity(optics.sweepIntensity * 0.35), location: 0.2),
                    .init(color: Color.white.opacity(optics.sweepIntensity), location: 0.5),
                    .init(color: optics.sweepTint.opacity(optics.sweepIntensity * 0.35), location: 0.8),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: max(90, width * 0.45))
            .rotationEffect(.degrees(-20))
            .offset(x: travel * width)
            .frame(width: width, height: geo.size.height, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                travel = 1.7
            }
        }
    }
}

// MARK: Edge light (the lit rim)

/// A vertical gradient stroke — bright along the top edge, fading out —
/// at 1.5 pt. Pronounced enough to see over dark photo backgrounds.
struct GlossEdge: View {
    var cornerRadius: CGFloat
    var optics: GlossOptics

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(optics.edgeTop), location: 0),
                        .init(color: Color.white.opacity(optics.edgeTop * 0.35), location: 0.4),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.5
            )
            .allowsHitTesting(false)
    }
}

// MARK: Glossy card modifier

/// Glossy glass card (DS 2.3). Use INSTEAD of `.card()`: same padding
/// contract, visibly glossy treatment. Static layers render under the
/// content (no text wash); the sweep passes over the whole surface.
struct GlossBackground: ViewModifier {
    var level: GlossLevel
    var tinted: Bool = false
    var cornerRadius: CGFloat = DS.Radius.card
    var padding: CGFloat = DS.Space.l

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let optics = GlossOptics.forScheme(scheme)
        content
            .padding(padding)
            .background(
                ZStack {
                    shape.fill(baseFill)
                    // Sheen sits UNDER the content: glass, not fog over text.
                    GlossSheen(cornerRadius: cornerRadius, optics: optics)
                }
                .clipShape(shape)
            )
            .overlay(
                Group {
                    if level == .animated && !reduceMotion {
                        GlossSweep(cornerRadius: cornerRadius, optics: optics)
                    }
                }
            )
            .overlay(GlossEdge(cornerRadius: cornerRadius, optics: optics))
            .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
    }

    /// Light surfaces get a tinted glass base (white → faint lavender) so
    /// the white sheen has contrast. Dark surfaces keep the charcoal card.
    private var baseFill: some ShapeStyle {
        if tinted {
            return AnyShapeStyle(DS.Surface.tintGradient)
        }
        if scheme == .light {
            return AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color.white, location: 0),
                        .init(color: Color(red: 0.955, green: 0.935, blue: 0.985), location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(DS.Surface.card)
    }
}

// MARK: Hero gloss (dark translucent hero cards)

/// The hero treatment: DS 2.0 hero gradient + warm corner glow + bright top
/// band + slow warm sweep (Reduce Motion aware) + lit rim + orange accent.
struct HeroGlossBackground: ViewModifier {
    var padding: CGFloat = DS.Space.l

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous)
        let optics = GlossOptics.forScheme(scheme, hero: true)
        content
            .padding(padding)
            .background(
                ZStack {
                    shape.fill(DS.Surface.heroGradient)
                    // Warm orange catch light in the top-trailing corner.
                    shape.fill(
                        LinearGradient(
                            colors: [DS.Orange.light.opacity(0.20), .clear],
                            startPoint: .topTrailing,
                            endPoint: .center
                        )
                    )
                    // Bright glass band along the top — under the text.
                    GlossSheen(cornerRadius: DS.Radius.hero, optics: optics)
                }
                .clipShape(shape)
            )
            .overlay(
                Group {
                    if !reduceMotion {
                        GlossSweep(
                            cornerRadius: DS.Radius.hero,
                            optics: optics,
                            period: 9
                        )
                    }
                }
            )
            .overlay(GlossEdge(cornerRadius: DS.Radius.hero, optics: optics))
            .overlay(
                // Restrained orange accent along the leading edge.
                shape.trim(from: 0.08, to: 0.42)
                    .stroke(DS.Orange.base.opacity(0.65), lineWidth: 1.5)
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
                            : [Color.primary.opacity(0.10), Color.primary.opacity(0.10)],
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
    /// Glossy glass card surface (DS 2.3). See `GlossLevel` for guidance.
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
