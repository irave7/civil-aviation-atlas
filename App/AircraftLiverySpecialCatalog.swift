enum AircraftLiverySpecialCatalog {
    static let entries: [AircraftLivery] = ana + eva + lufthansa + qantas + chinaEastern + southwest

    private static let ana = [
        AircraftLivery(
            id: "ana-star-wars-bb8", name: "星球大战 BB-8 号", operatorName: "全日空",
            category: .special, aircraftIDs: ["b777-300er"],
            palette: .init(body: 0xF2F3EF, primary: 0xE88124, accent: 0x55595C, pattern: .wideBelly),
            source: .init(title: "全日空 · 星球大战涂装发布",
                          url: "https://www.ana.co.jp/pr/15_0709/15-050.html",
                          detail: "波音 777-300ER。白色机身配橙色与灰色机械图案，绘有 BB-8。末班于 2022 年 3 月 31 日执行。"),
            registration: "JA789A", period: "2016 年至 2022 年"
        ),
        AircraftLivery(
            id: "ana-star-wars-r2d2", name: "星球大战 R2-D2 号", operatorName: "全日空",
            category: .special, aircraftIDs: ["b787-9"],
            palette: .init(body: 0xF1F4F7, primary: 0x19578A, accent: 0xA9BBC6, pattern: .wideBelly),
            source: .init(title: "全日空 · R2-D2 号亮相",
                          url: "https://www.ana.co.jp/eng/aboutana/press/2015/150914.html",
                          detail: "波音 787-9。银白底色配深蓝和银灰机械面板图案，机头取材自 R2-D2。"),
            registration: "JA873A", period: "2015 年发布"
        ),
        AircraftLivery(
            id: "ana-pikachu-jet-nh", name: "皮卡丘号", operatorName: "全日空",
            category: .special, aircraftIDs: ["b787-9"],
            palette: .init(body: 0xB9E3F1, primary: 0x369BAC, accent: 0xF4CA49, pattern: .ribbon),
            source: .init(title: "全日空 · 宝可梦彩绘机",
                          url: "https://www.ana.co.jp/en/ph/the-ana-experience/pikachujet/",
                          detail: "波音 787-9。以天蓝为底，绿色烈空坐横跨机身，皮卡丘与其他飞行宝可梦相伴。"),
            registration: "JA894A", period: "2023 年启用"
        ),
        AircraftLivery(
            id: "ana-eevee-jet-nh", name: "伊布号", operatorName: "全日空",
            category: .special, aircraftIDs: ["b777-300er"],
            palette: .init(body: 0xF8E2BD, primary: 0x5C4F92, accent: 0xE68D6E, pattern: .ribbon),
            source: .init(title: "全日空 · 宝可梦彩绘机",
                          url: "https://www.ana.co.jp/en/ph/the-ana-experience/pikachujet/",
                          detail: "波音 777-300ER。淡金和暖粉延展至机身，保留深蓝尾翼，图案以伊布及其进化形态为主体。"),
            registration: "JA784A", period: "2023 年启用"
        ),
        flyingHonu(id: "ana-honu-lani", name: "飞天海龟 · 晴空蓝 Lani", registration: "JA381A",
                   primary: 0x2B7DB6, accent: 0x94DCF0, period: "2019 年启用", inspiration: "夏威夷晴空"),
        flyingHonu(id: "ana-honu-kai", name: "飞天海龟 · 碧海绿 Kai", registration: "JA382A",
                   primary: 0x008B76, accent: 0x98D5BE, period: "2019 年启用", inspiration: "夏威夷清澈海水"),
        flyingHonu(id: "ana-honu-la", name: "飞天海龟 · 落日橙 Lā", registration: "JA383A",
                   primary: 0xDB6B46, accent: 0xFAC777, period: "2023 年投入航线", inspiration: "夏威夷落日")
    ]

    private static let eva = [
        evaJet(id: "eva-lolly-jet", name: "Hello Kitty 糖果机", aircraft: "b777-300er", registration: "B-16740",
               body: 0xFCF5F7, primary: 0xE85B89, accent: 0x8CD6CB, pattern: .ribbon,
               detail: "波音 777-300ER。糖果色机身图案围绕三丽鸥角色展开。"),
        evaJet(id: "eva-besties-jet", name: "Hello Kitty 闺蜜机", aircraft: "b777-300er", registration: "B-16722",
               body: 0xF5E8F2, primary: 0xD95E8D, accent: 0xB2A5DE, pattern: .wideBelly,
               detail: "波音 777-300ER。融入城市漫游与下午茶主题，机身以柔和多色图案呈现。"),
        evaJet(id: "eva-pinky-jet", name: "Hello Kitty 粉萌机", aircraft: "a321ceo", registration: "B-16217",
               body: 0xF4A9C5, primary: 0xE75E98, accent: 0xFFF4F7, pattern: .fullBody,
               detail: "空中客车 A321。机身以粉色为主，带有 Hello Kitty 与心形图案。"),
        evaJet(id: "eva-joyful-dream", name: "Hello Kitty 梦想机", aircraft: "a330-300", registration: "B-16332",
               body: 0xF5F6F4, primary: 0x299DAD, accent: 0xE88EBB, pattern: .ribbon,
               detail: "空中客车 A330-300。Hello Kitty、双子星和布丁狗等三丽鸥角色沿机身排开。"),
        evaJet(id: "eva-celebration-flight", name: "Hello Kitty 派对机", aircraft: "a330-300", registration: "B-16333",
               body: 0xFAF7F2, primary: 0xE39A36, accent: 0x71BB9E, pattern: .ribbon,
               detail: "空中客车 A330-300。鲜明的彩色图案搭配三丽鸥角色，围绕派对主题。")
    ]

    private static let lufthansa = [
        lufthansaCentenary(id: "lh-centenary-747", aircraft: "b747-8i", registration: "D-ABYN",
                           url: "https://newsroom.lufthansagroup.com/en/queen-of-the-skies-now-also-features-xxl-crane-for-100th-founding-anniversary/",
                           detail: "波音 747-8 洲际客机。汉莎百年纪念的深蓝机身与跨向两翼的白鹤，2026 年 3 月投入航线。"),
        lufthansaCentenary(id: "lh-centenary-787", aircraft: "b787-9", registration: "D-ABPU",
                           url: "https://newsroom.lufthansagroup.com/en/an-anniversary-fleet-for-lufthansa/",
                           detail: "波音 787-9。名为“柏林”的百年机队首架，深蓝机身绘有白鹤和百年数字。"),
        lufthansaCentenary(id: "lh-centenary-a380", aircraft: "a380-800", registration: "D-AIMH",
                           url: "https://newsroom.lufthansagroup.com/en/lufthansa-a380-now-with-xxl-crane/",
                           detail: "空中客车 A380-800。深蓝机身上的大型白鹤长约 47 米。"),
        lufthansaCentenary(id: "lh-centenary-a350", aircraft: "a350-900", registration: "D-AIXL",
                           url: "https://newsroom.lufthansagroup.com/en/lufthansa-anniversary-fleet-grows-now-also-includes-a320-and-a350-with-xxl-crane/",
                           detail: "空中客车 A350-900。深蓝机身绘白鹤，机身两侧使用不同周年文字。"),
        AircraftLivery(
            id: "lh-retro-747", name: "747 复古涂装", operatorName: "汉莎航空",
            category: .special, aircraftIDs: ["b747-8i"],
            palette: .init(body: 0xF1F0E9, primary: 0x263A66, accent: 0xE9B842, pattern: .lowStripe),
            source: .init(title: "Herpa · 汉莎 747-8 复古涂装档案",
                          url: "https://archiv.herpa.de/en/product-datasheet/474b27866a3d0f8c3ce8315a77a4db42/create",
                          detail: "波音 747-8 洲际客机。白色机背、蓝色窗线、银灰机腹与黄底鹤标。"),
            registration: "D-ABYT", period: "2015 年发布"
        ),
        AircraftLivery(
            id: "lh-retro-parabola", name: "百年复古 · 抛物线涂装", operatorName: "汉莎航空",
            category: .special, aircraftIDs: ["a321ceo"],
            palette: .init(body: 0xF5F3EB, primary: 0x243A61, accent: 0xA9ABB1, pattern: .lowStripe),
            source: .init(title: "汉莎航空 · 历史抛物线涂装",
                          url: "https://newsroom.lufthansagroup.com/en/lufthansa-flies-in-historic-parabola-design/",
                          detail: "空中客车 A321-200。以历史上的洛克希德 Super Star 为参考，白色机背搭配深蓝弧线和银灰机腹。"),
            registration: "D-AISZ", period: "2026 年发布"
        )
    ]

    private static let qantas = [
        AircraftLivery(
            id: "qantas-yam-dreaming", name: "飞行艺术 · Yam Dreaming", operatorName: "澳洲航空",
            category: .special, aircraftIDs: ["b787-9"],
            palette: .init(body: 0xF0E5D9, primary: 0x98472F, accent: 0xFCF3E3, pattern: .tailSweep),
            source: .init(title: "澳洲航空 · Yam Dreaming 彩绘机",
                          url: "https://news.qantas.com/media-releases/2018/qantas-unveils-special-indigenous-aircraft-livery",
                          detail: "波音 787-9。以原住民艺术家 Emily Kame Kngwarreye 的作品为灵感，用土红与浅色点纹呈现薯蓣主题。"),
            registration: "VH-ZND", period: "2018 年发布"
        ),
        AircraftLivery(
            id: "qantas-mendoowoorrji", name: "飞行艺术 · Mendoowoorrji", operatorName: "澳洲航空",
            category: .special, aircraftIDs: ["b737-800"],
            palette: .init(body: 0xE4D6BE, primary: 0x524945, accent: 0xC65A33, pattern: .ribbon),
            source: .init(title: "澳洲航空 · 飞行艺术系列",
                          url: "https://www.qantas.com/en-it/onboard/fleet/flying-art",
                          detail: "波音 737-800。取材自 Paddy Bedford 的绘画，以炭灰与赭色表现澳大利亚西部金伯利地区的景观。"),
            registration: "VH-XZJ", period: "2013 年交付"
        ),
        AircraftLivery(
            id: "qantaslink-two-sisters", name: "飞行艺术 · 两姐妹创世故事", operatorName: "澳航支线",
            category: .special, aircraftIDs: ["a220-300"],
            palette: .init(body: 0xF4F5F2, primary: 0x184759, accent: 0x70C6A0, pattern: .tailSweep),
            source: .init(title: "澳洲航空 · 首架 A220 涂装亮相",
                          url: "https://news.qantas.com/media-releases/2023/first-qantaslink-a220-rolls-out-of-paintshop-as-fleet-renewal-ramps-up",
                          detail: "空中客车 A220-300。白色前机身与蓝、绿、黄色点纹的后机身，取材自 Maringka Baker 的作品。"),
            registration: "VH-X4A", period: "2023 年发布"
        )
    ]

    private static let chinaEastern = [
        AircraftLivery(
            id: "mu-shanghai-museum", name: "上海博物馆 · 上博号", operatorName: "中国东方航空",
            category: .special, aircraftIDs: ["b777-300er"],
            palette: .init(body: 0xC1D9B5, primary: 0x518B70, accent: 0xAB8D60, pattern: .fullBody),
            source: .init(title: "中国东方航空 · 上博号文博主题航班",
                          url: "https://global.ceair.com/global/static/Announcement/AnnouncementMessage/chinaeasternnewstest/202611/t20261117_30709.html",
                          detail: "波音 777-300ER。江南春绿为底，机身图案取材自上海博物馆藏青铜器的兽面、波曲和几何纹饰。"),
            registration: "B-7349", period: "2025 年首航"
        ),
        AircraftLivery(
            id: "mu-national-museum", name: "中国国家博物馆 · 国博号", operatorName: "中国东方航空",
            category: .special, aircraftIDs: ["b777-300er"],
            palette: .init(body: 0xF6F2EE, primary: 0x615BB0, accent: 0xDC8566, pattern: .ribbon),
            source: .init(title: "中国国家博物馆 · 国博号首航",
                          url: "https://www.chnmuseum.cn/zx/gbxw/202509/t20250929_272863.shtml",
                          detail: "波音 777-300ER。双侧机身采用儿童画风格描绘馆藏玉龙、玉凤、鹰形陶鼎等六件文物。"),
            registration: "B-7882", period: "2025 年首航"
        ),
        AircraftLivery(
            id: "mu-toy-story", name: "玩具总动员 · 欢乐假日号", operatorName: "中国东方航空",
            category: .special, aircraftIDs: ["a330-300"],
            palette: .init(body: 0xBFE6F8, primary: 0x227BB7, accent: 0xF7D058, pattern: .ribbon),
            source: .init(title: "中国东方航空 · 玩具总动员主题航班",
                          url: "https://www.ceairgroup.com/ceairgroup/xwzx_158/dhxw_159/202606/t20260615_30032.html",
                          detail: "空中客车 A330-300。蓝天与云朵图案衬托玩具总动员角色，东航和上海迪士尼于 2018 年合作推出。"),
            registration: "B-5976", period: "2018 年发布"
        ),
        AircraftLivery(
            id: "mu-zootopia", name: "迪士尼 · 疯狂动物城号", operatorName: "中国东方航空",
            category: .special, aircraftIDs: ["a320ceo"],
            palette: .init(body: 0xA4D8F4, primary: 0x2190C4, accent: 0xE9923A, pattern: .wideBelly),
            source: .init(title: "中国东方航空 · 疯狂动物城主题彩绘机",
                          url: "https://global.ceair.com/global/static/Announcement/AnnouncementMessage/chinaeasternnewstest/202511/t20251124_29311.html",
                          detail: "空中客车 A320。浅蓝底色配橙、白和蓝色城市图案，绘有朱迪、尼克等角色。2025 年进行主题焕新。"),
            registration: "B-8119", period: "2024 年发布"
        ),
        AircraftLivery(
            id: "mu-worldskills-2026", name: "世界技能大赛 · 技能成才号", operatorName: "中国东方航空",
            category: .special, aircraftIDs: ["a330-200"],
            palette: .init(body: 0xF5F7F4, primary: 0x257FB9, accent: 0xEDB13B, pattern: .ribbon),
            source: .init(title: "中国东方航空 · 技能成才号首航",
                          url: "https://globalgt.ceair.com/global/static/Announcement/AnnouncementMessage/chinaeasternnewstest/202605/t20260525_29963.html",
                          detail: "空中客车 A330-200。白色机身配蓝、绿、黄和橙色几何图案，为上海第 48 届世界技能大赛重新喷绘。"),
            period: "2026 年发布"
        )
    ]

    private static let southwest = [
        AircraftLivery(
            id: "southwest-imua-one", name: "夏威夷 · Imua One", operatorName: "美国西南航空",
            category: .special, aircraftIDs: ["b737-max8"],
            palette: .init(body: 0x43428A, primary: 0xC54A4E, accent: 0xFFCB4A, pattern: .fullBody),
            source: .init(title: "美国西南航空 · Imua One 发布",
                          url: "https://investors.southwest.com/news-events/press-releases/detail/159/southwest-airlines-unveils-imua-one-a-high-flying-tribute-with-gratitude-to-southwest-employees-and-the-people-in-hawaii-they-serve",
                          detail: "波音 737 MAX 8。深蓝过渡至暖红和日出黄，设计取材自夏威夷文化及太平洋传统导航。"),
            registration: "N8710M", period: "2023 年发布"
        )
    ]

    private static func flyingHonu(id: String, name: String, registration: String, primary: UInt32,
                                  accent: UInt32, period: String, inspiration: String) -> AircraftLivery {
        AircraftLivery(id: id, name: name, operatorName: "全日空", category: .special, aircraftIDs: ["a380-800"],
                       palette: .init(body: 0xF2F7F8, primary: primary, accent: accent, pattern: .wideBelly),
                       source: .init(title: "全日空 · A380 飞天海龟涂装",
                                     url: "https://www.ana.co.jp/group/en/pr/pdf/20181213.pdf",
                                     detail: "空中客车 A380-800。以\(inspiration)为配色灵感，海龟图案从机首延伸至机身两侧。"),
                       registration: registration, period: period)
    }

    private static func evaJet(id: String, name: String, aircraft: String, registration: String, body: UInt32,
                               primary: UInt32, accent: UInt32, pattern: AircraftLivery.Palette.Pattern,
                               detail: String) -> AircraftLivery {
        AircraftLivery(id: id, name: name, operatorName: "长荣航空", category: .special, aircraftIDs: [aircraft],
                       palette: .init(body: body, primary: primary, accent: accent, pattern: pattern),
                       source: .init(title: "长荣航空 · 彩绘机涂装介绍",
                                     url: "https://www.evaair.com/sc-cn/fly-prepare/our-fleets/eva-special-livery-jets/",
                                     detail: detail), registration: registration)
    }

    private static func lufthansaCentenary(id: String, aircraft: String, registration: String,
                                           url: String, detail: String) -> AircraftLivery {
        AircraftLivery(id: id, name: "百年纪念 · 白鹤涂装", operatorName: "汉莎航空",
                       category: .special, aircraftIDs: [aircraft],
                       palette: .init(body: 0x173B75, primary: 0xF4F7FA, accent: 0x709AC4, pattern: .fullBody),
                       source: .init(title: "汉莎航空 · 百年纪念机队", url: url, detail: detail),
                       registration: registration, period: "2026 年百年纪念")
    }
}
