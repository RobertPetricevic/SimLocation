import Foundation

struct LocationConfig: Codable {
    var type: String
    var name: String?
    var latitude: Double?
    var longitude: Double?
    var waypoints: [WaypointConfig]?
    var speed: Double?
    var routingMode: String?

    struct WaypointConfig: Codable {
        var latitude: Double
        var longitude: Double
    }

    func toPreset() -> Preset? {
        let presetName = name ?? "Imported"
        switch type {
        case "single":
            guard let lat = latitude, let lng = longitude else { return nil }
            return Preset(name: presetName, mode: .single(latitude: lat, longitude: lng))
        case "route":
            guard let wps = waypoints, wps.count >= 2 else { return nil }
            let waypointModels = wps.map { Waypoint(latitude: $0.latitude, longitude: $0.longitude) }
            let spd = speed ?? 13.0
            let routing: RoutingMode = routingMode == "followRoads" ? .followRoads : .straightLine
            return Preset(name: presetName, mode: .route(waypoints: waypointModels, speed: spd, routingMode: routing))
        default:
            return nil
        }
    }

    static func from(preset: Preset) -> LocationConfig {
        switch preset.mode {
        case .single(let lat, let lng):
            return LocationConfig(
                type: "single",
                name: preset.name,
                latitude: lat,
                longitude: lng
            )
        case .route(let waypoints, let speed, let routing):
            return LocationConfig(
                type: "route",
                name: preset.name,
                waypoints: waypoints.map { WaypointConfig(latitude: $0.latitude, longitude: $0.longitude) },
                speed: speed,
                routingMode: routing == .followRoads ? "followRoads" : "straightLine"
            )
        }
    }

    static func decodeConfigs(from data: Data) throws -> [LocationConfig] {
        let decoder = JSONDecoder()
        // Try array first, then single object
        if let configs = try? decoder.decode([LocationConfig].self, from: data) {
            return configs
        }
        let single = try decoder.decode(LocationConfig.self, from: data)
        return [single]
    }
}
