import SwiftUI
import UIKit
import TeliaCore

/// Central design tokens. One source of truth for color, spacing, radius, and motion.
///
/// DS 2.0 (Update 1.2): premium two-tone language — warm off-white canvas with
/// charcoal surfaces in dark mode, floating cards with hairline borders and
/// soft depth, restrained purple + tasteful orange accents, large rounded
/// typography.
enum DS {

    // MARK: - Color

    /// Telia-inspired purple ramp — restrained, not neon.
    enum Purple {
        static let light = Color(red: 0.55, green: 0.35, blue: 0.92)   // #8C59EB
        static let base = Color(red: 0.46, green: 0.22, blue: 0.86)    // #7538DB
        static let deep = Color(red: 0.33, green: 0.13, blue: 0.66)    // #5421A8
        static let ink = Color(red: 0.22, green: 0.08, blue: 0.42)     // #38146B
    }

    /// Warm highlight ramp — used sparingly for emphasis and status.
    enum Orange {
        static let light = Color(red: 1.00, green: 0.72, blue: 0.50)   // #FFB880
        static let base = Color(red: 0.95, green: 0.45, blue: 0.18)    // #F2732E
        static let deep = Color(red: 0.76, green: 0.31, blue: 0.09)    // #C24F17
    }

    /// Adaptive surfaces: warm off-white in light mode, charcoal in dark mode.
    /// Built on UIKit dynamic colors so every SwiftUI consumer adapts
    /// automatically without environment plumbing.
    enum Surface {

        /// The page canvas behind all content.
        static let canvas = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.086, green: 0.086, blue: 0.110, alpha: 1)   // #16161C
                : UIColor(red: 0.965, green: 0.949, blue: 0.929, alpha: 1)   // #F6F2ED
        })

        /// Primary floating card surface.
        static let card = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.125, green: 0.122, blue: 0.157, alpha: 1)   // #201F28
                : UIColor.white
        })

        /// Inset/secondary surface inside cards (stats, input fields, rows).
        static let inset = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.165, green: 0.161, blue: 0.200, alpha: 1)   // #2A2933
                : UIColor(red: 0.937, green: 0.918, blue: 0.886, alpha: 1)   // #EFEAE2
        })

        /// Hairline border that gives cards their refined edge.
        static let hairline = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.09)
                : UIColor(white: 0.0, alpha: 0.07)
        })

        /// Fixed dark surface for hero cards — always pairs with white text.
        static let heroGradient = LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.15, blue: 0.21),   // charcoal
                Color(red: 0.25, green: 0.14, blue: 0.44),   // deep purple blend
                Color(red: 0.18, green: 0.09, blue: 0.30),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        /// Subtle purple tint used for gradient cards (primary text stays readable).
        static let tintGradient = LinearGradient(
            colors: [Purple.light.opacity(0.16), Purple.deep.opacity(0.10)],
            startPoint: .top, endPoint: .bottom
        )
    }

    static let accent = Color("AccentColor", bundle: nil)

    static let heroGradient = LinearGradient(
        colors: [Purple.base, Purple.deep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let softGradient = LinearGradient(
        colors: [Purple.light.opacity(0.16), Purple.deep.opacity(0.10)],
        startPoint: .top, endPoint: .bottom
    )

    /// Purple→orange highlight gradient for special moments only.
    static let sunsetGradient = LinearGradient(
        colors: [Orange.base, Purple.base],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Semantic — adapt to dark mode automatically through system materials.
    static let positive = Color.green
    static let warning = Orange.base
    static let negative = Color.red

    // MARK: - Typography
    // All styles use text styles so Dynamic Type scales naturally.

    enum Typo {
        static let display = SwiftUI.Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let title = SwiftUI.Font.system(.title2, design: .rounded).weight(.bold)
        static let titleSmall = SwiftUI.Font.system(.headline, design: .rounded)
        static let body = SwiftUI.Font.system(.body, design: .rounded)
        static let bodyEmphasis = SwiftUI.Font.system(.body, design: .rounded).weight(.medium)
        static let caption = SwiftUI.Font.system(.caption, design: .rounded)
    }

    // MARK: - Spacing & radius

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 22
        static let hero: CGFloat = 26
        static let chip: CGFloat = 999
        static let tile: CGFloat = 16
    }

    // MARK: - Motion
    // Durations are context-appropriate, never one-size-fits-all.

    enum Motion {
        static let tap: TimeInterval = 0.12
        static let reveal: TimeInterval = 0.22
        static let content: TimeInterval = 0.3
        static let stagger: TimeInterval = 0.04

        /// Use for staggered entrances; respects Reduce Motion.
        static func entrance(_ reduceMotion: Bool, index: Int) -> Animation? {
            guard !reduceMotion else { return nil }
            return .spring(response: 0.4, dampingFraction: 0.85)
            .delay(Double(min(index, 8)) * stagger)
        }
    }
}

// MARK: - Card container

/// The app's signature surface (DS 2.0): adaptive floating card with a
/// hairline border and one soft, static shadow. No expensive effects.
struct CardBackground: ViewModifier {
    var padding: CGFloat = DS.Space.l
    var gradient: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(gradient ? AnyShapeStyle(DS.Surface.tintGradient) : AnyShapeStyle(DS.Surface.card))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.Surface.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 14, y: 6)
    }
}

/// Premium hero surface: fixed dark charcoal→purple gradient with a warm
/// orange corner glow. Content must use white/off-white text.
struct HeroBackground: ViewModifier {
    var padding: CGFloat = DS.Space.l

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous)
                    .fill(DS.Surface.heroGradient)
            )
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DS.Orange.light.opacity(0.16), .clear],
                            startPoint: .topTrailing, endPoint: .center
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: DS.Purple.ink.opacity(0.35), radius: 18, y: 8)
    }
}

extension View {
    func card(gradient: Bool = false, padding: CGFloat = DS.Space.l) -> some View {
        modifier(CardBackground(padding: padding, gradient: gradient))
    }

    /// Premium dark hero card — always pair with white foreground text.
    func heroCard(padding: CGFloat = DS.Space.l) -> some View {
        modifier(HeroBackground(padding: padding))
    }
}

// MARK: - Card header

struct CardHeader: View {
    let title: String
    var symbol: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(DS.Purple.base)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DS.Purple.base.opacity(0.12))
                    )
            }
            Text(title)
                .font(DS.Typo.titleSmall)
                .kerning(-0.2)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(DS.Purple.base)
            }
        }
    }
}

// MARK: - Chips & badges

struct Chip: View {
    let text: String
    var color: Color = DS.Purple.base
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.14)))
            )
            .foregroundStyle(filled ? Color.white : color)
    }
}

struct VerificationBadge: View {
    let status: VerificationStatus
    var freshness: PriceVerification.Freshness

    private var color: Color {
        switch status {
        case .verified:
            switch freshness {
            case .fresh: return .green
            case .aging: return .orange
            case .stale: return .red
            case .unknown: return .gray
            }
        case .unverified: return .orange
        case .expired: return .red
        case .imported: return .blue
        }
    }

    private var label: String {
        switch status {
        case .verified: return freshness == .fresh ? "Verifierat" : freshness.label
        case .unverified: return "Overifierat"
        case .expired: return "Utgånget"
        case .imported: return "Importerat"
        }
    }

    var body: some View {
        Chip(text: label, color: color)
    }
}

struct CampaignBadge: View {
    let status: PriceVerification.CampaignStatus

    var body: some View {
        if status == .activeCampaign || status == .endsSoon {
            Chip(text: status.label, color: .pink)
        }
    }
}

// MARK: - Price text

struct PriceText: View {
    let monthly: Double?
    var ordinary: Double? = nil
    var large: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Format.monthly(monthly))
                .font(.system(large ? .title2 : .body, design: .rounded).weight(.bold))
                .foregroundStyle(monthly == nil ? Color.secondary : Color.primary)
            if let ordinary, let monthly, ordinary > monthly {
                Text(Format.monthly(ordinary))
                    .font(.system(large ? .subheadline : .caption, design: .rounded))
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Progress

struct ProgressBar: View {
    let progress: Double
    var color: Color = DS.Purple.base
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(Text("Framsteg"))
        .accessibilityValue(Text("\(Int(progress * 100)) procent"))
    }
}

struct RingGauge: View {
    let progress: Double
    let title: String
    let detail: String
    var color: Color = DS.Purple.base

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int((progress).rounded(.down) * 100))%")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                }
            }
            .frame(width: 92, height: 92)
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .lineLimit(1)
            Text(detail)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(detail)")
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let value: String
    let label: String
    var symbol: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(DS.Purple.base)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.m)
        .padding(.horizontal, DS.Space.s)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .fill(DS.Surface.inset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .strokeBorder(DS.Surface.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Hero stats

/// Compact circular stat used inside hero cards. Renders light text for the
/// fixed dark hero surface.
struct HeroStat: View {
    let value: String
    let label: String
    var symbol: String
    var tint: Color = DS.Orange.light

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s + 2)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty & error states

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DS.Purple.base.opacity(0.7))
                .padding(.bottom, 4)
            Text(title)
                .font(.system(.headline, design: .rounded))
            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.s + 2)
                        .background(Capsule().fill(DS.Purple.base))
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressableStyle())
                .padding(.top, DS.Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xl)
        .card()
    }
}

struct ErrorStateView: View {
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        EmptyStateView(
            symbol: "wifi.exclamationmark",
            title: title,
            message: message,
            actionTitle: retry == nil ? nil : "Försök igen",
            action: retry
        )
    }
}

// MARK: - Loading shimmer (disabled under Reduce Motion)

struct ShimmerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay(
                GeometryReader { geo in
                    if !reduceMotion {
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.35), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width)
                        .onAppear {
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                                phase = 1.4
                            }
                        }
                    }
                }
            )
            .clipped()
    }
}

struct LoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            ShimmerView().frame(height: 20).frame(maxWidth: 160)
            ShimmerView().frame(height: 14)
            ShimmerView().frame(height: 14).frame(maxWidth: 220)
        }
        .card()
    }
}

// MARK: - Section container

struct SectionCard<Content: View>: View {
    let title: String
    var symbol: String?
    var gradient: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            CardHeader(title: title, symbol: symbol)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(gradient: gradient)
    }
}
