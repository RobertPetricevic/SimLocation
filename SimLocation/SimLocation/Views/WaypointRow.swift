import SwiftUI

struct WaypointRow: View {
    let index: Int
    let waypoint: Waypoint
    var coordinateFormat: CoordinateFormat = .decimalDegrees
    let isEditing: Bool
    @Binding var pendingLatitude: String
    @Binding var pendingLongitude: String
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if isEditing {
            editView
        } else {
            displayView
        }
    }

    private var displayView: some View {
        HStack {
            Text("\(index).")
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Text(CoordinateFormat.format(lat: waypoint.latitude, lon: waypoint.longitude, as: coordinateFormat))
                .font(.system(.body, design: .monospaced))

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    private var editView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Edit waypoint \(index)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if coordinateFormat == .dms {
                DMSInputView(coordinateString: $pendingLatitude, isLatitude: true, label: "Latitude")
                DMSInputView(coordinateString: $pendingLongitude, isLatitude: false, label: "Longitude")
            } else {
                HStack(spacing: 6) {
                    TextField("Latitude", text: $pendingLatitude)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)

                    TextField("Longitude", text: $pendingLongitude)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                }
            }

            HStack {
                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)

                Button(action: onSave) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .disabled(
                    CoordinateFormat.parse(pendingLatitude, isLatitude: true) == nil ||
                    CoordinateFormat.parse(pendingLongitude, isLatitude: false) == nil
                )
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}
