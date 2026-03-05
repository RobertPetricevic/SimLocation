import Foundation

enum RoutingMode: String, CaseIterable, Identifiable, Codable {
    case straightLine = "Straight Line"
    case followRoads = "Follow Roads"

    var id: String { rawValue }
}
