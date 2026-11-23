import MapKit
import SwiftUI
import UIKit

@MainActor
struct FlightSimulatorGlobe: View {
    let origin: Airport
    let destination: Airport
    let progress: Double
    var aircraft: FlightSimulatorAircraftMarker? = nil
    var isFlying = false
    var groundPose: FlightGroundPose? = nil
    var departureAirStart: FlightGroundPose? = nil
    var arrivalAirEnd: FlightGroundPose? = nil
    var groundTrack: [FlightGroundPose] = []
    var runwayTrack: [FlightGroundPose] = []
    var isVisible = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }
    private var fraction: Double { progress.isFinite ? min(1, max(0, progress)) : 0 }

    var body: some View {
        Group {
            if DistributionPolicy.mapsAvailable, CLLocationCoordinate2DIsValid(origin.coordinate),
               CLLocationCoordinate2DIsValid(destination.coordinate) {
                FlightSimulatorRouteMap(origin: origin, destination: destination, progress: fraction,
                                        aircraft: aircraft, isFlying: isFlying, groundPose: groundPose,
                                        departureAirStart: departureAirStart, arrivalAirEnd: arrivalAirEnd,
                                        groundTrack: groundTrack, runwayTrack: runwayTrack, isVisible: isVisible)
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
    let groundPose: FlightGroundPose?
    let groundTrack: [FlightGroundPose]
    let runwayTrack: [FlightGroundPose]
    let isVisible: Bool
    private let airAnchors: AirAnchors

    private let arc: FlightSimulatorArc
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: FlightSimulatorMapCamera
    @State private var viewpoint: Viewpoint = .overview
    @State private var viewportSize = CGSize(width: 390, height: 235)
    @State private var projection = FlightSimulatorMapProjection()
    @State private var scrollVisible = true
    @State private var userChoseViewpoint = false
    @State private var lastFollowUpdate: ContinuousClock.Instant?

    private enum Viewpoint { case overview, follow, global, free }

    private struct TrackingState: Equatable {
        let progress: Double
        let groundPose: FlightGroundPose?
        let airAnchors: AirAnchors
        let isFlying: Bool
    }

    private struct AirAnchors: Equatable {
        let departure: FlightGroundPose?
        let arrival: FlightGroundPose?

        func arc(origin: Airport, destination: Airport) -> FlightSimulatorArc {
            FlightSimulatorArc(origin: coordinate(of: departure) ?? origin.coordinate,
                               destination: coordinate(of: arrival) ?? destination.coordinate,
                               departureCourse: departure?.heading, arrivalCourse: arrival?.heading)
        }

        private func coordinate(of pose: FlightGroundPose?) -> CLLocationCoordinate2D? {
            guard let coordinate = pose?.coordinate, CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            return coordinate
        }
    }

    init(origin: Airport, destination: Airport, progress: Double, aircraft: FlightSimulatorAircraftMarker?,
         isFlying: Bool, groundPose: FlightGroundPose?, departureAirStart: FlightGroundPose?, arrivalAirEnd: FlightGroundPose?,
         groundTrack: [FlightGroundPose], runwayTrack: [FlightGroundPose], isVisible: Bool) {
        self.origin = origin
        self.destination = destination
        self.progress = progress
        self.aircraft = aircraft
        self.isFlying = isFlying
        self.groundPose = groundPose
        self.groundTrack = groundTrack
        self.runwayTrack = runwayTrack
        self.isVisible = isVisible
        let anchors = AirAnchors(departure: departureAirStart, arrival: arrivalAirEnd)
        airAnchors = anchors
        let arc = anchors.arc(origin: origin, destination: destination)
        self.arc = arc
        _camera = State(initialValue: FlightSimulatorMapCamera(arc.overviewCamera(aspect: 1.3)))
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.origin == rhs.origin && lhs.destination == rhs.destination && lhs.progress == rhs.progress
            && lhs.aircraft == rhs.aircraft && lhs.isFlying == rhs.isFlying
            && lhs.groundPose == rhs.groundPose && lhs.airAnchors == rhs.airAnchors
            && lhs.groundTrack == rhs.groundTrack && lhs.runwayTrack == rhs.runwayTrack && lhs.isVisible == rhs.isVisible
    }

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }
    private var mapVisible: Bool { isVisible && scrollVisible }
    private var trackingState: TrackingState {
        TrackingState(progress: progress, groundPose: groundPose, airAnchors: airAnchors, isFlying: isFlying)
    }

    var body: some View {
        mapLayout
            .onChange(of: trackingState) { previous, next in
                track(from: previous, to: next)
            }
            .onScrollVisibilityChange(threshold: 0.12) { isVisible in
                scrollVisible = isVisible
            }
            .onChange(of: mapVisible) { _, visible in
                lastFollowUpdate = nil
                if visible { reframeViewport() }
            }
    }

    private func track(from previous: TrackingState, to next: TrackingState) {
        let endpointsChanged = previous.airAnchors != next.airAnchors
        let sessionChanged = previous.isFlying != next.isFlying
        if sessionChanged && !userChoseViewpoint {
            if next.isFlying && viewpoint == .overview { viewpoint = .follow }
            else if !next.isFlying && next.progress == 0 && viewpoint == .follow {
                viewpoint = .overview
                moveCamera(to: overviewCamera)
                return
            }
        }
        if endpointsChanged && viewpoint == .overview {
            moveCamera(to: overviewCamera)
            return
        }
        let groundTransition = (previous.groundPose == nil) != (next.groundPose == nil)
        let routeEdge = previous.progress != next.progress && (next.progress == 0 || next.progress == 1)
        updateTrackingCamera(force: endpointsChanged || sessionChanged || groundTransition || routeEdge)
    }

    private var mapLayout: some View {
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
    }

    private var mapCanvas: some View {
        FlightSimulatorNativeMap(arc: arc, progress: progress, groundPose: groundPose, isVisible: mapVisible,
                                 groundTrack: groundTrack, runwayTrack: runwayTrack,
                                 origin: origin.coordinate, destination: destination.coordinate, camera: camera) { result in
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
            reframeViewport()
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
        guard let profile = aircraft?.profile else { return 32 }
        let shortSide = max(1, min(size.width, size.height))
        let extent = max(profile.wingspanM, profile.lengthM)
        let typeWeight = pow(min(2, max(0.45, extent / 40)), 0.14)
        let minimum = min(shortSide * 0.29, min(84, max(56, shortSide * 0.19)) * typeWeight)
        let maximum = max(minimum, min(shortSide * 0.49, size.width * 0.39, 182))
        // The top-down model occupies about two thirds of its transparent rendering surface.
        let physical = max(profile.lengthM * projection.courseScale, profile.wingspanM * projection.spanScale) / 0.65
        let range = maximum - minimum
        guard range > 0, physical.isFinite else { return minimum }
        // A smooth shoulder keeps the aircraft readable at globe scale and leaves runway context at street scale.
        return minimum + range * tanh(max(0, hypot(minimum, physical) - minimum) / range)
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

    private var globalCamera: MapCamera { arc.globalCamera(aspect: viewportAspect, at: progress) }

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
                updateTrackingCamera(force: true)
            }
            .accessibilityIdentifier("simulator-globe-follow")
            Button("全球视角", systemImage: viewpoint == .global ? "checkmark" : "network") {
                userChoseViewpoint = true
                viewpoint = .global
                moveCamera(to: globalCamera)
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

    private func updateTrackingCamera(force: Bool) {
        guard mapVisible else { return }
        let target: MapCamera
        switch viewpoint {
        case .follow:
            target = arc.followCamera(at: progress, groundCoordinate: groundPose?.coordinate)
        case .global:
            target = globalCamera
            if !force, FlightSimulatorArc.angularDistance(camera.value.centerCoordinate, target.centerCoordinate) < .pi / 90 {
                return
            }
        case .overview, .free:
            return
        }
        let now = ContinuousClock.now
        if !force, let lastFollowUpdate, lastFollowUpdate.duration(to: now) < .milliseconds(600) { return }
        lastFollowUpdate = now
        moveCamera(to: target)
    }

    private func reframeViewport() {
        guard mapVisible else { return }
        switch viewpoint {
        case .overview: moveCamera(to: overviewCamera, animated: false)
        case .global: moveCamera(to: globalCamera, animated: false)
        case .follow:
            moveCamera(to: arc.followCamera(at: progress, groundCoordinate: groundPose?.coordinate), animated: false)
            lastFollowUpdate = ContinuousClock.now
        case .free: break
        }
    }

    private func moveCamera(to camera: MapCamera, animated: Bool = true) {
        guard mapVisible, !self.camera.matches(camera) else { return }
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

    func matches(_ camera: MapCamera) -> Bool {
        value.centerCoordinate.latitude == camera.centerCoordinate.latitude
            && value.centerCoordinate.longitude == camera.centerCoordinate.longitude
            && value.distance == camera.distance && value.pitch == camera.pitch && value.heading == camera.heading
    }
}

private struct FlightSimulatorMapProjection: Equatable {
    var origin: CGPoint?
    var destination: CGPoint?
    var aircraft: CGPoint?
    var heading = 0.0
    var courseScale = 0.0
    var spanScale = 0.0
}

// Use the native canvas for the route and point conversion, including in a pitched globe view.
private struct FlightSimulatorNativeMap: UIViewRepresentable {
    let arc: FlightSimulatorArc
    let progress: Double
    let groundPose: FlightGroundPose?
    let isVisible: Bool
    let groundTrack: [FlightGroundPose]
    let runwayTrack: [FlightGroundPose]
    let origin: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
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
        coordinator.observeGestures(on: map)
        map.canvasResized = { [weak map, weak coordinator] in
            if let map { coordinator?.project(on: map) }
        }
        coordinator.synchronize(on: map, forceProjection: true, animateCamera: false)
        return map
    }

    func updateUIView(_ map: Canvas, context: Context) {
        let coordinator = context.coordinator
        let before = coordinator.parent
        coordinator.parent = self
        guard isVisible else {
            if before.isVisible { coordinator.suspendProjection() }
            return
        }
        let positionChanged = before.progress != progress || before.groundPose != groundPose
        coordinator.synchronize(on: map, forceProjection: !before.isVisible || positionChanged,
                                animateCamera: before.isVisible)
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
        private var routeLines: [MKPolyline] = []
        private var routeInk: Set<ObjectIdentifier> = []
        private var runwayLine: MKPolyline?
        private var taxiLine: MKPolyline?
        private var queuedProjection: FlightSimulatorMapProjection?
        private var deliveredProjection: FlightSimulatorMapProjection?
        private var hasPendingDelivery = false
        private var appliedArc: FlightSimulatorArc?
        private var appliedGroundTrack: [FlightGroundPose] = []
        private var appliedRunwayTrack: [FlightGroundPose] = []
        private var appliedCamera: UUID?
        private var active = true

        init(parent: FlightSimulatorNativeMap) { self.parent = parent }

        func synchronize(on map: MKMapView, forceProjection: Bool, animateCamera: Bool) {
            guard active, parent.isVisible else { return }
            let routeChanged = appliedArc != parent.arc
            if routeChanged {
                appliedArc = parent.arc
                prepareRoute(on: map)
            }
            if appliedGroundTrack != parent.groundTrack || appliedRunwayTrack != parent.runwayTrack {
                appliedGroundTrack = parent.groundTrack
                appliedRunwayTrack = parent.runwayTrack
                updateGroundLines(on: map)
            }
            let cameraChanged = appliedCamera != parent.camera.revision
            if cameraChanged {
                appliedCamera = parent.camera.revision
                map.setCamera(parent.camera.native, animated: animateCamera && parent.camera.animated)
            }
            if forceProjection || routeChanged || cameraChanged { project(on: map) }
        }

        func suspendProjection() {
            queuedProjection = nil
            deliveredProjection = nil
        }

        private func prepareRoute(on map: MKMapView) {
            map.removeOverlays(routeLines)
            let segments = parent.arc.segments()
            let outlines = segments.map { MKGeodesicPolyline(coordinates: $0, count: $0.count) }
            let inks = segments.map { MKGeodesicPolyline(coordinates: $0, count: $0.count) }
            routeInk = Set(inks.map(ObjectIdentifier.init))
            routeLines = outlines + inks
            map.addOverlays(routeLines, level: .aboveLabels)
        }

        private func updateGroundLines(on map: MKMapView) {
            map.removeOverlays([runwayLine, taxiLine].compactMap { $0 })
            runwayLine = groundLine(parent.runwayTrack)
            taxiLine = parent.groundTrack == parent.runwayTrack ? nil : groundLine(parent.groundTrack)
            map.addOverlays([runwayLine, taxiLine].compactMap { $0 }, level: .aboveLabels)
        }

        private func groundLine(_ positions: [FlightGroundPose]) -> MKPolyline? {
            let coordinates = positions.map(\.coordinate)
            guard coordinates.count > 1 else { return nil }
            return MKGeodesicPolyline(coordinates: coordinates, count: coordinates.count)
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
            if parent.isVisible && gesture.state == .began { parent.onUserGesture() }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            switch line {
            case _ where line === runwayLine:
                renderer.strokeColor = .white
                renderer.lineWidth = 2.6
            case _ where line === taxiLine:
                renderer.strokeColor = .systemYellow
                renderer.lineWidth = 3.2
            case _ where routeInk.contains(ObjectIdentifier(line)):
                renderer.strokeColor = .systemMint
                renderer.lineWidth = 2.5
            default:
                renderer.strokeColor = UIColor.black.withAlphaComponent(0.65)
                renderer.lineWidth = 5
            }
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { project(on: mapView) }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { project(on: mapView) }
        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) { project(on: mapView) }

        func project(on map: MKMapView) {
            guard active, parent.isVisible, !map.bounds.isEmpty else { return }
            let arc = parent.arc
            let fraction = parent.progress
            let camera = map.camera
            let mapCamera = MapCamera(centerCoordinate: camera.centerCoordinate, distance: camera.centerCoordinateDistance,
                                      heading: camera.heading, pitch: camera.pitch)
            let coordinate = parent.groundPose?.coordinate ?? arc.coordinate(at: fraction)
            let trueHeading = parent.groundPose?.heading ?? arc.heading(at: fraction)
            let observer = FlightSimulatorArc.Observer(camera: mapCamera)
            let aircraft = visiblePoint(for: coordinate, on: map, observer: observer)
            let body = aircraft.flatMap {
                projectedAxis(at: coordinate, course: trueHeading, on: map, observer: observer, camera: mapCamera, center: $0)
            }
            let wing = aircraft.flatMap {
                projectedAxis(at: coordinate, course: trueHeading + 90, on: map, observer: observer, camera: mapCamera, center: $0)
            }
            let heading = body?.heading ?? trueHeading - camera.heading
            let projection = FlightSimulatorMapProjection(
                origin: visiblePoint(for: parent.origin, on: map, observer: observer),
                destination: visiblePoint(for: parent.destination, on: map, observer: observer),
                aircraft: aircraft,
                heading: (heading * 4).rounded() / 4,
                courseScale: ((body?.pointsPerMeter ?? 0) * 1_000).rounded() / 1_000,
                spanScale: ((wing?.pointsPerMeter ?? 0) * 1_000).rounded() / 1_000
            )
            queuedProjection = projection
            guard !hasPendingDelivery, deliveredProjection != projection else { return }
            hasPendingDelivery = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hasPendingDelivery = false
                guard self.active, self.parent.isVisible, let latest = self.queuedProjection,
                      latest != self.deliveredProjection else { return }
                self.deliveredProjection = latest
                self.parent.onProjection(latest)
            }
        }

        private func projectedAxis(at coordinate: CLLocationCoordinate2D, course: Double, on map: MKMapView,
                                   observer: FlightSimulatorArc.Observer, camera: MapCamera,
                                   center: CGPoint) -> (heading: Double, pointsPerMeter: Double)? {
            let distance = max(0.2, min(26_000, camera.distance * 0.004))
            let ahead = FlightSimulatorArc.offset(from: coordinate, course: course, meters: distance)
            let behind = FlightSimulatorArc.offset(from: coordinate, course: course + 180, meters: distance)
            let limit = max(14, min(map.bounds.width, map.bounds.height) * 0.12)

            func probe(_ coordinate: CLLocationCoordinate2D) -> CGPoint? {
                guard observer.sees(coordinate) else { return nil }
                let projected = map.convert(coordinate, toPointTo: map)
                let separation = hypot(projected.x - center.x, projected.y - center.y)
                // A projection on another wrapped copy of the globe is never a local tangent sample.
                return separation.isFinite && separation <= limit ? projected : nil
            }

            let before = probe(behind)
            let after = probe(ahead)
            let dx = (after ?? center).x - (before ?? center).x
            let dy = (after ?? center).y - (before ?? center).y
            let separation = hypot(dx, dy)
            guard separation > 0.02 else { return nil }
            let meters = before != nil && after != nil ? distance * 2 : distance
            return (atan2(dy, dx) * 180 / .pi + 90, separation / meters)
        }

        private func visiblePoint(for coordinate: CLLocationCoordinate2D, on map: MKMapView,
                                  observer: FlightSimulatorArc.Observer) -> CGPoint? {
            guard observer.sees(coordinate) else { return nil }
            let point = map.convert(coordinate, toPointTo: map)
            guard map.bounds.contains(point) else { return nil }
            return CGPoint(x: (point.x * 4).rounded() / 4, y: (point.y * 4).rounded() / 4)
        }

        func invalidate() { active = false }
    }
}
