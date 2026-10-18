import Foundation

// MARK: - Background preference (Core, platform-independent)

/// The user's chosen app background. Lives in Core so it is testable on
/// Linux; the app layer renders it via `BackgroundSurface`.
public struct BackgroundPreference: Codable, Hashable, Sendable {

    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// The app's default gradient background.
        case systemDefault
        /// One of the built-in preset gradients.
        case preset
        /// A solid color chosen by the user.
        case solid
        /// A photo imported from the user's own photo library (local only).
        case photo
    }

    /// How a photo is fitted to the screen.
    public enum PhotoFit: String, Codable, CaseIterable, Sendable {
        case fill
        case fit
    }

    public var kind: Kind
    /// Identifier of the preset when `kind == .preset`.
    public var presetID: String?
    /// Hex color like "4A38BF" when `kind == .solid`.
    public var hex: String?
    /// File name inside the app's Backgrounds directory when `kind == .photo`.
    public var fileName: String?
    /// Background blur, 0...1. Applied cheaply (static material), never as a
    /// live full-screen expensive blur.
    public var blur: Double
    /// Background intensity/opacity, 0...1 — lowers toward the default color
    /// to keep text readable.
    public var intensity: Double
    /// Extra dark dimming overlay for photos, 0...1. Guarantees card and text
    /// contrast on bright or busy wallpapers.
    public var dimming: Double
    /// Fill (crop to edges) or Fit (letterbox) for photo backgrounds.
    public var photoFit: PhotoFit

    public init(
        kind: Kind = .systemDefault,
        presetID: String? = nil,
        hex: String? = nil,
        fileName: String? = nil,
        blur: Double = 0,
        intensity: Double = 1,
        dimming: Double = 0.2,
        photoFit: PhotoFit = .fill
    ) {
        self.kind = kind
        self.presetID = presetID
        self.hex = hex
        self.fileName = fileName
        self.blur = blur
        self.intensity = intensity
        self.dimming = dimming
        self.photoFit = photoFit
    }

    private enum CodingKeys: String, CodingKey {
        case kind, presetID, hex, fileName, blur, intensity, dimming, photoFit
    }

    /// Tolerant decoding: a preference written by an older version — or one
    /// with a corrupt individual field — decodes with defaults for the bad
    /// fields instead of failing (and wiping the user's choice) wholesale.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .systemDefault
        presetID = (try? c.decodeIfPresent(String.self, forKey: .presetID))
        hex = (try? c.decodeIfPresent(String.self, forKey: .hex))
        fileName = (try? c.decodeIfPresent(String.self, forKey: .fileName))
        blur = ((try? c.decodeIfPresent(Double.self, forKey: .blur)) ?? 0).clampedToUnit()
        intensity = ((try? c.decodeIfPresent(Double.self, forKey: .intensity)) ?? 1).clampedToUnit()
        dimming = ((try? c.decodeIfPresent(Double.self, forKey: .dimming)) ?? 0.2).clampedToUnit()
        photoFit = (try? c.decodeIfPresent(PhotoFit.self, forKey: .photoFit)) ?? .fill
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(presetID, forKey: .presetID)
        try c.encodeIfPresent(hex, forKey: .hex)
        try c.encodeIfPresent(fileName, forKey: .fileName)
        try c.encode(blur, forKey: .blur)
        try c.encode(intensity, forKey: .intensity)
        try c.encode(dimming, forKey: .dimming)
        try c.encode(photoFit, forKey: .photoFit)
    }

    public static let `default` = BackgroundPreference()

    public var isDefault: Bool { kind == .systemDefault }
}

extension Double {
    /// Clamp into 0...1 for user-controlled sliders.
    public func clampedToUnit() -> Double { Swift.min(1, Swift.max(0, self)) }
}

// MARK: - Preset definitions (rendered by the app layer)

/// Built-in background presets. Colors are hex strings so Core stays free of
/// platform frameworks.
public enum BackgroundPresets {

    public struct Preset: Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        /// Two or three hex colors forming a soft gradient.
        public let colors: [String]
        /// true when the preset is designed to sit behind light text.
        public let dark: Bool

        public init(id: String, name: String, colors: [String], dark: Bool) {
            self.id = id
            self.name = name
            self.colors = colors
            self.dark = dark
        }
    }

    public static let all: [Preset] = [
        // DS 2.0 originals
        Preset(id: "telia-purple", name: "Telia lila",
               colors: ["2D1B69", "6C38C4", "17123B"], dark: true),
        Preset(id: "deep-midnight", name: "Midnatt",
               colors: ["0B1026", "1B2A4A", "05070F"], dark: true),
        Preset(id: "graphite", name: "Grafit",
               colors: ["1C1C22", "2E2E38", "121216"], dark: true),
        Preset(id: "soft-neutral", name: "Mjuk natur",
               colors: ["E8E4DC", "D6CFC2", "C9C0AF"], dark: false),
        Preset(id: "ocean-blue", name: "Havsblå",
               colors: ["0E3A5D", "16607F", "082741"], dark: true),
        Preset(id: "warm-sunset", name: "Varm solnedgång",
               colors: ["3D1E43", "8C3B4E", "241236"], dark: true),
        Preset(id: "minimal-light", name: "Minimal ljus",
               colors: ["F4F2F7", "EAE6F0", "FFFFFF"], dark: false),
        Preset(id: "dark-premium", name: "Mörk premium",
               colors: ["141019", "241A38", "0B0810"], dark: true),
        // DS 2.2 (Update 1.3) — studio additions
        Preset(id: "midnight-graphite", name: "Midnattsgrafit",
               colors: ["16181D", "262B33", "0D0F13"], dark: true),
        Preset(id: "deep-charcoal", name: "Djup kol",
               colors: ["1A1A1E", "32323A", "101014"], dark: true),
        Preset(id: "warm-neutral", name: "Varm neutral",
               colors: ["F1EBE2", "E4DACB", "F8F5EF"], dark: false),
        Preset(id: "soft-silver", name: "Mjukt silver",
               colors: ["D9DDE3", "C3C9D2", "EDEFF3"], dark: false),
        Preset(id: "telia-orange", name: "Telia orange",
               colors: ["3A1F14", "8A4A24", "2A150D"], dark: true),
        Preset(id: "elegant-fade", name: "Mörk till ljus",
               colors: ["23222B", "6B6675", "E8E5EC"], dark: true),
    ]

    public static let ids: Set<String> = Set(all.map(\.id))

    public static func preset(id: String) -> Preset? {
        all.first { $0.id == id }
    }
}
