import AppKit
import Foundation
import MapKit
import UniformTypeIdentifiers

@MainActor @Observable
final class AppViewModel {
    // Undo/Redo
    let undoManager = UndoManager()
    var canUndo: Bool = false
    var canRedo: Bool = false
    private var undoObservers: [Any] = []

    private func setupUndoObservers() {
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange,
            .NSUndoManagerDidCloseUndoGroup,
        ]
        for name in names {
            let observer = nc.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.canUndo = self?.undoManager.canUndo ?? false
                    self?.canRedo = self?.undoManager.canRedo ?? false
                }
            }
            undoObservers.append(observer)
        }
    }

    // Simulator state
    var simulators: [Simulator] = []
    var selectedSimulator: Simulator?
    var broadcastSimulators: Set<String> = []  // UDIDs of additional simulators to broadcast to
    var showBroadcastPopover: Bool = false

    /// All target UDIDs: primary + broadcast (excluding primary duplicate).
    var targetUDIDs: [String] {
        guard let primary = selectedSimulator else { return [] }
        var udids = [primary.id]
        for udid in broadcastSimulators.sorted() where udid != primary.id {
            udids.append(udid)
        }
        return udids
    }

    /// Simulators available for broadcast (all booted except the primary).
    var broadcastableSimulators: [Simulator] {
        simulators.filter { $0.id != selectedSimulator?.id }
    }

    func toggleBroadcast(for simulator: Simulator) {
        if broadcastSimulators.contains(simulator.id) {
            broadcastSimulators.remove(simulator.id)
        } else {
            broadcastSimulators.insert(simulator.id)
        }
    }

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

    // Waypoint editing
    var editingWaypointID: UUID?
    var pendingWaypointLatitude: String = ""
    var pendingWaypointLongitude: String = ""

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

    // Android support
    var adbAvailable: Bool = false
    var adbGuidanceDismissed: Bool = UserDefaults.standard.bool(forKey: "adbGuidanceDismissed")
    var showAdbGuidancePopover: Bool = false

    private let service = SimctlService()
    private let adbService = AdbService()
    private var activeAndroidRoutes: [String: Task<Void, any Error>] = [:]
    private var pollTimer: Timer?
    private let searchCompleter = MKLocalSearchCompleter()
    private var searchCompleterDelegate: SearchCompleterDelegate?
    private var routeDebounceTask: Task<Void, Never>?
    // Cache: key is "lat1,lng1->lat2,lng2", value is the resolved coordinates for that segment
    private var segmentCache: [String: [CLLocationCoordinate2D]] = [:]

    init() {
        setupUndoObservers()
    }

    /// Returns the platform for a given device ID, defaulting to .ios.
    private func platform(for deviceID: String) -> DevicePlatform {
        simulators.first(where: { $0.id == deviceID })?.platform ?? .ios
    }

    /// Whether any target device is Android.
    var hasAndroidTarget: Bool {
        targetUDIDs.contains { platform(for: $0) == .android }
    }

    /// Whether all target devices are Android.
    var allTargetsAndroid: Bool {
        !targetUDIDs.isEmpty && targetUDIDs.allSatisfy { platform(for: $0) == .android }
    }

    func dismissAdbGuidance() {
        adbGuidanceDismissed = true
        UserDefaults.standard.set(true, forKey: "adbGuidanceDismissed")
        showAdbGuidancePopover = false
    }

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

    // MARK: - Input Validation

    /// Validates the custom speed field. Must be a positive number.
    var isCustomSpeedValid: Bool {
        guard let value = Double(customSpeed) else { return false }
        return value > 0 && value <= 1000
    }

    /// Validates the route interval field. Empty is valid (uses default), otherwise must be positive.
    var isRouteIntervalValid: Bool {
        let trimmed = routeInterval.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        guard let value = Double(trimmed) else { return false }
        return value > 0
    }

    /// Validates the geofence radius field. Must be a positive number.
    var isGeofenceRadiusValid: Bool {
        guard let value = Double(pendingGeofenceRadius) else { return false }
        return value > 0
    }

    /// Validation error for single location latitude field.
    var singleLatitudeError: String? {
        let trimmed = singleLatitude.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if parseCoordinate(singleLatitude, isLatitude: true) == nil {
            if Double(trimmed) != nil || CoordinateFormat.parse(trimmed, isLatitude: true) == nil {
                // If it parsed as a number but failed validation, it's out of range
                if let raw = Double(trimmed), abs(raw) > 90 {
                    return "Must be between -90 and 90"
                }
                return "Invalid format"
            }
        }
        return nil
    }

    /// Validation error for single location longitude field.
    var singleLongitudeError: String? {
        let trimmed = singleLongitude.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if parseCoordinate(singleLongitude, isLatitude: false) == nil {
            if let raw = Double(trimmed), abs(raw) > 180 {
                return "Must be between -180 and 180"
            }
            return "Invalid format"
        }
        return nil
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

        // Convert waypoint pending fields
        if let lat = CoordinateFormat.parse(pendingWaypointLatitude, isLatitude: true) {
            pendingWaypointLatitude = CoordinateFormat.formatSingle(lat, isLatitude: true, as: newFormat)
        }
        if let lon = CoordinateFormat.parse(pendingWaypointLongitude, isLatitude: false) {
            pendingWaypointLongitude = CoordinateFormat.formatSingle(lon, isLatitude: false, as: newFormat)
        }
    }

    // MARK: - Simulator Management

    func refreshSimulators() async {
        var allDevices: [Simulator] = []

        // Fetch iOS simulators
        if let iosDevices = try? await service.listBootedDevices() {
            allDevices.append(contentsOf: iosDevices)
        }

        // Fetch Android emulators
        let available = await adbService.isAvailable()
        adbAvailable = available
        if available, let androidDevices = try? await adbService.listRunningEmulators() {
            allDevices.append(contentsOf: androidDevices)
        }

        simulators = allDevices
        if let selected = selectedSimulator,
           !allDevices.contains(where: { $0.id == selected.id }) {
            selectedSimulator = allDevices.first
        }
        if selectedSimulator == nil {
            selectedSimulator = allDevices.first
        }
        // Remove broadcast selections for devices that are no longer running
        let bootedIDs = Set(allDevices.map(\.id))
        broadcastSimulators = broadcastSimulators.intersection(bootedIDs)
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

        if editingWaypointID != nil {
            pendingWaypointLatitude = formatForInput(coordinate.latitude, isLatitude: true)
            pendingWaypointLongitude = formatForInput(coordinate.longitude, isLatitude: false)
            return
        }

        switch mode {
        case .single:
            singleLatitude = formatForInput(coordinate.latitude, isLatitude: true)
            singleLongitude = formatForInput(coordinate.longitude, isLatitude: false)
        case .route:
            let newWaypoint = Waypoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
            waypoints.append(newWaypoint)
            invalidateRoadRoute()
            undoManager.registerUndo(withTarget: self) { vm in
                vm.waypoints.removeAll { $0.id == newWaypoint.id }
                vm.invalidateRoadRoute()
            }
        case .scenario:
            break
        }
    }

    func updateWaypointCoordinate(id: UUID, latitude: Double, longitude: Double) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        let oldLat = waypoints[index].latitude
        let oldLng = waypoints[index].longitude
        waypoints[index].latitude = latitude
        waypoints[index].longitude = longitude
        invalidateRoadRoute()
        undoManager.registerUndo(withTarget: self) { vm in
            vm.updateWaypointCoordinate(id: id, latitude: oldLat, longitude: oldLng)
        }
    }

    func startEditingWaypoint(_ waypoint: Waypoint) {
        editingWaypointID = waypoint.id
        pendingWaypointLatitude = formatForInput(waypoint.latitude, isLatitude: true)
        pendingWaypointLongitude = formatForInput(waypoint.longitude, isLatitude: false)
    }

    func saveEditingWaypoint() {
        guard let id = editingWaypointID,
              let lat = parseCoordinate(pendingWaypointLatitude, isLatitude: true),
              let lng = parseCoordinate(pendingWaypointLongitude, isLatitude: false) else {
            return
        }
        updateWaypointCoordinate(id: id, latitude: lat, longitude: lng)
        editingWaypointID = nil
        pendingWaypointLatitude = ""
        pendingWaypointLongitude = ""
    }

    func cancelEditingWaypoint() {
        editingWaypointID = nil
        pendingWaypointLatitude = ""
        pendingWaypointLongitude = ""
    }

    func removeWaypoint(_ waypoint: Waypoint) {
        if editingWaypointID == waypoint.id {
            editingWaypointID = nil
        }
        guard let index = waypoints.firstIndex(where: { $0.id == waypoint.id }) else { return }
        let removed = waypoints.remove(at: index)
        invalidateRoadRoute()
        undoManager.registerUndo(withTarget: self) { vm in
            vm.waypoints.insert(removed, at: min(index, vm.waypoints.count))
            vm.invalidateRoadRoute()
        }
    }

    func moveWaypoints(from source: IndexSet, to destination: Int) {
        let oldWaypoints = waypoints
        waypoints.move(fromOffsets: source, toOffset: destination)
        invalidateRoadRoute()
        undoManager.registerUndo(withTarget: self) { vm in
            vm.waypoints = oldWaypoints
            vm.invalidateRoadRoute()
        }
    }

    func clearWaypoints() {
        let oldWaypoints = waypoints
        let oldResolved = resolvedRouteCoordinates
        let oldWarning = routeWarning
        let oldCache = segmentCache
        waypoints.removeAll()
        resolvedRouteCoordinates = nil
        routeWarning = nil
        segmentCache.removeAll()
        undoManager.registerUndo(withTarget: self) { vm in
            vm.waypoints = oldWaypoints
            vm.resolvedRouteCoordinates = oldResolved
            vm.routeWarning = oldWarning
            vm.segmentCache = oldCache
        }
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
        guard selectedSimulator != nil else {
            statusMessage = "No device selected"
            return
        }
        guard let lat = parseCoordinate(singleLatitude, isLatitude: true),
              let lng = parseCoordinate(singleLongitude, isLatitude: false) else {
            statusMessage = "Invalid coordinates"
            return
        }
        isLoading = true
        let udids = targetUDIDs
        var errors: [String] = []
        for udid in udids {
            do {
                if platform(for: udid) == .android {
                    try await adbService.setLocation(serial: udid, latitude: lat, longitude: lng)
                } else {
                    try await service.setLocation(udid: udid, latitude: lat, longitude: lng)
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        if errors.isEmpty {
            statusMessage = udids.count > 1
                ? "Location set on \(udids.count) devices"
                : "Location set to \(lat), \(lng)"
        } else {
            statusMessage = "Error: \(errors.joined(separator: "; "))"
        }
        isLoading = false
    }

    func startRoute() async {
        guard selectedSimulator != nil else {
            statusMessage = "No device selected"
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

        let interval = Double(routeInterval)
        let routeWaypoints: [Waypoint]
        let routeDescription: String

        if routingMode == .followRoads, let resolved = resolvedRouteCoordinates {
            routeWaypoints = resolved.map { Waypoint(latitude: $0.latitude, longitude: $0.longitude) }
            routeDescription = "Road route: \(routeWaypoints.count) points at \(resolvedSpeed) m/s"
        } else {
            routeWaypoints = waypoints
            routeDescription = "Route: \(routeWaypoints.count) waypoints at \(resolvedSpeed) m/s"
        }

        let udids = targetUDIDs
        let speed = resolvedSpeed
        var errors: [String] = []
        for udid in udids {
            do {
                if platform(for: udid) == .android {
                    // Cancel any existing route for this emulator
                    activeAndroidRoutes[udid]?.cancel()
                    // Start Android route simulation in background
                    let task = Task.detached { [adbService] in
                        try await adbService.simulateRoute(
                            serial: udid,
                            waypoints: routeWaypoints,
                            speed: speed
                        )
                    }
                    activeAndroidRoutes[udid] = task
                } else {
                    try await service.startRoute(
                        udid: udid,
                        waypoints: routeWaypoints,
                        speed: resolvedSpeed,
                        interval: interval
                    )
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        if errors.isEmpty {
            statusMessage = udids.count > 1
                ? "\(routeDescription) on \(udids.count) devices"
                : "\(routeDescription) started"
        } else {
            statusMessage = "Error: \(errors.joined(separator: "; "))"
        }
        isLoading = false
    }

    func clearLocation() async {
        guard selectedSimulator != nil else {
            statusMessage = "No device selected"
            return
        }
        isLoading = true
        let udids = targetUDIDs
        var errors: [String] = []
        for udid in udids {
            // Cancel any active Android route simulation
            activeAndroidRoutes[udid]?.cancel()
            activeAndroidRoutes.removeValue(forKey: udid)

            do {
                if platform(for: udid) == .android {
                    try await adbService.clearLocation(serial: udid)
                } else {
                    try await service.clearLocation(udid: udid)
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        if errors.isEmpty {
            statusMessage = udids.count > 1
                ? "Location cleared on \(udids.count) devices"
                : "Location cleared"
        } else {
            statusMessage = "Error: \(errors.joined(separator: "; "))"
        }
        isLoading = false
    }

    func runScenario() async {
        guard selectedSimulator != nil else {
            statusMessage = "No device selected"
            return
        }

        let iosUDIDs = targetUDIDs.filter { platform(for: $0) == .ios }
        if iosUDIDs.isEmpty {
            statusMessage = "Scenarios are only available for iOS simulators"
            return
        }

        isLoading = true
        var errors: [String] = []
        for udid in iosUDIDs {
            do {
                try await service.runScenario(udid: udid, scenario: selectedScenario)
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        let skippedAndroid = targetUDIDs.count - iosUDIDs.count
        if errors.isEmpty {
            var msg = iosUDIDs.count > 1
                ? "Scenario \"\(selectedScenario)\" started on \(iosUDIDs.count) simulators"
                : "Scenario \"\(selectedScenario)\" started"
            if skippedAndroid > 0 {
                msg += " (skipped \(skippedAndroid) Android emulator\(skippedAndroid == 1 ? "" : "s"))"
            }
            statusMessage = msg
        } else {
            statusMessage = "Error: \(errors.joined(separator: "; "))"
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
        undoManager.registerUndo(withTarget: self) { vm in
            vm.geofences.removeAll { $0.id == geofence.id }
            vm.saveGeofences()
        }
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
        let oldGeofence = geofences[index]
        geofences[index].name = name.isEmpty ? "Geofence" : name
        geofences[index].latitude = lat
        geofences[index].longitude = lng
        geofences[index].radius = radius
        saveGeofences()
        editingGeofenceID = nil
        pendingGeofenceLatitude = ""
        pendingGeofenceLongitude = ""
        statusMessage = "Geofence updated"
        undoManager.registerUndo(withTarget: self) { vm in
            guard let idx = vm.geofences.firstIndex(where: { $0.id == oldGeofence.id }) else { return }
            vm.geofences[idx] = oldGeofence
            vm.saveGeofences()
        }
    }

    func cancelEditingGeofence() {
        editingGeofenceID = nil
    }

    func deleteGeofence(_ geofence: Geofence) {
        if editingGeofenceID == geofence.id {
            editingGeofenceID = nil
        }
        guard let index = geofences.firstIndex(where: { $0.id == geofence.id }) else { return }
        let removed = geofences.remove(at: index)
        saveGeofences()
        undoManager.registerUndo(withTarget: self) { vm in
            vm.geofences.insert(removed, at: min(index, vm.geofences.count))
            vm.saveGeofences()
        }
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
