import SwiftUI

struct DMSInputView: View {
    @Binding var coordinateString: String
    let isLatitude: Bool
    let label: String

    @State private var degrees: String = ""
    @State private var minutes: String = ""
    @State private var seconds: String = ""
    @State private var direction: String = ""

    private var directions: [String] {
        isLatitude ? ["N", "S"] : ["E", "W"]
    }

    private var maxDegrees: Int { isLatitude ? 90 : 180 }

    private var degreesError: Bool {
        guard let d = Int(degrees) else { return !degrees.isEmpty }
        return d < 0 || d > maxDegrees
    }

    private var minutesError: Bool {
        guard let m = Int(minutes) else { return !minutes.isEmpty }
        return m < 0 || m > 59
    }

    private var secondsError: Bool {
        guard let s = Double(seconds) else { return !seconds.isEmpty }
        return s < 0 || s >= 60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                TextField("0", text: $degrees)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)
                    .foregroundStyle(degreesError ? .red : .primary)
                    .onChange(of: degrees) { updateString() }
                Text("°")
                    .foregroundStyle(.secondary)

                TextField("0", text: $minutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 36)
                    .foregroundStyle(minutesError ? .red : .primary)
                    .onChange(of: minutes) { updateString() }
                Text("'")
                    .foregroundStyle(.secondary)

                TextField("0.0", text: $seconds)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                    .foregroundStyle(secondsError ? .red : .primary)
                    .onChange(of: seconds) { updateString() }
                Text("\"")
                    .foregroundStyle(.secondary)

                Picker("", selection: $direction) {
                    ForEach(directions, id: \.self) { d in
                        Text(d).tag(d)
                    }
                }
                .frame(width: 56)
                .onChange(of: direction) { updateString() }
            }
            .font(.system(.callout, design: .monospaced))

            if degreesError || minutesError || secondsError {
                Text(validationHint)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .onAppear { parseFromString() }
        .onChange(of: coordinateString) {
            // Only re-parse if the external string changed (e.g. map tap)
            let currentBuilt = buildDMSString()
            if coordinateString != currentBuilt {
                parseFromString()
            }
        }
    }

    private func parseFromString() {
        // Try to parse as a Double first (DD format), then as DMS
        if let value = CoordinateFormat.parse(coordinateString, isLatitude: isLatitude) {
            let absolute = abs(value)
            let d = Int(absolute)
            let minutesDecimal = (absolute - Double(d)) * 60
            let m = Int(minutesDecimal)
            let s = (minutesDecimal - Double(m)) * 60

            degrees = "\(d)"
            minutes = "\(m)"
            seconds = String(format: "%.1f", s)

            if isLatitude {
                direction = value >= 0 ? "N" : "S"
            } else {
                direction = value >= 0 ? "E" : "W"
            }
        } else {
            degrees = ""
            minutes = ""
            seconds = ""
            direction = isLatitude ? "N" : "E"
        }
    }

    private func buildDMSString() -> String {
        let d = degrees.isEmpty ? "0" : degrees
        let m = minutes.isEmpty ? "0" : minutes
        let s = seconds.isEmpty ? "0.0" : seconds
        let dir = direction.isEmpty ? (isLatitude ? "N" : "E") : direction
        return "\(d)° \(m)' \(s)\" \(dir)"
    }

    private func updateString() {
        coordinateString = buildDMSString()
    }

    private var validationHint: String {
        if degreesError { return "Degrees: 0–\(maxDegrees)" }
        if minutesError { return "Minutes: 0–59" }
        if secondsError { return "Seconds: 0–59.9" }
        return ""
    }
}
