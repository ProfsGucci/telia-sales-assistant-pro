import XCTest
@testable import TeliaCore

final class BackgroundPreferenceTests: XCTestCase {

    func testDefaultIsSystemDefault() {
        let p = BackgroundPreference.default
        XCTAssertEqual(p.kind, .systemDefault)
        XCTAssertTrue(p.isDefault)
        XCTAssertEqual(p.blur, 0)
        XCTAssertEqual(p.intensity, 1)
    }

    func testRoundTripCoding() throws {
        let p = BackgroundPreference(kind: .preset, presetID: "telia-purple",
                                     blur: 0.3, intensity: 0.8)
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(BackgroundPreference.self, from: data)
        XCTAssertEqual(decoded, p)
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

    func testPresetCatalogIsWellFormed() {
        XCTAssertGreaterThanOrEqual(BackgroundPresets.all.count, 8)
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
        XCTAssertNotNil(BackgroundPresets.preset(id: "telia-purple"))
        XCTAssertNotNil(BackgroundPresets.preset(id: "deep-midnight"))
        XCTAssertNotNil(BackgroundPresets.preset(id: "graphite"))
        XCTAssertNotNil(BackgroundPresets.preset(id: "soft-neutral"))
        XCTAssertNotNil(BackgroundPresets.preset(id: "ocean-blue"))
        XCTAssertNotNil(BackgroundPresets.preset(id: "warm-sunset"))
        XCTAssertNotNil(BackgroundPresets.preset(id: "minimal-light"))
        XCTAssertNotNil(BackgroundPresets.preset(id: "dark-premium"))
    }
}
