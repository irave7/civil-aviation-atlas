import SwiftUI

struct AirportFlightLinks: View {
    let airport: Airport

    var body: some View {
        if let departure = boardURL(for: .departures), let arrival = boardURL(for: .arrivals) {
            VStack(alignment: .leading, spacing: 7) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { actions(departure: departure, arrival: arrival) }
                    VStack(alignment: .leading, spacing: 7) { actions(departure: departure, arrival: arrival) }
                }
                Text(airport.iata == "HKG" || airport.iata == "TPE" ? "机场官方航班看板" : "Flightradar24 航班看板 · 覆盖以提供方为准")
                    .font(AtlasTypography.font(.footnote))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actions(departure: URL, arrival: URL) -> some View {
        Link(destination: departure) {
            Label("出发动态", systemImage: "airplane.departure")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("airport-live-departures")
        Link(destination: arrival) {
            Label("到达动态", systemImage: "airplane.arrival")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("airport-live-arrivals")
    }

    private enum Direction: String { case departures, arrivals }

    private func boardURL(for direction: Direction) -> URL? {
        let code = airport.iata.lowercased()
        guard code.utf8.count == 3, code.utf8.allSatisfy({ (97...122).contains($0) }) else { return nil }
        switch code {
        case "hkg":
            return URL(string: "https://www.hongkongairport.com/en/flights/\(direction.rawValue)/passenger.page")
        case "tpe":
            return URL(string: "https://www.taoyuan-airport.com/flight_\(direction == .departures ? "depart" : "arrival")")
        default:
            return Self.radarBoardURL(code, arrivals: direction == .arrivals)
        }
    }

    static func radarBoardURL(_ airportCode: String, arrivals: Bool) -> URL? {
        let code = airportCode.lowercased()
        guard code.utf8.count == 3, code.utf8.allSatisfy({ (97...122).contains($0) }) else { return nil }
        return URL(string: "https://www.flightradar24.com/data/airports/\(code)/\(arrivals ? "arrivals" : "departures")")
    }

    static func flightURL(_ number: String) -> URL? {
        let normalized = number.lowercased().filter { !$0.isWhitespace }
        guard (3...8).contains(normalized.utf8.count),
              normalized.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) }) else { return nil }
        return URL(string: "https://www.flightradar24.com/data/flights/\(normalized)")
    }
}
