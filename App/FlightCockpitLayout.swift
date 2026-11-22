import Foundation

struct FlightCockpitLayout: Equatable {
    enum Column: String {
        case sideStick = "侧杆"
        case yoke = "驾驶盘"
        case regionalYoke = "双手操纵盘"
    }

    enum Screen: String, Identifiable {
        case attitude = "主飞行显示"
        case navigation = "导航显示"
        case engines = "发动机"
        case systems = "系统状态"
        case standby = "备用仪表"
        case flightData = "飞行数据"

        var id: Self { self }
    }

    let family: String
    let column: Column
    let screens: [Screen]
    let engines: Int
    let console: Console
    let reference: URL?

    enum Console {
        case airbus, airbusWide, boeingClassic, boeingDigital, regional, comac
    }

    init(profile: AircraftProfile) {
        let airbus = URL(string: "https://www.airbus.com/en/products-services/commercial-aircraft/cockpits")
        let boeing = URL(string: "https://www.boeing.com/commercial/airports/plan-manuals")
        let basic: [Screen] = [.attitude, .navigation, .engines, .systems]
        let wide: [Screen] = basic + [.standby, .flightData]
        switch profile.id {
        case "a220-300":
            family = "A220"
            column = .sideStick
            screens = [.attitude, .navigation, .systems, .engines, .standby]
            engines = 2
            console = .regional
            reference = airbus
        case "a319", "a320ceo", "a320neo", "a321ceo", "a321neo":
            family = "A320 系列"
            column = .sideStick
            screens = basic
            engines = 2
            console = .airbus
            reference = airbus
        case "a330-200", "a330-300", "a330-900":
            family = "A330 系列"
            column = .sideStick
            screens = [.attitude, .navigation, .standby, .engines, .systems]
            engines = 2
            console = .airbusWide
            reference = airbus
        case "a350-900", "a350-900ulr", "a350-1000", "a380-800":
            family = profile.id.hasPrefix("a380") ? "A380" : "A350 系列"
            column = .sideStick
            screens = wide
            engines = profile.id.hasPrefix("a380") ? 4 : 2
            console = .airbusWide
            reference = airbus
        case "b737-700", "b737-800", "b737-900er":
            family = "737 NG"
            column = .yoke
            screens = [.attitude, .navigation, .engines, .standby]
            engines = 2
            console = .boeingClassic
            reference = boeing
        case "b737-max8", "b737-max9":
            family = "737 MAX"
            column = .yoke
            screens = basic
            engines = 2
            console = .boeingDigital
            reference = URL(string: "https://www.boeing.com/commercial/737max/by-design")
        case "b747-400", "b747-8i":
            family = "747 系列"
            column = .yoke
            screens = [.attitude, .navigation, .engines, .standby, .systems]
            engines = 4
            console = profile.id == "b747-400" ? .boeingClassic : .boeingDigital
            reference = URL(string: "https://www.boeing.com/content/dam/boeing/v2/airports/acaps/747-8_Rev_E.pdf")
        case "b757-200", "b767-300er":
            family = "757 / 767"
            column = .yoke
            screens = [.attitude, .standby, .navigation, .engines]
            engines = 2
            console = .boeingClassic
            reference = boeing
        case "b777-200er", "b777-300er":
            family = "777 系列"
            column = .yoke
            screens = wide
            engines = 2
            console = .boeingDigital
            reference = URL(string: "https://www.boeing.com/Commercial/777/design-highlights")
        case "b787-8", "b787-9", "b787-10":
            family = "787 Dreamliner"
            column = .yoke
            screens = [.attitude, .navigation, .engines, .systems, .flightData]
            engines = 2
            console = .boeingDigital
            reference = URL(string: "https://www.boeing.com/commercial/787/by-design")
        case "c919":
            family = "C919"
            column = .sideStick
            screens = [.attitude, .navigation, .flightData, .engines, .systems]
            engines = 2
            console = .comac
            reference = URL(string: "https://www.geaerospace.com/news/press-releases/systems/ge-and-avic-providing-systems-chinas-first-large-commercial-aircraft-comacs")
        case "e195-e2":
            family = "E-Jets E2"
            column = .regionalYoke
            screens = [.attitude, .navigation, .engines, .flightData]
            engines = 2
            console = .regional
            reference = profile.sources.first.flatMap { URL(string: $0.url) }
        default:
            family = profile.series
            column = profile.manufacturer == .airbus || profile.manufacturer == .comac ? .sideStick : .yoke
            screens = basic
            engines = 2
            console = .regional
            reference = profile.sources.first.flatMap { URL(string: $0.url) }
        }
    }
}
