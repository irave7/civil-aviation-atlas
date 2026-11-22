import MapKit
import SwiftUI

extension Airport {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

struct GlobeView: View {
    let library: AtlasLibrary
    let open: (Airport) -> Void
    @State private var position = Self.worldCamera
    @State private var localAirports: [Airport] = []
    @State private var selection: String?
    @State private var routeLayer = true
    @Namespace private var mapScope

    private static var worldCamera: MapCameraPosition {
        .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 24, longitude: 115), distance: 31_000_000))
    }

    private var mapAirports: [Airport] {
        var visited: Set<String> = []
        let priority = ["PVG", "PEK", "HND", "ICN", "SYD", "LHR", "DXB", "JFK", "LAX", "FRA", "IST", "DOH", "DEL", "CPT", "GRU"]
        let visible = localAirports.isEmpty ? library.featured + priority.compactMap(library.airport) : library.featured + localAirports
        return visible.filter { visited.insert($0.id).inserted }
    }

    private var mapRoutes: [(String, Airport, Airport)] {
        guard routeLayer else { return [] }
        var pairs: Set<String> = []
        guard let origin = library.airport("HKG") else { return [] }
        return library.routes(at: origin).compactMap { route in
            let next = route.origin == origin.id ? route.destination : route.origin
            guard let destination = library.airport(next), pairs.insert(next).inserted else { return nil }
            return (next, origin, destination)
        }.prefix(17).map { $0 }
    }

    var body: some View {
        Map(position: $position, selection: $selection, scope: mapScope) {
            ForEach(mapRoutes, id: \.0) { _, origin, destination in
                MapPolyline(coordinates: [origin.coordinate, destination.coordinate], contourStyle: .geodesic)
                    .stroke(.cyan.opacity(0.72), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            }
            ForEach(mapAirports) { airport in
                Marker(airport.displayCode, systemImage: "airplane", coordinate: airport.coordinate)
                    .tint(.teal)
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
            guard context.camera.distance < 1_250_000 else {
                localAirports = []
                return
            }
            let region = context.region
            let longitudeSpan = min(180, region.span.longitudeDelta * 0.60)
            let latitudeSpan = region.span.latitudeDelta * 0.61
            localAirports = library.airports.compactMap { airport -> (Airport, Double)? in
                let rawLongitudeDelta = abs(airport.lon - region.center.longitude)
                let longitudeDelta = min(rawLongitudeDelta, 360 - rawLongitudeDelta)
                let latitudeDelta = abs(airport.lat - region.center.latitude)
                guard longitudeDelta <= longitudeSpan, latitudeDelta <= latitudeSpan else { return nil }
                return (airport, pow(longitudeDelta / max(longitudeSpan, 0.001), 2) + pow(latitudeDelta / max(latitudeSpan, 0.001), 2))
            }.sorted { $0.1 < $1.1 }.prefix(70).map { $0.0 }
        }
        .accessibilityIdentifier("world-globe")
        .overlay(alignment: .bottomLeading) {
            GlobeControls(
                featured: library.featured, routeLayer: $routeLayer, reset: reset, open: open
            )
                .padding(.leading, 16)
                .padding(.bottom, 44)
        }
    }

    private func reset() {
        withAnimation(.easeInOut(duration: 0.8)) { position = Self.worldCamera }
    }

    private func openSelection() {
        guard let selection, let airport = library.airport(selection) else { return }
        self.selection = nil
        open(airport)
    }
}

private struct GlobeControls: View {
    let featured: [Airport]
    @Binding var routeLayer: Bool
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
                Button {
                    routeLayer.toggle()
                } label: {
                    Label("航线", systemImage: routeLayer ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                }
                .buttonStyle(.glass)
                .accessibilityAddTraits(routeLayer ? .isSelected : [])
            }
        }
        .colorScheme(.dark)
        .tint(.mint)
    }
}
