import SwiftUI
import UIKit
import TeliaCore

// MARK: - Hex color helper

extension Color {
    /// Parses "RRGGBB" (with or without '#') into a Color. Returns nil on malformed input.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6,
              let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

// MARK: - Background layer

/// Renders the user's background preference behind the whole app.
///
/// Design constraints (see docs/DEBUG-REPORT-1.1.md):
/// - Static rendering only: no animated gradients, no live full-screen blur
///   pipelines. The photo blur uses a capped static `.blur` and the layer is
///   never re-rendered per frame.
/// - Readability: content sits in opaque material cards; the background's
///   `intensity` dims it toward the system background, and light presets
///   always render under a dark-mode-safe scrim in dark mode.
/// - Local only: photos are read from the app's own Documents directory.
struct BackgroundLayer: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var preference: BackgroundPreference { settings.data.background }

    var body: some View {
        ZStack {
            Color(.systemBackground)
            content
                .opacity(preference.intensity)
            // Light artwork needs a scrim in dark mode so pale areas don't
            // wash out; dark artwork needs one in light mode.
            if needsScrim {
                Color(.systemBackground)
                    .opacity(0.35)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: preference)
        .accessibilityHidden(true)
    }

    private var needsScrim: Bool {
        switch preference.kind {
        case .systemDefault:
            return false
        case .preset:
            guard let preset = BackgroundPresets.preset(id: preference.presetID ?? "") else { return false }
            return preset.dark != (colorScheme == .dark)
        case .solid:
            guard let color = Color(hex: preference.hex ?? "") else { return false }
            return colorScheme == .dark ? isLightColor(color) : !isLightColor(color)
        case .photo:
            return true // Unknown artwork: guarantee a readable floor.
        }
    }

    private func isLightColor(_ color: Color) -> Bool {
        // Cheap luminance check on the underlying components.
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
    }

    @ViewBuilder
    private var content: some View {
        switch preference.kind {
        case .systemDefault:
            // The app's default look: a restrained purple tint, close to 1.0.
            LinearGradient(
                colors: [DS.Purple.light.opacity(0.10), DS.Purple.deep.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .preset:
            if let preset = BackgroundPresets.preset(id: preference.presetID ?? "") {
                gradient(for: preset.colors)
            } else {
                LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
            }
        case .solid:
            if let color = Color(hex: preference.hex ?? "") {
                color
            } else {
                LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
            }
        case .photo:
            photoLayer
        }
    }

    private func gradient(for hexes: [String]) -> some View {
        let colors = hexes.compactMap { Color(hex: $0) }
        return LinearGradient(
            colors: colors.count >= 2 ? colors : [.clear],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var photoLayer: some View {
        if let fileName = preference.fileName,
           let image = BackgroundStore.loadPhoto(fileName: fileName) {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .blur(radius: preference.blur * 20) // capped, static
        } else {
            // Missing/corrupt file: fall back to default instead of stretching anything.
            LinearGradient(
                colors: [DS.Purple.light.opacity(0.10), DS.Purple.deep.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}
