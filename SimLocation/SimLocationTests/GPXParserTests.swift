import XCTest
@testable import SimLocation

final class GPXParserTests: XCTestCase {

    // MARK: - Track Points

    func testParseTrackPoints() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <name>Morning Run</name>
            <trkseg>
              <trkpt lat="40.7128" lon="-74.0060"/>
              <trkpt lat="40.7138" lon="-74.0070"/>
              <trkpt lat="40.7148" lon="-74.0080"/>
            </trkseg>
          </trk>
        </gpx>
        """
        let result = try GPXParser.parse(data: Data(gpx.utf8))

        XCTAssertEqual(result.name, "Morning Run")
        XCTAssertEqual(result.waypoints.count, 3)
        XCTAssertEqual(result.waypoints[0].latitude, 40.7128)
        XCTAssertEqual(result.waypoints[0].longitude, -74.0060)
        XCTAssertEqual(result.waypoints[2].latitude, 40.7148)
    }

    // MARK: - Route Points

    func testParseRoutePoints() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <rte>
            <name>Bike Route</name>
            <rtept lat="51.5074" lon="-0.1278"/>
            <rtept lat="51.5080" lon="-0.1290"/>
          </rte>
        </gpx>
        """
        let result = try GPXParser.parse(data: Data(gpx.utf8))

        XCTAssertEqual(result.name, "Bike Route")
        XCTAssertEqual(result.waypoints.count, 2)
        XCTAssertEqual(result.waypoints[0].latitude, 51.5074, accuracy: 0.0001)
    }

    // MARK: - Standalone Waypoints

    func testParseStandaloneWaypoints() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <wpt lat="48.8566" lon="2.3522"/>
          <wpt lat="48.8606" lon="2.3376"/>
        </gpx>
        """
        let result = try GPXParser.parse(data: Data(gpx.utf8))

        XCTAssertNil(result.name)
        XCTAssertEqual(result.waypoints.count, 2)
        XCTAssertEqual(result.waypoints[0].latitude, 48.8566, accuracy: 0.0001)
        XCTAssertEqual(result.waypoints[1].longitude, 2.3376, accuracy: 0.0001)
    }

    // MARK: - Mixed Points

    func testParseMixedPointTypes() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <wpt lat="1.0" lon="2.0"/>
          <trk>
            <trkseg>
              <trkpt lat="3.0" lon="4.0"/>
            </trkseg>
          </trk>
          <rte>
            <rtept lat="5.0" lon="6.0"/>
          </rte>
        </gpx>
        """
        let result = try GPXParser.parse(data: Data(gpx.utf8))
        XCTAssertEqual(result.waypoints.count, 3)
    }

    // MARK: - Track Name Extraction

    func testTrackNameFromTrack() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <name>My Track</name>
            <trkseg>
              <trkpt lat="10.0" lon="20.0"/>
            </trkseg>
          </trk>
        </gpx>
        """
        let result = try GPXParser.parse(data: Data(gpx.utf8))
        XCTAssertEqual(result.name, "My Track")
    }

    func testTrackNameFromRoute() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <rte>
            <name>My Route</name>
            <rtept lat="10.0" lon="20.0"/>
          </rte>
        </gpx>
        """
        let result = try GPXParser.parse(data: Data(gpx.utf8))
        XCTAssertEqual(result.name, "My Route")
    }

    func testNoName() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <trkseg>
              <trkpt lat="10.0" lon="20.0"/>
            </trkseg>
          </trk>
        </gpx>
        """
        let result = try GPXParser.parse(data: Data(gpx.utf8))
        XCTAssertNil(result.name)
    }

    // MARK: - Error Cases

    func testInvalidXMLThrows() {
        let data = Data("this is not xml".utf8)
        XCTAssertThrowsError(try GPXParser.parse(data: data)) { error in
            XCTAssertTrue(error is GPXParser.GPXError)
        }
    }

    func testEmptyGPXThrowsNoPoints() {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
        </gpx>
        """
        XCTAssertThrowsError(try GPXParser.parse(data: Data(gpx.utf8))) { error in
            guard let gpxError = error as? GPXParser.GPXError else {
                XCTFail("Expected GPXError")
                return
            }
            XCTAssertEqual(gpxError, .noPoints)
        }
    }

    func testMissingLatLonSkipsPoint() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <trkseg>
              <trkpt lat="10.0"/>
              <trkpt lat="20.0" lon="30.0"/>
            </trkseg>
          </trk>
        </gpx>
        """
        let result = try GPXParser.parse(data: Data(gpx.utf8))
        XCTAssertEqual(result.waypoints.count, 1)
        XCTAssertEqual(result.waypoints[0].latitude, 20.0)
    }

    // MARK: - Waypoint Identity

    func testWaypointsHaveUniqueIDs() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <trkseg>
              <trkpt lat="10.0" lon="20.0"/>
              <trkpt lat="30.0" lon="40.0"/>
            </trkseg>
          </trk>
        </gpx>
        """
        let result = try GPXParser.parse(data: Data(gpx.utf8))
        XCTAssertNotEqual(result.waypoints[0].id, result.waypoints[1].id)
    }
}

// Make GPXError Equatable for test assertions
extension GPXParser.GPXError: @retroactive Equatable {
    public static func == (lhs: GPXParser.GPXError, rhs: GPXParser.GPXError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidFormat, .invalidFormat): return true
        case (.noPoints, .noPoints): return true
        default: return false
        }
    }
}
