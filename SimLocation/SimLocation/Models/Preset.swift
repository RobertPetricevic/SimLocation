import Foundation

struct Preset: Identifiable, Codable {
    let id: UUID
    var name: String
    var mode: PresetMode
    var createdAt: Date

    init(name: String, mode: PresetMode) {
        self.id = UUID()
        self.name = name
        self.mode = mode
        self.createdAt = Date()
    }
}

enum PresetMode: Codable {
    case single(latitude: Double, longitude: Double)
    case route(waypoints: [Waypoint], speed: Double, routingMode: RoutingMode = .straightLine)
}
