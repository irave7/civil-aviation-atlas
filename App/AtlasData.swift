import Foundation
import Observation

struct AtlasSource: Codable, Identifiable, Hashable {
    let title: String
    let url: String
    var detail: String? = nil
    var id: String { url + title }
}

struct Runway: Codable, Identifiable, Hashable {
    let id: String
    let lengthM: Double
    let widthM: Double?
    let heading: Double?
    let lat: Double?
    let lon: Double?
    let surface: String?
    let status: String?
}

struct AirportTerminal: Codable, Identifiable, Hashable {
    let name: String
    let description: String
    var id: String { name }
}

struct Airport: Codable, Identifiable, Hashable {
    let id: String
    let iata: String
    let icao: String
    let name: String
    let city: String
    let country: String
    let lat: Double
    let lon: Double
    let elevationFt: Int?
    let runways: [Runway]?
    let terminals: [AirportTerminal]?
    let description: String?
    let opened: String?
    let sources: [AtlasSource]?
    let featured: Bool?
    let localizedName: String?
    let localizedCity: String?
    let localizedNameAliases: [String]?
    let localizedNameSource: String?
    let countryCode: String?
    let type: String?
    let civilUse: String?
    let publicAccess: String?
    let operatingStatus: String?

    var displayName: String { localizedName ?? name }
    var displayCity: String { localizedCity ?? (city.isEmpty ? country : city) }
    var displayCode: String { iata.isEmpty ? (icao.isEmpty ? id : icao) : iata }
    var nameSearchTerms: [String] {
        [iata, icao, id, displayName, name, displayCity, city, country, countryCode ?? ""] + (localizedNameAliases ?? [])
    }
    var hasDetailedModel: Bool { id == "HKG" }
    var hasBasicModel: Bool { AirportSiteCatalog.hasRunways(for: self) }
    var hasSiteModel: Bool { AirportSiteCatalog.hasBuildings(for: self) }
    var modelLabel: String {
        if hasDetailedModel { return "外观与内部" }
        if hasSiteModel {
            return AirportSiteCatalog.hasSurfaceLayout(for: self) ? "机场外部模型" : "建筑外观"
        }
        if hasBasicModel { return "跑道模型" }
        return AirportSiteCatalog.hasTerrain(for: self) ? "场址地形" : "机场场址"
    }
}

struct FlightRoute: Codable, Identifiable, Hashable {
    struct ObservedStatistics: Codable, Hashable {
        let observation: AirportRouteObservation
        let source: AtlasSource
    }

    let origin: String
    let destination: String
    let airline: String
    let aircraft: String
    let distanceKm: Double?
    let status: String?
    let sourceTitle: String?
    let sourceURL: String?
    let flightNumber: String?
    let validFrom: String?
    let validThrough: String?
    let departureLocal: String?
    let arrivalLocal: String?
    let frequency: String?
    let aircraftID: String?
    let aircraftVariant: String?
    let updatedAt: String?
    var observedStatistics: [ObservedStatistics]? = nil

    var id: String {
        [origin, destination, airline, flightNumber ?? aircraft, validFrom ?? "", validThrough ?? "", frequency ?? "", departureLocal ?? "", observedStatistics == nil ? "" : "observed"].joined(separator: "|")
    }

    var displayAircraftName: String {
        aircraft.components(separatedBy: "、").map(AircraftProfile.localizedFeedName).joined(separator: "、")
    }

    var hasVerifiedNonstop: Bool {
        if let observedStatistics { return observedStatistics.contains { $0.observation.verifiedNonstop == true } }
        return status != "已公布 · 未开航"
    }

    var aircraftSearchTerms: [String] {
        [aircraft, displayAircraftName, aircraftVariant ?? ""] + (aircraftID.flatMap { AircraftProfile.byID[$0]?.searchTerms } ?? [])
    }

    func isPublishedPlan(on date: String) -> Bool {
        guard status == "计划班表", let start = validFrom, let end = validThrough else { return false }
        return start <= date && date <= end
    }

    var source: AtlasSource? {
        guard let sourceURL else { return nil }
        return AtlasSource(title: sourceTitle ?? "航线来源", url: sourceURL)
    }
}

struct AirportCatalog: Codable {
    let airports: [Airport]
    let routes: [FlightRoute]
    let sources: [AtlasSource]
    let updatedAt: String
    let routeDistanceMethod: String
    let routeCoverage: String
}

@MainActor
@Observable
final class AtlasLibrary {
    static let shared = AtlasLibrary()

    let catalog: AirportCatalog?
    let airports: [Airport]
    let featured: [Airport]
    let aircraft = AircraftProfile.catalog
    private let byAirportID: [String: Airport]
    private let routesByAirport: [String: [FlightRoute]]
    private let searchIndex: [(airport: Airport, code: String, lookup: String)]
    private let bundle: Bundle
    private var observed: AirportObservedRouteLibrary?
    @ObservationIgnored private var observedLoad: Task<AirportObservedRouteLibrary, Never>?

    private init(bundle: Bundle = .main) {
        self.bundle = bundle
        let url = bundle.url(forResource: "airport-data", withExtension: "json")
            ?? bundle.url(forResource: "airport-data", withExtension: "json", subdirectory: "Resources")
        let loadedCatalog = url.flatMap { location in
            (try? Data(contentsOf: location)).flatMap { try? JSONDecoder().decode(AirportCatalog.self, from: $0) }
        }
        let loadedAirports = loadedCatalog?.airports ?? []
        let airportIndex = Dictionary(uniqueKeysWithValues: loadedAirports.map { ($0.id, $0) })
        catalog = loadedCatalog
        airports = loadedAirports
        byAirportID = airportIndex
        featured = ["HKG", "SIN", "SFO"].compactMap { airportIndex[$0] }
        var grouped: [String: [FlightRoute]] = [:]
        for route in loadedCatalog?.routes ?? [] {
            grouped[route.origin, default: []].append(route)
            if route.origin != route.destination { grouped[route.destination, default: []].append(route) }
        }
        routesByAirport = grouped
        searchIndex = loadedAirports.map { airport in
            let lookup = airport.nameSearchTerms.joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            return (airport, airport.displayCode.lowercased(), lookup)
        }
    }

    func airport(_ id: String) -> Airport? { byAirportID[id] }
    func aircraft(_ id: String) -> AircraftProfile? { aircraft.first { $0.id == id } }
    func routes(at airport: Airport) -> [FlightRoute] { routesByAirport[airport.id] ?? [] }
    func prepareObservedRoutes() async {
        guard observed == nil else { return }
        let resourceBundle = bundle
        let load = observedLoad ?? Task.detached(priority: .utility) {
            AirportObservedRouteLibrary(bundle: resourceBundle)
        }
        observedLoad = load
        observed = await load.value
        observedLoad = nil
    }
    func observedRoutes(at airport: Airport) -> [FlightRoute] { observed?.routes(at: airport) ?? [] }
    var observedRouteSources: [AtlasSource] { observed?.sources ?? [] }
    var observedRouteCoverage: String? { observed?.coverage }
    var isPreparingObservedRoutes: Bool { observed == nil }
    func longestRecordedRoute(at airport: Airport, on day: String) -> FlightRoute? {
        let published = routes(at: airport).filter { $0.isPublishedPlan(on: day) }
        let observed = observedRoutes(at: airport)
        let verified = published + observed.filter(\.hasVerifiedNonstop)
        let documented = routes(at: airport).filter { $0.status != "已公布 · 未开航" }
        let records = !verified.isEmpty ? verified : observed + documented
        return records.filter { ($0.distanceKm ?? 0) > 0 }.max { lhs, rhs in
            (lhs.distanceKm ?? 0) < (rhs.distanceKm ?? 0)
        }
    }
    func routes(for aircraft: AircraftProfile) -> [FlightRoute] {
        (catalog?.routes ?? []).filter { $0.aircraftID == aircraft.id }
    }

    func search(_ query: String, including include: (Airport) -> Bool = { _ in true }) -> [Airport] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        guard !key.isEmpty else { return featured.filter(include) }
        var exact: [Airport] = []
        var prefixes: [Airport] = []
        var matched: [Airport] = []
        let words = key.split(whereSeparator: \.isWhitespace)
        for item in searchIndex where include(item.airport) {
            if item.code == key || item.airport.icao.lowercased() == key {
                exact.append(item.airport)
            } else if item.code.hasPrefix(key) {
                prefixes.append(item.airport)
            } else if words.allSatisfy({ item.lookup.contains($0) }) {
                matched.append(item.airport)
            }
        }
        return Array((exact + prefixes + matched).prefix(200))
    }
}

struct AircraftCabinZone: Hashable {
    let label: String
    let numberOfRows: Int
    let seatGroups: [Int]
    let startM: Float
    let endM: Float
    var partialLastRow: [Int]? = nil
    var deck: Int = 0

    var seatCount: Int {
        let perRow = seatGroups.reduce(0, +)
        guard let partialLastRow else { return numberOfRows * perRow }
        return (numberOfRows - 1) * perRow + partialLastRow.reduce(0, +)
    }
}

struct AircraftConfiguration: Identifiable, Hashable {
    let id: String
    let airline: String
    let name: String
    let cabinDescription: String
    let seats: [AircraftCabinZone]
    let isIllustrative: Bool
}

enum AircraftManufacturer: String, CaseIterable, Hashable {
    case airbus = "Airbus"
    case boeing = "Boeing"
    case comac = "COMAC"
    case embraer = "Embraer"
    case mcdonnellDouglas = "McDonnell Douglas"
    case bombardier = "Bombardier"
    case atr = "ATR"
    case deHavilland = "De Havilland Canada"

    var displayName: String {
        switch self {
        case .airbus: "空中客车"
        case .boeing: "波音"
        case .comac: "中国商飞"
        case .embraer: "巴西航空工业"
        case .mcdonnellDouglas: "麦克唐纳·道格拉斯"
        case .bombardier: "庞巴迪"
        case .atr: "ATR"
        case .deHavilland: "加拿大德哈维兰"
        }
    }

    var aliases: [String] {
        switch self {
        case .airbus: ["空客", "空中巴士"]
        case .comac: ["商飞", "国产"]
        case .embraer: ["巴航工业", "巴航"]
        default: []
        }
    }

    func displayName(for model: String) -> String {
        let localizedModel = model.replacingOccurrences(of: "Intercontinental", with: "洲际客机", options: .caseInsensitive)
        return "\(displayName) \(localizedModel)"
    }
}

struct AircraftProfile: Identifiable, Hashable {
    let id: String
    let modelName: String
    let manufacturer: AircraftManufacturer
    let series: String
    let description: String
    let lengthM: Double
    let wingspanM: Double
    let rangeDescription: String
    let configurations: [AircraftConfiguration]
    let sources: [AtlasSource]

    var title: String { "\(manufacturer.rawValue) \(modelName)" }
    var displayName: String { manufacturer.displayName(for: modelName) }

    var searchTerms: [String] {
        let aliases = manufacturer.aliases.map { "\($0) \(modelName)" }
        return [id, title, displayName, modelName, series] + aliases + (Self.codesByProfile[id] ?? [])
    }

    func matchesSearch(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace).map { Self.searchKey(String($0)) }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return true }
        let fields = searchTerms.map(Self.searchKey)
        return terms.allSatisfy { term in fields.contains { $0.contains(term) } }
    }

    static func localizedFeedName(_ rawName: String) -> String {
        let text = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = feedNamesByCode[text.uppercased()] {
            let model = name.model
            let displayName = name.manufacturer.displayName(for: model)
            return text.caseInsensitiveCompare(model) == .orderedSame ? displayName : "\(displayName)（\(text)）"
        }
        if let name = profilesByFeedName[searchKey(text)] {
            return name.displayName
        }
        for manufacturer in AircraftManufacturer.allCases {
            let prefix = "\(manufacturer.rawValue) "
            if text.range(of: prefix, options: [.anchored, .caseInsensitive]) != nil {
                let model = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !model.isEmpty { return manufacturer.displayName(for: model) }
            }
        }
        return text
    }

    private static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }

    static let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })

    private static let profilesByFeedName: [String: AircraftProfile] = {
        var result: [String: AircraftProfile] = [:]
        for profile in catalog {
            result[searchKey(profile.modelName)] = profile
            result[searchKey(profile.title)] = profile
            if let code = profile.modelName.split(separator: " ").first, profile.modelName.hasSuffix(" (ceo)") {
                result[searchKey(String(code))] = profile
            }
        }
        return result
    }()

    private static let codesByProfile: [String: [String]] = [
        "a220-300": ["BCS3", "223"], "a319": ["A319", "319"],
        "a320ceo": ["A320", "320"], "a320neo": ["A20N", "32N"],
        "a321ceo": ["A321", "321"], "a321neo": ["A21N", "32Q"],
        "a330-200": ["A332", "332"], "a330-300": ["A333", "333"], "a330-900": ["A339", "339"],
        "a350-900": ["A359", "359"], "a350-900ulr": ["A359", "359", "超远程型"], "a350-1000": ["A35K", "351"],
        "a380-800": ["A388", "388"], "b737-700": ["B737", "73G"], "b737-800": ["B738", "738"],
        "b737-900er": ["B739", "739", "73J"], "b737-max8": ["B38M", "7M8"], "b737-max9": ["B39M", "7M9"],
        "b747-400": ["B744", "744"], "b747-8i": ["B748", "74H", "747-8I"],
        "b757-200": ["B752", "752"], "b767-300er": ["B763", "763", "76W"], "b777-200er": ["B772", "772", "77E"],
        "b777-300er": ["B77W", "77W"], "b787-8": ["B788", "788"], "b787-9": ["B789", "789"],
        "b787-10": ["B78X", "781"], "c919": ["C919"], "e195-e2": ["E295", "295"]
    ]

    private struct FeedType {
        let manufacturer: AircraftManufacturer
        let model: String

        init(_ manufacturer: AircraftManufacturer, _ model: String) {
            self.manufacturer = manufacturer
            self.model = model
        }
    }

    // Shared type codes are displayed at family precision. A359, for example, cannot identify the ULR variant.
    // ICAO Doc 8643 / FAA aircraft type designators and airline schedule equipment codes.
    private static let feedNamesByCode: [String: FeedType] = {
        let types: [(FeedType, [String])] = [
            (.init(.airbus, "A220-100"), ["BCS1", "221"]), (.init(.airbus, "A220-300"), ["BCS3", "223"]),
            (.init(.airbus, "A318"), ["A318", "318"]), (.init(.airbus, "A319"), ["A319", "319"]),
            (.init(.airbus, "A319neo"), ["A19N", "31N"]), (.init(.airbus, "A320"), ["A320", "320"]),
            (.init(.airbus, "A320neo"), ["A20N", "32N"]), (.init(.airbus, "A321"), ["A321", "321"]),
            (.init(.airbus, "A321neo"), ["A21N", "32Q"]), (.init(.airbus, "A321LR"), ["32L"]),
            (.init(.airbus, "A321XLR"), ["32X"]), (.init(.airbus, "A330-200"), ["A332", "332"]),
            (.init(.airbus, "A330-200F"), ["A33F", "33X"]), (.init(.airbus, "A330-300"), ["A333", "333"]),
            (.init(.airbus, "A330-800"), ["A338", "338"]), (.init(.airbus, "A330-900"), ["A339", "339"]),
            (.init(.airbus, "A340-300"), ["A343", "343"]), (.init(.airbus, "A340-500"), ["A345", "345"]),
            (.init(.airbus, "A340-600"), ["A346", "346"]), (.init(.airbus, "A350-900"), ["A359", "359"]),
            (.init(.airbus, "A350-1000"), ["A35K", "351"]), (.init(.airbus, "A380-800"), ["A388", "388"]),
            (.init(.boeing, "737-300"), ["B733", "733"]), (.init(.boeing, "737-400"), ["B734", "734"]),
            (.init(.boeing, "737-500"), ["B735", "735"]), (.init(.boeing, "737-600"), ["B736", "736"]),
            (.init(.boeing, "737-700"), ["B737", "73G", "73W"]), (.init(.boeing, "737-800"), ["B738", "738", "73H"]),
            (.init(.boeing, "737-900 系列"), ["B739", "739", "73J"]),
            (.init(.boeing, "737 MAX 7"), ["B37M", "7M7"]), (.init(.boeing, "737 MAX 8"), ["B38M", "7M8"]),
            (.init(.boeing, "737 MAX 9"), ["B39M", "7M9"]), (.init(.boeing, "737 MAX 10"), ["B3XM", "7MJ"]),
            (.init(.boeing, "747-400 系列"), ["B744", "744"]), (.init(.boeing, "747-400F"), ["74Y"]),
            (.init(.boeing, "747-8 系列"), ["B748"]), (.init(.boeing, "747-8 洲际客机"), ["74H", "747-8I"]),
            (.init(.boeing, "747-8F"), ["74N"]), (.init(.boeing, "757-200"), ["B752", "752"]),
            (.init(.boeing, "757-300"), ["B753", "753"]), (.init(.boeing, "767-200 系列"), ["B762", "762"]),
            (.init(.boeing, "767-300 系列"), ["B763", "763", "76W"]), (.init(.boeing, "767-300F"), ["76F"]),
            (.init(.boeing, "767-400ER"), ["B764", "764"]), (.init(.boeing, "777-200 系列"), ["B772", "772"]),
            (.init(.boeing, "777-200ER"), ["77E"]), (.init(.boeing, "777-200LR"), ["77L"]),
            (.init(.boeing, "777-200LR／777F"), ["B77L"]), (.init(.boeing, "777F"), ["77X"]),
            (.init(.boeing, "777-300"), ["B773", "773"]), (.init(.boeing, "777-300ER"), ["B77W", "77W"]),
            (.init(.boeing, "787-8"), ["B788", "788"]), (.init(.boeing, "787-9"), ["B789", "789"]),
            (.init(.boeing, "787-10"), ["B78X", "781"]), (.init(.comac, "C909"), ["AJ27", "ARJ21"]),
            (.init(.comac, "C919"), ["C919"]), (.init(.embraer, "E170"), ["E170", "E70"]),
            (.init(.embraer, "E175"), ["E75L", "E75S", "E75"]), (.init(.embraer, "E190"), ["E190", "E90"]),
            (.init(.embraer, "E195"), ["E195", "E95"]), (.init(.embraer, "E190-E2"), ["E290", "290"]),
            (.init(.embraer, "E195-E2"), ["E295", "295"]), (.init(.mcdonnellDouglas, "MD-11"), ["MD11", "M11"]),
            (.init(.mcdonnellDouglas, "MD-11F"), ["M1F"]), (.init(.bombardier, "CRJ200"), ["CRJ2", "CR2"]),
            (.init(.bombardier, "CRJ700"), ["CRJ7", "CR7"]), (.init(.bombardier, "CRJ900"), ["CRJ9", "CR9"]),
            (.init(.bombardier, "CRJ1000"), ["CRJX", "CRK"]), (.init(.atr, "42 系列"), ["AT43", "AT45", "AT46", "AT4"]),
            (.init(.atr, "72 系列"), ["AT72", "AT73", "AT75", "AT76", "AT7"]),
            (.init(.deHavilland, "Dash 8-400"), ["DH8D", "DH4"])
        ]
        return Dictionary(uniqueKeysWithValues: types.flatMap { type, codes in codes.map { ($0, type) } })
    }()

    var isTwinAisle: Bool {
        configurations.contains { configuration in
            configuration.seats.contains { $0.seatGroups.count >= 3 }
        }
    }

    static let catalog: [AircraftProfile] = [
        AircraftProfile(
            id: "a350-900", modelName: "A350-900", manufacturer: .airbus, series: "A350 系列",
            description: "双通道远程客机，搭载两台 Trent XWB 涡扇发动机。查看机翼、尾翼、机身、客舱和起落架，也可以切换航司客舱布局。",
            lengthM: 66.8, wingspanM: 64.75, rangeDescription: "标称航程随重量版本与任务配置变化，详见空客机型资料。",
            configurations: [
                AircraftConfiguration(id: "sia-long", airline: "新加坡航空", name: "远程客舱", cabinDescription: "按航司公开座位图与舱段布局制作，机身饰带与座椅外观为图鉴示意。", seats: [
                    AircraftCabinZone(label: "商务舱", numberOfRows: 11, seatGroups: [1, 2, 1], startM: 8, endM: 23.7, partialLastRow: [1, 0, 1]),
                    AircraftCabinZone(label: "优选经济舱", numberOfRows: 3, seatGroups: [2, 4, 2], startM: 25.4, endM: 29.0),
                    AircraftCabinZone(label: "经济舱", numberOfRows: 21, seatGroups: [3, 3, 3], startM: 31, endM: 55.9, partialLastRow: [2, 3, 2])
                ], isIllustrative: true),
                AircraftConfiguration(id: "cx-long", airline: "国泰航空", name: "三舱布局", cabinDescription: "依据国泰 A350-900 公开客舱布局重建，机身配色采用图鉴示意。", seats: [
                    AircraftCabinZone(label: "商务舱", numberOfRows: 10, seatGroups: [1, 2, 1], startM: 8, endM: 21.9, partialLastRow: [1, 0, 1]),
                    AircraftCabinZone(label: "特选经济舱", numberOfRows: 4, seatGroups: [2, 4, 2], startM: 24, endM: 29.5, partialLastRow: [2, 0, 2]),
                    AircraftCabinZone(label: "经济舱", numberOfRows: 24, seatGroups: [3, 3, 3], startM: 31, endM: 55.9, partialLastRow: [2, 3, 2])
                ], isIllustrative: true)
            ],
            sources: [manufacturerSource, planningSource, engineSource, singaporeSource,
                      AtlasSource(title: "新加坡航空 · A350-900 三舱座位图", url: "https://www.singaporeair.com/saar5/pdf/OurFleet/A350-900-3classes-LongHaul.pdf"),
                      AtlasSource(title: "国泰航空 · A350-900 机队与座位图", url: "https://www.cathaypacific.com/cx/en_SA/flying-with-us/aircraft-and-fleet/airbus-a350/900.html")]
        ),
        AircraftProfile(
            id: "a350-900ulr", modelName: "A350-900ULR", manufacturer: .airbus, series: "A350 系列 · 超远程型",
            description: "A350-900 的超远程版本。新加坡航空将该版本用于连接新加坡与纽约地区的定期不经停客运航班。",
            lengthM: 66.8, wingspanM: 64.75, rangeDescription: "空客机场规划资料列出超远程型设计航程可达约 18,000 公里。",
            configurations: [
                AircraftConfiguration(id: "sia-ulr", airline: "新加坡航空", name: "超远程客舱", cabinDescription: "参考公开两舱座位图。模型以舱段展示空间关系，具体座号与设备以航司座位图为准。", seats: [
                    AircraftCabinZone(label: "商务舱", numberOfRows: 17, seatGroups: [1, 2, 1], startM: 8, endM: 32.2, partialLastRow: [1, 2, 0]),
                    AircraftCabinZone(label: "优选经济舱", numberOfRows: 12, seatGroups: [2, 4, 2], startM: 34.5, endM: 54.7, partialLastRow: [1, 4, 1])
                ], isIllustrative: true)
            ],
            sources: [manufacturerSource, planningSource, engineSource, singaporeSource,
                      AtlasSource(title: "新加坡航空 · A350-900ULR 座位图", url: "https://www.singaporeair.com/saar5/pdf/OurFleet/A350-900-ULR.pdf")]
        )
    ] + AdditionalAircraftCatalog.profiles

    private static let manufacturerSource = AtlasSource(title: "空中客车 · A350 客机系列", url: "https://www.airbus.com/en/products-services/commercial-aircraft/passenger-aircraft/a350-family")
    private static let planningSource = AtlasSource(title: "空中客车 · A350 机场规划资料", url: "https://www.aircraft.airbus.com/sites/g/files/jlcbta126/files/2023-02/Airbus-Commercial-Aircraft-AC-A350-900-1000.pdf")
    private static let engineSource = AtlasSource(title: "罗尔斯-罗伊斯 · Trent XWB 技术资料", url: "https://www.rolls-royce.com/~/media/Files/R/Rolls-Royce/documents/civil-aerospace-downloads/High-Res-posters/High-Res-poster_Trent-XWB.pdf")
    private static let singaporeSource = AtlasSource(title: "新加坡航空 · A350-900 机型、班表与客舱", url: "https://www.singaporeair.com/en_UK/us/flying-withus/our-story/our-fleet/airbus-a350-900/")
}
