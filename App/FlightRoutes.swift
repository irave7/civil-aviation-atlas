import Foundation
import MapKit
import SwiftUI

struct AirportLongestRouteBanner: View {
    let airport: Airport
    let library: AtlasLibrary
    let open: (FlightRoute) -> Void

    var body: some View {
        Group {
            if let route = library.longestRecordedRoute(at: airport, on: FlightCalendar.isoDate(.now)),
               let km = route.distanceKm,
               let endpoint = library.airport(route.origin == airport.id ? route.destination : route.origin) {
                Button { open(route) } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "arrow.up.right.circle")
                            .font(AtlasTypography.font(.title3, weight: .semibold))
                            .foregroundStyle(.teal)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(route.hasVerifiedNonstop ? "已收录最远直飞" : "已收录最远航线")
                                .font(AtlasTypography.font(.caption, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("\(endpoint.displayName) · \(endpoint.displayCode)")
                                .font(AtlasTypography.font(.headline))
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(displayDistance(km))
                                .font(AtlasTypography.font(.title3, weight: .semibold).monospacedDigit())
                            if let item = route.observedStatistics?.first {
                                Text("实飞 · \(item.observation.period)")
                                    .font(AtlasTypography.font(.caption))
                                    .foregroundStyle(.secondary)
                            } else {
                                RouteStatusBadge(route: route, day: FlightCalendar.isoDate(.now))
                            }
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("airport-longest-route")
            } else if library.isPreparingObservedRoutes {
                Label("最远航线 · 正在读取资料", systemImage: "arrow.up.right.circle")
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("最远航线 · 暂无可核实的航线记录", systemImage: "arrow.up.right.circle")
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("airport-longest-route-unavailable")
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

struct AirportRoutePanel: View {
    let airport: Airport
    let library: AtlasLibrary
    let onAirport: (Airport) -> Void
    let onAircraft: (AircraftProfile) -> Void
    @State private var showFlightDetails = false

    private var subtitle: String {
        DistributionPolicy.liveFlightsAvailable
            ? "查询已收录班表和实飞统计。支持的机场还可查询官方航班资料。"
            : "查阅已收录的班表与历史实飞统计。当前航班以机场和航司公告为准。"
    }

    var body: some View {
        FlightRouteList(
            title: "\(airport.displayName)航线", subtitle: subtitle,
            routes: library.routes(at: airport) + library.observedRoutes(at: airport), library: library,
            distanceOrder: false, onAirport: onAirport, onAircraft: onAircraft
        ) {
            Button("机场航班资料", systemImage: "airplane.departure") { showFlightDetails = true }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("airport-flight-details")
        }
        .sheet(isPresented: $showFlightDetails) {
            AirportFlightBoardSheet(airport: airport, library: library)
                .presentationSizing(.page)
        }
    }
}

private struct AirportFlightBoardSheet: View {
    let airport: Airport?
    let library: AtlasLibrary
    var context: FlightBoardContext? = nil

    static func supports(_ airport: Airport, day: String) -> Bool {
        guard DistributionPolicy.liveFlightsAvailable else { return false }
        return OpenAirportSchedules.supports(airport.iata) || AvinorAirportBoard.supports(airport)
            || (airport.id == "HKG" && day <= FlightCalendar.lastHongKongHistoricalDay)
    }

    var body: some View {
        if DistributionPolicy.liveFlightsAvailable, let airport {
            if OpenAirportSchedules.supports(airport.iata) {
                OpenAirportSchedules(airport: airport, library: library, context: context)
            } else if AvinorAirportBoard.supports(airport) {
                AvinorAirportBoard(airport: airport, library: library, context: context)
            } else if airport.id == "HKG", context.map({ $0.day <= FlightCalendar.lastHongKongHistoricalDay }) ?? true {
                NavigationStack { HongKongFlightHistory(library: library, context: context) }
            } else {
                AirportFlightDetails(airport: airport, library: library, context: context)
            }
        } else {
            AirportFlightDetails(airport: airport, library: library, context: context)
        }
    }
}

struct FlightRouteList<Trailing: View>: View {
    private enum RecordFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case published = "班表与航司资料"
        case observed = "实飞记录"
        var id: Self { self }
        func includes(_ route: FlightRoute) -> Bool {
            switch self {
            case .all: true
            case .published: route.observedStatistics == nil
            case .observed: route.observedStatistics != nil
            }
        }
    }
    let title: String
    let subtitle: String
    let routes: [FlightRoute]
    let library: AtlasLibrary
    let distanceOrder: Bool
    let onAirport: (Airport) -> Void
    let onAircraft: ((AircraftProfile) -> Void)?
    @ViewBuilder let trailing: Trailing
    @State private var picked: FlightRoute?
    @State private var selectedDate = Date()
    @State private var plannedOnly = false
    @State private var query = ""
    @State private var filter = RecordFilter.all
    @FocusState private var searchFocused: Bool

    private var periodDay: String { FlightCalendar.isoDate(selectedDate) }

    private var searchTerms: [Substring] { query.split(whereSeparator: \.isWhitespace) }

    private func sortedRoutes(on periodDay: String, matching terms: [Substring]) -> [FlightRoute] {
        routes.filter { route in
            filter.includes(route) && (!plannedOnly || filter == .observed || route.isPublishedPlan(on: periodDay))
                && matchesSearch(route, terms: terms)
        }.sorted { lhs, rhs in
            let leftPlan = lhs.isPublishedPlan(on: periodDay)
            let rightPlan = rhs.isPublishedPlan(on: periodDay)
            if leftPlan != rightPlan { return leftPlan }
            if distanceOrder, lhs.distanceKm != rhs.distanceKm { return (lhs.distanceKm ?? 0) > (rhs.distanceKm ?? 0) }
            return (lhs.origin, lhs.destination, lhs.flightNumber ?? "", lhs.airline) < (rhs.origin, rhs.destination, rhs.flightNumber ?? "", rhs.airline)
        }
    }

    private func matchesSearch(_ route: FlightRoute, terms: [Substring]) -> Bool {
        if terms.isEmpty { return true }
        let airports = [route.origin, route.destination].compactMap(library.airport)
        let titles = airports.flatMap(\.nameSearchTerms)
        let fields = [route.origin, route.destination, route.airline, route.flightNumber ?? ""] + route.aircraftSearchTerms
        func searchKey(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                .filter { $0.isLetter || $0.isNumber }
        }
        let searchable = (fields + titles).map(searchKey)
        return terms.map { searchKey(String($0)) }.filter { !$0.isEmpty }.allSatisfy { term in
            searchable.contains { $0.contains(term) }
        }
    }

    private func longestScheduled(in records: [FlightRoute], on date: String) -> FlightRoute? {
        records.filter { $0.isPublishedPlan(on: date) && $0.distanceKm != nil }
            .max { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }
    }

    var body: some View {
        let day = periodDay
        let terms = searchTerms
        let records = sortedRoutes(on: day, matching: terms)
        let hasPublishedPlans = routes.contains { $0.status == "计划班表" }
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(AtlasTypography.font(.largeTitle).bold())
                    Text(subtitle).font(AtlasTypography.font(.subheadline)).foregroundStyle(.secondary)
                    trailing
                }
                .padding(.vertical, 5)
                if !routes.isEmpty {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索机场、航班号、航司或机型", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($searchFocused)
                            .submitLabel(.search)
                            .onSubmit { searchFocused = false }
                            .accessibilityIdentifier("route-search-field")
                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Label("清除航线搜索", systemImage: "xmark.circle.fill").labelStyle(.iconOnly)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if routes.contains(where: { $0.observedStatistics != nil }) {
                    Picker("航线资料", selection: $filter) {
                        ForEach(RecordFilter.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("route-record-filter")
                }
                if hasPublishedPlans && filter != .observed {
                    Toggle("仅显示涵盖所选日期的班表", isOn: $plannedOnly)
                        .accessibilityIdentifier("route-planned-filter")
                    if plannedOnly || distanceOrder {
                        DatePicker("选择日期", selection: $selectedDate, displayedComponents: .date)
                            .environment(\.timeZone, FlightCalendar.hongKongZone)
                            .accessibilityIdentifier("route-date-picker")
                    }
                }
            }
            if distanceOrder, terms.isEmpty, let longest = longestScheduled(in: records, on: day) {
                Section("所选日期收录的最远定期航线") {
                    Button { picked = longest } label: { RouteRow(route: longest, library: library, day: day) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("longest-scheduled-route")
                }
            }
            Section {
                if records.isEmpty {
                    if terms.isEmpty {
                        ContentUnavailableView("暂无对应班表", systemImage: "airplane.circle", description: Text("可查看机场和机型资料，或调整日期。"))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
                ForEach(records) { route in
                    Button { picked = route } label: { RouteRow(route: route, library: library, day: day) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("route-\(route.flightNumber ?? "\(route.origin)-\(route.destination)")")
                }
            } header: {
                let title = distanceOrder ? "已收录不经停航线" : "已收录班表与航线"
                Text("\(title) · \(records.count.formatted()) 条")
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $picked) { route in
            NavigationStack {
                RouteDetail(route: route, library: library, day: day, openAirport: { airport in
                    picked = nil
                    onAirport(airport)
                }, openAircraft: onAircraft.map { action in { current in
                    picked = nil
                    action(current)
                } })
            }
            .presentationSizing(.page)
        }
    }
}

extension FlightRouteList where Trailing == EmptyView {
    init(title: String, subtitle: String, routes: [FlightRoute], library: AtlasLibrary, distanceOrder: Bool,
         onAirport: @escaping (Airport) -> Void, onAircraft: ((AircraftProfile) -> Void)?) {
        self.init(title: title, subtitle: subtitle, routes: routes, library: library, distanceOrder: distanceOrder,
                  onAirport: onAirport, onAircraft: onAircraft) { EmptyView() }
    }
}

private struct RouteRow: View {
    let route: FlightRoute
    let library: AtlasLibrary
    let day: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 17) {
                endpoints.frame(width: 252, alignment: .leading)
                service.frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
                schedule.frame(width: 172, alignment: .leading)
                distance.frame(width: 95, alignment: .trailing)
                chevron
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    endpoints
                    Spacer(minLength: 3)
                    distance
                    chevron
                }
                service
                schedule
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .contentShape(.rect)
    }

    private var endpoints: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            leg(route.origin)
            Image(systemName: route.observedStatistics == nil ? "airplane" : "arrow.left.arrow.right")
                .font(AtlasTypography.font(.caption).weight(.semibold))
                .foregroundStyle(.teal)
                .accessibilityHidden(true)
            leg(route.destination)
        }
        .accessibilityElement(children: .combine)
    }

    private func leg(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(library.airport(code)?.displayCode ?? code)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
            if let airport = library.airport(code) {
                Text(airport.displayName)
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var service: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let observation = route.observedStatistics?.first?.observation {
                Text(observation.period).font(AtlasTypography.font(.subheadline, weight: .semibold))
                if let flights = observation.flights {
                    Text("统计期记录 \(flights.formatted()) 班")
                        .font(AtlasTypography.font(.caption))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text([route.airline, route.flightNumber].compactMap { $0 }.joined(separator: " · "))
                    .font(AtlasTypography.font(.subheadline).weight(.semibold))
                Text(route.displayAircraftName)
                    .font(AtlasTypography.font(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 5) {
            RouteStatusBadge(route: route, day: day)
            if let time = localTimeLabel(for: route) {
                Text(time)
                    .font(AtlasTypography.font(.caption2).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var distance: some View {
        if let km = route.distanceKm {
            Text(displayDistance(km))
                .font(AtlasTypography.font(.title3, weight: .semibold).monospacedDigit())
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(AtlasTypography.font(.caption).weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

private struct RouteStatusBadge: View {
    let route: FlightRoute
    let day: String

    var body: some View {
        if let status = route.status {
            let coversDate = route.isPublishedPlan(on: day)
            let caption = status == "计划班表" && !coversDate ? "班表未覆盖所选日期" : status
            let tint = coversDate ? Color.teal : Color.secondary
            Text(caption)
                .font(AtlasTypography.font(.caption2).weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.12), in: .capsule)
        }
    }
}

private func displayDistance(_ km: Double) -> String {
    "\(km.formatted(.number.precision(.fractionLength(0)))) km"
}

func localTimeLabel(for route: FlightRoute) -> String? {
    switch (route.departureLocal, route.arrivalLocal) {
    case let (departure?, arrival?): "\(departure) → \(arrival) · 当地时间"
    case let (departure?, nil): "\(departure) 离港 · 当地时间"
    case let (nil, arrival?): "\(arrival) 抵达 · 当地时间"
    case (nil, nil): nil
    }
}

struct RouteDetail: View {
    let route: FlightRoute
    let library: AtlasLibrary
    let day: String
    let openAirport: (Airport) -> Void
    let openAircraft: ((AircraftProfile) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showFlightDetails = false

    private var origin: Airport? { library.airport(route.origin) }
    private var destination: Airport? { library.airport(route.destination) }
    private var flightBoardAirport: Airport? {
        [origin, destination].compactMap { $0 }.first { AirportFlightBoardSheet.supports($0, day: day) }
            ?? origin ?? destination
    }

    var body: some View {
        GeometryReader { viewport in
            let wide = viewport.size.width >= 790 && !textSize.isAccessibilitySize
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    endpoints
                    if DistributionPolicy.mapsAvailable, let origin, let destination,
                       origin.hasCoordinates, destination.hasCoordinates {
                        if wide {
                            HStack(alignment: .top, spacing: 18) {
                                routeMap(origin: origin, destination: destination, height: 385)
                                    .frame(maxWidth: .infinity)
                                facts.frame(width: 300)
                            }
                        } else {
                            routeMap(origin: origin, destination: destination, height: 250)
                            facts
                        }
                    } else {
                        facts
                    }
                    if let sources = route.observedStatistics?.map(\.source) {
                        SourceLinks(sources: sources.reduce(into: [AtlasSource]()) { result, source in
                            if !result.contains(source) { result.append(source) }
                        })
                    } else if let source = route.source {
                        SourceLinks(sources: [source])
                    }
                    if let asOf = route.updatedAt {
                        Text("资料核对日期 \(asOf) · 计划机型可能因航班调整而变化。")
                            .font(AtlasTypography.font(.footnote)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 1050, alignment: .leading)
                .padding(.horizontal, wide ? 28 : 18)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("route-detail")
        }
        .navigationTitle(route.flightNumber ?? "航线详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFlightDetails) {
            let airport = flightBoardAirport
            let context = FlightBoardContext(route: route, day: day, airportID: airport?.id ?? route.origin)
            AirportFlightBoardSheet(airport: airport, library: library, context: context)
                .presentationSizing(.page)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                if route.flightNumber != nil {
                    Button("查看航班资料", systemImage: "airplane") { showFlightDetails = true }
                        .accessibilityIdentifier("route-flight-details")
                }
                if let modelID = route.aircraftID, let model = library.aircraft(modelID), let openAircraft {
                    Button("查看客机", systemImage: "cube") { openAircraft(model) }
                        .accessibilityLabel("查看 \(model.displayName) 三维模型")
                        .accessibilityIdentifier("route-aircraft-\(modelID)")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
                    .accessibilityIdentifier("route-detail-close")
            }
        }
    }

    private var endpoints: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                endpoint(airport: origin, fallbackCode: route.origin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: route.observedStatistics == nil ? "airplane" : "arrow.left.arrow.right")
                    .foregroundStyle(.teal)
                    .padding(.top, 12)
                    .accessibilityHidden(true)
                endpoint(airport: destination, fallbackCode: route.destination)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 10) {
                endpoint(airport: origin, fallbackCode: route.origin)
                endpoint(airport: destination, fallbackCode: route.destination)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: 18))
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let km = route.distanceKm {
                AtlasFact(label: "机场间大圆距离", value: displayDistance(km), symbol: "ruler")
            }
            VStack(alignment: .leading, spacing: 10) {
                RouteStatusBadge(route: route, day: day)
                if let evidence = route.observedStatistics, !evidence.isEmpty {
                    observedFacts(evidence)
                } else {
                    plannedFacts
                }
            }
            .font(AtlasTypography.font(.subheadline))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: .rect(cornerRadius: 15))
        }
        .accessibilityIdentifier("route-facts")
    }

    private var plannedFacts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(route.airline).font(AtlasTypography.font(.headline))
            VStack(alignment: .leading, spacing: 3) {
                Text(route.status == "计划班表" ? "计划机型" : "资料所列机型")
                    .font(AtlasTypography.font(.caption)).foregroundStyle(.secondary)
                Text([route.displayAircraftName, route.aircraftVariant].compactMap { $0 }.joined(separator: " · "))
                    .font(AtlasTypography.font(.subheadline))
            }
            Divider()
            if let time = localTimeLabel(for: route) {
                Label(time, systemImage: "clock").monospacedDigit()
            }
            if let from = route.validFrom, let through = route.validThrough {
                Label("\(from) 至 \(through)", systemImage: "calendar")
            }
            if let frequency = route.frequency {
                Label(frequency, systemImage: "repeat")
            }
        }
    }

    private func observedFacts(_ evidence: [FlightRoute.ObservedStatistics]) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("连接两座机场的历史记录，按来源与统计期展示。")
                .foregroundStyle(.secondary)
            ForEach(evidence, id: \.self) { item in
                let observation = item.observation
                VStack(alignment: .leading, spacing: 5) {
                    Text(observation.period).font(AtlasTypography.font(.headline))
                    Text(item.source.title).foregroundStyle(.secondary)
                    Text(observation.verifiedNonstop == true ? "有不经停记录" : "经停情况未核实")
                        .foregroundStyle(.secondary)
                    if let note = observation.note {
                        Text(note).foregroundStyle(.secondary)
                    }
                    if let source = observation.verificationURL, let url = URL(string: source) {
                        Link("不经停查核来源", destination: url)
                    }
                    if let flights = observation.flights {
                        Text("记录班次 \(flights.formatted())")
                    }
                    if let passengers = observation.passengers {
                        Text("记录旅客 \(passengers.formatted())")
                    }
                    ForEach(observation.operators ?? [], id: \.self) { record in
                        let names = record.aircraft.map(AircraftProfile.localizedFeedName)
                        Text(([record.airline] + names).joined(separator: " · "))
                            .font(AtlasTypography.font(.caption))
                    }
                }
            }
        }
    }

    private func routeMap(origin: Airport, destination: Airport, height: CGFloat) -> some View {
        Map {
            MapPolyline(coordinates: [origin.coordinate, destination.coordinate], contourStyle: .geodesic)
                .stroke(.mint, lineWidth: 3)
            Marker(origin.displayCode, coordinate: origin.coordinate).tint(.teal)
            Marker(destination.displayCode, coordinate: destination.coordinate).tint(.teal)
        }
        .mapStyle(.imagery(elevation: .flat))
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 17))
        .accessibilityIdentifier("route-map")
    }

    @ViewBuilder
    private func endpoint(airport: Airport?, fallbackCode: String) -> some View {
        if let airport {
            Button { openAirport(airport) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(airport.displayCode).font(.system(.title, design: .monospaced, weight: .bold))
                    Text(airport.displayName)
                        .font(AtlasTypography.font(.subheadline))
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("route-airport-\(airport.id)")
        } else {
            Text(fallbackCode).font(AtlasTypography.font(.title).monospaced().bold())
        }
    }
}

enum FlightCalendar {
    static let hongKongZone = TimeZone(identifier: "Asia/Hong_Kong") ?? .gmt
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = hongKongZone
        return value
    }

    static func isoDate(_ date: Date, in timeZone: TimeZone = hongKongZone) -> String {
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let value = localCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", value.year ?? 0, value.month ?? 0, value.day ?? 0)
    }

    static var lastHongKongHistoricalDate: Date { calendar.date(byAdding: .day, value: -1, to: .now) ?? .now }
    static var lastHongKongHistoricalDay: String { isoDate(lastHongKongHistoricalDate) }

    static func hongKongDate(for day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}

private struct HongKongFlightHistory: View {
    let library: AtlasLibrary
    let context: FlightBoardContext?

    private struct Batch: Decodable {
        let date: String
        let list: [Movement]?
    }
    private struct Movement: Decodable {
        struct FlightNumber: Decodable { let no: String; let airline: String? }
        let time: String?
        let flight: [FlightNumber]?
        let destination: [String]?
        let origin: [String]?
        let status: String?
        let terminal: String?
    }

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var arrival: Bool
    @State private var movements: [Movement] = []
    @State private var loading = true
    @State private var failed = false
    @State private var revision = 0

    init(library: AtlasLibrary, context: FlightBoardContext? = nil) {
        self.library = library
        self.context = context
        _date = State(initialValue: context.flatMap { FlightCalendar.hongKongDate(for: $0.day) } ?? FlightCalendar.lastHongKongHistoricalDate)
        _arrival = State(initialValue: context?.isArrival ?? false)
    }

    var body: some View {
        List {
            if let context { PublishedFlightFacts(context: context, library: library) }
            Section {
                if let context {
                    LabeledContent("香港当地日期", value: context.day)
                } else {
                    DatePicker("香港当地日期", selection: $date, in: ...FlightCalendar.lastHongKongHistoricalDate, displayedComponents: .date)
                        .environment(\.timeZone, FlightCalendar.hongKongZone)
                    Picker("方向", selection: $arrival) {
                        Text("客运离港").tag(false)
                        Text("客运抵港").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                Text("香港机场管理局开放数据，每日更新至上一自然日。历史记录未提供机型。")
            }
            Section {
                if loading {
                    ProgressView("正在向香港机场查询")
                } else if failed {
                    Button("重新查询", systemImage: "arrow.clockwise") { revision += 1 }
                } else if movements.isEmpty {
                    Text("当天没有返回匹配的航班记录").foregroundStyle(.secondary)
                }
                ForEach(Array(movements.enumerated()), id: \.offset) { _, movement in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            let numbers = movement.flight ?? []
                            let number = context.flatMap { selected in numbers.first { $0.no.uppercased().filter { !$0.isWhitespace } == selected.flightNumber.uppercased().filter { !$0.isWhitespace } } } ?? numbers.first
                            Text(number?.no ?? "航班").font(AtlasTypography.font(.headline).monospacedDigit())
                            let codes = (arrival ? movement.origin : movement.destination) ?? []
                            Text(codes.map { code in
                                library.airport(code).map { "\($0.displayName) \(code)" } ?? code
                            }.joined(separator: " / "))
                            .foregroundStyle(.secondary)
                            Spacer()
                            Text(movement.time ?? "—").monospacedDigit()
                        }
                        let airlines = Set((movement.flight ?? []).compactMap(\.airline)).sorted()
                        if !airlines.isEmpty { Text("航司代码 \(airlines.joined(separator: "、"))").font(AtlasTypography.font(.caption)).foregroundStyle(.secondary) }
                        if let status = movement.status, !status.isEmpty { Text(status).font(AtlasTypography.font(.caption)).foregroundStyle(.secondary) }
                        if let terminal = movement.terminal, !terminal.isEmpty { Text("航站楼 \(terminal)").font(AtlasTypography.font(.caption)).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 3)
                }
            }
            Section {
                Link("香港机场管理局 · 航班资料开放数据", destination: URL(string: "https://data.gov.hk/sc-data/dataset/aahk-team1-flight-info")!)
            }
        }
        .accessibilityIdentifier("flight-details-board")
        .navigationTitle(context?.flightNumber ?? "香港机场历史航班")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .task(id: "\(FlightCalendar.isoDate(date))-\(arrival)-\(revision)") { await load() }
    }

    private func load() async {
        guard DistributionPolicy.liveFlightsAvailable else { return }
        let requestedDay = context?.day ?? FlightCalendar.isoDate(date)
        var url = URLComponents()
        url.scheme = "https"
        url.host = "www.hongkongairport.com"
        url.path = "/flightinfo-rest/rest/flights/past"
        url.queryItems = [
            URLQueryItem(name: "date", value: requestedDay), URLQueryItem(name: "arrival", value: arrival ? "true" : "false"),
            URLQueryItem(name: "lang", value: "zh_CN"), URLQueryItem(name: "cargo", value: "false")
        ]
        guard let location = url.url else { return }
        loading = true
        failed = false
        movements = []
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: location, timeoutInterval: 15))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let batches = try JSONDecoder().decode([Batch].self, from: data)
            guard !Task.isCancelled else { return }
            let records = batches.filter { $0.date == requestedDay }.flatMap { $0.list ?? [] }
            movements = records.filter { record in
                guard let context else { return true }
                let codes = (arrival ? record.origin : record.destination) ?? []
                return (record.flight ?? []).contains { flight in codes.contains { context.matches(number: flight.no, airport: $0) } }
            }
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
            loading = false
        }
    }
}
