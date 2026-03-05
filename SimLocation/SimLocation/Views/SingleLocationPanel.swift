import SwiftUI

struct SingleLocationPanel: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Click the map to set a location, or enter coordinates manually.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if viewModel.coordinateFormat == .dms {
                VStack(spacing: 8) {
                    DMSInputView(coordinateString: $viewModel.singleLatitude, isLatitude: true, label: "Latitude")
                    if let error = viewModel.singleLatitudeError {
                        Text(error).font(.caption2).foregroundStyle(.red).padding(.leading)
                    }
                    DMSInputView(coordinateString: $viewModel.singleLongitude, isLatitude: false, label: "Longitude")
                    if let error = viewModel.singleLongitudeError {
                        Text(error).font(.caption2).foregroundStyle(.red).padding(.leading)
                    }
                }
                .padding(.horizontal)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Form {
                        TextField("Latitude", text: $viewModel.singleLatitude)
                        TextField("Longitude", text: $viewModel.singleLongitude)
                    }
                    if let error = viewModel.singleLatitudeError {
                        Text(error).font(.caption2).foregroundStyle(.red)
                    }
                    if let error = viewModel.singleLongitudeError {
                        Text(error).font(.caption2).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)
            }

            Button("Set Location") {
                Task { await viewModel.setLocation() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                viewModel.selectedSimulator == nil
                || viewModel.isLoading
                || viewModel.parseCoordinate(viewModel.singleLatitude, isLatitude: true) == nil
                || viewModel.parseCoordinate(viewModel.singleLongitude, isLatitude: false) == nil
            )
            .padding(.horizontal)
        }
    }
}
