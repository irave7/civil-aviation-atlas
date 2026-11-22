import MapKit
import SwiftUI

extension Airport {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

#if MAINLAND_DISTRIBUTION && !MAINLAND_APPROVED_MAPS
struct GlobeView: View {
    let library: AtlasLibrary
    let open: (Airport) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("探索机场")
                        .font(AtlasTypography.font(.largeTitle, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("从机场目录查找机场，或选择下方机场查看资料。")
                        .foregroundStyle(.secondary)
                }
                ForEach(library.featured) { airport in
                    Button { open(airport) } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "airplane.arrival")
                                .foregroundStyle(.teal)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(airport.displayName)
                                    .font(AtlasTypography.font(.headline))
                                Text(airport.displayCode)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: .rect(cornerRadius: 14))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("globe-featured-\(airport.id)")
                }
                if let number = DistributionPolicy.icpRecordNumber {
                    Link("APP 备案号 \(number)", destination: DistributionPolicy.icpLookupURL)
                        .font(.footnote)
                }
            }
            .frame(maxWidth: 570, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("mainland-airport-browse")
    }
}
#else
#if !MAINLAND_DISTRIBUTION
private enum GlobeAirportCategory {
    case transport, heliport, other

    init(_ airport: Airport) {
        if airport.type == "heliport" {
            self = .heliport
            return
        }
        let militaryFacility = [
            "air force base", "air force station", "air base", "naval air station", "naval air facility",
            "military airfield", "military airport", "military city", "aeropuerto militar", "base aérea", "空军基地", "军用机场"
        ].contains(where: airport.name.localizedCaseInsensitiveContains)
            || airport.name.hasPrefix("RAF ")
        let isPublic = airport.publicAccess?.contains("非公众使用") != true
        let isPreparing = airport.operatingStatus?.contains("筹备") == true
        let hasCivilTransport = airport.civilUse == "运输机场"
            || (airport.civilUse != "通用机场" && airport.scheduledService == true)
        self = isPublic && !militaryFacility && !isPreparing && hasCivilTransport ? .transport : .other
    }

    var symbol: String {
        switch self {
        case .transport: "airplane"
        case .heliport: "helicopter"
        case .other: "mappin"
        }
    }

    var color: Color {
        switch self {
        case .transport: .teal
        case .heliport: .orange
        case .other: .indigo
        }
    }
}
#endif

struct GlobeView: View {
    let library: AtlasLibrary
    let open: (Airport) -> Void
    @State private var position = Self.worldCamera
#if !MAINLAND_DISTRIBUTION
    @State private var visibleRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 24, longitude: 115),
        span: MKCoordinateSpan(latitudeDelta: 110, longitudeDelta: 160)
    )
    @State private var isLocalView = false
    @State private var selection: String?
    @State private var routeLayer = true
    @State private var showsHeliports = false
    @State private var showsOtherAirports = false
#endif
    @Namespace private var mapScope

    private static var worldCamera: MapCameraPosition {
        .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 24, longitude: 115), distance: 31_000_000))
    }

#if !MAINLAND_DISTRIBUTION
    private var mapAirports: [Airport] {
        var visited: Set<String> = []
        let priority = ["PVG", "PEK", "HND", "ICN", "SYD", "LHR", "DXB", "JFK", "LAX", "FRA", "IST", "DOH", "DEL", "CPT", "GRU"]
        let featured = library.featured + priority.compactMap(library.airport)
        if isLocalView {
            return nearestVisibleAirports(limit: 70, includeTransport: true)
        }
        let nearbyOptional = showsHeliports || showsOtherAirports
            ? nearestVisibleAirports(limit: 10, includeTransport: false) : []
        return (featured.filter { GlobeAirportCategory($0) == .transport } + nearbyOptional)
            .filter { $0.hasCoordinates && visited.insert($0.id).inserted }
    }

    private func nearestVisibleAirports(limit: Int, includeTransport: Bool) -> [Airport] {
        let center = visibleRegion.center
        let longitudeSpan = max(0.001, min(180, visibleRegion.span.longitudeDelta * 0.60))
        let latitudeSpan = max(0.001, visibleRegion.span.latitudeDelta * 0.61)
        return library.airports.compactMap { airport -> (Airport, Double)? in
            guard airport.hasCoordinates else { return nil }
            let rawLongitudeDelta = abs(airport.lon - center.longitude)
            let longitudeDelta = min(rawLongitudeDelta, 360 - rawLongitudeDelta)
            let latitudeDelta = abs(airport.lat - center.latitude)
            guard longitudeDelta <= longitudeSpan, latitudeDelta <= latitudeSpan else { return nil }
            let category = GlobeAirportCategory(airport)
            let include = switch category {
            case .transport: includeTransport
            case .heliport: showsHeliports
            case .other: showsOtherAirports
            }
            guard include else { return nil }
            let longitudeFraction = longitudeDelta / longitudeSpan
            let latitudeFraction = latitudeDelta / latitudeSpan
            return (airport, longitudeFraction * longitudeFraction + latitudeFraction * latitudeFraction)
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.id < rhs.0.id : lhs.1 < rhs.1
        }.prefix(limit).map { $0.0 }
    }

    private var mapRoutes: [(String, Airport, Airport)] {
        guard routeLayer else { return [] }
        var pairs: Set<String> = []
        guard let origin = library.airport("HKG"), GlobeAirportCategory(origin) == .transport else { return [] }
        return library.routes(at: origin).compactMap { route in
            let next = route.origin == origin.id ? route.destination : route.origin
            guard let destination = library.airport(next), GlobeAirportCategory(destination) == .transport,
                  pairs.insert(next).inserted else { return nil }
            return (next, origin, destination)
        }.prefix(17).map { $0 }
    }
#endif

    var body: some View {
#if MAINLAND_DISTRIBUTION
        Map(position: $position, scope: mapScope)
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapCompass(scope: mapScope)
                MapScaleView(scope: mapScope)
            }
            .mapScope(mapScope)
            .accessibilityIdentifier("world-globe")
            .overlay(alignment: .topLeading) {
                GlobeControls(featured: library.featured, reset: reset, open: open)
                    .padding(.leading, 16)
                    .padding(.top, 16)
            }
#else
        Map(position: $position, selection: $selection, scope: mapScope) {
            ForEach(mapRoutes, id: \.0) { _, origin, destination in
                MapPolyline(coordinates: [origin.coordinate, destination.coordinate], contourStyle: .geodesic)
                    .stroke(.cyan.opacity(0.72), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            }
            ForEach(mapAirports) { airport in
                let category = GlobeAirportCategory(airport)
                Marker(airport.displayCode, systemImage: category.symbol, coordinate: airport.coordinate)
                    .tint(category.color)
                    .tag(airport.id)
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControls {
            MapCompass(scope: mapScope)
            MapScaleView(scope: mapScope)
        }
        .mapScope(mapScope)
        .onChange(of: selection) { openSelection() }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            isLocalView = context.camera.distance < 1_250_000
        }
        .accessibilityIdentifier("world-globe")
        .overlay(alignment: .bottomLeading) {
            GlobeControls(
                featured: library.featured, routeLayer: $routeLayer, showsHeliports: $showsHeliports,
                showsOtherAirports: $showsOtherAirports, reset: reset, open: open
            )
                .padding(.leading, 16)
                .padding(.bottom, 44)
        }
#endif
    }

    private func reset() {
        withAnimation(.easeInOut(duration: 0.8)) { position = Self.worldCamera }
    }

#if !MAINLAND_DISTRIBUTION
    private func openSelection() {
        guard let selection, let airport = library.airport(selection) else { return }
        self.selection = nil
        open(airport)
    }
#endif
}

private struct GlobeControls: View {
    let featured: [Airport]
#if !MAINLAND_DISTRIBUTION
    @Binding var routeLayer: Bool
    @Binding var showsHeliports: Bool
    @Binding var showsOtherAirports: Bool

    private var airportCategoriesLabel: String {
        var categories = ["运输机场"]
        if showsHeliports { categories.append("直升机场") }
        if showsOtherAirports { categories.append("其他机场") }
        return categories.joined(separator: "、")
    }
#endif
    let reset: () -> Void
    let open: (Airport) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let airport = featured.first {
                Button { open(airport) } label: {
                    Label("\(airport.displayCode) · \(airport.displayName)", systemImage: "cube")
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("globe-featured-\(airport.id)")
            }
            HStack(spacing: 7) {
                Button("返回全球", systemImage: "globe", action: reset)
                    .buttonStyle(.glass)
#if !MAINLAND_DISTRIBUTION
                Button {
                    routeLayer.toggle()
                } label: {
                    Label("航线", systemImage: routeLayer ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                }
                .buttonStyle(.glass)
                .accessibilityAddTraits(routeLayer ? .isSelected : [])
                Menu {
                    Toggle("直升机场", systemImage: "helicopter", isOn: $showsHeliports)
                        .accessibilityIdentifier("globe-show-heliports")
                    Toggle("其他机场", systemImage: "mappin", isOn: $showsOtherAirports)
                        .accessibilityIdentifier("globe-show-other-airports")
                } label: {
                    Label("机场类型", systemImage: showsHeliports || showsOtherAirports
                          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.glass)
                .accessibilityValue(airportCategoriesLabel)
                .accessibilityIdentifier("globe-airport-categories")
#endif
            }
        }
        .colorScheme(.dark)
        .tint(.mint)
    }
}
#endif
