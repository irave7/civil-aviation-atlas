import Foundation
import simd

struct AirportSiteCatalog: Decodable {
    let updatedAt: String
    let airports: [String: [AirportSiteFeature]]

    static let metersPerUnit: Float = 100
    static let source = AtlasSource(title: "© OpenStreetMap contributors · ODbL", url: "https://www.openstreetmap.org/copyright")
    static let resourceURL = Bundle.main.url(forResource: "airport-site-layouts", withExtension: "json")
        ?? Bundle.main.url(forResource: "airport-site-layouts", withExtension: "json", subdirectory: "Resources")
    static let runwaySupplementURL = resource(named: "airport-runway-supplements")
    static let buildingResourceURL = resource(named: "airport-building-layouts")
    static let overtureSource = AtlasSource(
        title: "© OpenStreetMap contributors, Overture Maps Foundation · ODbL",
        url: "https://docs.overturemaps.org/attribution/"
    )
    private static let eastAsiaBuildingsSource = AtlasSource(
        title: "Qian Shi 等 · East Asian Buildings",
        url: "https://doi.org/10.5281/zenodo.8174931",
        detail: "CC BY 4.0，经 Overture Maps Buildings 提供。"
    )

    private static let bundled: Self? = resourceURL.flatMap { url in
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
    private static let runwaySupplement = load(AirportRunwaySupplement.self, named: "airport-runway-supplements")
    private static let terrainCatalog = load(AirportTerrainCatalog.self, named: "airport-site-terrain")
    private static let buildingCatalog = load(Self.self, named: "airport-building-layouts")

    private static func load<T: Decodable>(_ type: T.Type, named name: String) -> T? {
        resource(named: name).flatMap { (try? Data(contentsOf: $0)).flatMap { try? JSONDecoder().decode(type, from: $0) } }
    }

    private static func resource(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "json")
            ?? Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Resources")
    }

    static func preload(for airport: Airport) {
        _ = plan(for: airport)
        _ = terrain(for: airport)
    }

    static func hasBuildings(for airport: Airport) -> Bool {
        func modeled(_ feature: AirportSiteFeature) -> Bool {
            feature.kind.isBuilding && (feature.area ? feature.points.count >= 3 : feature.kind == .tower)
        }
        return bundled?.airports[airport.id]?.contains(where: modeled) == true
            || buildingCatalog?.airports[airport.id]?.contains(where: modeled) == true
    }

    static func hasSurfaceLayout(for airport: Airport) -> Bool {
        func isPavement(_ feature: AirportSiteFeature) -> Bool {
            feature.kind == .taxiway || feature.kind == .apron
        }
        return bundled?.airports[airport.id]?.contains(where: isPavement) == true
            || buildingCatalog?.airports[airport.id]?.contains(where: isPavement) == true
    }

    static func modelDataSources(for airport: Airport) -> [AtlasSource] {
        let original = bundled?.airports[airport.id] ?? []
        let additional = buildingCatalog?.airports[airport.id] ?? []
        var sources: [AtlasSource] = []
        if !original.isEmpty || usesSupplementalRunways(for: airport) || additional.contains(where: { $0.provenance != "overture" }) {
            sources.append(source)
        }
        if additional.contains(where: { $0.provenance == "overture" }) {
            sources.append(overtureSource)
        }
        return sources
    }

    static var buildingDataSources: [AtlasSource] {
        guard let buildingCatalog else { return [] }
        let features = buildingCatalog.airports.values.lazy.joined()
        var sources: [AtlasSource] = []
        if features.contains(where: { $0.provenance != "overture" }) { sources.append(source) }
        if features.contains(where: { $0.provenance == "overture" }) {
            sources.append(overtureSource)
            sources.append(eastAsiaBuildingsSource)
        }
        return sources
    }

    static func hasRunways(for airport: Airport) -> Bool {
        runwayRecords(for: airport).contains(where: validRunway)
    }

    static func hasTerrain(for airport: Airport) -> Bool {
        terrain(for: airport) != nil
    }

    static func terrain(for airport: Airport) -> AirportTerrainGrid? {
        guard let grid = terrainCatalog?.airports[airport.id], grid.isValid else { return nil }
        return grid
    }

    static var terrainSource: AtlasSource? {
        terrainCatalog.map { AtlasSource(title: $0.sourceTitle, url: $0.sourceURL) }
    }

    static var terrainSources: [AtlasSource] {
        guard let terrainCatalog, let terrainSource else { return [] }
        return [terrainSource, AtlasSource(title: "高程数据许可与署名", url: terrainCatalog.licenseURL)]
            + terrainCatalog.credits
    }

    static func runwayRecords(for airport: Airport) -> [Runway] {
        let records = airport.runways ?? []
        if records.contains(where: validRunway) { return records }
        return runwaySupplement?.airports[airport.id] ?? records
    }

    static func usesSupplementalRunways(for airport: Airport) -> Bool {
        !(airport.runways ?? []).contains(where: validRunway)
            && runwaySupplement?.airports[airport.id]?.contains(where: validRunway) == true
    }

    static func plan(for airport: Airport) -> AirportSitePlan {
        let original = bundled?.airports[airport.id] ?? []
        let additional = buildingCatalog?.airports[airport.id] ?? []
        let features = original + additional
        return AirportSitePlan(
            features: features.compactMap { feature in
                let points = feature.points.compactMap { pair -> SIMD2<Float>? in
                    guard pair.count == 2, pair[0].isFinite, pair[1].isFinite else { return nil }
                    return offset(latitude: pair[0], longitude: pair[1], from: airport)
                }
                let minimum = feature.area ? 3 : feature.kind == .tower ? 1 : 2
                guard points.count >= minimum else { return nil }
                return AirportSitePlan.Feature(source: feature, points: points)
            },
            runways: runways(for: airport),
            hasOpenStreetMapData: !original.isEmpty || additional.contains { $0.provenance != "overture" },
            hasOvertureData: additional.contains { $0.provenance == "overture" }
        )
    }

    static func runways(for airport: Airport) -> [AirportSitePlan.RunwayLine] {
        let runways = runwayRecords(for: airport).filter(validRunway)
        return runways.enumerated().map { index, runway in
            let location: SIMD2<Float>?
            if let latitude = runway.lat, let longitude = runway.lon, latitude.isFinite, longitude.isFinite {
                location = offset(latitude: latitude, longitude: longitude, from: airport)
            } else {
                location = nil
            }
            let heading = runway.heading.flatMap { $0.isFinite ? Float($0) : nil }
            let designation = Int(runway.id.prefix(while: \.isNumber)).flatMap { (1...36).contains($0) ? Float($0 * 10) : nil }
            let width = runway.widthM.flatMap { $0.isFinite && $0 > 1 ? Float($0) / metersPerUnit : nil }
            return AirportSitePlan.RunwayLine(
                id: runway.id, center: location ?? [0, Float(index) * 2.3],
                bearing: heading ?? designation ?? 90, length: Float(runway.lengthM) / metersPerUnit,
                width: width ?? 0.34, widthVerified: width != nil,
                approximatePlacement: location == nil || heading == nil
            )
        }
    }

    private static func validRunway(_ runway: Runway) -> Bool {
        runway.lengthM.isFinite && runway.lengthM > 1 && runway.lengthM <= 15_000
    }

    private static func offset(latitude: Double, longitude: Double, from airport: Airport) -> SIMD2<Float> {
        var longitudeDelta = longitude - airport.lon
        if longitudeDelta > 180 { longitudeDelta -= 360 }
        if longitudeDelta < -180 { longitudeDelta += 360 }
        let east = longitudeDelta * 111_319.49 * cos(airport.lat * .pi / 180)
        let south = (airport.lat - latitude) * 110_750
        return [Float(east) / metersPerUnit, Float(south) / metersPerUnit]
    }
}

private struct AirportRunwaySupplement: Decodable {
    let airports: [String: [Runway]]
}

private struct AirportTerrainCatalog: Decodable {
    let sourceTitle: String
    let sourceURL: String
    let licenseURL: String
    let credits: [AtlasSource]
    let airports: [String: AirportTerrainGrid]
}

struct AirportTerrainGrid: Decodable {
    let size: Int
    let halfSpanM: Double
    let elevationsM: [Int]

    var isValid: Bool {
        (3...33).contains(size) && (100...10_000).contains(halfSpanM)
            && elevationsM.count == size * size && elevationsM.allSatisfy { (-11_000...9_000).contains($0) }
    }
}

struct AirportSiteFeature: Decodable {
    enum Kind: String, Decodable {
        case terminal, taxiway, apron, tower, hangar, building, boundary

        var isBuilding: Bool {
            switch self {
            case .terminal, .tower, .hangar, .building: true
            case .taxiway, .apron, .boundary: false
            }
        }
    }

    let id: String
    let kind: Kind
    let name: String?
    let points: [[Double]]
    let area: Bool
    let heightM: Double?
    let widthM: Double?
    let provenance: String?

    var documentedHeight: Float? {
        guard let heightM, (2...850).contains(heightM) else { return nil }
        return Float(heightM) / AirportSiteCatalog.metersPerUnit
    }
}

struct AirportSitePlan {
    struct Feature: Identifiable {
        let source: AirportSiteFeature
        let points: [SIMD2<Float>]
        var id: String { source.id }
        var bounds: Bounds { Bounds(points) }
    }

    struct RunwayLine: Identifiable {
        let id: String
        let center: SIMD2<Float>
        let bearing: Float
        let length: Float
        let width: Float
        let widthVerified: Bool
        let approximatePlacement: Bool

        var ends: [SIMD2<Float>] {
            let angle = bearing * .pi / 180
            let half = SIMD2<Float>(sin(angle), -cos(angle)) * (length / 2)
            return [center - half, center + half]
        }
    }

    struct Bounds {
        let low: SIMD2<Float>
        let high: SIMD2<Float>

        init(_ points: [SIMD2<Float>]) {
            low = points.reduce(points.first ?? .zero) { simd_min($0, $1) }
            high = points.reduce(points.first ?? .zero) { simd_max($0, $1) }
        }

        var center: SIMD2<Float> { (low + high) / 2 }
        var size: SIMD2<Float> { high - low }
        var span: Float { max(size.x, size.y) }
    }

    let features: [Feature]
    let runways: [RunwayLine]
    let hasOpenStreetMapData: Bool
    let hasOvertureData: Bool

    var bounds: Bounds { Bounds(features.flatMap(\.points) + runways.flatMap(\.ends)) }
    var tallestBuilding: Float { features.compactMap { $0.source.documentedHeight }.max() ?? 0 }
}
