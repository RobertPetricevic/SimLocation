import XCTest
@testable import SimLocation

final class PresetServiceTests: XCTestCase {

    // MARK: - Preset Model

    func testPresetInitialization() {
        let preset = Preset(name: "Home", mode: .single(latitude: 45.0, longitude: -93.0))
        XCTAssertEqual(preset.name, "Home")
        XCTAssertFalse(preset.id.uuidString.isEmpty)
    }

    func testPresetSingleModeCodable() throws {
        let original = Preset(name: "Office", mode: .single(latitude: 40.7128, longitude: -74.0060))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        if case .single(let lat, let lon) = decoded.mode {
            XCTAssertEqual(lat, 40.7128)
            XCTAssertEqual(lon, -74.0060)
        } else {
            XCTFail("Expected single mode")
        }
    }

    func testPresetRouteModeCodable() throws {
        let waypoints = [
            Waypoint(latitude: 40.0, longitude: -74.0),
            Waypoint(latitude: 41.0, longitude: -75.0),
        ]
        let original = Preset(name: "Commute", mode: .route(waypoints: waypoints, speed: 13.0))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)

        XCTAssertEqual(decoded.name, "Commute")
        if case .route(let wps, let speed, let routing) = decoded.mode {
            XCTAssertEqual(wps.count, 2)
            XCTAssertEqual(speed, 13.0)
            XCTAssertEqual(routing, .straightLine)
            XCTAssertEqual(wps[0].latitude, 40.0)
            XCTAssertEqual(wps[1].longitude, -75.0)
        } else {
            XCTFail("Expected route mode")
        }
    }

    func testPresetArrayCodable() throws {
        let presets = [
            Preset(name: "A", mode: .single(latitude: 1.0, longitude: 2.0)),
            Preset(name: "B", mode: .single(latitude: 3.0, longitude: 4.0)),
        ]

        let data = try JSONEncoder().encode(presets)
        let decoded = try JSONDecoder().decode([Preset].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "A")
        XCTAssertEqual(decoded[1].name, "B")
    }

    // MARK: - Waypoint Model

    func testWaypointCodable() throws {
        let original = Waypoint(latitude: 51.5074, longitude: -0.1278)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Waypoint.self, from: data)

        XCTAssertEqual(decoded.latitude, original.latitude)
        XCTAssertEqual(decoded.longitude, original.longitude)
        XCTAssertEqual(decoded.id, original.id)
    }

    func testWaypointUniqueIDs() {
        let a = Waypoint(latitude: 0, longitude: 0)
        let b = Waypoint(latitude: 0, longitude: 0)
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - Simulator Model

    func testSimulatorDisplayNameIOS() {
        let sim = Simulator(
            id: "ABC-123",
            name: "iPhone 15",
            runtime: "com.apple.CoreSimulator.SimRuntime.iOS-17-2",
            platform: .ios
        )
        XCTAssertEqual(sim.displayName, "iPhone 15 — iOS 17 2")
    }

    func testSimulatorDisplayNameAndroid() {
        let sim = Simulator(
            id: "emulator-5554",
            name: "Pixel_7",
            runtime: "14",
            platform: .android
        )
        XCTAssertEqual(sim.displayName, "Pixel_7 — Android 14")
    }

    // MARK: - SpeedPreset

    func testSpeedPresetValues() {
        XCTAssertEqual(SpeedPreset.walk.metersPerSecond, 1.4)
        XCTAssertEqual(SpeedPreset.run.metersPerSecond, 3.0)
        XCTAssertEqual(SpeedPreset.bicycle.metersPerSecond, 5.5)
        XCTAssertEqual(SpeedPreset.drive.metersPerSecond, 13.0)
        XCTAssertEqual(SpeedPreset.highway.metersPerSecond, 30.0)
        XCTAssertNil(SpeedPreset.custom.metersPerSecond)
    }

    func testSpeedPresetLabels() {
        XCTAssertEqual(SpeedPreset.walk.label, "Walk (1.4 m/s)")
        XCTAssertEqual(SpeedPreset.custom.label, "Custom")
    }
}
