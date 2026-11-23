import SwiftUI
import MapKit

/// MKMapView wrapper. Every animation frame is its own overlay; only the
/// current frame is visible, the rest stay loaded (alpha 0) so playback is smooth.
struct RadarMapView: UIViewRepresentable {
    let provider: RadarProvider
    let layer: MapLayer
    let frames: [RadarFrame]
    let currentIndex: Int
    let opacity: Double
    let center: CLLocationCoordinate2D?
    let places: [Place]
    var recenterToken: Int = 0
    var onAuthFailure: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.setRegion(MKCoordinateRegion(center: center ?? CLLocationCoordinate2D(latitude: 20, longitude: 0),
                                         span: MKCoordinateSpan(latitudeDelta: center == nil ? 120 : 6,
                                                                longitudeDelta: center == nil ? 120 : 6)),
                      animated: false)
        context.coordinator.didCenter = center != nil
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.sync(map: map, view: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var overlays: [RadarTileOverlay] = []
        private var renderers: [ObjectIdentifier: MKTileOverlayRenderer] = [:]
        private var overlayKey = ""
        private var annotationKey = ""
        private var currentIndex = 0
        private var opacity = 0.75
        private var lastRecenterToken = 0
        var didCenter = false

        func sync(map: MKMapView, view: RadarMapView) {
            currentIndex = view.currentIndex
            opacity = view.opacity

            // Rebuild overlays only when source/layer/frames change.
            let key = "\(view.provider.source.rawValue)|\(view.layer.rawValue)|" +
                view.frames.map { String(Int($0.date.timeIntervalSince1970)) }.joined(separator: ",")
            if key != overlayKey {
                map.removeOverlays(overlays)
                renderers.removeAll()
                let useTime = view.provider.source.supportsTime && view.layer == .radar
                overlays = (useTime ? view.frames.map { Optional($0) } : [nil]).map { frame in
                    let overlay = RadarTileOverlay(provider: view.provider, layer: view.layer, frame: frame)
                    overlay.onAuthFailure = { DispatchQueue.main.async { view.onAuthFailure() } }
                    return overlay
                }
                map.addOverlays(overlays, level: .aboveRoads)
                overlayKey = key
            }
            applyAlpha()

            // Center once when location becomes available, or on demand.
            if let center = view.center, !didCenter || view.recenterToken != lastRecenterToken {
                map.setRegion(MKCoordinateRegion(center: center,
                                                 span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)),
                              animated: didCenter)
                didCenter = true
                lastRecenterToken = view.recenterToken
            }

            // Saved places as pins.
            let aKey = view.places.map { "\($0.id)\($0.latitude)\($0.longitude)" }.joined()
            if aKey != annotationKey {
                map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
                map.addAnnotations(view.places.map { place in
                    let pin = MKPointAnnotation()
                    pin.coordinate = place.coordinate
                    pin.title = place.name
                    return pin
                })
                annotationKey = aKey
            }
        }

        private func applyAlpha() {
            let visible = overlays.count == 1 ? 0 : currentIndex
            for (i, overlay) in overlays.enumerated() {
                guard let renderer = renderers[ObjectIdentifier(overlay)] else { continue }
                let alpha = i == visible ? opacity : 0
                if renderer.alpha != alpha { renderer.alpha = alpha }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tile = overlay as? RadarTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKTileOverlayRenderer(tileOverlay: tile)
            renderers[ObjectIdentifier(tile)] = renderer
            let index = overlays.firstIndex { $0 === tile } ?? 0
            let visible = overlays.count == 1 ? 0 : currentIndex
            renderer.alpha = index == visible ? opacity : 0
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "place"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = .systemTeal
            view.glyphImage = UIImage(systemName: "star.fill")
            view.displayPriority = .required
            return view
        }
    }
}
