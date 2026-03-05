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
                    DMSInputView(coordinateString: $viewModel.singleLongitude, isLatitude: false, label: "Longitude")
                }
                .padding(.horizontal)
            } else {
                Form {
                    TextField("Latitude", text: $viewModel.singleLatitude)
                    TextField("Longitude", text: $viewModel.singleLongitude)
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
