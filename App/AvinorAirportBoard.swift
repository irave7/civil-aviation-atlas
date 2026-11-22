import Foundation
import SwiftUI
#if canImport(FoundationXML)
import FoundationXML
#endif

struct AvinorAirportBoard: View {
    let airport: Airport
    let library: AtlasLibrary

    @Environment(\.dismiss) private var dismiss
    @State private var direction = AvinorFlight.Direction.departure
    @State private var snapshot: AvinorFeed.Snapshot?
    @State private var isLoading = true
    @State private var requestInProgress = false
    @State private var failure: String?
    @State private var refreshCount = 0

    // The 43 airports in Avinor's published airport directory.
    private static let supportedCodes: Set<String> = [
        "AES", "ALF", "ANX", "BDU", "BGO", "BJF", "BNN", "BOO", "BVG", "EVE", "FDE",
        "FRO", "HAA", "HFT", "HOV", "HVG", "KKN", "KRS", "KSU", "LKL", "LKN", "LYR",
        "MEH", "MJF", "MOL", "MQN", "OSL", "OSY", "RET", "RRS", "RVK", "SDN", "SKN",
        "SOG", "SOJ", "SSJ", "SVG", "SVJ", "TOS", "TRD", "VAW", "VDS", "VRY"
    ]

    static func supports(_ airport: Airport) -> Bool {
        airport.countryCode == "NO" && supportedCodes.contains(airport.iata.uppercased())
    }

    private var displayedFlights: [AvinorFlight] {
        snapshot?.flights.filter { $0.direction == direction } ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("航班方向", selection: $direction) {
                        Text("出发").tag(AvinorFlight.Direction.departure)
                        Text("到达").tag(AvinorFlight.Direction.arrival)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("avinor-board-direction")
                } footer: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("时间为挪威当地时间。查看约过去 1 小时至未来 6 小时的航班。此数据源未提供执飞机型。")
                        if let snapshot { snapshotTime(snapshot) }
                    }
                }
                Section {
                    if isLoading && snapshot == nil {
                        ProgressView("正在读取机场航班")
                    } else if let failure {
                        Label(failure, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("avinor-board-error")
                    } else if displayedFlights.isEmpty {
                        ContentUnavailableView("此方向暂无航班", systemImage: "airplane")
                    } else {
                        ForEach(displayedFlights) { flight in
                            flightRow(flight)
                        }
                    }
                } header: {
                    Text("\(airport.displayCode) · \(airport.displayName)")
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("avinor-board")
            .navigationTitle("机场航班动态")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Link("Flight data from Avinor", destination: AvinorFeed.attribution)
                    .font(.callout.weight(.semibold))
                    .accessibilityIdentifier("avinor-board-attribution")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
            .refreshable { await refresh() }
            .task(id: refreshCount) { await refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("刷新", systemImage: "arrow.clockwise") { refreshCount += 1 }
                        .disabled(isLoading)
                        .accessibilityIdentifier("avinor-board-refresh")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("avinor-board-done")
                }
            }
        }
    }

    private func flightRow(_ flight: AvinorFlight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(flight.number).font(.system(.headline, design: .monospaced))
                Spacer()
                Text(AvinorFeed.localTime(flight.scheduledAt))
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .accessibilityLabel("计划 \(AvinorFeed.localTime(flight.scheduledAt))")
            }
            Text(airportLabel(flight.airportCode))
                .font(AtlasTypography.font(.subheadline, weight: .semibold))
            if let status = flight.statusText {
                Text(status).font(AtlasTypography.font(.subheadline))
            }
            if !flight.viaCodes.isEmpty {
                Text("经停 \(flight.viaCodes.map(airportLabel).joined(separator: "、"))")
                    .font(AtlasTypography.font(.footnote)).foregroundStyle(.secondary)
            }
            if !flight.facilities.isEmpty {
                Text(flight.facilities.joined(separator: " · "))
                    .font(AtlasTypography.font(.footnote)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("avinor-flight-\(flight.id)")
    }

    private func airportLabel(_ code: String) -> String {
        guard let destination = library.airport(code) else { return code }
        return "\(destination.displayName)  \(code)"
    }

    private func snapshotTime(_ current: AvinorFeed.Snapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 3) {
                Text("读取时间 \(AvinorFeed.localDateTime(current.readAt))")
                Text("来源更新 \(AvinorFeed.localDateTime(current.updatedAt))")
                if context.date.timeIntervalSince(current.readAt) > 360 {
                    Text("此页显示上次读取的航班动态。轻点刷新可重新查询。")
                }
            }
        }
    }

    private func refresh() async {
        guard !requestInProgress else { return }
        requestInProgress = true
        isLoading = true
        defer {
            requestInProgress = false
            isLoading = false
        }
        do {
            let response = try await AvinorBoardCache.shared.board(at: airport.iata.uppercased())
            try Task.checkCancellation()
            snapshot = response
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            snapshot = nil
            failure = (error as? AvinorFeed.FeedError)?.message ?? "暂时无法连接机场航班服务。可到 Avinor 查看。"
        }
    }
}

private struct AvinorFlight: Identifiable, Sendable {
    enum Direction: String, Hashable, Sendable {
        case departure = "D"
        case arrival = "A"
    }

    let id: String
    let number: String
    let direction: Direction
    let airportCode: String
    let scheduledAt: Date
    let statusCode: String?
    let statusTime: Date?
    let delayed: Bool
    let viaCodes: [String]
    let gate: String?
    let checkIn: String?
    let belt: String?

    var facilities: [String] {
        [
            gate.map { "登机口 \($0)" },
            direction == .departure ? checkIn.map { "值机区 \($0)" } : belt.map { "行李转盘 \($0)" }
        ].compactMap { $0 }
    }

    var statusText: String? {
        let time = statusTime.map { " \(AvinorFeed.localTime($0))" } ?? ""
        switch statusCode {
        case "A": return "已到达\(time)"
        case "C": return "已取消"
        case "D": return "已离港\(time)"
        case "E": return (delayed ? "延误 · 预计" : "预计") + time
        case "N": return time.isEmpty ? "等待更新" : "下次通报\(time)"
        case let code?: return "状态 \(code)"
        case nil: return delayed ? "延误" : nil
        }
    }
}

private actor AvinorBoardCache {
    static let shared = AvinorBoardCache()

    private struct CachedBoard {
        let expires: ContinuousClock.Instant
        let result: Result<AvinorFeed.Snapshot, Error>
    }

    private let clock = ContinuousClock()
    private var active: [String: Task<AvinorFeed.Snapshot, Error>] = [:]
    private var cache: [String: CachedBoard] = [:]

    func board(at code: String) async throws -> AvinorFeed.Snapshot {
        if let active = active[code] { return try await active.value }
        let now = clock.now
        if let cached = cache[code], now < cached.expires { return try cached.result.get() }

        let task = Task { try await AvinorFeed.download(airport: code) }
        active[code] = task
        let result = await task.result
        // Reopening, switching direction, and repeated refreshes share the same upstream request.
        cache[code] = CachedBoard(expires: now.advanced(by: .seconds(180)), result: result)
        active[code] = nil
        return try result.get()
    }
}

private enum AvinorFeed {
    static let attribution = URL(string: "https://www.avinor.no")!
    private static let norwayZone = TimeZone(identifier: "Europe/Oslo") ?? .gmt

    struct Snapshot: Sendable {
        let flights: [AvinorFlight]
        let updatedAt: Date
        let readAt: Date
    }

    enum FeedError: Error {
        case unavailable, unrecognized, expired

        var message: String {
            switch self {
            case .unavailable: "机场航班服务暂时无法读取。可到 Avinor 查看。"
            case .unrecognized: "机场返回了无法识别的航班资料。"
            case .expired: "机场返回的时刻超出当前查询范围。可到 Avinor 查看最新资料。"
            }
        }
    }

    static func localTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "zh_CN"), timeZone: norwayZone))
    }

    static func localDateTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .numeric, time: .shortened, locale: Locale(identifier: "zh_CN"), timeZone: norwayZone))
    }

    static func download(airport: String) async throws -> Snapshot {
        var endpoint = URLComponents(string: "https://asrv.avinor.no/XmlFeed/v1.0")!
        endpoint.queryItems = [
            URLQueryItem(name: "airport", value: airport),
            URLQueryItem(name: "TimeFrom", value: "1"),
            URLQueryItem(name: "TimeTo", value: "6")
        ]
        if airport == "VRY" { endpoint.queryItems?.append(URLQueryItem(name: "serviceType", value: "E")) }
        guard let url = endpoint.url else { throw FeedError.unavailable }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 14)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.url?.scheme == "https", http.url?.host == "asrv.avinor.no",
              data.count <= 4_000_000 else { throw FeedError.unavailable }
        return try decode(data, airport: airport, now: .now)
    }

    static func decode(_ data: Data, airport: String, now: Date) throws -> Snapshot {
        let reader = AvinorXMLReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.airport == airport, let updatedAt = reader.updatedAt,
              reader.flightElements == 0 || !reader.flights.isEmpty else { throw FeedError.unrecognized }
        let lower = now.addingTimeInterval(-3 * 3600)
        let upper = now.addingTimeInterval(8 * 3600)
        var seen = Set<String>()
        let records = reader.flights.filter { flight in
            let operational = ["A", "D", "E"].contains(flight.statusCode ?? "") ? flight.statusTime : nil
            let overlaps = (lower...upper).contains(flight.scheduledAt) || operational.map { (lower...upper).contains($0) } == true
            return overlaps && seen.insert(flight.id).inserted
        }.sorted {
            ($0.scheduledAt, $0.number) < ($1.scheduledAt, $1.number)
        }
        guard reader.flightElements == 0 || !records.isEmpty else { throw FeedError.expired }
        return Snapshot(flights: records, updatedAt: updatedAt, readAt: now)
    }
}

private final class AvinorXMLReader: NSObject, XMLParserDelegate {
    private struct Draft {
        let id: String?
        var fields: [String: String] = [:]
        var statusCode: String?
        var statusTime: String?
    }

    private let compactISO = ISO8601DateFormatter()
    private let fractionalISO: ISO8601DateFormatter = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format
    }()
    private var draft: Draft?
    private var path: [String] = []
    private var buffer = ""

    private(set) var airport: String?
    private(set) var updatedAt: Date?
    private(set) var flightElements = 0
    private(set) var flights: [AvinorFlight] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        path.append(elementName)
        switch path.count {
        case 1 where elementName == "airport":
            airport = attributeDict["name"]
        case 2 where elementName == "flights":
            updatedAt = date(attributeDict["lastUpdate"])
        case 3 where elementName == "flight" && path[1] == "flights":
            flightElements += 1
            draft = Draft(id: attributeDict["uniqueID"] ?? attributeDict["uniqueId"])
        case 4:
            buffer = ""
            if elementName == "status" {
                draft?.statusCode = attributeDict["code"]
                draft?.statusTime = attributeDict["time"]
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if draft != nil && path.count == 4 { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if path.count == 4, elementName != "status", let value = cleaned(buffer) {
            draft?.fields[elementName] = value
        } else if path.count == 3, elementName == "flight", let draft {
            if let flight = makeFlight(from: draft) { flights.append(flight) }
            self.draft = nil
        }
        path.removeLast()
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        parser.abortParsing()
    }

    private func makeFlight(from draft: Draft) -> AvinorFlight? {
        let fields = draft.fields
        guard let number = fields["flight_id"] ?? fields["flightId"],
              let rawDirection = fields["arr_dep"], let direction = AvinorFlight.Direction(rawValue: rawDirection),
              let code = fields["airport"], let scheduledAt = date(fields["schedule_time"]) else { return nil }
        let keys = [rawDirection, number, code, String(scheduledAt.timeIntervalSinceReferenceDate)]
        let via = fields["via_airport"]?.split(separator: ",").compactMap { cleaned(String($0)) } ?? []
        return AvinorFlight(
            id: cleaned(draft.id) ?? keys.joined(separator: "|"),
            number: number, direction: direction, airportCode: code, scheduledAt: scheduledAt,
            statusCode: cleaned(draft.statusCode), statusTime: date(draft.statusTime),
            delayed: ["Y", "TRUE"].contains(fields["delayed"]?.uppercased() ?? ""),
            viaCodes: via, gate: fields["gate"], checkIn: fields["check_in"], belt: fields["belt_number"] ?? fields["belt"]
        )
    }

    private func cleaned(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private func date(_ text: String?) -> Date? {
        guard let text = cleaned(text) else { return nil }
        return compactISO.date(from: text) ?? fractionalISO.date(from: text)
    }
}
