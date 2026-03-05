import SwiftUI

struct GeofencePanel: View {
    @Bindable var viewModel: AppViewModel
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isAddingGeofence {
                    geofenceForm(
                        hint: "Click the map or enter coordinates",
                        onConfirm: { viewModel.confirmAddGeofence() },
                        onCancel: {
                            viewModel.isAddingGeofence = false
                            viewModel.pendingGeofenceLatitude = ""
                            viewModel.pendingGeofenceLongitude = ""
                        }
                    )
                } else {
                    Button {
                        viewModel.pendingGeofenceName = "Geofence \(viewModel.geofences.count + 1)"
                        viewModel.pendingGeofenceRadius = "100"
                        viewModel.pendingGeofenceLatitude = ""
                        viewModel.pendingGeofenceLongitude = ""
                        viewModel.isAddingGeofence = true
                    } label: {
                        Label("Add Geofence", systemImage: "circle.dashed")
                            .font(.callout)
                    }
                }

                ForEach(viewModel.geofences) { geofence in
                    if viewModel.editingGeofenceID == geofence.id {
                        geofenceForm(
                            hint: "Click the map or edit coordinates",
                            onConfirm: { viewModel.saveEditingGeofence() },
                            onCancel: { viewModel.cancelEditingGeofence() }
                        )
                    } else {
                        geofenceRow(geofence)
                    }
                }
            }
        } label: {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                Text("Geofences")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    private func geofenceForm(hint: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Name", text: $viewModel.pendingGeofenceName)
                .textFieldStyle(.roundedBorder)
                .font(.callout)

            if viewModel.coordinateFormat == .dms {
                DMSInputView(coordinateString: $viewModel.pendingGeofenceLatitude, isLatitude: true, label: "Latitude")
                DMSInputView(coordinateString: $viewModel.pendingGeofenceLongitude, isLatitude: false, label: "Longitude")
            } else {
                HStack(spacing: 6) {
                    TextField("Latitude", text: $viewModel.pendingGeofenceLatitude)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)

                    TextField("Longitude", text: $viewModel.pendingGeofenceLongitude)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                }
            }

            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Radius (m)", text: $viewModel.pendingGeofenceRadius)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .frame(width: 80)
                    if !viewModel.isGeofenceRadiusValid {
                        Text("Must be > 0")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .disabled(
                    viewModel.parseCoordinate(viewModel.pendingGeofenceLatitude, isLatitude: true) == nil ||
                    viewModel.parseCoordinate(viewModel.pendingGeofenceLongitude, isLatitude: false) == nil ||
                    !viewModel.isGeofenceRadiusValid
                )
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private func geofenceRow(_ geofence: Geofence) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isInsideGeofence(geofence) ? Color.green.opacity(0.6) : Color.blue.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(geofence.name)
                    .font(.callout)
                Text("\(Int(geofence.radius))m — \(CoordinateFormat.format(lat: geofence.latitude, lon: geofence.longitude, as: viewModel.coordinateFormat))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.startEditingGeofence(geofence)
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.deleteGeofence(geofence)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
