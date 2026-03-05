import Foundation

enum CoordinateFormat: String, CaseIterable {
    case decimalDegrees = "dd"
    case dms = "dms"

    var label: String {
        switch self {
        case .decimalDegrees: return "DD"
        case .dms: return "DMS"
        }
    }

    // MARK: - Formatting (pair)

    static func format(lat: Double, lon: Double, as format: CoordinateFormat) -> String {
        switch format {
        case .decimalDegrees:
            return String(format: "%.4f, %.4f", lat, lon)
        case .dms:
            return "\(toDMS(lat, isLatitude: true)), \(toDMS(lon, isLatitude: false))"
        }
    }

    // MARK: - Formatting (single value for input fields)

    static func formatSingle(_ value: Double, isLatitude: Bool, as format: CoordinateFormat) -> String {
        switch format {
        case .decimalDegrees:
            return String(format: "%.6f", value)
        case .dms:
            return toDMS(value, isLatitude: isLatitude)
        }
    }

    // MARK: - Parsing (handles both DD and DMS)

    /// Parses a coordinate string in either decimal degrees or DMS format.
    /// Returns nil if the string cannot be parsed.
    static func parse(_ string: String, isLatitude: Bool) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }

        let value: Double?

        // Try decimal degrees first
        if let dd = Double(trimmed) {
            value = dd
        } else {
            // Try DMS: e.g. "40° 42' 46.1\" N" or "40°42'46.1\"N"
            value = parseDMS(trimmed, isLatitude: isLatitude)
        }

        // Validate range
        guard let result = value else { return nil }
        let limit = isLatitude ? 90.0 : 180.0
        guard abs(result) <= limit else { return nil }
        return result
    }

    // MARK: - Private

    private static func toDMS(_ value: Double, isLatitude: Bool) -> String {
        let absolute = abs(value)
        let degrees = Int(absolute)
        let minutesDecimal = (absolute - Double(degrees)) * 60
        let minutes = Int(minutesDecimal)
        let seconds = (minutesDecimal - Double(minutes)) * 60

        let direction: String
        if isLatitude {
            direction = value >= 0 ? "N" : "S"
        } else {
            direction = value >= 0 ? "E" : "W"
        }

        return String(format: "%d° %d' %.1f\" %@", degrees, minutes, seconds, direction)
    }

    private static func parseDMS(_ string: String, isLatitude: Bool) -> Double? {
        // Normalize: replace common separators
        var s = string
        s = s.replacingOccurrences(of: "°", with: " ")
        s = s.replacingOccurrences(of: "'", with: " ")
        s = s.replacingOccurrences(of: "'", with: " ")
        s = s.replacingOccurrences(of: "\"", with: " ")
        s = s.replacingOccurrences(of: "″", with: " ")
        s = s.replacingOccurrences(of: "′", with: " ")

        let upper = s.uppercased()
        var negative = false

        // Check for direction letter
        if upper.contains("S") || upper.contains("W") {
            negative = true
        }
        // Remove direction letters
        s = upper
            .replacingOccurrences(of: "N", with: " ")
            .replacingOccurrences(of: "S", with: " ")
            .replacingOccurrences(of: "E", with: " ")
            .replacingOccurrences(of: "W", with: " ")

        // Split into numeric components
        let parts = s.split(whereSeparator: { $0.isWhitespace }).compactMap { Double($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }

        let degrees = parts[0]
        let minutes = parts.count > 1 ? parts[1] : 0
        let seconds = parts.count > 2 ? parts[2] : 0

        var result = degrees + minutes / 60.0 + seconds / 3600.0
        if negative { result = -result }
        return result
    }
}
