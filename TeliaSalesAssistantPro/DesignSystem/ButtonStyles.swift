import SwiftUI
import TeliaCore

// MARK: - Pressable style

/// Satisfying springy press feedback. Brief and small by design — safe for
/// motion-sensitive users (it never runs without a direct touch).
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Haptics (light, only for meaningful moments)

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Primary button

struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var loading: Bool = false
    /// Optional accent override (e.g. DS.Orange.base for highlight actions).
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button {
            if !loading { Haptics.tap(); action() }
        } label: {
            HStack(spacing: DS.Space.s) {
                if loading {
                    ProgressView()
                        .tint(.white)
                } else if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                    .fill(loading ? AnyShapeStyle(DS.Purple.base.opacity(0.6)) : AnyShapeStyle(fillStyle))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .foregroundStyle(.white)
            .shadow(color: shadowColor.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(PressableStyle())
        .disabled(loading)
    }

    private var fillStyle: some ShapeStyle {
        if let tint { return AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .top, endPoint: .bottom)) }
        return AnyShapeStyle(DS.heroGradient)
    }

    private var shadowColor: Color {
        tint ?? DS.Purple.base
    }
}

// MARK: - Secondary button

/// Quiet companion to PrimaryButton: tinted text on an inset surface with a
/// hairline border — never competes with the primary action.
struct SecondaryButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = DS.Purple.base
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                    .fill(DS.Surface.inset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                    .strokeBorder(DS.Surface.hairline, lineWidth: 1)
            )
            .foregroundStyle(tint)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Animated check toggle

struct CheckToggle: View {
    let done: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(.title3))
                .foregroundStyle(done ? DS.Purple.base : Color.secondary)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .accessibilityLabel(done ? "Avmarkera" : "Markera som klar")
    }
}

// MARK: - Favorite toggle

struct FavoriteToggle: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: active ? "star.fill" : "star")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(active ? DS.Orange.base : Color.secondary)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: active)
        }
        .buttonStyle(PressableStyle(scale: 0.8))
        .accessibilityLabel(active ? "Ta bort från favoriter" : "Lägg till i favoriter")
    }
}
