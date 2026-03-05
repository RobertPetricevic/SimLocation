import Foundation

struct Waypoint: Identifiable, Codable {
    let id: UUID
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.id = UUID()
        self.latitude = latitude
        self.longitude = longitude
    }
}
