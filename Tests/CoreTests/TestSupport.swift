import XCTest
@testable import TeliaCore

/// Single-overload replacement for `XCTAssertEqual(_, _, accuracy:)`.
///
/// Apple's Swift type-checker can time out resolving XCTAssertEqual's large
/// `accuracy:` overload family when expectations are integer-literal
/// arithmetic (`299 * 12`). One concrete signature keeps checking fast on
/// both Linux and Apple toolchains.
func assertClose(
    _ value: Double,
    _ expected: Double,
    accuracy: Double = 0.01,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(value, expected, accuracy: accuracy, file: file, line: line)
}
