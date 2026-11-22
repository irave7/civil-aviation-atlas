import MapKit
import SwiftUI
#if !MAINLAND_DISTRIBUTION
import ImageIO
import UniformTypeIdentifiers
#endif

#if MAINLAND_DISTRIBUTION && !MAINLAND_APPROVED_MAPS
struct AirportImagery: View {
    let airport: Airport

    var body: some View {
        ContentUnavailableView("暂无实景", systemImage: "globe.asia.australia", description: Text(airport.displayName))
            .accessibilityIdentifier("mainland-airport-imagery-unavailable")
    }
}
#else
private enum AirportImagerySource: String, Identifiable {
    case apple = "Apple 卫星影像"
#if MAINLAND_DISTRIBUTION
    case offline = "影像暂不可用"
#else
    case sentinel = "Sentinel-2 历史卫星影像"
    case offline = "离线机场图"
#endif

    var id: Self { self }

    var symbol: String {
        switch self {
        case .apple: "globe.asia.australia"
#if !MAINLAND_DISTRIBUTION
        case .sentinel: "globe"
#endif
        case .offline: "map"
        }
    }

}

private enum AirportImageryLoad: Equatable {
    case loading, ready, limitedDetail, partial, failed
}

struct AirportImagery: View {
    let airport: Airport
#if !MAINLAND_DISTRIBUTION
    private let plan: AirportSitePlan
#endif
    private let siteCamera: MapCamera
    @State private var currentCamera: MapCamera
    @State private var cameraChange = 0
    @State private var lastTilt = 46.0
    @State private var source: AirportImagerySource
    @State private var status = AirportImageryLoad.loading
    @State private var didRender = false
    @State private var attempt = 0
    @State private var automatic = true
#if !MAINLAND_DISTRIBUTION
    @State private var lookAround: MKLookAroundScene?
    @State private var showLookAround = false
    @State private var showPhotos = false
#endif

    init(airport: Airport) {
        self.airport = airport
#if MAINLAND_DISTRIBUTION
        let initial = MapCamera(centerCoordinate: airport.coordinate, distance: 5_800)
#else
        let airportPlan = AirportSiteCatalog.plan(for: airport)
        plan = airportPlan
        let initial = Self.fitAirport(airport, plan: airportPlan)
#endif
        siteCamera = initial
        _currentCamera = State(initialValue: initial)
        _source = State(initialValue: Self.preferredSource(for: airport))
    }

    private var isTilted: Bool { currentCamera.pitch > 6 }

    private static func preferredSource(for airport: Airport) -> AirportImagerySource {
#if MAINLAND_DISTRIBUTION
        .apple
#else
        airport.countryCode == "CN" ? .apple : .sentinel
#endif
    }

    private var sourceOptions: [AirportImagerySource] {
#if MAINLAND_DISTRIBUTION
        [.apple, .offline]
#else
        airport.countryCode == "CN" ? [.apple, .offline] : [.sentinel, .apple, .offline]
#endif
    }

    private var automaticFallback: AirportImagerySource? {
        guard let index = sourceOptions.firstIndex(of: source) else { return nil }
        let next = sourceOptions.index(after: index)
        return sourceOptions.indices.contains(next) ? sourceOptions[next] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            viewport
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controls
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
        .background(Color(red: 0.063, green: 0.104, blue: 0.145))
        .colorScheme(.dark)
        .tint(.mint)
#if !MAINLAND_DISTRIBUTION
        .sheet(isPresented: $showPhotos) { AirportPhotos(airport: airport) }
        .lookAroundViewer(isPresented: $showLookAround, initialScene: lookAround)
        .task(id: airport.id) { await requestStreetView() }
#endif
        .task(id: attempt) {
            guard let fallback = automaticFallback else { return }
            let startingAttempt = attempt
            do { try await Task.sleep(for: .seconds(9)) } catch { return }
            guard attempt == startingAttempt && !didRender else { return }
            if automatic { switchSource(fallback, automatic: true) }
            else if status == .loading { status = .failed }
        }
    }

    @ViewBuilder
    private var viewport: some View {
        if source == .offline {
#if MAINLAND_DISTRIBUTION
            ContentUnavailableView {
                Label("卫星影像暂不可用", systemImage: "globe.asia.australia")
            } description: {
                Text("检查网络连接后重新加载影像。")
            } actions: {
                Button("重新加载") { switchSource(.apple, automatic: true) }
            }
            .accessibilityIdentifier("mainland-satellite-unavailable")
#else
            if !plan.features.isEmpty || !plan.runways.isEmpty {
                AirportPlanView(airport: airport)
            } else {
                ContentUnavailableView {
                    Label(airport.displayName, systemImage: "mappin.circle")
                } description: {
                    Text("\(airport.displayCode) · \(airport.lat.formatted(.number.precision(.fractionLength(5))))°, \(airport.lon.formatted(.number.precision(.fractionLength(5))))°\n已保存机场参考点，当前没有可用的离线跑道图形。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("airport-offline-location")
            }
#endif
        } else {
            mapView(attempt: attempt)
        }
    }

    private func mapView(attempt mapAttempt: Int) -> some View {
        AirportSatelliteMap(
            airport: airport, source: source, camera: currentCamera, cameraChange: cameraChange,
            cameraChanged: { camera in
                guard mapAttempt == attempt else { return }
                currentCamera = camera
                if camera.pitch >= 16 { lastTilt = camera.pitch }
            },
            loadChanged: { update in
                guard mapAttempt == attempt else { return }
                if update == .ready || update == .limitedDetail { didRender = true }
                status = update
            }
        )
        .id(mapAttempt)
        .accessibilityIdentifier("airport-satellite-map")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(source == .offline ? source.rawValue : "卫星影像") · \(airport.displayCode) · \(airport.displayName)")
                    .font(AtlasTypography.font(.caption, weight: .semibold))
                    .lineLimit(2)
                Text(statusText)
                    .font(AtlasTypography.font(.caption2))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("airport-imagery-status")
#if !MAINLAND_DISTRIBUTION
                if source == .sentinel {
                    Link("EOxCloudless — EOX IT Services GmbH", destination: URL(string: "https://cloudless.eox.at/")!)
                        .foregroundStyle(.mint)
                    Link("Contains modified Copernicus Sentinel data 2016 & 2017 · CC BY 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                        .foregroundStyle(.mint)
                }
#endif
            }
            .font(AtlasTypography.font(.caption2))
            ViewThatFits(in: .horizontal) {
                buttons(iconOnly: false).fixedSize(horizontal: true, vertical: false)
                buttons(iconOnly: true)
            }
        }
    }

    private var statusText: String {
        switch (source, status) {
#if MAINLAND_DISTRIBUTION
        case (.offline, _): "请重新加载 Apple 卫星影像"
        case (.apple, .partial), (.apple, .limitedDetail): "正在载入更多 Apple 卫星影像"
        case (.apple, .failed): "Apple 影像暂不可用"
#else
        case (.offline, _): "离线公开资料 · 可从影像来源菜单重试"
        case (.apple, .partial), (.apple, .limitedDetail): "部分 Apple 影像尚未载入，可切换影像来源"
        case (.apple, .failed): "Apple 影像暂不可用，可切换来源或重试"
        case (.sentinel, .loading): "正在加载 EOX 历史卫星影像"
        case (.sentinel, .ready): "2016 年 Sentinel-2 区域合成 · 平面影像，机场设施可能已变化"
        case (.sentinel, .limitedDetail): "2016 年历史影像 · 机场参考点附近细节有限，可查看离线图"
        case (.sentinel, .partial): "2016 年历史合成 · 部分区域瓦片尚未载入"
        case (.sentinel, .failed): "EOX 影像暂不可用，可切换至 Apple 卫星影像或离线机场图"
#endif
        case (.apple, .loading): "正在加载 Apple 卫星影像"
        case (.apple, .ready): "Apple 地图 · 影像时间和清晰度随地区变化"
        }
    }

    private func buttons(iconOnly: Bool) -> some View {
        HStack(spacing: 7) {
#if !MAINLAND_DISTRIBUTION
            Menu {
                Button("自动选择卫星影像", systemImage: "arrow.trianglehead.clockwise") {
                    switchSource(Self.preferredSource(for: airport), automatic: true)
                }
                Divider()
                ForEach(sourceOptions) { item in
                    Button {
                        switchSource(item, automatic: false)
                    } label: {
                        Label(item.rawValue, systemImage: source == item ? "checkmark" : item.symbol)
                    }
                }
            } label: {
                label("影像来源", symbol: "square.3.layers.3d", iconOnly: iconOnly)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("airport-imagery-source")
#endif

            if source != .offline {
                Button {
                    setCamera(center: currentCamera.centerCoordinate, distance: currentCamera.distance, pitch: isTilted ? 0 : lastTilt)
                } label: {
                    label(isTilted ? "卫星俯视" : "倾斜视角", symbol: isTilted ? "view.2d" : "view.3d", iconOnly: iconOnly)
                }
                .buttonStyle(.glass)
                .accessibilityValue(isTilted ? "倾斜" : "俯视")
                .accessibilityIdentifier("airport-imagery-pitch")

                Button {
                    setCamera(center: siteCamera.centerCoordinate, distance: siteCamera.distance, pitch: currentCamera.pitch)
                } label: {
                    label("查看全场", symbol: "location.viewfinder", iconOnly: iconOnly)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("airport-imagery-recenter")
            }
#if !MAINLAND_DISTRIBUTION
            if AirportPhotos.available(for: airport) {
                Button { showPhotos = true } label: {
                    label("实景照片", symbol: "photo.on.rectangle.angled", iconOnly: iconOnly)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("airport-imagery-photos")
            }
            if lookAround != nil {
                Button { showLookAround = true } label: {
                    label("街景", symbol: "binoculars", iconOnly: iconOnly)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("airport-imagery-look-around")
            }
#endif
        }
    }

    @ViewBuilder
    private func label(_ title: String, symbol: String, iconOnly: Bool) -> some View {
        if iconOnly { Label(title, systemImage: symbol).labelStyle(.iconOnly) }
        else { Label(title, systemImage: symbol) }
    }

    private func switchSource(_ next: AirportImagerySource, automatic: Bool) {
        guard sourceOptions.contains(next) else { return }
        self.automatic = automatic
        source = next
        status = .loading
        didRender = false
        attempt += 1
    }

    private func setCamera(center: CLLocationCoordinate2D, distance: Double, pitch: Double) {
        currentCamera = MapCamera(centerCoordinate: center, distance: distance, heading: currentCamera.heading, pitch: pitch)
        cameraChange += 1
    }

#if !MAINLAND_DISTRIBUTION
    private func requestStreetView() async {
        let terminal = plan.features.filter { $0.source.kind == .terminal }.max { $0.bounds.span < $1.bounds.span }
        let coordinate = terminal.map { Self.coordinate(for: $0.bounds.center, airport: airport) } ?? airport.coordinate
        if let scene = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene, !Task.isCancelled {
            lookAround = scene
        }
    }

    private static func fitAirport(_ airport: Airport, plan: AirportSitePlan) -> MapCamera {
        let mappedPoints = plan.features.flatMap(\.points) + plan.runways.filter { !$0.approximatePlacement }.flatMap(\.ends)
        let metersPerUnit = Double(AirportSiteCatalog.metersPerUnit)
        guard !mappedPoints.isEmpty else {
            let distance = plan.runways.map(\.length).max().map { max(2_400, Double($0) * metersPerUnit * 2.35) } ?? 5_800
            return MapCamera(centerCoordinate: airport.coordinate, distance: distance)
        }
        let bounds = AirportSitePlan.Bounds(mappedPoints)
        return MapCamera(centerCoordinate: coordinate(for: bounds.center, airport: airport), distance: max(2_400, Double(bounds.span) * metersPerUnit * 2.35))
    }

    private static func coordinate(for point: SIMD2<Float>, airport: Airport) -> CLLocationCoordinate2D {
        let scale = Double(AirportSiteCatalog.metersPerUnit)
        let latitude = airport.lat - Double(point.y) * scale / 110_750
        let metersPerLongitudeDegree = 111_319.49 * max(0.01, cos(airport.lat * .pi / 180))
        let longitude = airport.lon + Double(point.x) * scale / metersPerLongitudeDegree
        let wrappedLongitude = (longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        return CLLocationCoordinate2D(latitude: min(90, max(-90, latitude)), longitude: wrappedLongitude)
    }
#endif
}

private struct AirportSatelliteMap: UIViewRepresentable {
    let airport: Airport
    let source: AirportImagerySource
    let camera: MapCamera
    let cameraChange: Int
    let cameraChanged: (MapCamera) -> Void
    let loadChanged: (AirportImageryLoad) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
        map.isPitchEnabled = true
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 180, maxCenterCoordinateDistance: 3_000_000)

        switch source {
        case .apple:
            map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
#if !MAINLAND_DISTRIBUTION
        case .sentinel:
            map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
            let tiles = AirportSentinelTiles(reference: MKMapPoint(airport.coordinate)) { [weak coordinator = context.coordinator] loaded, limitedDetail in
                Task { @MainActor in coordinator?.archiveTileFinished(loaded: loaded, limitedDetail: limitedDetail) }
            }
            map.addOverlay(tiles, level: .aboveLabels)
#endif
        case .offline:
            break
        }
#if !MAINLAND_DISTRIBUTION
        let reference = MKPointAnnotation()
        reference.coordinate = airport.coordinate
        reference.title = airport.displayCode
        reference.subtitle = airport.displayName
        map.addAnnotation(reference)
#endif
        map.setCamera(nativeCamera, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let previous = context.coordinator.parent.cameraChange
        context.coordinator.parent = self
        if previous != cameraChange { map.setCamera(nativeCamera, animated: true) }
    }

    private var nativeCamera: MKMapCamera {
        MKMapCamera(lookingAtCenter: camera.centerCoordinate, fromDistance: camera.distance, pitch: camera.pitch, heading: camera.heading)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: AirportSatelliteMap
        private var latest: AirportImageryLoad = .loading
#if !MAINLAND_DISTRIBUTION
        private var receivedArchiveTile = false
        private var archiveDetailIsLimited = false
#endif

        init(parent: AirportSatelliteMap) { self.parent = parent }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let value = mapView.camera
            let camera = MapCamera(centerCoordinate: value.centerCoordinate, distance: value.centerCoordinateDistance, heading: value.heading, pitch: value.pitch)
            guard CLLocationCoordinate2DIsValid(camera.centerCoordinate), camera.distance.isFinite, camera.distance > 0 else { return }
            Task { @MainActor [weak self] in self?.parent.cameraChanged(camera) }
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard parent.source == .apple else { return }
            report(fullyRendered ? .ready : .partial)
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: any Error) {
            guard parent.source == .apple else { return }
            report(latest == .ready ? .partial : .failed)
        }

#if !MAINLAND_DISTRIBUTION
        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let tileOverlay = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            return MKTileOverlayRenderer(tileOverlay: tileOverlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let identifier = "airport-reference"
            let marker = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            marker.annotation = annotation
            marker.glyphImage = UIImage(systemName: "airplane")
            marker.markerTintColor = .systemTeal
            marker.canShowCallout = true
            return marker
        }

        func archiveTileFinished(loaded: Bool, limitedDetail: Bool?) {
            if loaded { receivedArchiveTile = true }
            if let limitedDetail { archiveDetailIsLimited = limitedDetail }
            report(loaded ? (archiveDetailIsLimited ? .limitedDetail : .ready) : (receivedArchiveTile ? .partial : .failed))
        }
#endif

        private func report(_ update: AirportImageryLoad) {
            guard latest != update else { return }
            latest = update
            Task { @MainActor [weak self] in
                guard let self, self.latest == update else { return }
                self.parent.loadChanged(update)
            }
        }
    }
}
#endif

#if !MAINLAND_DISTRIBUTION
private final class AirportSentinelTiles: MKTileOverlay, @unchecked Sendable {
    private static let nativeMaximumZoom = 14
    private let reference: MKMapPoint
    private let tileFinished: @Sendable (Bool, Bool?) -> Void

    init(reference: MKMapPoint, tileFinished: @escaping @Sendable (Bool, Bool?) -> Void) {
        self.reference = reference
        self.tileFinished = tileFinished
        super.init(urlTemplate: nil)
        canReplaceMapContent = true
        maximumZ = 22
        tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, (any Error)?) -> Void) {
        guard (0...maximumZ).contains(path.z) else {
            result(nil, URLError(.badURL))
            return
        }
        let zoom = min(path.z, Self.nativeMaximumZoom)
        let divisions = 1 << (path.z - zoom)
        let dimension = 1 << path.z
        let wrappedX = (path.x % dimension + dimension) % dimension
        guard (0..<dimension).contains(path.y) else {
            result(nil, URLError(.badURL))
            return
        }
        let x = wrappedX / divisions
        let y = path.y / divisions
        let scale = Double(1 << zoom) / MKMapSize.world.width
        let showsReference = zoom >= 12 && Int(reference.x * scale) == x && Int(reference.y * scale) == y
        // Only the 2016 layer uses EOX's CC BY 4.0 embedded-viewing terms.
        let url = URL(string: "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default/GoogleMapsCompatible/\(zoom)/\(y)/\(x).jpg")!
        Task.detached(priority: .userInitiated) { [tileFinished] in
            do {
                let data = try await AirportSentinelRequests.shared.tile(at: url)
                guard let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) > 0 else {
                    throw URLError(.cannotDecodeContentData)
                }
                let tile = divisions == 1 ? data : Self.crop(image, column: wrappedX % divisions, row: path.y % divisions, divisions: divisions)
                result(tile, tile == nil ? URLError(.cannotDecodeContentData) : nil)
                tileFinished(tile != nil, showsReference ? Self.isNearlyUniform(image) : nil)
            } catch {
                result(nil, error)
                tileFinished(false, nil)
            }
        }
    }

    private static func crop(_ source: CGImageSource, column: Int, row: Int, divisions: Int) -> Data? {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = max(1, image.width / divisions)
        let height = max(1, image.height / divisions)
        let rect = CGRect(x: min(image.width - width, column * image.width / divisions),
                          y: min(image.height - height, row * image.height / divisions), width: width, height: height)
        let data = NSMutableData()
        guard let cropped = image.cropping(to: rect),
              let encoded = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(encoded, cropped, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        return CGImageDestinationFinalize(encoded) ? data as Data : nil
    }

    private static func isNearlyUniform(_ source: CGImageSource) -> Bool? {
        let size = 16
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: size] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return (0..<3).allSatisfy { channel in
                let samples = stride(from: channel, to: buffer.count, by: 4).map { buffer[$0] }
                return Int(samples.max() ?? 0) - Int(samples.min() ?? 0) < 12
            }
        }
    }
}

private actor AirportSentinelRequests {
    static let shared = AirportSentinelRequests()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        configuration.httpMaximumConnectionsPerHost = 5
        configuration.urlCache = URLCache(memoryCapacity: 12 * 1024 * 1024, diskCapacity: 0)
        return URLSession(configuration: configuration)
    }()
    private var active: [URL: Task<Data, Error>] = [:]

    func tile(at url: URL) async throws -> Data {
        if let existing = active[url] { return try await existing.value }
        // A close zoom may show several crops of one native-resolution archive tile.
        let request = Task { [session] in
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.mimeType == "image/jpeg" else {
                throw URLError(.badServerResponse)
            }
            return data
        }
        active[url] = request
        defer { active[url] = nil }
        return try await request.value
    }
}
#endif
