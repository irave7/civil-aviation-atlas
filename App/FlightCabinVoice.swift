import Foundation

enum FlightCabinVoice: String, Identifiable, Sendable {
    case automatic, off
    case airChina = "air-china"
    case chinaEastern = "china-eastern"
    case chinaSouthern = "china-southern"
    case xiamenAir = "xiamen-air"
    case japanAirlines = "japan-airlines"
    case singaporeAirlines = "singapore-airlines"
    case emirates, lufthansa

    static let domestic: [Self] = [.airChina, .chinaEastern, .chinaSouthern, .xiamenAir]
    static let international: [Self] = [.japanAirlines, .singaporeAirlines, .emirates, .lufthansa]

    enum Phase: String, Sendable {
        case briefing, departing, approach, arrived

        init?(cue: ExplorationNarrationCue) {
            switch cue {
            case .briefing: self = .briefing
            case .taxiOut: self = .departing
            case .approach: self = .approach
            case .arrived: self = .arrived
            default: return nil
            }
        }
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "跟随航线航司"
        case .off: "关闭航司广播"
        case .airChina: "中国国际航空"
        case .chinaEastern: "中国东方航空"
        case .chinaSouthern: "中国南方航空"
        case .xiamenAir: "厦门航空"
        case .japanAirlines: "日本航空"
        case .singaporeAirlines: "新加坡航空"
        case .emirates: "阿联酋航空"
        case .lufthansa: "汉莎航空"
        }
    }

    static func matching(operatorName: String) -> Self? {
        let normalized = operatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized.lowercased() {
        case "中国国航", "国航", "air china": return .airChina
        case "东方航空", "东航", "china eastern", "china eastern airlines": return .chinaEastern
        case "南方航空", "南航", "china southern", "china southern airlines": return .chinaSouthern
        case "厦航", "xiamenair", "xiamen airlines": return .xiamenAir
        case "日航", "japan airlines": return .japanAirlines
        case "新航", "singapore airlines": return .singaporeAirlines
        case "emirates": return .emirates
        case "德国汉莎航空", "lufthansa": return .lufthansa
        default: return (domestic + international).first { $0.title == normalized }
        }
    }

    func recording(for phase: Phase) -> URL? {
        guard self != .automatic && self != .off else { return nil }
        let filename = "carrier-\(rawValue)-\(phase.rawValue)"
        return Bundle.main.url(forResource: filename, withExtension: "m4a", subdirectory: "CarrierCabin")
            ?? Bundle.main.url(forResource: filename, withExtension: "m4a")
    }
}
