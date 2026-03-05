import AppKit
import Foundation
import MapKit
import UniformTypeIdentifiers

@MainActor @Observable
final class AppViewModel {
    // Simulator state
    var simulators: [Simulator] = []
    var selectedSimulator: Simulator?

    // Mode
    var mode: LocationMode = .single

    // Single location
    var singleLatitude: String = ""
    var singleLongitude: String = ""

    // Route
    var waypoints: [Waypoint] = []
    var selectedSpeedPreset: SpeedPreset = .drive
    var customSpeed: String = "13.0"
    var routeInterval: String = ""
    var routingMode: RoutingMode = .straightLine
    var resolvedRouteCoordinates: [CLLocationCoordinate2D]?
    var isCalculatingRoute: Bool = false
    var routeWarning: String?

    // Scenario
    var selectedScenario: String = "City Run"
    let scenarios = ["City Run", "City Bicycle Ride", "Freeway Drive", "Apple"]

    // Search
    var searchText: String = "" {
        didSet { searchCompleter.queryFragment = searchText }
    }
    var searchResults: [MKLocalSearchCompletion] = []

    // Presets
    var presets: [Preset] = []
    var showSavePresetAlert: Bool = false
    var newPresetName: String = ""

    // Geofences
    var geofences: [Geofence] = []
    var isAddingGeofence: Bool = false
    var pendingGeofenceName: String = "Geofence"
    var pendingGeofenceRadius: String = "100"
    var pendingGeofenceLatitude: String = ""
    var pendingGeofenceLongitude: String = ""
    var editingGeofenceID: UUID?

    // Coordinate format
    var coordinateFormat: CoordinateFormat = CoordinateFormat(
        rawValue: UserDefaults.standard.string(forKey: "coordinateFormat") ?? "dd"
    ) ?? .decimalDegrees {
        didSet {
            UserDefaults.standard.set(coordinateFormat.rawValue, forKey: "coordinateFormat")
            convertInputFields(from: oldValue, to: coordinateFormat)
        }
    }

    // Status
    var statusMessage: String = "Ready"
    var isLoading: Bool = false

    // Map region
    var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    private let service = SimctlService()
    private var pollTimer: Timer?
    private let searchCompleter = MKLocalSearchCompleter()
    private var searchCompleterDelegate: SearchCompleterDelegate?
    private var routeDebounceTask: Task<Void, Never>?
    // Cache: key is "lat1,lng1->lat2,lng2", value is the resolved coordinates for that segment
    private var segmentCache: [String: [CLLocationCoordinate2D]] = [:]

    var transportTypeForSpeed: MKDirectionsTransportType {
        switch selectedSpeedPreset {
        case .walk, .run:
            return .walking
        case .bicycle, .drive, .highway, .custom:
            return .automobile
        }
    }

    var resolvedSpeed: Double {
        if selectedSpeedPreset == .custom {
            return Double(customSpeed) ?? 13.0
        }
        return selectedSpeedPreset.metersPerSecond ?? 13.0
    }

    /// Parses a coordinate string using the current format, falling back to the other format.
    func parseCoordinate(_ string: String, isLatitude: Bool) -> Double? {
        CoordinateFormat.parse(string, isLatitude: isLatitude)
    }

    /// Formats a coordinate value for an input field using the current format.
    func formatForInput(_ value: Double, isLatitude: Bool) -> String {
        CoordinateFormat.formatSingle(value, isLatitude: isLatitude, as: coordinateFormat)
    }

    private func convertInputFields(from oldFormat: CoordinateFormat, to newFormat: CoordinateFormat) {
        guard oldFormat != newFormat else { return }

        // Convert single location fields
        if let lat = CoordinateFormat.parse(singleLatitude, isLatitude: true) {
            singleLatitude = CoordinateFormat.formatSingle(lat, isLatitude: true, as: newFormat)
        }
        if let lon = CoordinateFormat.parse(singleLongitude, isLatitude: false) {
            singleLongitude = CoordinateFormat.formatSingle(lon, isLatitude: false, as: newFormat)
        }

        // Convert geofence pending fields
        if let lat = CoordinateFormat.parse(pendingGeofenceLatitude, isLatitude: true) {
            pendingGeofenceLatitude = CoordinateFormat.formatSingle(lat, isLatitude: true, as: newFormat)
        }
        if let lon = CoordinateFormat.parse(pendingGeofenceLongitude, isLatitude: false) {
            pendingGeofenceLongitude = CoordinateFormat.formatSingle(lon, isLatitude: false, as: newFormat)
        }
    }

    // MARK: - Simulator Management

    func refreshSimulators() async {
        do {
            let devices = try await service.listBootedDevices()
            simulators = devices
            if let selected = selectedSimulator,
               !devices.contains(where: { $0.id == selected.id }) {
                selectedSimulator = devices.first
            }
            if selectedSimulator == nil {
                selectedSimulator = devices.first
            }
        } catch {
            // Silently ignore polling errors
        }
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshSimulators()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Map Interactions

    func handleMapTap(coordinate: CLLocationCoordinate2D) {
        if isAddingGeofence || editingGeofenceID != nil {
            pendingGeofenceLatitude = formatForInput(coordinate.latitude, isLatitude: true)
            pendingGeofenceLongitude = formatForInput(coordinate.longitude, isLatitude: false)
            return
        }

        switch mode {
        case .single:
            singleLatitude = formatForInput(coordinate.latitude, isLatitude: true)
            singleLongitude = formatForInput(coordinate.longitude, isLatitude: false)
        case .route:
            waypoints.append(Waypoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
            invalidateRoadRoute()
        case .scenario:
            break
        }
    }

    func updateWaypointCoordinate(id: UUID, latitude: Double, longitude: Double) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        waypoints[index].latitude = latitude
        waypoints[index].longitude = longitude
        invalidateRoadRoute()
    }

    func removeWaypoint(_ waypoint: Waypoint) {
        waypoints.removeAll { $0.id == waypoint.id }
        invalidateRoadRoute()
    }

    func clearWaypoints() {
        waypoints.removeAll()
        resolvedRouteCoordinates = nil
        routeWarning = nil
        segmentCache.removeAll()
    }

    // MARK: - Road Routing

    func invalidateRoadRoute() {
        resolvedRouteCoordinates = nil
        routeWarning = nil
        routeDebounceTask?.cancel()
        if routingMode == .followRoads && waypoints.count >= 2 {
            routeDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                guard !Task.isCancelled else { return }
                await calculateRoadRoute()
            }
        }
    }

    private func segmentKey(from source: Waypoint, to dest: Waypoint) -> String {
        "\(String(format: "%.6f", source.latitude)),\(String(format: "%.6f", source.longitude))->\(String(format: "%.6f", dest.latitude)),\(String(format: "%.6f", dest.longitude))"
    }

    func calculateRoadRoute() async {
        guard routingMode == .followRoads, waypoints.count >= 2 else {
            resolvedRouteCoordinates = nil
            routeWarning = nil
            return
        }

        isCalculatingRoute = true
        routeWarning = nil
        var allCoordinates: [CLLocationCoordinate2D] = []
        var failedSegments: [Int] = []

        for i in 0..<(waypoints.count - 1) {
            guard !Task.isCancelled else { break }

            let source = waypoints[i]
            let destination = waypoints[i + 1]
            let key = segmentKey(from: source, to: destination)

            let sourceCoord = CLLocationCoordinate2D(latitude: source.latitude, longitude: source.longitude)
            let destCoord = CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)

            // Skip directions for very close waypoints (< 50m) — straight line is fine
            let sourceLocation = CLLocation(latitude: source.latitude, longitude: source.longitude)
            let destLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
            if sourceLocation.distance(from: destLocation) < 50 {
                if allCoordinates.isEmpty {
                    allCoordinates.append(sourceCoord)
                }
                allCoordinates.append(destCoord)
                continue
            }

            // Use cached result if available
            if let cached = segmentCache[key] {
                if allCoordinates.isEmpty {
                    allCoordinates.append(contentsOf: cached)
                } else {
                    allCoordinates.append(contentsOf: cached.dropFirst())
                }
                continue
            }

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: sourceCoord))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
            request.transportType = transportTypeForSpeed
            request.requestsAlternateRoutes = true

            let directions = MKDirections(request: request)

            do {
                let response = try await directions.calculate()
                guard let route = response.routes.min(by: { $0.distance < $1.distance }) else {
                    failedSegments.append(i + 1)
                    if allCoordinates.isEmpty {
                        allCoordinates.append(sourceCoord)
                    }
                    allCoordinates.append(destCoord)
                    continue
                }

                let polyline = route.polyline
                let pointCount = polyline.pointCount
                var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
                polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))

                // Cache the result
                segmentCache[key] = coords

                if allCoordinates.isEmpty {
                    allCoordinates.append(contentsOf: coords)
                } else {
                    allCoordinates.append(contentsOf: coords.dropFirst())
                }
            } catch {
                print("MKDirections error for segment \(i + 1): \(error.localizedDescription)")
                failedSegments.append(i + 1)
                if allCoordinates.isEmpty {
                    allCoordinates.append(sourceCoord)
                }
                allCoordinates.append(destCoord)
            }
        }

        guard !Task.isCancelled else {
            isCalculatingRoute = false
            return
        }

        resolvedRouteCoordinates = allCoordinates
        isCalculatingRoute = false

        if !failedSegments.isEmpty {
            let segmentList = failedSegments.map { String($0) }.joined(separator: ", ")
            routeWarning = "Directions failed for segment(s) \(segmentList). Using straight lines."
        }
    }

    // MARK: - Commands

    func setLocation() async {
        guard let sim = selectedSimulator else {
            statusMessage = "No simulator selected"
            return
        }
        guard let lat = parseCoordinate(singleLatitude, isLatitude: true),
              let lng = parseCoordinate(singleLongitude, isLatitude: false) else {
            statusMessage = "Invalid coordinates"
            return
        }
        isLoading = true
        do {
            try await service.setLocation(udid: sim.id, latitude: lat, longitude: lng)
            statusMessage = "Location set to \(lat), \(lng)"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func startRoute() async {
        guard let sim = selectedSimulator else {
            statusMessage = "No simulator selected"
            return
        }
        guard waypoints.count >= 2 else {
            statusMessage = "Need at least 2 waypoints"
            return
        }
        isLoading = true

        if routingMode == .followRoads && resolvedRouteCoordinates == nil {
            await calculateRoadRoute()
        }

        do {
            let interval = Double(routeInterval)
            let routeWaypoints: [Waypoint]

            if routingMode == .followRoads, let resolved = resolvedRouteCoordinates {
                routeWaypoints = resolved.map { Waypoint(latitude: $0.latitude, longitude: $0.longitude) }
                statusMessage = "Road route started: \(routeWaypoints.count) points at \(resolvedSpeed) m/s"
            } else {
                routeWaypoints = waypoints
                statusMessage = "Route started: \(routeWaypoints.count) waypoints at \(resolvedSpeed) m/s"
            }

            try await service.startRoute(
                udid: sim.id,
                waypoints: routeWaypoints,
                speed: resolvedSpeed,
                interval: interval
            )
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func clearLocation() async {
        guard let sim = selectedSimulator else {
            statusMessage = "No simulator selected"
            return
        }
        isLoading = true
        do {
            try await service.clearLocation(udid: sim.id)
            statusMessage = "Location cleared"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func runScenario() async {
        guard let sim = selectedSimulator else {
            statusMessage = "No simulator selected"
            return
        }
        isLoading = true
        do {
            try await service.runScenario(udid: sim.id, scenario: selectedScenario)
            statusMessage = "Scenario \"\(selectedScenario)\" started"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Presets

    func loadPresets() {
        presets = PresetService.load()
    }

    func saveCurrentAsPreset(name: String) {
        let presetMode: PresetMode
        switch mode {
        case .single:
            guard let lat = parseCoordinate(singleLatitude, isLatitude: true),
                  let lng = parseCoordinate(singleLongitude, isLatitude: false) else {
                statusMessage = "Invalid coordinates"
                return
            }
            presetMode = .single(latitude: lat, longitude: lng)
        case .route:
            guard waypoints.count >= 2 else {
                statusMessage = "Need at least 2 waypoints"
                return
            }
            presetMode = .route(waypoints: waypoints, speed: resolvedSpeed, routingMode: routingMode)
        case .scenario:
            statusMessage = "Scenarios cannot be saved as presets"
            return
        }

        let preset = Preset(name: name, mode: presetMode)
        presets.append(preset)
        PresetService.save(presets)
        statusMessage = "Preset \"\(name)\" saved"
    }

    func applyPreset(_ preset: Preset) {
        switch preset.mode {
        case .single(let latitude, let longitude):
            mode = .single
            singleLatitude = formatForInput(latitude, isLatitude: true)
            singleLongitude = formatForInput(longitude, isLatitude: false)
            mapRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        case .route(let savedWaypoints, let speed, let savedRoutingMode):
            mode = .route
            waypoints = savedWaypoints
            routingMode = savedRoutingMode
            let matchingPreset = SpeedPreset.allCases.first { $0.metersPerSecond == speed }
            if let matchingPreset {
                selectedSpeedPreset = matchingPreset
            } else {
                selectedSpeedPreset = .custom
                customSpeed = String(speed)
            }
            if let first = savedWaypoints.first {
                mapRegion = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            }
            invalidateRoadRoute()
        }
        statusMessage = "Preset \"\(preset.name)\" applied"
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        PresetService.save(presets)
    }

    // MARK: - Geofences

    private static var geofenceFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SimLocation", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("geofences.json")
    }

    func loadGeofences() {
        guard let data = try? Data(contentsOf: Self.geofenceFileURL),
              let loaded = try? JSONDecoder().decode([Geofence].self, from: data)
        else { return }
        geofences = loaded
        pendingGeofenceName = "Geofence \(geofences.count + 1)"
    }

    func saveGeofences() {
        guard let data = try? JSONEncoder().encode(geofences) else { return }
        try? data.write(to: Self.geofenceFileURL, options: .atomic)
    }

    func confirmAddGeofence() {
        guard let lat = parseCoordinate(pendingGeofenceLatitude, isLatitude: true),
              let lng = parseCoordinate(pendingGeofenceLongitude, isLatitude: false) else {
            statusMessage = "Invalid coordinates"
            return
        }
        let radius = Double(pendingGeofenceRadius) ?? 100
        let name = pendingGeofenceName.trimmingCharacters(in: .whitespaces)
        let geofence = Geofence(
            name: name.isEmpty ? "Geofence" : name,
            latitude: lat,
            longitude: lng,
            radius: radius
        )
        geofences.append(geofence)
        saveGeofences()
        isAddingGeofence = false
        pendingGeofenceName = "Geofence \(geofences.count + 1)"
        pendingGeofenceLatitude = ""
        pendingGeofenceLongitude = ""
        pendingGeofenceRadius = "100"
        statusMessage = "Geofence added"
    }

    func startEditingGeofence(_ geofence: Geofence) {
        editingGeofenceID = geofence.id
        pendingGeofenceName = geofence.name
        pendingGeofenceLatitude = formatForInput(geofence.latitude, isLatitude: true)
        pendingGeofenceLongitude = formatForInput(geofence.longitude, isLatitude: false)
        pendingGeofenceRadius = String(Int(geofence.radius))
    }

    func saveEditingGeofence() {
        guard let id = editingGeofenceID,
              let index = geofences.firstIndex(where: { $0.id == id }),
              let lat = parseCoordinate(pendingGeofenceLatitude, isLatitude: true),
              let lng = parseCoordinate(pendingGeofenceLongitude, isLatitude: false) else {
            statusMessage = "Invalid coordinates"
            return
        }
        let radius = Double(pendingGeofenceRadius) ?? 100
        let name = pendingGeofenceName.trimmingCharacters(in: .whitespaces)
        geofences[index].name = name.isEmpty ? "Geofence" : name
        geofences[index].latitude = lat
        geofences[index].longitude = lng
        geofences[index].radius = radius
        saveGeofences()
        editingGeofenceID = nil
        pendingGeofenceLatitude = ""
        pendingGeofenceLongitude = ""
        statusMessage = "Geofence updated"
    }

    func cancelEditingGeofence() {
        editingGeofenceID = nil
    }

    func deleteGeofence(_ geofence: Geofence) {
        if editingGeofenceID == geofence.id {
            editingGeofenceID = nil
        }
        geofences.removeAll { $0.id == geofence.id }
        saveGeofences()
    }

    func isInsideGeofence(_ geofence: Geofence) -> Bool {
        let center = CLLocation(latitude: geofence.latitude, longitude: geofence.longitude)
        let current: CLLocation
        switch mode {
        case .single:
            guard let lat = parseCoordinate(singleLatitude, isLatitude: true),
                  let lng = parseCoordinate(singleLongitude, isLatitude: false) else { return false }
            current = CLLocation(latitude: lat, longitude: lng)
        case .route:
            guard let first = waypoints.first else { return false }
            current = CLLocation(latitude: first.latitude, longitude: first.longitude)
        case .scenario:
            return false
        }
        return current.distance(from: center) <= geofence.radius
    }

    // MARK: - Import / Export

    func importConfigs() {
        let gpxType = UTType(filenameExtension: "gpx") ?? UTType.xml
        let panel = NSOpenPanel()
        panel.title = "Import Config"
        panel.allowedContentTypes = [.json, gpxType]
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return }

        var imported = 0
        var applied = false

        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else { continue }

            if url.pathExtension.lowercased() == "gpx" {
                guard let result = try? GPXParser.parse(data: data) else {
                    statusMessage = "Failed to parse \(url.lastPathComponent)"
                    continue
                }
                let name = result.name ?? url.deletingPathExtension().lastPathComponent
                if result.waypoints.count == 1 {
                    let wp = result.waypoints[0]
                    let preset = Preset(name: name, mode: .single(latitude: wp.latitude, longitude: wp.longitude))
                    if !applied {
                        applyPreset(preset)
                        applied = true
                    } else {
                        presets.append(preset)
                    }
                    imported += 1
                } else {
                    let preset = Preset(name: name, mode: .route(waypoints: result.waypoints, speed: 13.0, routingMode: .straightLine))
                    if !applied {
                        applyPreset(preset)
                        applied = true
                    } else {
                        presets.append(preset)
                    }
                    imported += 1
                }
            } else {
                guard let configs = try? LocationConfig.decodeConfigs(from: data) else {
                    statusMessage = "Failed to parse \(url.lastPathComponent)"
                    continue
                }

                if configs.count == 1 && !applied {
                    if let preset = configs[0].toPreset() {
                        applyPreset(preset)
                        applied = true
                        imported += 1
                    }
                } else {
                    for config in configs {
                        if let preset = config.toPreset() {
                            presets.append(preset)
                            imported += 1
                        }
                    }
                }
            }
        }

        if imported > 0 {
            PresetService.save(presets)
            statusMessage = "Imported \(imported) config(s)"
        }
    }

    func exportCurrentConfig() {
        let config: LocationConfig
        switch mode {
        case .single:
            guard let lat = parseCoordinate(singleLatitude, isLatitude: true),
                  let lng = parseCoordinate(singleLongitude, isLatitude: false) else {
                statusMessage = "Invalid coordinates"
                return
            }
            config = LocationConfig(type: "single", latitude: lat, longitude: lng)
        case .route:
            guard waypoints.count >= 2 else {
                statusMessage = "Need at least 2 waypoints"
                return
            }
            config = LocationConfig(
                type: "route",
                waypoints: waypoints.map { LocationConfig.WaypointConfig(latitude: $0.latitude, longitude: $0.longitude) },
                speed: resolvedSpeed,
                routingMode: routingMode == .followRoads ? "followRoads" : "straightLine"
            )
        case .scenario:
            statusMessage = "Scenarios cannot be exported"
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export JSON Config"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "location.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else {
            statusMessage = "Failed to encode config"
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            statusMessage = "Exported to \(url.lastPathComponent)"
        } catch {
            statusMessage = "Export error: \(error.localizedDescription)"
        }
    }

    func exportAllPresets() {
        guard !presets.isEmpty else {
            statusMessage = "No presets to export"
            return
        }

        let configs = presets.map { LocationConfig.from(preset: $0) }

        let panel = NSSavePanel()
        panel.title = "Export All Presets"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "presets.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(configs) else {
            statusMessage = "Failed to encode presets"
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            statusMessage = "Exported \(presets.count) preset(s) to \(url.lastPathComponent)"
        } catch {
            statusMessage = "Export error: \(error.localizedDescription)"
        }
    }

    // MARK: - Search

    func setupSearch() {
        let delegate = SearchCompleterDelegate { [weak self] results in
            self?.searchResults = results
        }
        searchCompleterDelegate = delegate
        searchCompleter.delegate = delegate
        searchCompleter.resultTypes = [.address, .pointOfInterest]
    }

    func selectSearchResult(_ completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)

        Task {
            do {
                let response = try await search.start()
                guard let item = response.mapItems.first else { return }
                let coordinate = item.placemark.coordinate

                mapRegion = MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )

                searchText = ""
                searchResults = []
                statusMessage = "Location: \(completion.title)"
            } catch {
                statusMessage = "Search error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Search Completer Delegate

private final class SearchCompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    let onResults: @MainActor ([MKLocalSearchCompletion]) -> Void

    init(onResults: @escaping @MainActor ([MKLocalSearchCompletion]) -> Void) {
        self.onResults = onResults
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            onResults(results)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}
