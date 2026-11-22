import MapKit
import simd
import SwiftUI
import UIKit

@MainActor
struct FlightSimulatorGlobe: View {
    let origin: Airport
    let destination: Airport
    let progress: Double
    var aircraft: FlightSimulatorAircraftMarker? = nil
    var isFlying = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }
    private var fraction: Double { progress.isFinite ? (1000 * min(1, max(0, progress))).rounded() / 1000 : 0 }

    var body: some View {
        Group {
            if DistributionPolicy.mapsAvailable, CLLocationCoordinate2DIsValid(origin.coordinate),
               CLLocationCoordinate2DIsValid(destination.coordinate) {
                FlightSimulatorRouteMap(origin: origin, destination: destination, progress: fraction,
                                        aircraft: aircraft, isFlying: isFlying)
                    .equatable()
                    .id(RouteIdentity(origin: origin.id, destination: destination.id))
            } else {
                offlineTrack
            }
        }
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: palette.corner))
        .overlay { RoundedRectangle(cornerRadius: palette.corner).strokeBorder(palette.line).allowsHitTesting(false) }
    }

    private struct RouteIdentity: Hashable {
        let origin: String
        let destination: String
    }

    private var offlineTrack: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("离线航程示意", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(AtlasTypography.font(.headline, weight: .bold))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            ZStack(alignment: .leading) {
                Capsule().fill(palette.line).frame(height: 4)
                GeometryReader { track in
                    Capsule().fill(palette.accent)
                        .frame(width: track.size.width * fraction, height: 4)
                        .position(x: track.size.width * fraction / 2, y: track.size.height / 2)
                    Image(systemName: "airplane")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 24, height: 24)
                        .position(x: 12 + max(0, track.size.width - 24) * fraction, y: track.size.height / 2)
                }
                .frame(height: 28)
            }
            .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(origin.displayCode)
                Spacer(minLength: 2)
                Text(destination.displayCode)
            }
            .font(palette.readout(.headline))
            .foregroundStyle(palette.ink)
            .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(palette.subtle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("离线航程示意，从\(origin.displayName)到\(destination.displayName)")
        .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityIdentifier("simulator-progress-track")
    }
}

@MainActor
private struct FlightSimulatorRouteMap: View, Equatable {
    let origin: Airport
    let destination: Airport
    let progress: Double
    let aircraft: FlightSimulatorAircraftMarker?
    let isFlying: Bool

    @State private var arc: FlightSimulatorArc
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var camera: FlightSimulatorMapCamera
    @State private var viewpoint: Viewpoint = .overview
    @State private var viewportSize = CGSize(width: 390, height: 235)
    @State private var projection = FlightSimulatorMapProjection()
    @State private var visible = true
    @State private var userChoseViewpoint = false
    @State private var lastFollowUpdate: ContinuousClock.Instant?

    private enum Viewpoint { case overview, follow, global, free }

    init(origin: Airport, destination: Airport, progress: Double, aircraft: FlightSimulatorAircraftMarker?, isFlying: Bool) {
        self.origin = origin
        self.destination = destination
        self.progress = progress
        self.aircraft = aircraft
        self.isFlying = isFlying
        let arc = FlightSimulatorArc(origin: origin.coordinate, destination: destination.coordinate)
        _arc = State(initialValue: arc)
        _camera = State(initialValue: FlightSimulatorMapCamera(arc.overviewCamera(aspect: 1.3)))
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.origin == rhs.origin && lhs.destination == rhs.destination && lhs.progress == rhs.progress
            && lhs.aircraft == rhs.aircraft && lhs.isFlying == rhs.isFlying
    }

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    mapTitle
                    Spacer(minLength: 4)
                    viewpointMenu
                }
                VStack(alignment: .leading, spacing: 3) {
                    mapTitle
                    viewpointMenu
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            mapCanvas
        }
        .onChange(of: progress) { _, next in
            updateFollowCamera(force: next == 0 || next == 1)
        }
        .onChange(of: isFlying) { _, active in
            guard !userChoseViewpoint else { return }
            if active && viewpoint == .overview {
                viewpoint = .follow
                updateFollowCamera(force: true)
            } else if !active && progress == 0 && viewpoint == .follow {
                viewpoint = .overview
                moveCamera(to: overviewCamera)
            }
        }
        .onScrollVisibilityChange(threshold: 0.12) { isVisible in
            visible = isVisible
            if isVisible { updateFollowCamera(force: true) }
        }
    }

    private var mapCanvas: some View {
        FlightSimulatorNativeMap(arc: arc, progress: progress, camera: camera) { result in
            projection = result
        } onUserGesture: {
            userChoseViewpoint = true
            viewpoint = .free
        }
        .background(palette.stage)
        .onGeometryChange(for: CGSize.self) { geometry in
            CGSize(width: geometry.size.width.rounded(), height: geometry.size.height.rounded())
        } action: { size in
            guard size.width > 0, size.height > 0 else { return }
            viewportSize = size
            switch viewpoint {
            case .overview: moveCamera(to: overviewCamera, animated: false)
            case .global: moveCamera(to: arc.globalCamera(aspect: viewportAspect), animated: false)
            case .follow, .free: break
            }
        }
        .accessibilityIdentifier("simulator-globe")
        .overlay {
            GeometryReader { canvas in
                let size = canvas.size
                let width = aircraftWidth(in: size)
                let plane = projection.aircraft
                airportBadge(origin, point: projection.origin, size: size, departure: true,
                             plane: plane, aircraftWidth: width)
                airportBadge(destination, point: projection.destination, size: size, departure: false,
                             plane: plane, aircraftWidth: width)
                aircraftBadge(heading: projection.heading, width: width)
                    .position(plane ?? .zero)
                    .opacity(plane == nil ? 0 : 1)
                    .accessibilityHidden(plane == nil)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func airportBadge(_ airport: Airport, point: CGPoint?, size: CGSize,
                              departure: Bool, plane: CGPoint?, aircraftWidth: CGFloat) -> some View {
        if let point {
            let color: Color = departure ? .mint : .orange
            Circle().fill(color)
                .overlay { Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1.5) }
                .frame(width: 10, height: 10)
                .position(point)
                .accessibilityHidden(true)
            Label(airport.displayCode, systemImage: departure ? "airplane.departure" : "airplane.arrival")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .fixedSize()
                .padding(.horizontal, 7)
                .frame(height: 23)
                .foregroundStyle(color)
                .background(Color(white: 0.08, opacity: 0.94), in: .capsule)
                .overlay { Capsule().strokeBorder(color.opacity(0.65)) }
                .position(badgePosition(for: point, plane: plane, size: size, aircraftWidth: aircraftWidth))
                .accessibilityLabel("\(departure ? "出发" : "抵达")，\(airport.displayName)，\(airport.displayCode)")
        }
    }

    private func badgePosition(for point: CGPoint, plane: CGPoint?, size: CGSize, aircraftWidth: CGFloat) -> CGPoint {
        let verticalOffset: CGFloat = point.y < size.height / 2 ? -27 : 27
        var x = point.x
        let y = min(size.height - 24, max(17, point.y + verticalOffset))
        if let plane, abs(y - plane.y) < aircraftWidth * 0.38 + 14,
           abs(x - plane.x) < aircraftWidth / 2 + 34 {
            let gap = aircraftWidth / 2 + 37
            x = plane.x + (plane.x < size.width / 2 ? gap : -gap)
        }
        return CGPoint(x: min(size.width - 36, max(36, x)), y: y)
    }

    private func aircraftWidth(in size: CGSize) -> CGFloat {
        guard aircraft != nil else { return 32 }
        let compact = UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact || size.width < 440
        let ideal = compact ? min(115, max(96, size.width * 0.26)) : min(148, max(128, size.width * 0.19))
        return min(ideal, size.height * 0.84)
    }

    private func aircraftBadge(heading: Double, width: CGFloat) -> some View {
        Group {
            if let aircraft {
                FlightSimulatorMapAircraft(marker: aircraft, heading: heading)
                    .frame(width: width, height: width * 0.76)
            } else {
                Image(systemName: "airplane")
                    .font(.system(size: 18, weight: .bold))
                    .rotationEffect(.degrees(heading - 90))
                    .foregroundStyle(Color(white: 0.07))
                    .frame(width: 32, height: 32)
                    .background(.mint, in: .circle)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
        .accessibilityElement(children: aircraft == nil ? .ignore : .contain)
        .accessibilityLabel("模拟飞机")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityIdentifier("simulator-globe-aircraft")
    }

    private var mapTitle: some View {
        Label("航线地图", systemImage: "globe.asia.australia")
            .font(AtlasTypography.font(.headline, weight: .bold))
            .foregroundStyle(palette.ink)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(.isHeader)
    }

    private var viewportAspect: CGFloat { max(0.25, viewportSize.width / max(1, viewportSize.height)) }

    private var overviewCamera: MapCamera {
        let markerWidth = aircraftWidth(in: viewportSize)
        let usableWidth = max(viewportSize.width * 0.35, viewportSize.width - markerWidth - 12)
        let usableHeight = max(viewportSize.height * 0.35, viewportSize.height - markerWidth * 0.76 - 12)
        let padding = max(1, viewportSize.width * 0.72 / usableWidth, viewportSize.height * 0.72 / usableHeight)
        return arc.overviewCamera(aspect: viewportAspect, padding: padding)
    }

    private var viewpointMenu: some View {
        Menu {
            Button("航线总览", systemImage: viewpoint == .overview ? "checkmark" : "globe.asia.australia") {
                userChoseViewpoint = true
                viewpoint = .overview
                moveCamera(to: overviewCamera)
            }
            .accessibilityIdentifier("simulator-globe-overview")
            Button("跟随飞机", systemImage: viewpoint == .follow ? "checkmark" : "location.fill") {
                userChoseViewpoint = true
                viewpoint = .follow
                updateFollowCamera(force: true)
            }
            .accessibilityIdentifier("simulator-globe-follow")
            Button("全球视角", systemImage: viewpoint == .global ? "checkmark" : "network") {
                userChoseViewpoint = true
                viewpoint = .global
                moveCamera(to: arc.globalCamera(aspect: viewportAspect))
            }
            .accessibilityIdentifier("simulator-globe-global")
        } label: {
            Label(viewpointLabel, systemImage: viewpoint == .follow ? "location.fill" : "viewfinder")
                .font(AtlasTypography.font(.subheadline, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(minHeight: 44)
                .foregroundStyle(palette.accent)
        }
        .accessibilityLabel("地图视角")
        .accessibilityValue(viewpointLabel)
        .accessibilityIdentifier("simulator-globe-viewpoint")
    }

    private var viewpointLabel: String {
        switch viewpoint {
        case .overview: "航线总览"
        case .follow: "跟随飞机"
        case .global: "全球视角"
        case .free: "自由浏览"
        }
    }

    private func updateFollowCamera(force: Bool) {
        guard viewpoint == .follow, visible else { return }
        let now = ContinuousClock.now
        if !force, let lastFollowUpdate, lastFollowUpdate.duration(to: now) < .milliseconds(600) { return }
        lastFollowUpdate = now
        moveCamera(to: arc.followCamera(at: progress))
    }

    private func moveCamera(to camera: MapCamera, animated: Bool = true) {
        self.camera = FlightSimulatorMapCamera(camera, animated: animated && !reduceMotion)
    }
}

private struct FlightSimulatorMapCamera {
    let revision = UUID()
    let value: MapCamera
    let animated: Bool

    init(_ value: MapCamera, animated: Bool = false) {
        self.value = value
        self.animated = animated
    }

    var native: MKMapCamera {
        MKMapCamera(lookingAtCenter: value.centerCoordinate, fromDistance: value.distance,
                    pitch: value.pitch, heading: value.heading)
    }
}

private struct FlightSimulatorMapProjection: Equatable {
    var origin: CGPoint?
    var destination: CGPoint?
    var aircraft: CGPoint?
    var heading = 0.0
}

// Use the native canvas for the route and point conversion, including in a pitched globe view.
private struct FlightSimulatorNativeMap: UIViewRepresentable {
    let arc: FlightSimulatorArc
    let progress: Double
    let camera: FlightSimulatorMapCamera
    let onProjection: (FlightSimulatorMapProjection) -> Void
    let onUserGesture: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> Canvas {
        let map = Canvas()
        let coordinator = context.coordinator
        map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        map.overrideUserInterfaceStyle = .dark
        map.showsCompass = true
        map.isPitchEnabled = true
        map.accessibilityIdentifier = "simulator-globe"
        map.delegate = coordinator
        coordinator.prepareRoute(on: map)
        coordinator.observeGestures(on: map)
        map.canvasResized = { [weak map, weak coordinator] in
            if let map { coordinator?.project(on: map) }
        }
        map.setCamera(camera.native, animated: false)
        return map
    }

    func updateUIView(_ map: Canvas, context: Context) {
        let coordinator = context.coordinator
        let before = coordinator.parent
        coordinator.parent = self
        if before.camera.revision != camera.revision {
            map.setCamera(camera.native, animated: camera.animated)
            coordinator.project(on: map)
        } else if before.progress != progress {
            coordinator.project(on: map)
        }
    }

    static func dismantleUIView(_ map: Canvas, coordinator: Coordinator) {
        map.delegate = nil
        map.canvasResized = nil
        coordinator.invalidate()
    }

    final class Canvas: MKMapView {
        var canvasResized: (() -> Void)?
        private var lastSize = CGSize.zero

        override func layoutSubviews() {
            super.layoutSubviews()
            if lastSize != bounds.size {
                lastSize = bounds.size
                canvasResized?()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: FlightSimulatorNativeMap
        private var routeLine: MKGeodesicPolyline?
        private var queuedProjection: FlightSimulatorMapProjection?
        private var deliveredProjection: FlightSimulatorMapProjection?
        private var hasPendingDelivery = false
        private var active = true

        init(parent: FlightSimulatorNativeMap) { self.parent = parent }

        func prepareRoute(on map: MKMapView) {
            let route = parent.arc.routePoints
            let outline = MKGeodesicPolyline(coordinates: route, count: route.count)
            let ink = MKGeodesicPolyline(coordinates: route, count: route.count)
            routeLine = ink
            map.addOverlays([outline, ink], level: .aboveLabels)
        }

        func observeGestures(on map: MKMapView) {
            let action = #selector(gestureBegan(_:))
            let recognizers = [UIPanGestureRecognizer(target: self, action: action),
                               UIPinchGestureRecognizer(target: self, action: action),
                               UIRotationGestureRecognizer(target: self, action: action)]
            for recognizer in recognizers {
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = self
                map.addGestureRecognizer(recognizer)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func gestureBegan(_ gesture: UIGestureRecognizer) {
            if gesture.state == .began { parent.onUserGesture() }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKGeodesicPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = line === routeLine ? .systemMint : UIColor.black.withAlphaComponent(0.65)
            renderer.lineWidth = line === routeLine ? 2.5 : 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { project(on: mapView) }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { project(on: mapView) }
        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) { project(on: mapView) }

        func project(on map: MKMapView) {
            guard active, !map.bounds.isEmpty else { return }
            let arc = parent.arc
            let fraction = parent.progress
            let camera = map.camera
            let mapCamera = MapCamera(centerCoordinate: camera.centerCoordinate, distance: camera.centerCoordinateDistance,
                                      heading: camera.heading, pitch: camera.pitch)
            let before = map.convert(arc.coordinate(at: max(0, fraction - 0.002)), toPointTo: map)
            let after = map.convert(arc.coordinate(at: min(1, fraction + 0.002)), toPointTo: map)
            var heading = arc.heading(at: fraction) - camera.heading
            if before.x.isFinite, before.y.isFinite, after.x.isFinite, after.y.isFinite,
               hypot(after.x - before.x, after.y - before.y) > 0.005 {
                heading = atan2(after.y - before.y, after.x - before.x) * 180 / .pi + 90
            }
            let projection = FlightSimulatorMapProjection(
                origin: visiblePoint(for: arc.routePoints[0], on: map, camera: mapCamera),
                destination: visiblePoint(for: arc.routePoints[2], on: map, camera: mapCamera),
                aircraft: visiblePoint(for: arc.coordinate(at: fraction), on: map, camera: mapCamera),
                heading: (heading * 4).rounded() / 4
            )
            queuedProjection = projection
            guard !hasPendingDelivery, deliveredProjection != projection else { return }
            hasPendingDelivery = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hasPendingDelivery = false
                guard self.active, let latest = self.queuedProjection, latest != self.deliveredProjection else { return }
                self.deliveredProjection = latest
                self.parent.onProjection(latest)
            }
        }

        private func visiblePoint(for coordinate: CLLocationCoordinate2D, on map: MKMapView, camera: MapCamera) -> CGPoint? {
            guard parent.arc.isOnVisibleHemisphere(coordinate, camera: camera) else { return nil }
            let point = map.convert(coordinate, toPointTo: map)
            guard map.bounds.contains(point) else { return nil }
            return CGPoint(x: (point.x * 4).rounded() / 4, y: (point.y * 4).rounded() / 4)
        }

        func invalidate() { active = false }
    }
}

private struct FlightSimulatorArc {
    private static let earthRadius = 6_371_000.0
    private let origin: CLLocationCoordinate2D
    private let destination: CLLocationCoordinate2D
    private let start: SIMD3<Double>
    private let direction: SIMD3<Double>
    private let angle: Double
    let routePoints: [CLLocationCoordinate2D]

    init(origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) {
        self.origin = origin
        self.destination = destination
        let start = Self.vector(origin)
        let end = Self.vector(destination)
        let parallel = simd_dot(start, end)
        let orthogonal = end - start * parallel
        let length = simd_length(orthogonal)
        self.start = start
        angle = atan2(length, parallel)
        // Antipodal endpoints admit multiple great circles. Pick a stable perpendicular.
        let axis = abs(start.z) < 0.9 ? SIMD3<Double>(0, 0, 1) : SIMD3<Double>(1, 0, 0)
        let tangent = length > 1e-12 ? orthogonal / length : simd_normalize(axis - start * simd_dot(start, axis))
        direction = tangent
        let midpoint = Self.coordinate(start * cos(angle / 2) + tangent * sin(angle / 2))
        routePoints = [origin, midpoint, destination]
    }

    func coordinate(at progress: Double) -> CLLocationCoordinate2D {
        if progress <= 0 { return origin }
        if progress >= 1 { return destination }
        let arc = angle * progress
        return Self.coordinate(start * cos(arc) + direction * sin(arc))
    }

    func heading(at progress: Double) -> Double {
        let coordinate = coordinate(at: progress)
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        let east = SIMD3<Double>(-sin(longitude), cos(longitude), 0)
        let north = SIMD3<Double>(-sin(latitude) * cos(longitude), -sin(latitude) * sin(longitude), cos(latitude))
        let arc = progress * angle
        let tangent = direction * cos(arc) - start * sin(arc)
        return atan2(simd_dot(tangent, east), simd_dot(tangent, north)) * 180 / .pi
    }

    func overviewCamera(aspect: CGFloat, padding: CGFloat = 1) -> MapCamera {
        let diameter = Self.earthRadius * angle
        let fit = Double(padding) * max(2.35, 2.35 / Double(max(0.6, aspect)))
        let horizon = Self.earthRadius * (1 / cos(min(1.46, angle / 2 + 0.08)) - 1)
        let distance = min(53_000_000, max(24_000, diameter * fit, horizon))
        return MapCamera(centerCoordinate: routePoints[1], distance: distance)
    }

    func globalCamera(aspect: CGFloat) -> MapCamera {
        let fit = max(1, min(1.42, 1.3 / Double(aspect)))
        return MapCamera(centerCoordinate: routePoints[1], distance: 37_000_000 * fit)
    }

    func followCamera(at progress: Double) -> MapCamera {
        let regionalDistance = min(2_200_000, max(24_000, Self.earthRadius * angle * 0.19))
        let blend = min(1, min(progress, 1 - progress) / 0.10)
        let smooth = blend * blend * (3 - 2 * blend)
        return MapCamera(centerCoordinate: coordinate(at: progress), distance: 9_000 + (regionalDistance - 9_000) * smooth,
                         pitch: 30 * (1 - smooth))
    }

    func isOnVisibleHemisphere(_ coordinate: CLLocationCoordinate2D, camera: MapCamera) -> Bool {
        guard camera.distance >= 1_000_000 else { return true }
        let margin = Self.earthRadius / (Self.earthRadius + camera.distance) - 0.035
        return simd_dot(Self.vector(coordinate), Self.vector(camera.centerCoordinate)) >= margin
    }

    private static func vector(_ coordinate: CLLocationCoordinate2D) -> SIMD3<Double> {
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        return SIMD3(cos(latitude) * cos(longitude), cos(latitude) * sin(longitude), sin(latitude))
    }

    private static func coordinate(_ point: SIMD3<Double>) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: atan2(point.z, hypot(point.x, point.y)) * 180 / .pi,
                               longitude: atan2(point.y, point.x) * 180 / .pi)
    }
}
