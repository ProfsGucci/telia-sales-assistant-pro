import XCTest
@testable import TeliaCore

final class BackgroundPreferenceTests: XCTestCase {

    func testDefaultIsSystemDefault() {
        let p = BackgroundPreference.default
        XCTAssertEqual(p.kind, .systemDefault)
        XCTAssertTrue(p.isDefault)
        XCTAssertEqual(p.blur, 0)
        XCTAssertEqual(p.intensity, 1)
        XCTAssertEqual(p.dimming, 0.2, "Default photo dimming keeps text readable")
        XCTAssertEqual(p.photoFit, .fill)
    }

    func testRoundTripCoding() throws {
        let p = BackgroundPreference(kind: .preset, presetID: "telia-purple",
                                     blur: 0.3, intensity: 0.8)
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(BackgroundPreference.self, from: data)
        XCTAssertEqual(decoded, p)
    }

    func testRoundTripCodingPhotoWithFitAndDimming() throws {
        // DS 2.2: full photo preference incl. the new fields survives a save.
        let p = BackgroundPreference(kind: .photo, fileName: "bg-123.jpg",
                                     blur: 0.25, intensity: 0.9,
                                     dimming: 0.45, photoFit: .fit)
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(BackgroundPreference.self, from: data)
        XCTAssertEqual(decoded, p)
        XCTAssertEqual(decoded.photoFit, .fit)
        XCTAssertEqual(decoded.dimming, 0.45)
    }

    func testDecodingLegacyJSONWithoutNewFields() throws {
        // Simulates data written before blur/intensity existed.
        let json = """
        {"kind":"solid","hex":"4A38BF"}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(BackgroundPreference.self, from: json)
        XCTAssertEqual(p.kind, .solid)
        XCTAssertEqual(p.hex, "4A38BF")
        XCTAssertEqual(p.blur, 0, "Missing blur must default, not fail")
        XCTAssertEqual(p.intensity, 1, "Missing intensity must default, not fail")
        XCTAssertEqual(p.photoFit, .fill, "1.2-era photo preference must default fit, not fail")
        XCTAssertEqual(p.dimming, 0.2, "1.2-era photo preference must default dimming, not fail")
    }

    func testDecodingLegacyPhotoPreferenceKeepsFileName() throws {
        // Written by 1.2 (no dimming/photoFit keys) — must not be wiped.
        let json = """
        {"kind":"photo","fileName":"bg-legacy.jpg","blur":0.1,"intensity":1}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(BackgroundPreference.self, from: json)
        XCTAssertEqual(p.kind, .photo)
        XCTAssertEqual(p.fileName, "bg-legacy.jpg")
        XCTAssertEqual(p.dimming, 0.2)
        XCTAssertEqual(p.photoFit, .fill)
    }

    func testDecodingEmptyObjectGivesDefault() throws {
        let json = "{}".data(using: .utf8)!
        let p = try JSONDecoder().decode(BackgroundPreference.self, from: json)
        XCTAssertEqual(p, BackgroundPreference.default)
    }

    func testOutOfRangeValuesAreClamped() throws {
        let json = """
        {"kind":"photo","fileName":"bg.jpg","blur":1.7,"intensity":-0.4}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(BackgroundPreference.self, from: json)
        XCTAssertEqual(p.blur, 1)
        XCTAssertEqual(p.intensity, 0)
    }

    func testDimmingIsClamped() throws {
        let json = """
        {"kind":"photo","fileName":"bg.jpg","dimming":2.5}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(BackgroundPreference.self, from: json)
        XCTAssertEqual(p.dimming, 1)
        let json2 = """
        {"kind":"photo","fileName":"bg.jpg","dimming":-3}
        """.data(using: .utf8)!
        let p2 = try JSONDecoder().decode(BackgroundPreference.self, from: json2)
        XCTAssertEqual(p2.dimming, 0)
    }

    func testCorruptIndividualFieldFallsBackInsteadOfFailing() throws {
        // Root-cause regression test for the 1.x "backgrounds reset" bug:
        // one corrupt field (blur is a string here) must not throw the whole
        // preference away — the rest survives with defaults for bad fields.
        let json = """
        {"kind":"preset","presetID":"graphite","blur":"oeps","intensity":0.6}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(BackgroundPreference.self, from: json)
        XCTAssertEqual(p.kind, .preset)
        XCTAssertEqual(p.presetID, "graphite")
        XCTAssertEqual(p.blur, 0, "Corrupt blur falls back to default")
        XCTAssertEqual(p.intensity, 0.6, "Valid fields keep their values")
    }

    func testCorruptKindKeepsDecodeableSiblings() throws {
        let json = """
        {"kind":42,"hex":"2E2E38","dimming":0.3}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(BackgroundPreference.self, from: json)
        XCTAssertEqual(p.kind, .systemDefault, "Corrupt kind falls back to default")
        XCTAssertEqual(p.hex, "2E2E38")
        XCTAssertEqual(p.dimming, 0.3)
    }

    func testPresetCatalogIsWellFormed() {
        XCTAssertEqual(BackgroundPresets.all.count, 14, "8 originals + 6 DS 2.2 additions")
        XCTAssertEqual(BackgroundPresets.all.count, BackgroundPresets.ids.count, "Preset IDs must be unique")
        for preset in BackgroundPresets.all {
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertGreaterThanOrEqual(preset.colors.count, 2, "\(preset.id) needs a gradient")
            XCTAssertLessThanOrEqual(preset.colors.count, 3)
            for hex in preset.colors {
                XCTAssertEqual(hex.count, 6, "\(preset.id) has malformed hex \(hex)")
                XCTAssertTrue(hex.allSatisfy { $0.isHexDigit }, "\(hex) is not hex")
            }
        }
        // Original 8 IDs are stable API — saved preferences must keep working.
        for id in ["telia-purple", "deep-midnight", "graphite", "soft-neutral",
                   "ocean-blue", "warm-sunset", "minimal-light", "dark-premium"] {
            XCTAssertNotNil(BackgroundPresets.preset(id: id), "Legacy preset \(id) must survive")
        }
    }

    func testNewDS22PresetsExist() {
        // Update 1.3 studio additions.
        for id in ["midnight-graphite", "deep-charcoal", "warm-neutral",
                   "soft-silver", "telia-orange", "elegant-fade"] {
            let preset = BackgroundPresets.preset(id: id)
            XCTAssertNotNil(preset, "DS 2.2 preset \(id) must exist")
            if let preset {
                XCTAssertEqual(preset.colors.count, 3)
            }
        }
        // The dark-to-light fade must stay flagged dark so light mode keeps
        // its canvas scrim for readability.
        XCTAssertEqual(BackgroundPresets.preset(id: "elegant-fade")?.dark, true)
    }
}
