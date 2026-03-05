import SwiftUI

struct WaypointRow: View {
    let index: Int
    let waypoint: Waypoint
    var coordinateFormat: CoordinateFormat = .decimalDegrees
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text("\(index).")
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Text(CoordinateFormat.format(lat: waypoint.latitude, lon: waypoint.longitude, as: coordinateFormat))
                .font(.system(.body, design: .monospaced))

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }
}
