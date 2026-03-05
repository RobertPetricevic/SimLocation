import SwiftUI
import MapKit

struct ModePanel: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            // Search bar
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search location...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                            viewModel.searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)

                if !viewModel.searchResults.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.searchResults.prefix(6), id: \.self) { result in
                                Button {
                                    viewModel.selectSearchResult(result)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.callout)
                                            .foregroundStyle(.primary)
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .padding(.horizontal)
                    .padding(.top, 4)
                }
            }

            Picker("Mode", selection: $viewModel.mode) {
                ForEach(LocationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()

            switch viewModel.mode {
            case .single:
                SingleLocationPanel(viewModel: viewModel)
            case .route:
                RoutePanel(viewModel: viewModel)
            case .scenario:
                ScenarioPanel(viewModel: viewModel)
            }

            if viewModel.mode != .scenario {
                Button {
                    viewModel.showSavePresetAlert = true
                } label: {
                    Label("Save as Preset", systemImage: "star")
                }
                .padding(.horizontal)
                .disabled(
                    viewModel.mode == .single
                        ? (viewModel.parseCoordinate(viewModel.singleLatitude, isLatitude: true) == nil || viewModel.parseCoordinate(viewModel.singleLongitude, isLatitude: false) == nil)
                        : viewModel.waypoints.count < 2
                )
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.importConfigs()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

                if viewModel.mode != .scenario {
                    Button {
                        viewModel.exportCurrentConfig()
                    } label: {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                    .disabled(
                        viewModel.mode == .single
                            ? (viewModel.parseCoordinate(viewModel.singleLatitude, isLatitude: true) == nil || viewModel.parseCoordinate(viewModel.singleLongitude, isLatitude: false) == nil)
                            : viewModel.waypoints.count < 2
                    )
                }
            }
            .padding(.horizontal)

            Divider()

            GeofencePanel(viewModel: viewModel)

            if !viewModel.presets.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Presets")
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(viewModel.presets) { preset in
                                HStack {
                                    Button {
                                        viewModel.applyPreset(preset)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: presetIcon(preset))
                                                .foregroundStyle(.secondary)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(preset.name)
                                                    .font(.callout)
                                                Text(presetDetail(preset))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        viewModel.deletePreset(preset)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 12)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
            }

        }
        .padding(.top, 12)
        }

        Divider()

        // Coordinate format toggle
        Picker("Format", selection: $viewModel.coordinateFormat) {
            ForEach(CoordinateFormat.allCases, id: \.self) { format in
                Text(format.label).tag(format)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        }
        .alert("Save Preset", isPresented: $viewModel.showSavePresetAlert) {
            TextField("Name", text: $viewModel.newPresetName)
            Button("Save") {
                let name = viewModel.newPresetName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    viewModel.saveCurrentAsPreset(name: name)
                }
                viewModel.newPresetName = ""
            }
            Button("Cancel", role: .cancel) {
                viewModel.newPresetName = ""
            }
        }
    }

    private func presetIcon(_ preset: Preset) -> String {
        switch preset.mode {
        case .single: return "mappin"
        case .route: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }

    private func presetDetail(_ preset: Preset) -> String {
        switch preset.mode {
        case .single(let lat, let lng):
            return CoordinateFormat.format(lat: lat, lon: lng, as: viewModel.coordinateFormat)
        case .route(let waypoints, let speed, _):
            return "\(waypoints.count) waypoints, \(speed) m/s"
        }
    }
}
