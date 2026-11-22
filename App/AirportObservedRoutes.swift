import Foundation

struct AirportRouteObservation: Codable, Hashable {
    struct Operator: Codable, Hashable {
        let airline: String
        let aircraft: [String]
    }

    let sourceID: String
    let period: String
    let flights: Int?
    let passengers: Int?
    let operators: [Operator]?
    let verifiedNonstop: Bool?
    let verificationURL: String?
    let note: String?

    var endDateKey: String {
        let end = period.components(separatedBy: "…").last ?? period
        return switch end.count {
        case 4: end + "-12-31"
        case 7: end + "-31"
        default: end
        }
    }
}

struct AirportObservedRouteLibrary {
    private struct Dataset: Decodable {
        struct Source: Decodable {
            let id: String
            let title: String
            let url: String
            let detail: String?
        }
        struct Route: Decodable {
            let origin: String
            let destination: String
            let distanceKm: Double
            let observations: [AirportRouteObservation]
        }
        let asOf: String
        let coverage: String
        let sources: [Source]
        let routes: [Route]
    }

    let sources: [AtlasSource]
    let coverage: String?
    private let routesByAirport: [String: [FlightRoute]]

    init(bundle: Bundle) {
        let resource = DistributionPolicy.observedRoutesCatalog
        let url = bundle.url(forResource: resource, withExtension: "json")
            ?? bundle.url(forResource: resource, withExtension: "json", subdirectory: "Resources")
        let dataset = url.flatMap { try? Data(contentsOf: $0, options: [.mappedIfSafe]) }
            .flatMap { try? JSONDecoder().decode(Dataset.self, from: $0) }
        coverage = dataset.map { "\($0.coverage) · 整理于 \($0.asOf)" }
        sources = (dataset?.sources ?? []).map { AtlasSource(title: $0.title, url: $0.url, detail: $0.detail) }
        var sourceByID: [String: AtlasSource] = [:]
        for (record, source) in zip(dataset?.sources ?? [], sources) {
            sourceByID[record.id] = source
        }
        var grouped: [String: [FlightRoute]] = [:]
        for row in dataset?.routes ?? [] {
            let observations = row.observations.compactMap { item in
                sourceByID[item.sourceID].map { FlightRoute.ObservedStatistics(observation: item, source: $0) }
            }.sorted { $0.observation.endDateKey > $1.observation.endDateKey }
            guard let latest = observations.first, row.origin != row.destination else { continue }
            let operators = observations.flatMap { $0.observation.operators ?? [] }
            let airlineNames = Set(operators.map(\.airline)).sorted()
            let equipment = Set(operators.flatMap(\.aircraft)).sorted()
            let route = FlightRoute(
                origin: row.origin, destination: row.destination,
                airline: airlineNames.isEmpty ? "航司未公开" : airlineNames.joined(separator: "、"),
                aircraft: equipment.isEmpty ? "机型未公开" : equipment.joined(separator: "、"),
                distanceKm: row.distanceKm, status: "实飞记录", sourceTitle: latest.source.title, sourceURL: latest.source.url,
                flightNumber: nil, validFrom: nil, validThrough: nil, departureLocal: nil, arrivalLocal: nil, frequency: nil,
                aircraftID: nil, aircraftVariant: nil, updatedAt: nil, observedStatistics: observations
            )
            grouped[row.origin, default: []].append(route)
            grouped[row.destination, default: []].append(route)
        }
        routesByAirport = grouped
    }

    func routes(at airport: Airport) -> [FlightRoute] {
        routesByAirport[airport.id] ?? []
    }
}
