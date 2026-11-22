import Foundation
import SwiftUI

struct FlightBoardContext {
    let route: FlightRoute
    let day: String
    let airportID: String

    var flightNumber: String { route.flightNumber ?? "" }
    var isArrival: Bool { route.destination == airportID }
    var otherAirport: String { isArrival ? route.origin : route.destination }

    func matches(number: String, airport: String) -> Bool {
        number.uppercased().filter { !$0.isWhitespace } == flightNumber.uppercased().filter { !$0.isWhitespace }
            && airport.caseInsensitiveCompare(otherAirport) == .orderedSame
    }

    func matches(dayForTimestamp timestamp: Date, in timeZone: TimeZone) -> Bool {
        FlightCalendar.isoDate(timestamp, in: timeZone) == day
    }
}

struct AirportFlightDetails: View {
    let airport: Airport?
    let library: AtlasLibrary
    var context: FlightBoardContext? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let context {
                    PublishedFlightFacts(context: context, library: library)
                } else if let airport {
                    let records = library.routes(at: airport)
                    Section("\(airport.displayName) · \(airport.displayCode)") {
                        if records.isEmpty {
                            Text("暂无已收录的航班班表。可在机场航线页查看已收录的历史资料。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(records) { route in
                                NavigationLink {
                                    let item = FlightBoardContext(route: route, day: FlightCalendar.isoDate(.now), airportID: airport.id)
                                    List { PublishedFlightFacts(context: item, library: library) }
                                        .navigationTitle(route.flightNumber ?? "航班资料")
                                        .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text([route.flightNumber, route.airline].compactMap { $0 }.joined(separator: " · "))
                                            .font(AtlasTypography.font(.headline))
                                        Text("\(route.origin) → \(route.destination)")
                                            .font(AtlasTypography.font(.subheadline)).foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityIdentifier("flight-published-\(route.flightNumber ?? route.id)")
                            }
                        }
                    }
                }
                Section("航班动态") {
                    Text(DistributionPolicy.liveFlightsAvailable
                         ? "当前没有可在图鉴内查询的官方动态。班表中列出的时刻和机型可能调整。"
                         : "此版本提供已收录的班表和历史航线。当前航班以机场和航司公告为准。")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("flight-details-board")
            .navigationTitle(context?.flightNumber ?? "机场航班资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("flight-details-close")
                }
            }
        }
    }
}

struct PublishedFlightFacts: View {
    let context: FlightBoardContext
    let library: AtlasLibrary

    var body: some View {
        let route = context.route
        Section("已收录资料") {
            LabeledContent("出发机场", value: airportLabel(route.origin))
            LabeledContent("到达机场", value: airportLabel(route.destination))
            LabeledContent("航空公司", value: route.airline)
            LabeledContent("资料所列机型", value: [route.displayAircraftName, route.aircraftVariant].compactMap { $0 }.joined(separator: " · "))
            if let time = localTimeLabel(for: route) { LabeledContent("班表时刻", value: time) }
            if let frequency = route.frequency { LabeledContent("班期", value: frequency) }
            if let from = route.validFrom, let through = route.validThrough {
                LabeledContent("班表日期", value: "\(from) 至 \(through)")
            }
            if let status = route.status {
                LabeledContent("资料状态", value: status == "计划班表" && !route.isPublishedPlan(on: context.day) ? "班表未覆盖所选日期" : status)
            }
            if let source = route.source { SourceLinks(sources: [source]) }
        }
        .accessibilityIdentifier("flight-published-facts")
    }

    private func airportLabel(_ code: String) -> String {
        library.airport(code).map { "\($0.displayName) · \($0.displayCode)" } ?? code
    }
}
