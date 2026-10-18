import XCTest
@testable import TeliaCore

// MARK: - Personnummer validation tests
//
// Fixtures are SYNTHETIC numbers (well-known test identities like
// 811218-9876 and numbers generated to pass the Luhn check) — never real
// customer data.

final class PersonnummerTests: XCTestCase {

    // MARK: Valid forms

    func testValidTwelveDigitWithDash() {
        let n = Personnummer.validate("19811218-9876")
        XCTAssertNotNil(n)
        XCTAssertEqual(n?.digits12, "198112189876")
        XCTAssertEqual(n?.isCoordinationNumber, false)
        XCTAssertEqual(n?.masked, "19811218-****")
        XCTAssertEqual(n?.full, "19811218-9876")
    }

    func testValidTenDigitFormNormalizesToTwelve() {
        // 10-digit without century → 12-digit canonical.
        let n = Personnummer.validate("811218-9876")
        XCTAssertEqual(n?.digits12, "198112189876")
    }

    func testValidTenDigitTwentyFirstCentury() {
        // 010101-0015 is a valid checksum for a person born 2001.
        let n = Personnummer.validate("010101-0015")
        XCTAssertNotNil(n)
        XCTAssertEqual(n?.digits12, "200101010015")
    }

    func testValidWithoutSeparator() {
        XCTAssertNotNil(Personnummer.validate("19640823-3234"))
        XCTAssertNotNil(Personnummer.validate("6408233234"))
        XCTAssertNotNil(Personnummer.validate("196408233234"))
    }

    func testValidCoordinationNumber() {
        // Day 75 = coordination form of the 15th.
        let n = Personnummer.validate("19811275-9876")
        XCTAssertNotNil(n, "Samordningsnummer with valid checksum must pass")
        XCTAssertEqual(n?.isCoordinationNumber, true)
        XCTAssertEqual(n?.digits12, "198112759876")
    }

    // MARK: Invalid forms

    func testInvalidChecksumRejected() {
        // Last digit altered → checksum fails.
        XCTAssertNil(Personnummer.validate("19811218-9877"))
        XCTAssertNil(Personnummer.validate("811218-9875"))
    }

    func testInvalidDateRejected() {
        // Fixtures have VALID checksums — rejection must come from the date:
        // Feb 30, Apr 31 and month 13 do not exist.
        XCTAssertNil(Personnummer.validate("810230-1234"), "Feb 30 must be rejected")
        XCTAssertNil(Personnummer.validate("810431-1231"), "Apr 31 must be rejected")
        XCTAssertNil(Personnummer.validate("811330-1231"), "Month 13 must be rejected")
    }

    func testGarbageRejected() {
        XCTAssertNil(Personnummer.validate(""))
        XCTAssertNil(Personnummer.validate("abcdefghij"))
        XCTAssertNil(Personnummer.validate("811218-987x"))
        XCTAssertNil(Personnummer.validate("12345"))
        XCTAssertNil(Personnummer.validate("12345678901234567890"))
        XCTAssertNil(Personnummer.validate("81121A-9876"))
    }

    func testDigitsNeverModifiedSilently() {
        // An invalid checksum returns nil — it is not "fixed" to a nearby
        // valid number.
        let bad = Personnummer.validate("19811218-9870")
        XCTAssertNil(bad)
    }

    // MARK: Helpers used by other tests

    func testMaskedStringFromStoredValue() {
        XCTAssertEqual(Personnummer.maskedString("198503123211"), "19850312-****")
        XCTAssertEqual(Personnummer.fullString("198503123211"), "19850312-3211")
        // Bad stored data degrades safely.
        XCTAssertEqual(Personnummer.maskedString("not-a-number"), "••••••••")
    }

    func testSamePersonComparison() {
        XCTAssertTrue(Personnummer.isSamePerson("811218-9876", "19811218-9876"))
        XCTAssertFalse(Personnummer.isSamePerson("811218-9876", "640823-3234"))
        XCTAssertFalse(Personnummer.isSamePerson("811218-9876", "garbage"))
    }
}
