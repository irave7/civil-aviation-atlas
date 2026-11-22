enum AircraftLiveryChinaCatalog {
    static let entries: [AircraftLivery] = [
        standard(
            "air-china", "中国国际航空",
            aircraft: ["c919", "a319", "a320ceo", "a320neo", "a321ceo", "a321neo", "a330-200", "a330-300", "a350-900",
                       "b737-700", "b737-800", "b737-max8", "b747-400", "b747-8i", "b777-300er", "b787-9"],
            palette: .init(body: 0xF7F7F3, primary: 0xB52632, accent: 0x273450, pattern: .lowStripe),
            source: AtlasSource(title: "中国国际航空 · 机型介绍与客舱布局", url: "https://m.airchina.com.cn/c/invoke/jxjsList%40pg",
                                detail: "空客另有天津总装 A320neo 向国航交付的公开记录。")
        ),
        standard(
            "china-eastern", "中国东方航空",
            aircraft: ["c919", "a319", "a320ceo", "a320neo", "a321ceo", "a321neo", "a330-200", "a330-300", "a350-900",
                       "b737-700", "b737-800", "b737-max8", "b777-300er", "b787-9"],
            palette: .init(body: 0xF9F9F7, primary: 0x223B74, accent: 0xC72041, pattern: .tailSweep),
            source: AtlasSource(title: "中国东方航空 · 2025 年度报告机队资料",
                                url: "https://www.ceair.com/global/static/AboutChinaEasternAirlines/intoEasternAirlines/InvestorRelations/periodicReports/ShanghaiStockExchangeReleased/ShanghaiStockExchangeReleased2025/202604/P020260408479381018446.pdf")
        ),
        standard(
            "china-southern", "中国南方航空",
            aircraft: ["c919", "a319", "a320ceo", "a320neo", "a321ceo", "a321neo", "a330-200", "a330-300", "a350-900",
                       "b737-700", "b737-800", "b737-max8", "b777-300er", "b787-8", "b787-9"],
            palette: .init(body: 0xF8FAFB, primary: 0x1265A0, accent: 0xDD3148, pattern: .lowStripe),
            source: AtlasSource(title: "中国南方航空 · 客舱布局与机型",
                                url: "https://www.csair.com/sg/zh/tourguide/flight_service/",
                                detail: "型号对照机型资料、南航运营公告及中国商飞 C919 交付资料。")
        ),
        standard(
            "xiamen-airlines", "厦门航空",
            aircraft: ["a321neo", "b737-700", "b737-800", "b737-max8", "b787-8", "b787-9"],
            palette: .init(body: 0xF6FAFC, primary: 0x1674B2, accent: 0x77B5D6, pattern: .ribbon),
            source: AtlasSource(title: "厦门航空 · 客机座位图",
                                url: "https://www.xiamenair.com/ja-jp/article-detail?articleLink=%2Fcms-i18n-ow%2Fcms-ja-jp%2Fcontents%2F5059.json")
        ),
        standard(
            "hainan-airlines", "海南航空",
            aircraft: ["a320neo", "a321neo", "a330-200", "a330-300", "a330-900", "b737-800", "b737-max8", "b787-8", "b787-9"],
            palette: .init(body: 0xFBF8F3, primary: 0xB91D37, accent: 0xE9BB42, pattern: .tailSweep),
            source: AtlasSource(title: "海南航空 · 官方机队信息和座位图",
                                url: "https://www.hnair.com/dachenghaihang/hhjd/jdxx/")
        ),
        standard(
            "juneyao-airlines", "吉祥航空",
            aircraft: ["a320ceo", "a320neo", "a321ceo", "a321neo", "b787-9"],
            palette: .init(body: 0xFAF6EE, primary: 0x922540, accent: 0xC7A76D, pattern: .tailSweep),
            source: AtlasSource(title: "吉祥航空 · 机型介绍", url: "https://www.juneyaoair.com/modelIntro/index")
        ),
        standard(
            "shenzhen-airlines", "深圳航空",
            aircraft: ["a319", "a320ceo", "a330-300", "b737-800"],
            palette: .init(body: 0xF9F7F2, primary: 0xB71930, accent: 0xCCA255, pattern: .wideBelly),
            source: AtlasSource(title: "深圳航空 · 机队机型介绍",
                                url: "https://globalpage.shenzhenair.com/zhair/cms/static/pages/wcm/static-midbookmarks/CompanyOverview/FleetModel/FleetModel_cn?language_id=103")
        ),
        standard(
            "shandong-airlines", "山东航空",
            aircraft: ["b737-700", "b737-800", "b737-max8"],
            palette: .init(body: 0xF6F8FA, primary: 0x1A4589, accent: 0xCC2636, pattern: .lowStripe),
            source: AtlasSource(title: "山东航空 · 机队机型", url: "https://www.sda.cn/trip/airType.html")
        ),
        standard(
            "spring-airlines", "春秋航空",
            aircraft: ["a320ceo", "a320neo", "a321neo"],
            palette: .init(body: 0xF8FAF4, primary: 0x278243, accent: 0xC5CE3C, pattern: .wideBelly),
            source: AtlasSource(title: "春秋航空 · 机队沿革与品牌涂装", url: "https://www.ch.com/Static/AboutUs?GAT=0")
        )
    ]

    private static func standard(
        _ id: String,
        _ airline: String,
        aircraft: Set<String>,
        palette: AircraftLivery.Palette,
        source: AtlasSource
    ) -> AircraftLivery {
        AircraftLivery(id: id, name: "\(airline)标准涂装", operatorName: airline, category: .domestic,
                       aircraftIDs: aircraft, palette: palette, source: source)
    }
}
