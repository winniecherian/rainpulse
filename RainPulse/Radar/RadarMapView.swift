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
    var interactive: Bool = true
    var span: Double = 6
    /// 0 = standard (muted), 1 = hybrid, 2 = satellite
    var mapStyle: Int = 3
    var showWindFlow: Bool = false
    var cyclones: [Cyclone] = []
    var focus: CLLocationCoordinate2D? = nil
    var focusToken: Int = 0
    /// Model (GFS) rain forecast frames, and which one to show instead of the radar tiles.
    var modelFrames: RainModelFrames? = nil
    var modelIndex: Int? = nil
    var onRegionChange: (MKCoordinateRegion) -> Void = { _ in }
    /// "Rain Truth" crowd reports shown as emoji pins.
    var reports: [CrowdReport] = []
    var onSelectReport: (CrowdReport) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = interactive
        map.showsCompass = interactive
        map.isUserInteractionEnabled = interactive
        map.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = Coordinator.configuration(for: mapStyle)
        map.overrideUserInterfaceStyle = Coordinator.interfaceStyle(for: mapStyle)
        context.coordinator.mapStyle = mapStyle
        map.setRegion(MKCoordinateRegion(center: center ?? CLLocationCoordinate2D(latitude: 20, longitude: 0),
                                         span: MKCoordinateSpan(latitudeDelta: center == nil ? 120 : span,
                                                                longitudeDelta: center == nil ? 120 : span)),
                      animated: false)
        context.coordinator.didCenter = center != nil
        let wind = WindFlowView(frame: map.bounds)
        wind.mapView = map
        wind.isHidden = true
        map.addSubview(wind)
        context.coordinator.windView = wind
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
        var mapStyle = 0
        var windView: WindFlowView?
        private var windTask: Task<Void, Never>?
        private var showWind = false
        private var cycloneOverlays: [MKOverlay] = []
        private var cycloneAnnotations: [CycloneAnnotation] = []
        private var cycloneKey = ""
        private var lastFocusToken = 0
        var hideTiles = false
        var onRegionChange: (MKCoordinateRegion) -> Void = { _ in }
        private var modelOverlay: RainModelOverlay?
        private var modelKey = ""
        private var modelImages: [Int: CGImage] = [:]
        private var shownModelIndex: Int?
        private weak var mapRef: MKMapView?
        private var currentModelFrames: RainModelFrames?
        private var desiredModelIndex: Int?
        private var baseOverlays: [BaseTileOverlay] = []
        private var baseKey = ""
        private var reportAnnotations: [ReportAnnotation] = []
        private var reportKey = ""
        var onSelectReport: (CrowdReport) -> Void = { _ in }

        /// 3 = Dark (muted standard map in dark mode): rain and clouds stand out most.
        static func interfaceStyle(for style: Int) -> UIUserInterfaceStyle {
            style == 3 || style == 4 || NASAStyle.from(style) != nil ? .dark : .unspecified
        }

        static func configuration(for style: Int) -> MKMapConfiguration {
            switch style {
            case 1: return MKHybridMapConfiguration()
            case 2: return MKImageryMapConfiguration()
            case 4: return MKHybridMapConfiguration()   // shown dark
            case 5, 6, 7: return MKHybridMapConfiguration()   // NASA imagery covers it; Apple labels stay on top
            default: return MKStandardMapConfiguration(emphasisStyle: .muted)
            }
        }

        func sync(map: MKMapView, view: RadarMapView) {
            currentIndex = view.currentIndex
            opacity = view.opacity
            if view.mapStyle != mapStyle {
                mapStyle = view.mapStyle
                map.preferredConfiguration = Self.configuration(for: mapStyle)
                map.overrideUserInterfaceStyle = Self.interfaceStyle(for: mapStyle)
            }

            syncBase(map: map, style: view.mapStyle)
            onSelectReport = view.onSelectReport
            syncReports(map: map, reports: view.reports)

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
            onRegionChange = view.onRegionChange
            mapRef = map
            hideTiles = view.modelIndex != nil && view.modelFrames != nil
            applyAlpha()
            syncModel(map: map, frames: view.modelFrames, index: view.modelIndex)

            // Center once when location becomes available, or on demand.
            if let center = view.center, !didCenter || view.recenterToken != lastRecenterToken {
                map.setRegion(MKCoordinateRegion(center: center,
                                                 span: MKCoordinateSpan(latitudeDelta: view.span, longitudeDelta: view.span)),
                              animated: didCenter)
                didCenter = true
                lastRecenterToken = view.recenterToken
            }

            // Focus on a point (e.g. a cyclone) on demand.
            if let focus = view.focus, view.focusToken != lastFocusToken {
                map.setRegion(MKCoordinateRegion(center: focus, span: MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 14)),
                              animated: true)
                lastFocusToken = view.focusToken
            }

            // Wind flow animation.
            if view.showWindFlow != showWind {
                showWind = view.showWindFlow
                if showWind { windView?.start(); refreshWind(map) } else { windTask?.cancel(); windView?.stop() }
            }

            // Cyclone tracks, cones and markers.
            let cKey = view.cyclones.map { "\($0.id)\($0.position.lat)\($0.position.lon)\($0.segments.count)" }.joined()
            if cKey != cycloneKey {
                map.removeOverlays(cycloneOverlays)
                map.removeAnnotations(cycloneAnnotations)
                cycloneOverlays = []
                cycloneAnnotations = []
                for storm in view.cyclones {
                    for ring in storm.cone where ring.count > 2 {
                        let poly = ConePolygon(coordinates: ring.map(\.cl), count: ring.count)
                        cycloneOverlays.append(poly)
                    }
                    for seg in storm.segments where seg.points.count > 1 {
                        let line = TrackPolyline(coordinates: seg.points.map(\.cl), count: seg.points.count)
                        line.isForecast = seg.isForecast
                        line.category = seg.category
                        cycloneOverlays.append(line)
                    }
                    let pin = CycloneAnnotation()
                    pin.coordinate = storm.position.cl
                    pin.title = storm.name
                    pin.subtitle = "\(storm.categoryLabel) · \(Int(storm.maxWindKmh.rounded())) km/h"
                    pin.alertLevel = storm.alertLevel
                    cycloneAnnotations.append(pin)
                }
                map.addOverlays(cycloneOverlays, level: .aboveLabels)
                map.addAnnotations(cycloneAnnotations)
                cycloneKey = cKey
            }

            // Saved places as pins.
            let aKey = view.places.map { "\($0.id)\($0.latitude)\($0.longitude)" }.joined()
            if aKey != annotationKey {
                map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) && !($0 is CycloneAnnotation) && !($0 is ReportAnnotation) })
                map.addAnnotations(view.places.map { place in
                    let pin = MKPointAnnotation()
                    pin.coordinate = place.coordinate
                    pin.title = place.name
                    return pin
                })
                annotationKey = aKey
            }
        }

        /// NASA base imagery under the radar (live clouds refresh every 10 minutes).
        private func syncBase(map: MKMapView, style: Int) {
            let nasa = NASAStyle.from(style)
            let key = nasa.map { "\($0.rawValue)|" + ($0 == .liveClouds ? NASAStyle.cloudTime(Date()) : "") } ?? ""
            guard key != baseKey else { return }
            map.removeOverlays(baseOverlays)
            baseOverlays = nasa?.overlays() ?? []
            for (i, overlay) in baseOverlays.enumerated() {
                map.insertOverlay(overlay, at: i, level: .aboveRoads)
            }
            baseKey = key
        }

        private func syncReports(map: MKMapView, reports: [CrowdReport]) {
            let key = reports.map(\.id).sorted().joined(separator: ",")
            guard key != reportKey else { return }
            map.removeAnnotations(reportAnnotations)
            reportAnnotations = reports.map { r in
                let pin = ReportAnnotation()
                pin.report = r
                pin.coordinate = r.coordinate
                pin.title = r.condition.label
                let mins = max(1, Int(Date().timeIntervalSince(r.time) / 60))
                pin.subtitle = [r.area, String(localized: "\(mins) min ago")].compactMap { $0 }.joined(separator: " · ")
                return pin
            }
            map.addAnnotations(reportAnnotations)
            reportKey = key
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let pin = annotation as? ReportAnnotation, let r = pin.report { onSelectReport(r) }
        }

        private func applyAlpha() {
            let visible = hideTiles ? -1 : (overlays.count == 1 ? 0 : currentIndex)
            for (i, overlay) in overlays.enumerated() {
                guard let renderer = renderers[ObjectIdentifier(overlay)] else { continue }
                let alpha = i == visible ? opacity : 0
                if renderer.alpha != alpha { renderer.alpha = alpha }
            }
        }

        /// Shows one GFS rain frame as an image overlay (rendered once per frame, then cached).
        private func syncModel(map: MKMapView, frames: RainModelFrames?, index: Int?) {
            let key = frames.map { "\($0.dates.first?.timeIntervalSince1970 ?? 0)|\($0.lats.first ?? 0)|\($0.lons.first ?? 0)|\($0.lats.count)x\($0.lons.count)" } ?? ""
            if key != modelKey {
                modelImages.removeAll()
                if let old = modelOverlay { map.removeOverlay(old) }
                modelOverlay = nil
                shownModelIndex = nil
                modelKey = key
                if let frames {
                    let o = RainModelOverlay(rect: frames.boundingMapRect)
                    map.addOverlay(o, level: .aboveRoads)
                    modelOverlay = o
                }
            }
            currentModelFrames = frames
            desiredModelIndex = index
            guard let frames, let overlay = modelOverlay,
                  let renderer = map.renderer(for: overlay) as? RainModelRenderer else {
                return   // renderer not created yet; rendererFor fills it in
            }
            guard let index, frames.dates.indices.contains(index) else {
                if renderer.image != nil { renderer.image = nil; renderer.setNeedsDisplay() }
                shownModelIndex = nil
                return
            }
            renderer.alpha = opacity
            guard index != shownModelIndex else { return }
            if modelImages[index] == nil { modelImages[index] = frames.image(frame: index) }
            renderer.image = modelImages[index]
            renderer.setNeedsDisplay()
            shownModelIndex = index
        }

        private func refreshWind(_ map: MKMapView) {
            guard showWind else { return }
            windTask?.cancel()
            let region = map.region
            windTask = Task { [weak self] in
                let field = await WindService.shared.field(for: region)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.windView?.field = field }
            }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if showWind { windView?.setPaused(true) }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            onRegionChange(mapView.region)
            guard showWind else { return }
            windView?.setPaused(false)
            refreshWind(mapView)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let model = overlay as? RainModelOverlay {
                let r = RainModelRenderer(overlay: model)
                r.alpha = opacity
                if let frames = currentModelFrames, let i = desiredModelIndex, frames.dates.indices.contains(i) {
                    if modelImages[i] == nil { modelImages[i] = frames.image(frame: i) }
                    r.image = modelImages[i]
                    shownModelIndex = i
                } else {
                    shownModelIndex = nil
                }
                return r
            }
            if let cone = overlay as? ConePolygon {
                let r = MKPolygonRenderer(polygon: cone)
                r.fillColor = UIColor.systemOrange.withAlphaComponent(0.15)
                r.strokeColor = UIColor.systemOrange.withAlphaComponent(0.8)
                r.lineWidth = 1
                r.lineDashPattern = [4, 4]
                return r
            }
            if let line = overlay as? TrackPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = Self.trackColor(line.category)
                r.lineWidth = line.isForecast ? 3 : 4
                if line.isForecast { r.lineDashPattern = [6, 5] }
                return r
            }
            if let base = overlay as? BaseTileOverlay { return MKTileOverlayRenderer(tileOverlay: base) }
            guard let tile = overlay as? RadarTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKTileOverlayRenderer(tileOverlay: tile)
            renderers[ObjectIdentifier(tile)] = renderer
            let index = overlays.firstIndex { $0 === tile } ?? 0
            let visible = overlays.count == 1 ? 0 : currentIndex
            renderer.alpha = index == visible ? opacity : 0
            return renderer
        }

        static func trackColor(_ category: String) -> UIColor {
            switch category.uppercased() {
            case "TD": return .systemTeal
            case "TS": return .systemYellow
            case "CAT1": return .systemOrange
            case "CAT2": return UIColor(red: 1, green: 0.45, blue: 0.1, alpha: 1)
            case "CAT3": return .systemRed
            case "CAT4": return .systemPink
            case "CAT5": return .systemPurple
            default: return .white
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            if let cluster = annotation as? MKClusterAnnotation {
                let v = MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: "reportCluster")
                let wet = cluster.memberAnnotations.compactMap { ($0 as? ReportAnnotation)?.report }.filter { $0.condition.isWet }.count
                v.glyphText = "\(cluster.memberAnnotations.count)"
                v.markerTintColor = wet * 2 >= cluster.memberAnnotations.count ? .systemBlue : .systemYellow
                v.titleVisibility = .hidden
                return v
            }
            if let storm = annotation as? CycloneAnnotation {
                let id = "cyclone"
                let v = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.glyphImage = UIImage(systemName: "hurricane")
                v.markerTintColor = storm.alertLevel == "Red" ? .systemRed : (storm.alertLevel == "Orange" ? .systemOrange : .systemGreen)
                v.titleVisibility = .visible
                v.canShowCallout = true
                v.displayPriority = .required
                return v
            }
            if let pin = annotation as? ReportAnnotation, let r = pin.report {
                let id = "report"
                let v = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.glyphText = r.condition.emoji
                v.markerTintColor = r.condition == .waterlogging ? .systemRed
                    : (r.condition == .dry ? .systemYellow : .systemBlue)
                v.titleVisibility = .hidden
                v.canShowCallout = true
                v.displayPriority = r.condition == .waterlogging ? .required : .defaultHigh
                v.clusteringIdentifier = r.condition == .waterlogging ? nil : "reports"
                return v
            }
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

final class ConePolygon: MKPolygon {}
final class TrackPolyline: MKPolyline {
    var isForecast = false
    var category = ""
}
final class ReportAnnotation: MKPointAnnotation {
    var report: CrowdReport?
}
final class CycloneAnnotation: MKPointAnnotation {
    var alertLevel = "Green"
}

/// Image overlay covering the GFS grid area.
final class RainModelOverlay: NSObject, MKOverlay {
    let boundingMapRect: MKMapRect
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate }
    init(rect: MKMapRect) { boundingMapRect = rect }
}

final class RainModelRenderer: MKOverlayRenderer {
    var image: CGImage?
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let image else { return }
        let r = rect(for: overlay.boundingMapRect)
        context.saveGState()
        context.interpolationQuality = .high
        // Map renderers use a top-left origin; CGImage draws bottom-up, so flip.
        context.translateBy(x: r.minX, y: r.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
        context.restoreGState()
    }
}
