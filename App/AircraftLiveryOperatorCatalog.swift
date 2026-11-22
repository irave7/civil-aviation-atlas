import Foundation

enum AircraftLiveryOperatorCatalog {
    static let entries = AircraftLiveryChinaCatalog.entries + [
        standard("cathay-pacific", "国泰航空", category: .domestic,
                 aircraft: ["a321neo", "a330-300", "a350-900", "a350-1000", "b777-300er"],
                 palette: .init(body: 0xF1F3F2, primary: 0x00615F, accent: 0x9BB6AF, pattern: .tailSweep),
                 source: AtlasSource(title: "国泰航空 · 2025 年报与机队", url: "https://www.cathaypacific.com/content/dam/cx/about-us/investor-relations/interim-annual-reports/en/2025_cx_annual_report_en.pdf")),
        standard("singapore-airlines", "新加坡航空",
                 aircraft: ["a350-900", "a350-900ulr", "a380-800", "b777-300er", "b787-10", "b737-max8"],
                 palette: .init(body: 0xFAFAF8, primary: 0x12244F, accent: 0xE7A935, pattern: .lowStripe),
                 source: AtlasSource(title: "新加坡航空 · 客机与各机型座位图", url: "https://agent360.singaporeair.com/en_UK/sg/product-services")),
        standard("lufthansa", "汉莎航空",
                 aircraft: ["a319", "a320ceo", "a320neo", "a321ceo", "a321neo", "a330-300", "a350-900", "a350-1000", "a380-800", "b747-400", "b747-8i", "b787-9"],
                 palette: .init(body: 0xF6F7F5, primary: 0x142B4A, accent: 0xDDE5E8, pattern: .tailSweep),
                 source: AtlasSource(title: "汉莎航空 · 客机机队", url: "https://www.lufthansa.com/de/en/seat-maps")),
        standard("united-airlines", "美国联合航空",
                 aircraft: ["a319", "a320ceo", "a321neo", "b737-700", "b737-800", "b737-900er", "b737-max8", "b737-max9", "b757-200", "b767-300er", "b777-200er", "b777-300er", "b787-8", "b787-9", "b787-10"],
                 palette: .init(body: 0xF6F6F8, primary: 0x143E8C, accent: 0x369ADB, pattern: .ribbon),
                 source: AtlasSource(title: "美国联合航空 · 2025 年报主线机队", url: "https://ir.united.com/static-files/6037ca53-cfcd-44db-8f9c-6df6b3f91ab7")),
        standard("delta-air-lines", "达美航空",
                 aircraft: ["a220-300", "a319", "a320ceo", "a321ceo", "a321neo", "a330-200", "a330-300", "a330-900", "a350-900", "b737-800", "b737-900er", "b757-200", "b767-300er"],
                 palette: .init(body: 0xF8F9F8, primary: 0x142448, accent: 0xCF1639, pattern: .wideBelly),
                 source: AtlasSource(title: "达美航空 · 客机机队", url: "https://www.delta.com/intl/en/aircraft/overview")),
        standard("all-nippon-airways", "全日空",
                 aircraft: ["a320neo", "a321ceo", "a321neo", "b737-800", "b767-300er", "b777-300er", "b787-8", "b787-9", "b787-10"],
                 palette: .init(body: 0xF6F8F8, primary: 0x163B96, accent: 0x21ABDA, pattern: .lowStripe),
                 source: AtlasSource(title: "全日空 · 机队及运营机型", url: "https://www.ana.co.jp/group/investors/data/kessan/pdf/2025_07_1.pdf")),
        standard("klm", "荷兰皇家航空",
                 aircraft: ["a321neo", "a330-200", "a330-300", "b737-700", "b737-800", "b777-200er", "b777-300er", "b787-9", "b787-10", "e195-e2"],
                 palette: .init(body: 0x4CB4E1, primary: 0x45A7E5, accent: 0xF9FBFC, pattern: .wideBelly),
                 source: AtlasSource(title: "荷兰皇家航空 · 官方机队", url: "https://www.klm.com/information/travel-class-extra-options/aircraft-types")),
        standard("emirates", "阿联酋航空",
                 aircraft: ["a350-900", "a380-800", "b777-300er"],
                 palette: .init(body: 0xF9F8F6, primary: 0xCC2035, accent: 0x147749, pattern: .tailSweep),
                 source: AtlasSource(title: "阿联酋航空 · 官方机队和机身外观", url: "https://www.emirates.com/us/english/experience/our-fleet/")),
        standard("southwest-heart", "美国西南航空", name: "爱心标准涂装",
                 aircraft: ["b737-700", "b737-800", "b737-max8"],
                 palette: .init(body: 0x1E459D, primary: 0xDA2331, accent: 0xF7B61D, pattern: .fullBody),
                 source: AtlasSource(title: "美国西南航空档案 · Heart 涂装", url: "https://history.southwest.com/our-stories/our-heart-livery/")),
        standard("qantas", "澳洲航空",
                 aircraft: ["a330-200", "a330-300", "a380-800", "b737-800", "b787-9"],
                 palette: .init(body: 0xF9F7F4, primary: 0xCF192D, accent: 0xFAF6F3, pattern: .tailSweep),
                 source: AtlasSource(title: "澳洲航空 · 机队与更新计划", url: "https://www.qantas.com/en-us/onboard/fleet/new-fleet"))
    ]

    private static func standard(
        _ id: String,
        _ airline: String,
        category: AircraftLivery.Category = .international,
        name: String = "标准涂装",
        aircraft: Set<String>,
        palette: AircraftLivery.Palette,
        source: AtlasSource
    ) -> AircraftLivery {
        AircraftLivery(id: id, name: "\(airline)\(name)", operatorName: airline, category: category,
                       aircraftIDs: aircraft, palette: palette, source: source)
    }
}
