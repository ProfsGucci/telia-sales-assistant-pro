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

// MARK: - Shared background rendering
// Single source of truth for HOW a background preference is rendered.
// Used by the app-wide BackgroundLayer AND by the Background Studio preview,
// so what the user previews is exactly what gets applied (DS 2.2 root-cause
// fix for preview/actual mismatches).

struct BackgroundSurface: View {
    let preference: BackgroundPreference

    var body: some View {
        ZStack {
            DS.Surface.canvas
            content
                .opacity(preference.intensity)
            contrastTreatment
        }
        .accessibilityHidden(true)
    }

    // MARK: Content layer

    @ViewBuilder
    private var content: some View {
        switch preference.kind {
        case .systemDefault:
            // The app's default look: a restrained purple tint, close to 1.x.
            LinearGradient(
                colors: [DS.Purple.light.opacity(0.10), DS.Purple.deep.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .preset:
            if let preset = BackgroundPresets.preset(id: preference.presetID ?? "") {
                gradient(for: preset.colors)
            } else {
                // Unknown preset id (e.g. removed in a future version):
                // fall back to the default instead of a blank layer.
                LinearGradient(
                    colors: [DS.Purple.light.opacity(0.10), DS.Purple.deep.opacity(0.06)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        case .solid:
            if let color = Color(hex: preference.hex ?? "") {
                color
            } else {
                LinearGradient(
                    colors: [DS.Purple.light.opacity(0.10), DS.Purple.deep.opacity(0.06)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
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
                let fitted = preference.photoFit == .fit
                    ? image.size.aspectFit(geo.size)
                    : image.size.aspectFill(geo.size)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .clipped()
            .blur(radius: preference.blur * 20) // capped, static
        } else {
            // Missing/corrupt file: fall back to default instead of breaking.
            LinearGradient(
                colors: [DS.Purple.light.opacity(0.10), DS.Purple.deep.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    // MARK: Contrast treatment
    // Photos: user-controlled black dimming (default 0.2) guarantees card and
    // text contrast on bright AND dark wallpapers — a black scrim works in
    // both appearances, unlike the old canvas-colored scrim that washed out
    // dark photos in light mode.
    // Presets/solids: a light scrim only when the artwork's brightness
    // mismatches the current color scheme.

    @ViewBuilder
    private var contrastTreatment: some View {
        switch preference.kind {
        case .photo:
            Color.black
                .opacity(preference.dimming)
        case .preset, .solid:
            if needsSchemeScrim {
                DS.Surface.canvas
                    .opacity(0.35)
            }
        case .systemDefault:
            EmptyView()
        }
    }

    private var needsSchemeScrim: Bool {
        switch preference.kind {
        case .systemDefault:
            return false
        case .preset:
            guard let preset = BackgroundPresets.preset(id: preference.presetID ?? "") else { return false }
            return colorScheme == .dark ? !preset.dark : preset.dark
        case .solid:
            guard let color = Color(hex: preference.hex ?? "") else { return false }
            return colorScheme == .dark ? !isDarkColor(color) : isDarkColor(color)
        case .photo:
            return false // handled by the black dimming layer above
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private func isDarkColor(_ color: Color) -> Bool {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) <= 0.5
    }
}

private extension CGSize {
    func aspectFit(_ size: CGSize) -> CGSize {
        let scale = min(size.width / width, size.height / height)
        return CGSize(width: width * scale, height: height * scale)
    }

    func aspectFill(_ size: CGSize) -> CGSize {
        let scale = max(size.width / width, size.height / height)
        return CGSize(width: width * scale, height: height * scale)
    }
}

// MARK: - App-wide background layer

/// Renders the user's background preference behind the whole app.
///
/// Design constraints (see docs/DEBUG-REPORT-1.3.md):
/// - Static rendering only: no animated gradients, no live full-screen blur
///   pipelines. The photo blur is capped and the decoded image is cached
///   (decoded once), so the layer costs nothing per frame beyond compositing.
/// - Readability: content sits in opaque cards; photos get user-controlled
///   dark dimming; preset/solid artwork gets a scheme-matched scrim.
/// - Local only: photos live in the app's Documents directory.
struct BackgroundLayer: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var preference: BackgroundPreference { settings.data.background }

    var body: some View {
        BackgroundSurface(preference: preference)
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: preference)
    }
}
