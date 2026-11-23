import MapKit
import SwiftUI
import UIKit

extension Airport {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

#if MAINLAND_DISTRIBUTION && !MAINLAND_APPROVED_MAPS
struct GlobeView: View {
    let library: AtlasLibrary
    let open: (Airport) -> Void
    let favorites: AtlasFavorites
    let openAircraft: (AircraftProfile) -> Void
    let explore: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: AtlasPalette { AtlasPalette(colorScheme, contrast: contrast) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: palette.isDark ? 16 : 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("探索机场")
                        .font(AtlasTypography.font(.largeTitle, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("从机场资料开始，也可以进入探索，选择机场、机型或航线任务。")
                        .font(AtlasTypography.font(.body))
                        .foregroundStyle(palette.muted)
                }
                Button(action: explore) {
                    Label("进入探索", systemImage: "safari")
                        .font(AtlasTypography.font(.headline))
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                let saved = favorites.airportIDs.compactMap(library.airport).sorted { $0.displayCode < $1.displayCode }
                let fleet = library.aircraft.filter { favorites.aircraftIDs.contains($0.id) }
                if !saved.isEmpty || !fleet.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("我的收藏").font(AtlasTypography.font(.headline))
                        ForEach(saved) { airport in
                            GlobeCompactAirport(airport: airport, palette: palette, open: open)
                        }
                        ForEach(fleet) { profile in
                            Button { openAircraft(profile) } label: {
                                Label(profile.displayName, systemImage: "airplane").frame(minHeight: 44)
                            }
                        }
                    }
                }
                if let first = library.featured.first {
                    GlobeAirportBrief(airport: first, palette: palette, open: open)
                }
                if !library.featured.dropFirst().isEmpty {
                    VStack(spacing: 0) {
                        ForEach(library.featured.dropFirst()) { airport in
                            GlobeCompactAirport(airport: airport, palette: palette, open: open)
                            if airport.id != library.featured.last?.id {
                                Rectangle().fill(palette.line).frame(height: 1)
                            }
                        }
                    }
                    .clipShape(.rect(cornerRadius: palette.corner))
                    .overlay { RoundedRectangle(cornerRadius: palette.corner).strokeBorder(palette.line).allowsHitTesting(false) }
                }
                if let number = DistributionPolicy.icpRecordNumber {
                    Link("APP 备案号 \(number)", destination: DistributionPolicy.icpLookupURL)
                        .font(AtlasTypography.font(.footnote))
                        .tint(palette.accent)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(palette.page)
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
    let favorites: AtlasFavorites
    let openAircraft: (AircraftProfile) -> Void
    let explore: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var worldDistance = Self.standardWorldDistance
    @State private var position = Self.worldCamera(distance: Self.standardWorldDistance)
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

    private var palette: AtlasPalette { AtlasPalette(colorScheme, contrast: contrast) }

    private static let standardWorldDistance = 31_000_000.0

    private static func worldCamera(distance: Double) -> MapCameraPosition {
        .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 24, longitude: 115), distance: distance))
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
        GeometryReader { geometry in
            let size = geometry.size
            let wide = UIDevice.current.userInterfaceIdiom == .pad && !typeSize.isAccessibilitySize
                && size.width >= 730 && size.width >= size.height
            let railWidth = min(345, max(265, size.width * 0.28))

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    map
                        .environment(\.colorScheme, .dark)
                        .background(palette.stage)
                        .overlay(alignment: .topLeading) {
                            mapToolbar(iconOnly: size.width < 420 || typeSize.isAccessibilitySize)
                                .padding(10)
                        }
                        .onGeometryChange(for: Bool.self) { geometry in
                            geometry.size.height > geometry.size.width * 1.4
                        } action: { isNarrowPortrait in
                            fitWorld(isNarrowPortrait: isNarrowPortrait)
                        }
                    if !wide, let featured = library.featured.first {
                        Rectangle().fill(palette.line).frame(height: 1)
                        HStack(spacing: 0) {
                            GlobeCompactAirport(airport: featured, palette: palette, open: open)
                            Divider().frame(height: 24)
                            exploreButton
                                .padding(.horizontal, 10)
                        }
                        .background(palette.surface)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if wide {
                    featuredRail(width: railWidth, border: .leading)
                }
            }
        }
        .background(palette.page)
    }

    @ViewBuilder
    private func featuredRail(width: CGFloat, border: Alignment) -> some View {
        if let airport = library.featured.first {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let saved = favorites.airportIDs.compactMap(library.airport).sorted { $0.displayCode < $1.displayCode }
                    let fleet = library.aircraft.filter { favorites.aircraftIDs.contains($0.id) }
                    if !saved.isEmpty || !fleet.isEmpty {
                        Label("收藏", systemImage: "star.fill")
                            .font(AtlasTypography.font(.headline))
                            .foregroundStyle(palette.ink)
                        ForEach(saved) { item in
                            GlobeCompactAirport(airport: item, palette: palette, open: open)
                                .clipShape(.rect(cornerRadius: 12))
                                .accessibilityIdentifier("globe-saved-\(item.id)")
                        }
                        ForEach(fleet) { item in
                            Button { openAircraft(item) } label: {
                                Label(item.displayName, systemImage: "airplane")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .accessibilityIdentifier("globe-saved-aircraft-\(item.id)")
                        }
                    }
                    GlobeAirportBrief(airport: airport, palette: palette, open: open)
                    exploreButton
                }
                .padding(16)
            }
            .accessibilityIdentifier("globe-featured-rail")
            .frame(width: width)
            .background(palette.subtle)
            .overlay(alignment: border) {
                Rectangle().fill(palette.line).frame(width: 1).allowsHitTesting(false)
            }
        }
    }

    private var exploreButton: some View {
        Button(action: explore) {
            Label("探索", systemImage: "safari")
                .font(AtlasTypography.font(.headline))
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 44, minHeight: 44)
        }
        .foregroundStyle(palette.accent)
        .accessibilityIdentifier("globe-open-exploration")
    }

    private var map: some View {
#if MAINLAND_DISTRIBUTION
        Map(position: $position, scope: mapScope)
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapCompass(scope: mapScope)
                MapScaleView(scope: mapScope)
            }
            .mapScope(mapScope)
            .accessibilityIdentifier("world-globe")
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
#endif
    }

    private func mapToolbar(iconOnly: Bool) -> some View {
        HStack(spacing: 2) {
#if !MAINLAND_DISTRIBUTION
            Button {
                routeLayer.toggle()
            } label: {
                mapControlLabel("航线", systemImage: routeLayer ? "point.topleft.down.to.point.bottomright.curvepath.fill"
                                                              : "point.topleft.down.to.point.bottomright.curvepath",
                                iconOnly: iconOnly)
            }
            .buttonStyle(.plain)
            .accessibilityValue(routeLayer ? "已显示" : "已隐藏")
            .accessibilityAddTraits(routeLayer ? .isSelected : [])
            .accessibilityIdentifier("globe-route-layer")

            Menu {
                Toggle("直升机场", systemImage: "helicopter", isOn: $showsHeliports)
                    .accessibilityIdentifier("globe-show-heliports")
                Toggle("其他机场", systemImage: "mappin", isOn: $showsOtherAirports)
                    .accessibilityIdentifier("globe-show-other-airports")
            } label: {
                mapControlLabel("机场类型", systemImage: showsHeliports || showsOtherAirports
                                ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                                iconOnly: iconOnly)
            }
            .buttonStyle(.plain)
            .accessibilityValue(airportCategoriesLabel)
            .accessibilityIdentifier("globe-airport-categories")
#endif
            Divider().frame(height: 18)
            Button(action: reset) {
                mapControlLabel("全球", systemImage: "globe", iconOnly: iconOnly)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回全球")
            .accessibilityIdentifier("globe-reset-world")
        }
        .font(AtlasTypography.font(.subheadline, weight: .semibold))
        .padding(.horizontal, 8)
        .foregroundStyle(palette.selectionInk)
        .background(palette.surface.opacity(0.96), in: .capsule)
        .overlay { Capsule().strokeBorder(palette.line.opacity(0.8)).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }

    private func mapControlLabel(_ title: LocalizedStringKey, systemImage: String, iconOnly: Bool) -> some View {
        let label = Label(title, systemImage: systemImage)
        return Group {
            if iconOnly { label.labelStyle(.iconOnly) }
            else { label.labelStyle(.titleAndIcon).padding(.horizontal, 5) }
        }
        .frame(minWidth: 44, minHeight: 44)
    }

#if !MAINLAND_DISTRIBUTION
    private var airportCategoriesLabel: String {
        var categories = ["运输机场"]
        if showsHeliports { categories.append("直升机场") }
        if showsOtherAirports { categories.append("其他机场") }
        return categories.joined(separator: "、")
    }
#endif

    private func fitWorld(isNarrowPortrait: Bool) {
        let distance = isNarrowPortrait ? 52_000_000.0 : Self.standardWorldDistance
        guard worldDistance != distance else { return }
        worldDistance = distance
        if !position.positionedByUser {
            position = Self.worldCamera(distance: distance)
        }
    }

    private func reset() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) {
            position = Self.worldCamera(distance: worldDistance)
        }
    }

#if !MAINLAND_DISTRIBUTION
    private func openSelection() {
        guard let selection, let airport = library.airport(selection) else { return }
        self.selection = nil
        open(airport)
    }
#endif
}

#endif

private struct GlobeAirportBrief: View {
    let airport: Airport
    let palette: AtlasPalette
    let open: (Airport) -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var codeSize = 45.0

    var body: some View {
        VStack(alignment: .leading, spacing: palette.isDark ? 10 : 13) {
            Text("精选机场")
                .font(AtlasTypography.font(.footnote, weight: .semibold))
                .foregroundStyle(palette.muted)
            #if !MAINLAND_DISTRIBUTION
            if airport.id == "HKG" {
                HongKongTerminalCover()
            }
            #endif
            VStack(alignment: .leading, spacing: 3) {
                Text(airport.displayCode)
                    .font(.system(size: codeSize, weight: .bold, design: palette.isDark ? .monospaced : .default))
                    .foregroundStyle(palette.ink)
                Text(airport.displayName)
                    .font(AtlasTypography.font(.title3, weight: .bold))
                    .foregroundStyle(palette.ink)
                Text(metadata)
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(palette.muted)
            }
            .accessibilityElement(children: .combine)
            Rectangle().fill(palette.line).frame(height: 1)
            if DistributionPolicy.mapsAvailable {
                Text(airport.modelLabel)
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(palette.muted)
            }

            Button {
                open(airport)
            } label: {
                Label(DistributionPolicy.airportSiteModelsAvailable ? "打开三维模型" : "查看机场资料",
                      systemImage: DistributionPolicy.airportSiteModelsAvailable ? "cube" : "arrow.up.right")
                    .font(AtlasTypography.font(.subheadline, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(palette.onAccent)
                    .background(palette.accent, in: .rect(cornerRadius: palette.isDark ? 10 : 22))
            }
            .buttonStyle(.plain)
            .accessibilityHint(airport.displayName)
            .accessibilityIdentifier("globe-featured-\(airport.id)")
        }
        .padding(palette.isDark ? 13 : 17)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .atlasPanel(palette)
    }

    private var metadata: String {
        [airport.displayCity, airport.icao].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct GlobeCompactAirport: View {
    let airport: Airport
    let palette: AtlasPalette
    let open: (Airport) -> Void

    var body: some View {
        Button {
            open(airport)
        } label: {
            HStack(spacing: 12) {
                Text(airport.displayCode)
                    .font(AtlasTypography.font(.headline, design: palette.isDark ? .monospaced : .default, weight: .bold))
                    .foregroundStyle(palette.selectionInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(palette.selection, in: .rect(cornerRadius: palette.isDark ? 7 : 12))
                Text(airport.displayName)
                    .font(AtlasTypography.font(.body, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 4)
                Image(systemName: DistributionPolicy.airportSiteModelsAvailable ? "cube" : "chevron.right")
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 4)
            .background(palette.surface)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(DistributionPolicy.airportSiteModelsAvailable ? "打开三维模型" : "查看机场资料")
        .accessibilityIdentifier("globe-featured-\(airport.id)")
    }
}
