import SwiftUI
import MapKit

class WaypointAnnotation: MKPointAnnotation {
    var waypointID: UUID

    init(waypointID: UUID) {
        self.waypointID = waypointID
        super.init()
    }
}

class SingleLocationAnnotation: MKPointAnnotation {}

class GeofenceCircle: NSObject, MKOverlay {
    let geofenceID: UUID
    let circle: MKCircle

    var coordinate: CLLocationCoordinate2D { circle.coordinate }
    var boundingMapRect: MKMapRect { circle.boundingMapRect }

    init(geofenceID: UUID, center: CLLocationCoordinate2D, radius: CLLocationDistance) {
        self.geofenceID = geofenceID
        self.circle = MKCircle(center: center, radius: radius)
        super.init()
    }
}

struct MapContainerView: NSViewRepresentable {
    var viewModel: AppViewModel

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsZoomControls = true
        mapView.showsCompass = true
        mapView.setRegion(viewModel.mapRegion, animated: false)

        let clickGesture = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        clickGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(clickGesture)

        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        // Update coordinator's reference to current view model
        context.coordinator.viewModel = viewModel

        // Skip annotation updates while user is dragging a waypoint
        guard !context.coordinator.isDragging else { return }

        // Update map region if it changed significantly
        let currentCenter = mapView.region.center
        let newCenter = viewModel.mapRegion.center
        let threshold = 0.0001
        if abs(currentCenter.latitude - newCenter.latitude) > threshold ||
           abs(currentCenter.longitude - newCenter.longitude) > threshold {
            mapView.setRegion(viewModel.mapRegion, animated: true)
        }

        // --- Annotation diffing ---
        let existingSingles = mapView.annotations.compactMap { $0 as? SingleLocationAnnotation }
        let existingWaypoints = mapView.annotations.compactMap { $0 as? WaypointAnnotation }

        switch viewModel.mode {
        case .single:
            // Remove waypoint annotations (mode switch)
            if !existingWaypoints.isEmpty {
                mapView.removeAnnotations(existingWaypoints)
            }

            if let lat = CoordinateFormat.parse(viewModel.singleLatitude, isLatitude: true),
               let lng = CoordinateFormat.parse(viewModel.singleLongitude, isLatitude: false) {
                let desired = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                if let existing = existingSingles.first {
                    // Update in-place if coordinate changed
                    if abs(existing.coordinate.latitude - desired.latitude) > 1e-10 ||
                       abs(existing.coordinate.longitude - desired.longitude) > 1e-10 {
                        existing.coordinate = desired
                    }
                    // Remove extras if somehow more than one
                    if existingSingles.count > 1 {
                        mapView.removeAnnotations(Array(existingSingles.dropFirst()))
                    }
                } else {
                    let annotation = SingleLocationAnnotation()
                    annotation.coordinate = desired
                    annotation.title = "Location"
                    mapView.addAnnotation(annotation)
                }
            } else {
                // No valid coordinate — remove any existing single annotation
                if !existingSingles.isEmpty {
                    mapView.removeAnnotations(existingSingles)
                }
            }

        case .route:
            // Remove single-location annotations (mode switch)
            if !existingSingles.isEmpty {
                mapView.removeAnnotations(existingSingles)
            }

            // Build lookup of existing waypoint annotations by ID
            var existingByID: [UUID: WaypointAnnotation] = [:]
            for wa in existingWaypoints {
                existingByID[wa.waypointID] = wa
            }

            let desiredIDs = Set(viewModel.waypoints.map { $0.id })

            // Remove stale waypoint annotations
            let stale = existingWaypoints.filter { !desiredIDs.contains($0.waypointID) }
            if !stale.isEmpty {
                mapView.removeAnnotations(stale)
            }

            // Add or update waypoint annotations
            for (index, wp) in viewModel.waypoints.enumerated() {
                let expectedTitle = "Waypoint \(index + 1)"
                if let existing = existingByID[wp.id] {
                    if abs(existing.coordinate.latitude - wp.latitude) > 1e-10 ||
                       abs(existing.coordinate.longitude - wp.longitude) > 1e-10 {
                        existing.coordinate = CLLocationCoordinate2D(latitude: wp.latitude, longitude: wp.longitude)
                    }
                    if existing.title != expectedTitle {
                        existing.title = expectedTitle
                    }
                } else {
                    let annotation = WaypointAnnotation(waypointID: wp.id)
                    annotation.coordinate = CLLocationCoordinate2D(latitude: wp.latitude, longitude: wp.longitude)
                    annotation.title = expectedTitle
                    mapView.addAnnotation(annotation)
                }
            }

            // --- Polyline overlay diffing ---
            let routeCoords: [CLLocationCoordinate2D]?
            if let resolved = viewModel.resolvedRouteCoordinates, resolved.count >= 2 {
                routeCoords = resolved
            } else if viewModel.waypoints.count >= 2 {
                routeCoords = viewModel.waypoints.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
            } else {
                routeCoords = nil
            }

            var routeHash: Int?
            if let coords = routeCoords {
                var hasher = Hasher()
                for c in coords {
                    hasher.combine(c.latitude)
                    hasher.combine(c.longitude)
                }
                routeHash = hasher.finalize()
            }

            if routeHash != context.coordinator.lastRouteCoordinateHash {
                // Remove existing polylines
                let existingPolylines = mapView.overlays.compactMap { $0 as? MKPolyline }
                if !existingPolylines.isEmpty {
                    mapView.removeOverlays(existingPolylines)
                }
                // Add new polyline if we have coords
                if var coords = routeCoords {
                    let polyline = MKPolyline(coordinates: &coords, count: coords.count)
                    mapView.addOverlay(polyline)
                }
                context.coordinator.lastRouteCoordinateHash = routeHash
            }

        case .scenario:
            // Remove all custom annotations when in scenario mode
            if !existingSingles.isEmpty { mapView.removeAnnotations(existingSingles) }
            if !existingWaypoints.isEmpty { mapView.removeAnnotations(existingWaypoints) }
            // Remove polylines
            let polylines = mapView.overlays.compactMap { $0 as? MKPolyline }
            if !polylines.isEmpty { mapView.removeOverlays(polylines) }
            context.coordinator.lastRouteCoordinateHash = nil
        }

        // Remove polylines when not in route mode
        if viewModel.mode != .route {
            let polylines = mapView.overlays.compactMap { $0 as? MKPolyline }
            if !polylines.isEmpty { mapView.removeOverlays(polylines) }
            context.coordinator.lastRouteCoordinateHash = nil
        }

        // --- Geofence overlay diffing ---
        let existingCircles = mapView.overlays.compactMap { $0 as? GeofenceCircle }
        var existingCirclesByID: [UUID: GeofenceCircle] = [:]
        for circle in existingCircles {
            existingCirclesByID[circle.geofenceID] = circle
        }

        let desiredGeofenceIDs = Set(viewModel.geofences.map { $0.id })

        // Remove stale geofence circles
        let staleCircles = existingCircles.filter { !desiredGeofenceIDs.contains($0.geofenceID) }
        if !staleCircles.isEmpty {
            mapView.removeOverlays(staleCircles)
        }

        // Add or recreate changed geofence circles
        for geofence in viewModel.geofences {
            let inside = viewModel.isInsideGeofence(geofence)
            let newState = (lat: geofence.latitude, lng: geofence.longitude, radius: geofence.radius, inside: inside)

            if let existing = existingCirclesByID[geofence.id],
               let lastState = context.coordinator.lastGeofenceStates[geofence.id],
               abs(lastState.lat - newState.lat) < 1e-10 &&
               abs(lastState.lng - newState.lng) < 1e-10 &&
               abs(lastState.radius - newState.radius) < 1e-10 &&
               lastState.inside == newState.inside {
                // No change — keep existing
                _ = existing
            } else {
                // Remove old if present
                if let existing = existingCirclesByID[geofence.id] {
                    mapView.removeOverlay(existing)
                }
                let center = CLLocationCoordinate2D(latitude: geofence.latitude, longitude: geofence.longitude)
                let circle = GeofenceCircle(geofenceID: geofence.id, center: center, radius: geofence.radius)
                circle.circle.title = inside ? "inside" : "outside"
                mapView.addOverlay(circle)
            }
            context.coordinator.lastGeofenceStates[geofence.id] = newState
        }

        // Clean up stale geofence state
        let staleGeofenceIDs = Set(context.coordinator.lastGeofenceStates.keys).subtracting(desiredGeofenceIDs)
        for id in staleGeofenceIDs {
            context.coordinator.lastGeofenceStates.removeValue(forKey: id)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, MKMapViewDelegate, NSGestureRecognizerDelegate {
        var viewModel: AppViewModel
        var isDragging = false
        var lastRouteCoordinateHash: Int?
        var lastGeofenceStates: [UUID: (lat: Double, lng: Double, radius: Double, inside: Bool)] = [:]

        init(viewModel: AppViewModel) {
            self.viewModel = viewModel
        }

        // Prevent the click gesture from firing when the user clicks on an annotation
        func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            guard let mapView = gestureRecognizer.view as? MKMapView else { return true }
            let clickPoint = gestureRecognizer.location(in: mapView)

            for annotation in mapView.annotations {
                let annotationPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
                let dx = clickPoint.x - annotationPoint.x
                let dy = clickPoint.y - annotationPoint.y
                // MKMarkerAnnotationView is roughly 40pt wide and the pin tip is offset above the coordinate
                if abs(dx) < 22 && dy > -50 && dy < 10 {
                    return false
                }
            }
            return true
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            viewModel.handleMapTap(coordinate: coordinate)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            viewModel.mapRegion = mapView.region
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 3
                return renderer
            }
            if let geofenceCircle = overlay as? GeofenceCircle {
                let renderer = MKCircleRenderer(circle: geofenceCircle.circle)
                let inside = geofenceCircle.circle.title == "inside"
                renderer.fillColor = (inside ? NSColor.systemGreen : NSColor.systemBlue).withAlphaComponent(0.15)
                renderer.strokeColor = inside ? .systemGreen : .systemBlue
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            let identifier = "Pin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = true

            if annotation is WaypointAnnotation {
                view.markerTintColor = .systemBlue
                view.isDraggable = true
                if let title = annotation.title ?? nil {
                    view.glyphText = title.replacingOccurrences(of: "Waypoint ", with: "")
                }
            } else if annotation is SingleLocationAnnotation {
                view.markerTintColor = .systemRed
                view.isDraggable = false
            } else {
                view.markerTintColor = .systemRed
                view.isDraggable = false
            }

            return view
        }

        func mapView(_ mapView: MKMapView, annotationView: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            switch newState {
            case .starting, .dragging:
                isDragging = true
            case .ending, .canceling:
                isDragging = false
                if let waypointAnnotation = annotationView.annotation as? WaypointAnnotation {
                    let coord = waypointAnnotation.coordinate
                    viewModel.updateWaypointCoordinate(
                        id: waypointAnnotation.waypointID,
                        latitude: coord.latitude,
                        longitude: coord.longitude
                    )
                }
                annotationView.setDragState(.none, animated: false)
            default:
                break
            }
        }
    }
}
