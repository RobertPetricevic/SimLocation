import Foundation

enum LocationMode: String, CaseIterable, Identifiable {
    case single = "Single"
    case route = "Route"
    case scenario = "Scenario"

    var id: String { rawValue }
}
