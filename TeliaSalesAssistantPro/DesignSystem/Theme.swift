import SwiftUI
import TeliaCore

/// Central design tokens. One source of truth for color, spacing, radius, and motion.
enum DS {

    // MARK: - Color

    /// Telia-inspired purple ramp — restrained, not neon.
    enum Purple {
        static let light = Color(red: 0.55, green: 0.35, blue: 0.92)   // #8C59EB
        static let base = Color(red: 0.46, green: 0.22, blue: 0.86)    // #7538DB
        static let deep = Color(red: 0.33, green: 0.13, blue: 0.66)    // #5421A8
        static let ink = Color(red: 0.22, green: 0.08, blue: 0.42)     // #38146B
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

    // Semantic — adapt to dark mode automatically through system materials.
    static let positive = Color.green
    static let warning = Color.orange
    static let negative = Color.red

    // MARK: - Spacing & radius

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 16
        static let chip: CGFloat = 999
        static let tile: CGFloat = 12
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

/// The app's signature surface: soft background, hairline stroke, gentle shadow.
struct CardBackground: ViewModifier {
    var padding: CGFloat = DS.Space.l
    var gradient: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(gradient ? AnyShapeStyle(DS.softGradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
    }
}

extension View {
    func card(gradient: Bool = false, padding: CGFloat = DS.Space.l) -> some View {
        modifier(CardBackground(padding: padding, gradient: gradient))
    }
}

// MARK: - Card header

struct CardHeader: View {
    let title: String
    var symbol: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(DS.Purple.base)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            Text(title)
                .font(.system(.headline, design: .rounded))
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
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
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
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            CardHeader(title: title, symbol: symbol)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
