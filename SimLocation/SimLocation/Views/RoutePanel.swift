import SwiftUI

struct RoutePanel: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Click the map to add waypoints.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            // Waypoint list
            if viewModel.waypoints.isEmpty {
                Text("No waypoints yet")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                List {
                    ForEach(Array(viewModel.waypoints.enumerated()), id: \.element.id) { index, wp in
                        WaypointRow(index: index + 1, waypoint: wp, coordinateFormat: viewModel.coordinateFormat) {
                            viewModel.removeWaypoint(wp)
                        }
                    }
                    .onMove { source, destination in
                        viewModel.waypoints.move(fromOffsets: source, toOffset: destination)
                        viewModel.invalidateRoadRoute()
                    }
                }
                .frame(minHeight: 100, maxHeight: 250)
            }

            // Routing mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Routing")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Routing", selection: $viewModel.routingMode) {
                    ForEach(RoutingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: viewModel.routingMode) {
                    viewModel.invalidateRoadRoute()
                }

                if viewModel.isCalculatingRoute {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Calculating road route...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let warning = viewModel.routeWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if viewModel.routingMode == .followRoads,
                   let coords = viewModel.resolvedRouteCoordinates {
                    Text("\(coords.count) route points calculated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            // Speed controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Speed")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Speed", selection: $viewModel.selectedSpeedPreset) {
                    ForEach(SpeedPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .labelsHidden()

                if viewModel.selectedSpeedPreset == .custom {
                    HStack {
                        TextField("m/s", text: $viewModel.customSpeed)
                            .frame(width: 80)
                        Text("m/s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Interval:")
                        .font(.caption)
                    TextField("seconds", text: $viewModel.routeInterval)
                        .frame(width: 60)
                    Text("s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            // Action buttons
            HStack {
                Button("Start Route") {
                    Task { await viewModel.startRoute() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.waypoints.count < 2
                    || viewModel.selectedSimulator == nil
                    || viewModel.isLoading
                    || viewModel.isCalculatingRoute
                )

                Button("Clear All") {
                    viewModel.clearWaypoints()
                }
                .disabled(viewModel.waypoints.isEmpty)
            }
            .padding(.horizontal)
        }
    }
}
