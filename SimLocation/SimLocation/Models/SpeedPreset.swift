import Foundation

enum SpeedPreset: String, CaseIterable, Identifiable {
    case walk = "Walk"
    case run = "Run"
    case bicycle = "Bicycle"
    case drive = "Drive"
    case highway = "Highway"
    case custom = "Custom"

    var id: String { rawValue }

    var metersPerSecond: Double? {
        switch self {
        case .walk: return 1.4
        case .run: return 3.0
        case .bicycle: return 5.5
        case .drive: return 13.0
        case .highway: return 30.0
        case .custom: return nil
        }
    }

    var label: String {
        if let speed = metersPerSecond {
            return "\(rawValue) (\(speed) m/s)"
        }
        return rawValue
    }
}
