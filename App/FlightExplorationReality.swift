import Foundation
import SwiftUI

struct FlightExplorationReality: View {
    let origin: Airport
    let destination: Airport
    let route: FlightRoute
    var onWind: (Double, Double?, String) -> Void = { _, _, _ in }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    #if !MAINLAND_DISTRIBUTION
    @State private var request = 0
    @State private var isLoading = false
    @State private var weather: Result<[AirportWeatherObservation], Error>?
    @State private var aircraft: Result<PublicAircraftObservation?, Error>?
    @State private var selectedWind: String?

    private var candidateCallsign: String? {
        guard route.origin == origin.id, route.destination == destination.id,
              route.isPublishedPlan(on: FlightCalendar.isoDate(.now)), let number = route.flightNumber else { return nil }
        return FlightRealitySource.callsign(for: number, operatorName: route.airline)
    }

    private var latestWind: AirportWeatherObservation? {
        guard case let .success(observations) = weather else { return nil }
        return observations.first { report in
            report.windSpeed.map { (0...120).contains($0) } == true
                && Date.now.timeIntervalSince(report.date) <= TimeInterval(2 * 3600)
        }
    }
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: palette.contentGap) {
                Text("机场天气与航班资料")
                    .font(AtlasTypography.font(.title3, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if let number = route.flightNumber, route.origin == origin.id, route.destination == destination.id {
                    let details = [number, route.airline, route.displayAircraftName].joined(separator: " · ")
                    Text("已收录班表 \(details)")
                        .font(AtlasTypography.font(.subheadline))
                    if let time = localTimeLabel(for: route) {
                        Text(time)
                            .font(AtlasTypography.font(.footnote).monospacedDigit())
                            .foregroundStyle(palette.muted)
                    }
                }
                #if MAINLAND_DISTRIBUTION
                Text("航程可离线体验。天气和航班动态以机场和航司公告为准。")
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(palette.muted)
                #else
                if DistributionPolicy.liveFlightsAvailable {
                    onlineObservations
                }
                #endif
            }
            .foregroundStyle(palette.ink)
            .frame(maxWidth: 680, alignment: .leading)
            .padding(16)
            .atlasPanel(palette)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(palette.page)
        .tint(palette.accent)
        .toolbarBackground(palette.surface, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .accessibilityIdentifier("exploration-reality-panel")
    }

    #if !MAINLAND_DISTRIBUTION
    @ViewBuilder
    private var onlineObservations: some View {
        let callsign = candidateCallsign
        VStack(alignment: .leading, spacing: 12) {
            if request == 0 {
                Button(callsign == nil ? "读取机场天气" : "读取机场天气与航班观测", systemImage: "cloud.sun") {
                    request += 1
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("exploration-reality-fetch")
            } else if isLoading {
                ProgressView("正在查询公开观测")
            }
            if let weather {
                switch weather {
                case .success(let reports):
                    ForEach([origin, destination]) { airport in
                        weatherRow(airport, report: reports.first { $0.station == airport.icao.uppercased() })
                    }
                    if let report = latestWind, let speed = report.windSpeed {
                        Button("用观测风速体验", systemImage: "wind") {
                            selectedWind = report.station
                            onWind(speed, report.directionDegrees, report.station)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("exploration-reality-wind")
                        if let selectedWind {
                            Text("已采用 \(selectedWind) 地面风速")
                                .foregroundStyle(palette.accent)
                                .accessibilityIdentifier("exploration-reality-wind-applied")
                        }
                    }
                    Text("采用最近有效机场观测中的地面风速来调整模拟动态。巡航颠簸和具体跑道风况以相应的实际观测为准。")
                        .foregroundStyle(palette.muted)
                case .failure:
                    Text("机场天气暂时无法读取。仍可体验预设情景。")
                        .foregroundStyle(palette.muted)
                }
                Link("NOAA 航空气象中心 · METAR", destination: FlightRealitySource.weatherDocumentation)
            }
            if let callsign, let aircraft {
                Divider().overlay(palette.line)
                aircraftRow(callsign, result: aircraft)
                Link("adsb.lol · ODbL 1.0", destination: FlightRealitySource.aircraftDocumentation)
            } else if callsign == nil {
                Text("此航线暂无可核实的实时执飞资料。")
                    .foregroundStyle(palette.muted)
            }
        }
        .font(AtlasTypography.font(.footnote))
        .task(id: request) {
            guard request > 0 else { return }
            await fetch(callsign: callsign)
        }
    }

    private func weatherRow(_ airport: Airport, report: AirportWeatherObservation?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(airport.displayName) · \(airport.displayCode)").fontWeight(.semibold)
            if let report {
                Text(report.windDescription).monospacedDigit()
                if let temperature = report.temperature { Text("气温 \(temperature.formatted()) ℃").monospacedDigit() }
                Text("观测 \(Self.utcLabel(report.date))")
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
                if let raw = report.raw, !raw.isEmpty {
                    DisclosureGroup("METAR 原文") {
                        Text(raw).font(.system(.footnote, design: .monospaced))
                    }
                }
            } else {
                Text("近 4 小时暂无可用机场观测").foregroundStyle(palette.muted)
            }
        }
    }

    private func aircraftRow(_ callsign: String, result: Result<PublicAircraftObservation?, Error>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("公开信号 · \(callsign)").fontWeight(.semibold)
            switch result {
            case .success(let observation?):
                if let altitude = observation.altitude { Text("气压高度 \(altitude.formatted()) 英尺").monospacedDigit() }
                if let speed = observation.groundSpeed {
                    Text("地速 \(speed.formatted(.number.precision(.fractionLength(0)))) 节").monospacedDigit()
                }
                Text("观测 \(Self.utcLabel(observation.date))")
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
                Text("接收到该呼号信号。实际执飞、起降机场和航班状态请以航司资料为准。")
                    .foregroundStyle(palette.muted)
            case .success(nil):
                Text("暂无可唯一匹配的近期信号。覆盖随接收站分布变化。")
                    .foregroundStyle(palette.muted)
            case .failure:
                Text("暂时无法读取该呼号的公开信号。")
                    .foregroundStyle(palette.muted)
            }
        }
    }

    @MainActor
    private func fetch(callsign: String?) async {
        guard DistributionPolicy.liveFlightsAvailable else { return }
        isLoading = true
        defer { isLoading = false }
        async let weatherResult = FlightRealitySource.weather(for: [origin.icao, destination.icao])
        async let aircraftResult = FlightRealitySource.aircraft(for: callsign)
        let (observations, signal) = await (weatherResult, aircraftResult)
        guard !Task.isCancelled else { return }
        weather = observations
        aircraft = signal
    }

    private static func utcLabel(_ date: Date) -> String {
        let style = Date.FormatStyle(date: .numeric, time: .standard, locale: Locale(identifier: "zh_CN"), timeZone: .gmt)
        return "\(date.formatted(style)) UTC"
    }
    #endif
}

#if !MAINLAND_DISTRIBUTION
private struct AirportWeatherObservation: Decodable, Sendable {
    let station: String
    let observationTime: Int
    let windDirection: ObservedValue?
    let windSpeed: Double?
    let gust: Double?
    let temperature: Double?
    let raw: String?

    enum CodingKeys: String, CodingKey {
        case station = "icaoId", observationTime = "obsTime", windDirection = "wdir"
        case windSpeed = "wspd", gust = "wgst", temperature = "temp", raw = "rawOb"
    }

    var date: Date { Date(timeIntervalSince1970: TimeInterval(observationTime)) }

    var directionDegrees: Double? {
        guard case .number(let degrees) = windDirection else { return nil }
        return Double(degrees)
    }

    var windDescription: String {
        guard let windSpeed else { return "地面风速未报告" }
        if windSpeed == 0 { return "地面静风" }
        let direction = switch windDirection {
        case .number(let degrees): "\(degrees)°"
        case .text("VRB"): "风向多变"
        default: ""
        }
        return ["地面风", direction, "\(windSpeed.formatted()) 节", gust.map { "阵风 \($0.formatted()) 节" } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private enum ObservedValue: Decodable, Sendable {
    case number(Int)
    case text(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let number = try? value.decode(Int.self) {
            self = .number(number)
        } else {
            self = .text(try value.decode(String.self))
        }
    }
}

private struct PublicAircraftObservation: Sendable {
    let date: Date
    let altitude: Int?
    let groundSpeed: Double?
}

private enum FlightRealitySource {
    static let weatherDocumentation = URL(string: "https://aviationweather.gov/data/api/")!
    static let aircraftDocumentation = URL(string: "https://www.adsb.lol/docs/open-data/api")!

    // FAA Order JO 7340.2 three-letter operating-company designators for scheduled catalog entries.
    private static let knownOperators = [
        "SQ": ("SIA", "新加坡航空"), "CX": ("CPA", "国泰航空"), "MU": ("CES", "中国东方航空"),
        "LH": ("DLH", "德国汉莎航空"), "EK": ("UAE", "阿联酋航空"), "QF": ("QFA", "澳洲航空"),
        "QR": ("QTR", "卡塔尔航空"), "JL": ("JAL", "日本航空"), "DL": ("DAL", "达美航空")
    ]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config, delegate: FlightRealityHostDelegate(), delegateQueue: nil)
    }()

    static func callsign(for number: String, operatorName: String) -> String? {
        let normalized = number.uppercased().filter { !$0.isWhitespace }
        let prefix = String(normalized.prefix(2))
        let suffix = normalized.dropFirst(2)
        guard let (designator, airline) = knownOperators[prefix], airline == operatorName,
              (1...4).contains(suffix.utf8.count), suffix.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return designator + suffix
    }

    static func weather(for airportCodes: [String]) async -> Result<[AirportWeatherObservation], Error> {
        do {
            let stations = Set(airportCodes.map { $0.uppercased() }.filter { code in
                code.utf8.count == 4 && code.utf8.allSatisfy { (65...90).contains($0) }
            })
            guard !stations.isEmpty else { return .success([]) }
            var endpoint = URLComponents(string: "https://aviationweather.gov/api/data/metar")!
            endpoint.queryItems = [
                URLQueryItem(name: "ids", value: stations.sorted().joined(separator: ",")),
                URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "hours", value: "4")
            ]
            guard let data = try await get(endpoint.url) else { return .success([]) }
            let decoded = try JSONDecoder().decode([AirportWeatherObservation].self, from: data)
            let now = Date()
            let recent = decoded.filter { stations.contains($0.station) && (-300...14400).contains(now.timeIntervalSince($0.date)) }
                .sorted { $0.date > $1.date }
            var seen = Set<String>()
            return .success(recent.filter { seen.insert($0.station).inserted })
        } catch {
            return .failure(error)
        }
    }

    static func aircraft(for callsign: String?) async -> Result<PublicAircraftObservation?, Error> {
        guard let callsign else { return .success(nil) }
        do {
            let endpoint = URL(string: "https://api.adsb.lol/v2/callsign/\(callsign)")
            guard let data = try await get(endpoint) else { return .success(nil) }
            let reply = try JSONDecoder().decode(AircraftResponse.self, from: data)
            let responseDate = Date(timeIntervalSince1970: reply.now / 1000)
            guard (-30...120).contains(Date.now.timeIntervalSince(responseDate)), let records = reply.aircraft else { return .success(nil) }
            let matches = records.filter { record in
                record.flight?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == callsign
                    && record.seen.map { (0...60).contains($0) } == true
            }
            guard matches.count == 1, let record = matches.first, let seen = record.seen else { return .success(nil) }
            let altitude: Int? = if case .number(let value) = record.altitude { value } else { nil }
            return .success(PublicAircraftObservation(date: responseDate.addingTimeInterval(-seen), altitude: altitude, groundSpeed: record.groundSpeed))
        } catch {
            return .failure(error)
        }
    }

    private static func get(_ endpoint: URL?) async throws -> Data? {
        guard DistributionPolicy.liveFlightsAvailable, let endpoint, endpoint.scheme == "https" else {
            throw URLError(.unsupportedURL)
        }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("CivilAviationAtlas/1.2 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.host == endpoint.host,
              (200..<300).contains(http.statusCode), data.count <= 512_000 else { throw URLError(.badServerResponse) }
        return http.statusCode == 204 ? nil : data
    }

    private struct AircraftResponse: Decodable {
        struct Signal: Decodable {
            let flight: String?
            let seen: Double?
            let altitude: ObservedValue?
            let groundSpeed: Double?

            enum CodingKeys: String, CodingKey {
                case flight, seen, altitude = "alt_baro", groundSpeed = "gs"
            }
        }

        let now: Double
        let aircraft: [Signal]?

        enum CodingKeys: String, CodingKey { case now, aircraft = "ac" }
    }
}

private final class FlightRealityHostDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let sameSecureHost = request.url?.scheme == "https" && request.url?.host == task.originalRequest?.url?.host
        completionHandler(sameSecureHost ? request : nil)
    }
}
#endif
