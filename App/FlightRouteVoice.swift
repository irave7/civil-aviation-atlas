import Foundation

struct FlightRouteVoice {
    let departureVariant: Int
    let arrivalVariant: Int

    init() {
        departureVariant = Int.random(in: 0...1)
        arrivalVariant = Int.random(in: 0...1)
    }

    private init(departureVariant: Int, arrivalVariant: Int) {
        self.departureVariant = departureVariant
        self.arrivalVariant = arrivalVariant
    }

    func nextFlight() -> Self {
        Self(departureVariant: 1 - departureVariant, arrivalVariant: 1 - arrivalVariant)
    }

    func recording(for cue: ExplorationNarrationCue, leg: ExplorationLeg) -> URL? {
        switch cue {
        case .briefing: recording(airport: leg.start, phase: "departure", variant: departureVariant)
        case .arrived: recording(airport: leg.end, phase: "arrival", variant: arrivalVariant)
        default: nil
        }
    }

    func spokenText(for cue: ExplorationNarrationCue, leg: ExplorationLeg) -> String? {
        switch cue {
        case .briefing:
            return departureVariant == 0
                ? "今天从\(leg.start.displayName)出发，前往\(leg.end.displayName)。我们先核对飞行设置。"
                : "欢迎登机。我们将从\(leg.start.displayName)起飞，目的地是\(leg.end.displayName)。准备好就可以开始。"
        case .arrived:
            return arrivalVariant == 0
                ? "欢迎抵达\(leg.end.displayName)。从\(leg.start.displayName)出发的这一程已经完成。"
                : "我们已经到达\(leg.end.displayName)。停稳后，可以打开飞行记录看看这一路的表现。"
        default: return nil
        }
    }

    private func recording(airport: Airport, phase: String, variant: Int) -> URL? {
        let nearby = ["JP", "KR", "HK", "MO", "TW", "SG", "MY", "TH", "VN", "ID", "PH", "IN"]
        let region = airport.countryCode ?? ""
        let fallback = region == "CN" ? "CN" : nearby.contains(region) ? "ASIA" : "WORLD"
        return [airport.displayCode, fallback].lazy.compactMap { key in
            let name = "route-\(key)-\(phase)-\(variant)"
            return Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "RouteVoices")
                ?? Bundle.main.url(forResource: name, withExtension: "m4a")
        }.first
    }
}
