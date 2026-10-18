import SwiftUI
import TeliaCore

// MARK: - Pressable style

/// Subtle scale + opacity press feedback. Instant (no spring bounce), respects Reduce Motion.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.linear(duration: DS.Motion.tap), value: configuration.isPressed)
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
    let action: () -> Void

    var body: some View {
        Button {
            if !loading { action() }
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
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                    .fill(loading ? AnyShapeStyle(DS.Purple.base.opacity(0.6)) : AnyShapeStyle(DS.heroGradient))
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle())
        .disabled(loading)
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
        Button(action: action) {
            Image(systemName: active ? "heart.fill" : "heart")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(active ? .pink : Color.secondary)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: active)
        }
        .buttonStyle(PressableStyle(scale: 0.8))
        .accessibilityLabel(active ? "Ta bort från favoriter" : "Lägg till i favoriter")
    }
}
