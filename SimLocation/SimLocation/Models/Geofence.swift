import Foundation

struct Geofence: Identifiable, Codable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double // meters

    init(name: String, latitude: Double, longitude: Double, radius: Double) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
    }
}
