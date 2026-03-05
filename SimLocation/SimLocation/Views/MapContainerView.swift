import SwiftUI
import MapKit

class WaypointAnnotation: MKPointAnnotation {
    var waypointID: UUID

    init(waypointID: UUID) {
        self.waypointID = waypointID
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

        // Remove existing annotations and overlays
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)

        switch viewModel.mode {
        case .single:
            if let lat = CoordinateFormat.parse(viewModel.singleLatitude, isLatitude: true),
               let lng = CoordinateFormat.parse(viewModel.singleLongitude, isLatitude: false) {
                let annotation = MKPointAnnotation()
                annotation.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                annotation.title = "Location"
                mapView.addAnnotation(annotation)
            }

        case .route:
            for (index, wp) in viewModel.waypoints.enumerated() {
                let annotation = WaypointAnnotation(waypointID: wp.id)
                annotation.coordinate = CLLocationCoordinate2D(
                    latitude: wp.latitude,
                    longitude: wp.longitude
                )
                annotation.title = "Waypoint \(index + 1)"
                mapView.addAnnotation(annotation)
            }

            if let resolved = viewModel.resolvedRouteCoordinates, resolved.count >= 2 {
                var coords = resolved
                let polyline = MKPolyline(coordinates: &coords, count: coords.count)
                mapView.addOverlay(polyline)
            } else if viewModel.waypoints.count >= 2 {
                var coords = viewModel.waypoints.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                let polyline = MKPolyline(coordinates: &coords, count: coords.count)
                mapView.addOverlay(polyline)
            }

        case .scenario:
            break
        }

        // Geofence circle overlays (visible in all modes)
        for geofence in viewModel.geofences {
            let center = CLLocationCoordinate2D(latitude: geofence.latitude, longitude: geofence.longitude)
            let circle = MKCircle(center: center, radius: geofence.radius)
            circle.title = viewModel.isInsideGeofence(geofence) ? "inside" : "outside"
            mapView.addOverlay(circle)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, MKMapViewDelegate, NSGestureRecognizerDelegate {
        var viewModel: AppViewModel
        var isDragging = false

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
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                let inside = circle.title == "inside"
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
