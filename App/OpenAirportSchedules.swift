import Foundation
import SwiftUI

struct OpenAirportSchedules: View {
    let airport: Airport
    let library: AtlasLibrary
    let context: FlightBoardContext?

    @Environment(\.dismiss) private var dismiss
    @State private var direction: TaoyuanFlight.Direction
    @State private var flights: [TaoyuanFlight] = []
    @State private var isLoading = false
    @State private var failure: String?
    @State private var lastFetched: Date?
    @State private var refreshToken = 0

    static func supports(_ iata: String) -> Bool { iata.uppercased() == "TPE" }

    init(airport: Airport, library: AtlasLibrary, context: FlightBoardContext? = nil) {
        self.airport = airport
        self.library = library
        self.context = context
        _direction = State(initialValue: context?.isArrival == true ? .arrival : .departure)
    }

    private var displayedFlights: [TaoyuanFlight] {
        flights.filter { flight in
            guard flight.direction == direction else { return false }
            guard let context else { return true }
            return context.matches(number: flight.flightNumber, airport: flight.airportCode)
                && context.matches(dayForTimestamp: flight.scheduledAt, in: TaoyuanFlight.airportTimeZone)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let context { PublishedFlightFacts(context: context, library: library) }
                Section {
                    if let context {
                        LabeledContent("机场当地日期", value: context.day)
                    } else {
                        Picker("航班方向", selection: $direction) {
                            Text("出发").tag(TaoyuanFlight.Direction.departure)
                            Text("到达").tag(TaoyuanFlight.Direction.arrival)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                } footer: {
                    Text("时间采用桃园当地时间（UTC+8）。机型按机场公布内容显示。")
                }
                Section {
                    if isLoading && flights.isEmpty {
                        ProgressView("正在读取机场数据")
                    } else if displayedFlights.isEmpty && failure == nil {
                        ContentUnavailableView("暂无匹配航班", systemImage: "airplane", description: Text("机场数据仅包含近期公布的航班。"))
                    } else {
                        ForEach(displayedFlights) { flight in
                            flightRow(flight)
                        }
                    }
                } header: {
                    Text("\(airport.displayCode) · \(airport.displayName)")
                } footer: {
                    if let lastFetched {
                        Text("读取时间 \(TaoyuanFlight.format(lastFetched))（UTC+8）")
                    }
                }
                if let failure {
                    Section {
                        Label(failure, systemImage: "info.circle")
                            .font(AtlasTypography.font(.subheadline))
                    }
                }
                Section("数据来源") {
                    Link("桃園國際機場股份有限公司（2026） · 桃園國際機場即時航班第二版", destination: TaoyuanFlight.dataset)
                    Link("政府資料開放授權條款第 1 版", destination: TaoyuanFlight.license)
                }
            }
            .accessibilityIdentifier("flight-details-board")
            .navigationTitle(context?.flightNumber ?? "桃园机场航班动态")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await refresh() }
            .task(id: refreshToken) { await refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        refreshToken += 1
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityIdentifier("open-flights-refresh")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func flightRow(_ flight: TaoyuanFlight) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(flight.flightNumber).font(AtlasTypography.font(.headline).monospacedDigit())
                Spacer()
                Text(TaoyuanFlight.format(flight.scheduledAt)).font(AtlasTypography.font(.subheadline).monospacedDigit())
            }
            let destination = library.airport(flight.airportCode)?.displayName ?? flight.airportName
            Text(destination.isEmpty ? flight.airportCode : "\(destination)  \(flight.airportCode)")
                .font(AtlasTypography.font(.subheadline))
            HStack(alignment: .firstTextBaseline) {
                Text(flight.airline)
                Text("机型 \(flight.aircraft.map(AircraftProfile.localizedFeedName) ?? "未公布")")
            }
            .font(AtlasTypography.font(.caption))
            .foregroundStyle(.secondary)
            if let status = flight.status {
                Text(status).font(AtlasTypography.font(.caption)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let records = try await TaoyuanFlight.download()
            try Task.checkCancellation()
            flights = records
            failure = nil
            lastFetched = Date()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch let error as TaoyuanFlight.FeedError {
            failure = error.message
        } catch {
            failure = "开放数据服务暂时无法连接。可稍后刷新。"
        }
    }
}

private struct TaoyuanFlight: Identifiable, Sendable {
    enum Direction: String, Hashable, Sendable {
        case departure = "D"
        case arrival = "A"

        init?(record: String) {
            switch record.uppercased() {
            case "D", "PD", "CD", "DEP", "DEPARTURE", "出境", "出發", "出发", "起飛", "起飞": self = .departure
            case "A", "PA", "CA", "ARR", "ARRIVAL", "入境", "抵達", "抵达", "到達", "到达": self = .arrival
            default: return nil
            }
        }
    }

    enum FeedError: Error {
        case unavailable, unrecognized, expired

        var message: String {
            switch self {
            case .unavailable: "机场开放数据服务暂时无法读取。"
            case .unrecognized: "机场返回的数据格式暂时无法识别。"
            case .expired: "机场开放数据返回了较早的时刻表。"
            }
        }
    }

    let flightNumber: String
    let direction: Direction
    let airline: String
    let airportCode: String
    let airportName: String
    let scheduledAt: Date
    let aircraft: String?
    let status: String?

    var id: String { "\(direction.rawValue)|\(flightNumber)|\(airportCode)|\(scheduledAt.timeIntervalSinceReferenceDate)" }

    static let dataset = URL(string: "https://data.gov.tw/dataset/177644")!
    static let license = URL(string: "https://data.gov.tw/en/license")!
    private static let feed = URL(string: "https://odp.taoyuan-airport.com/dataset/2025102001?format=csv")!
    static let airportTimeZone = TimeZone(identifier: "Asia/Taipei")!

    static func format(_ date: Date) -> String {
        let format = Date.FormatStyle(date: .numeric, time: .shortened, locale: Locale(identifier: "zh_CN"), timeZone: airportTimeZone)
        return date.formatted(format)
    }

    static func download() async throws -> [TaoyuanFlight] {
        guard DistributionPolicy.liveFlightsAvailable else { throw FeedError.unavailable }
        var request = URLRequest(url: feed, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 12)
        request.setValue("text/csv", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.url?.scheme == "https", data.count <= 8_000_000 else { throw FeedError.unavailable }
        try Task.checkCancellation()
        return try decode(data, now: Date())
    }

    static func decode(_ data: Data, now: Date) throws -> [TaoyuanFlight] {
        guard var text = String(data: data, encoding: .utf8) else { throw FeedError.unrecognized }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let table = try readCSV(text)
        guard let first = table.first else { throw FeedError.unrecognized }
        let header = first.map { cleaned($0) }
        let hasHeader = header.contains("機型") || header.contains("表訂時間")
        let layout = ColumnLayout(header: hasHeader ? header : nil)
        let rows = hasHeader ? table.dropFirst() : table[...]
        let timestamp = DateFormatter()
        timestamp.locale = Locale(identifier: "en_US_POSIX")
        timestamp.calendar = Calendar(identifier: .gregorian)
        timestamp.timeZone = airportTimeZone
        timestamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var ids = Set<String>()
        let records: [TaoyuanFlight] = rows.compactMap { values in
            guard hasHeader || values.count == 22 else { return nil }
            func field(_ index: Int?) -> String {
                guard let index, values.indices.contains(index) else { return "" }
                return cleaned(values[index])
            }
            guard let direction = Direction(record: field(layout.direction)) else { return nil }
            let code = field(layout.airlineCode).uppercased()
            let suffix = field(layout.flight).uppercased().filter { !$0.isWhitespace }
            let airportCode = field(layout.airportCode).uppercased()
            let date = field(layout.scheduledDate).replacingOccurrences(of: "/", with: "-")
            let enteredTime = field(layout.scheduledTime)
            let time = enteredTime.split(separator: ":").count == 2 ? enteredTime + ":00" : enteredTime
            guard !code.isEmpty, !suffix.isEmpty, airportCode.count == 3,
                  let scheduledAt = timestamp.date(from: "\(date) \(time)") else { return nil }
            let airlineName = field(layout.airlineName)
            let airportName = field(layout.airportName)
            let aircraft = field(layout.aircraft)
            let status = field(layout.status)
            let record = TaoyuanFlight(
                flightNumber: suffix.hasPrefix(code) && suffix.count > code.count ? suffix : code + suffix,
                direction: direction, airline: airlineName.isEmpty ? code : airlineName, airportCode: airportCode,
                airportName: airportName, scheduledAt: scheduledAt, aircraft: aircraft.isEmpty ? nil : aircraft,
                status: status.isEmpty ? nil : status
            )
            return ids.insert(record.id).inserted ? record : nil
        }
        guard !records.isEmpty else { throw FeedError.unrecognized }
        guard let latest = records.map(\.scheduledAt).max(), latest > now.addingTimeInterval(-36 * 3600) else {
            throw FeedError.expired
        }
        return records.sorted {
            $0.scheduledAt == $1.scheduledAt ? $0.flightNumber < $1.flightNumber : $0.scheduledAt < $1.scheduledAt
        }
    }

    private static func cleaned(_ cell: String) -> String {
        let value = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["-", "–", "—", "N/A", "NULL"].contains(value.uppercased()) ? "" : value
    }

    private struct ColumnLayout {
        let direction: Int?
        let airlineCode: Int?
        let airlineName: Int?
        let flight: Int?
        let scheduledDate: Int?
        let scheduledTime: Int?
        let airportCode: Int?
        let airportName: Int?
        let aircraft: Int?
        let status: Int?

        init(header: [String]?) {
            // Positions are the version 2 field order declared by the provider for a file without column titles.
            func column(_ names: [String], position: Int) -> Int? {
                guard let header else { return position }
                return names.lazy.compactMap { header.firstIndex(of: $0) }.first
            }
            direction = column(["方向", "種類"], position: 1)
            airlineCode = column(["航空公司代碼"], position: 2)
            airlineName = column(["航空公司中文"], position: 3)
            flight = column(["班次", "航班號"], position: 4)
            scheduledDate = column(["表訂日期", "表定日期"], position: 6)
            scheduledTime = column(["表訂時間", "表定時間"], position: 7)
            airportCode = column(["往來地點"], position: 10)
            airportName = column(["往來地點中文", "往來地點英文"], position: 12)
            status = column(["航班動態中文", "航班狀態", "備註"], position: 16)
            aircraft = column(["機型"], position: 18)
        }
    }

    private static func readCSV(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            index = text.index(after: index)
            if character == "\"" {
                if quoted && index < text.endIndex && text[index] == "\"" {
                    field.append("\"")
                    index = text.index(after: index)
                } else {
                    quoted.toggle()
                }
            } else if quoted {
                field.append(character)
            } else if character == "," {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row.removeAll(keepingCapacity: true)
                field = ""
            } else {
                field.append(character)
            }
        }
        guard !quoted else { throw FeedError.unrecognized }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}
