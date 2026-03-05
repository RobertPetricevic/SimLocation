import XCTest
@testable import SimLocation

final class CoordinateFormatTests: XCTestCase {

    // MARK: - Parsing Decimal Degrees

    func testParseDecimalDegreesLatitude() {
        XCTAssertEqual(CoordinateFormat.parse("45.5", isLatitude: true), 45.5)
        XCTAssertEqual(CoordinateFormat.parse("-33.8688", isLatitude: true), -33.8688)
        XCTAssertEqual(CoordinateFormat.parse("0", isLatitude: true), 0)
    }

    func testParseDecimalDegreesLongitude() {
        XCTAssertEqual(CoordinateFormat.parse("151.2093", isLatitude: false), 151.2093)
        XCTAssertEqual(CoordinateFormat.parse("-122.4194", isLatitude: false), -122.4194)
        XCTAssertEqual(CoordinateFormat.parse("180", isLatitude: false), 180.0)
        XCTAssertEqual(CoordinateFormat.parse("-180", isLatitude: false), -180.0)
    }

    // MARK: - Range Validation

    func testLatitudeOutOfRange() {
        XCTAssertNil(CoordinateFormat.parse("91", isLatitude: true))
        XCTAssertNil(CoordinateFormat.parse("-91", isLatitude: true))
    }

    func testLongitudeOutOfRange() {
        XCTAssertNil(CoordinateFormat.parse("181", isLatitude: false))
        XCTAssertNil(CoordinateFormat.parse("-181", isLatitude: false))
    }

    func testBoundaryValues() {
        XCTAssertEqual(CoordinateFormat.parse("90", isLatitude: true), 90.0)
        XCTAssertEqual(CoordinateFormat.parse("-90", isLatitude: true), -90.0)
        XCTAssertEqual(CoordinateFormat.parse("180", isLatitude: false), 180.0)
        XCTAssertEqual(CoordinateFormat.parse("-180", isLatitude: false), -180.0)
    }

    // MARK: - Parsing DMS

    func testParseDMSWithSpaces() {
        let result = CoordinateFormat.parse("40° 42' 46.1\" N", isLatitude: true)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 40.71280555, accuracy: 0.0001)
    }

    func testParseDMSSouth() {
        let result = CoordinateFormat.parse("33° 52' 10.0\" S", isLatitude: true)
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!, 0)
        XCTAssertEqual(result!, -33.86944444, accuracy: 0.0001)
    }

    func testParseDMSWest() {
        let result = CoordinateFormat.parse("122° 25' 9.9\" W", isLatitude: false)
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!, 0)
        XCTAssertEqual(result!, -122.41941667, accuracy: 0.001)
    }

    func testParseDMSEast() {
        let result = CoordinateFormat.parse("151° 12' 33.5\" E", isLatitude: false)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!, 0)
        XCTAssertEqual(result!, 151.20930556, accuracy: 0.001)
    }

    func testParseDMSCompact() {
        // No spaces between parts
        let result = CoordinateFormat.parse("40°42'46.1\"N", isLatitude: true)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 40.71280555, accuracy: 0.0001)
    }

    func testParseDMSDegreesOnly() {
        let result = CoordinateFormat.parse("45° N", isLatitude: true)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 45.0, accuracy: 0.0001)
    }

    func testParseDMSDegreesAndMinutes() {
        let result = CoordinateFormat.parse("45° 30' N", isLatitude: true)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 45.5, accuracy: 0.0001)
    }

    // MARK: - Invalid Input

    func testParseEmptyString() {
        XCTAssertNil(CoordinateFormat.parse("", isLatitude: true))
    }

    func testParseWhitespaceOnly() {
        XCTAssertNil(CoordinateFormat.parse("   ", isLatitude: true))
    }

    func testParseGarbage() {
        XCTAssertNil(CoordinateFormat.parse("not a coordinate", isLatitude: true))
    }

    // MARK: - Formatting

    func testFormatDecimalDegreesPair() {
        let result = CoordinateFormat.format(lat: 40.7128, lon: -74.0060, as: .decimalDegrees)
        XCTAssertEqual(result, "40.7128, -74.0060")
    }

    func testFormatDMSPair() {
        let result = CoordinateFormat.format(lat: 45.0, lon: -90.0, as: .dms)
        XCTAssertTrue(result.contains("N"))
        XCTAssertTrue(result.contains("W"))
    }

    func testFormatSingleDecimalDegrees() {
        let result = CoordinateFormat.formatSingle(45.123456, isLatitude: true, as: .decimalDegrees)
        XCTAssertEqual(result, "45.123456")
    }

    func testFormatSingleDMS() {
        let result = CoordinateFormat.formatSingle(45.5, isLatitude: true, as: .dms)
        XCTAssertTrue(result.contains("45°"))
        XCTAssertTrue(result.contains("30'"))
        XCTAssertTrue(result.contains("N"))
    }

    func testFormatSingleNegativeLongitude() {
        let result = CoordinateFormat.formatSingle(-122.4194, isLatitude: false, as: .dms)
        XCTAssertTrue(result.contains("W"))
    }

    // MARK: - Roundtrip

    func testRoundtripDMS() {
        let original = 40.712806
        let formatted = CoordinateFormat.formatSingle(original, isLatitude: true, as: .dms)
        let parsed = CoordinateFormat.parse(formatted, isLatitude: true)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!, original, accuracy: 0.0001)
    }

    func testRoundtripDecimalDegrees() {
        let original = -33.868800
        let formatted = CoordinateFormat.formatSingle(original, isLatitude: true, as: .decimalDegrees)
        let parsed = CoordinateFormat.parse(formatted, isLatitude: true)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!, original, accuracy: 0.0001)
    }
}
