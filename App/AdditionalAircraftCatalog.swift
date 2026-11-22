enum AdditionalAircraftCatalog {
    static let profiles = featured + airbusExpansion + boeingExpansion

    private static let featured: [AircraftProfile] = [
        AircraftProfile(
            id: "a320neo", modelName: "A320neo", manufacturer: .airbus, series: "A320neo 系列 · 单通道",
            description: "A320neo 保留 A320 的机身尺寸，换装 LEAP-1A 或 PW1100G-JM 发动机并采用鲨鳍式翼梢。客舱的典型 3–3 排布适合观察单通道客机的横向空间关系。",
            lengthM: 37.57, wingspanM: 35.80, rangeDescription: "空客技术资料标称约 6,400 公里（3,450 海里）。",
            configurations: [
                cabin("lh-180", "德国汉莎航空", "180 座配置", "依据汉莎公开的 180 座图，重建 3–3 座椅。前舱等级分隔随执飞任务调整。", [
                    zone("单通道客舱", 30, [3, 3], 5.8, 31.7)
                ])
            ],
            sources: [airbusNarrowbody, AtlasSource(title: "汉莎航空 · A320neo 机队及座位图", url: "https://www.lufthansa.com/al/en/32n")]
        ),
        AircraftProfile(
            id: "a321neo", modelName: "A321neo", manufacturer: .airbus, series: "A320neo 系列 · 加长型",
            description: "A321neo 与 A320neo 的翼展相同，机身加长约 6.9 米，增加了可用于座椅及客舱设施的长度。航司可以选择不同的舱门和客舱组合。",
            lengthM: 44.51, wingspanM: 35.80, rangeDescription: "普通 A321neo 约 6,500 公里以上。LR 延程型可达约 7,400 公里。",
            configurations: [
                cabin("dl-194", "达美航空", "194 座三分区", "采用达美公开的 20 座头等舱、60 座 Comfort+ 和 114 座主客舱方案。达美另有不同分区。", [
                    zone("国内头等舱", 5, [2, 2], 6.0, 10.8),
                    zone("舒适经济区", 10, [3, 3], 12.1, 21.1),
                    zone("主客舱", 19, [3, 3], 22.6, 38.4)
                ])
            ],
            sources: [airbusNarrowbody, AtlasSource(title: "空中客车 · A320 系列和变型航程", url: "https://www.airbus.com/en/products-services/commercial-aircraft/passenger-aircraft/a320-family"), AtlasSource(title: "达美航空 · A321neo 194 座公开座位图", url: "https://www.delta.com/global/en/aircraft/airbus/a321-neo")]
        ),
        AircraftProfile(
            id: "a330-900", modelName: "A330-900", manufacturer: .airbus, series: "A330neo 系列 · 双通道",
            description: "A330-900 沿用 A330-300 的机身长度，配备两台 Trent 7000 与重新设计的翼梢。代表性经济舱采用 2–4–2，和 A350、787 常见的 3–3–3 排布形成空间对照。",
            lengthM: 63.66, wingspanM: 64.00, rangeDescription: "空客 2026 年资料列出 242 吨与 251 吨版本，航程分别约 12,050 与 13,250 公里。",
            configurations: [
                cabin("dl-281", "达美航空", "281 座四分区", "依据达美公开座位图，分为 Delta One、Premium Select、Comfort+ 和主客舱。", [
                    zone("Delta One 商务舱", 8, [1, 2, 1], 7.3, 19.3, last: [1, 0, 0]),
                    zone("尊尚经济舱", 4, [2, 3, 2], 20.5, 24.5),
                    zone("舒适经济区", 7, [2, 4, 2], 25.6, 32.1),
                    zone("主客舱", 21, [2, 4, 2], 33.1, 54.4)
                ])
            ],
            sources: [AtlasSource(title: "空中客车 · A330 系列技术资料（2026 年 4 月）", url: "https://mediaassets.airbus.com/pm_38_896_896589-6vwqkjd9gw.pdf?fileName=airbus-a330-family-facts-and-figures-april-2026.pdf"), AtlasSource(title: "达美航空 · A330-900 公开座位图", url: "https://www.delta.com/us/en/aircraft/airbus/a330-900")]
        ),
        AircraftProfile(
            id: "a380-800", modelName: "A380-800", manufacturer: .airbus, series: "A380 系列 · 全长双层",
            description: "A380-800 采用四台翼下发动机和贯穿机身大部分长度的上下双层客舱。可从分层座位观察较宽的主层与较窄的上层，及不同舱等级如何在两层分配。",
            lengthM: 72.73, wingspanM: 79.75, rangeDescription: "空客标称约 14,800 公里（约 8,000 海里）。",
            configurations: [
                cabin("sq-471", "新加坡航空", "471 座双层四舱", "按新航公开座位图表示两层舱位。上层为 6 间套房和 78 个商务舱座位，主层为 44 个优选经济舱座位和 343 个经济舱座位。", [
                    zone("主层 · 优选经济舱", 6, [2, 4, 2], 8.6, 16.7, last: [2, 0, 2]),
                    zone("主层 · 经济舱", 35, [3, 4, 3], 18.1, 63.0, last: [1, 1, 1]),
                    zone("上层 · 套房", 3, [1, 1], 10.0, 18.0, deck: 1),
                    zone("上层 · 商务舱", 20, [1, 2, 1], 19.9, 61.6, last: [1, 0, 1], deck: 1)
                ])
            ],
            sources: [AtlasSource(title: "空中客车 · A380 架构及航程", url: "https://www.airbus.com/en/products-services/commercial-aircraft/passenger-aircraft/a380"), AtlasSource(title: "空中客车 · A380 机场规划尺寸", url: "https://www.aircraft.airbus.com/sites/default/files/2025-12/AC_A380_20251201.pdf"), AtlasSource(title: "新加坡航空 · A380 471 座双层座位图", url: "https://www.singaporeair.com/content/dam/sia/web-assets/pdfs/flying-withus/our-story/A380-800-Version-2%201.pdf")]
        ),
        AircraftProfile(
            id: "b737-800", modelName: "737-800", manufacturer: .boeing, series: "新一代 737 · 单通道",
            description: "737-800 属于 737 Next Generation，采用 CFM56-7B 发动机和低位机翼。带翼梢小翼的版本翼展约 35.8 米，基础版本约 34.3 米。",
            lengthM: 39.47, wingspanM: 35.79, rangeDescription: "波音 737 NG 技术页标注最多约 5,190 公里（2,800 海里）。",
            configurations: [
                cabin("dl-160", "达美航空", "160 座三分区", "依据达美公布的 16 座头等舱、54 座 Comfort+、90 座主客舱方案；同型号可能有其他分区。", [
                    zone("国内头等舱", 4, [2, 2], 5.8, 10.1),
                    zone("舒适经济区", 9, [3, 3], 11.2, 19.4),
                    zone("主客舱", 15, [3, 3], 20.5, 34.5)
                ])
            ],
            sources: [AtlasSource(title: "波音 · 737 Next Generation 技术数据", url: "https://www.boeing.com/commercial/737ng"), AtlasSource(title: "波音 · 737-800 有／无翼梢小翼的机场规划尺寸", url: "https://www.boeing.com/content/dam/boeing/v2/airports/faq/arcandapproachspeeds.pdf"), AtlasSource(title: "达美航空 · 737-800 公开座位图", url: "https://www.delta.com/apac/en/aircraft/boeing/737-800")]
        ),
        AircraftProfile(
            id: "b737-max8", modelName: "737 MAX 8", manufacturer: .boeing, series: "737 MAX 系列 · 单通道",
            description: "737 MAX 8 也称 737-8。它与 737-800 的机身长度接近，外部可观察较大的 LEAP-1B 短舱、短舱后缘锯齿与上下分叉式翼梢。",
            lengthM: 39.5, wingspanM: 35.9, rangeDescription: "波音标称最多约 6,480 公里（3,500 海里）。",
            configurations: [
                cabin("reference", "图鉴示例", "166 座代表性两舱", "采用 2–2 前舱和 3–3 经济舱的代表性排布，未指定航空公司。", [
                    zone("前部高级客舱", 4, [2, 2], 5.8, 10.1),
                    zone("经济舱", 25, [3, 3], 11.5, 34.4)
                ])
            ],
            sources: [AtlasSource(title: "波音 · 737 MAX 型号与技术数据", url: "https://www.boeing.com/commercial/737max"), AtlasSource(title: "波音 · 737 MAX 翼梢设计", url: "https://www.boeing.com/commercial/737max/737-max-winglets")]
        ),
        AircraftProfile(
            id: "b777-300er", modelName: "777-300ER", manufacturer: .boeing, series: "777 系列 · 加长延程型",
            description: "777-300ER 是加长的远程双发宽体客机，采用两台 GE90-115B 发动机、后掠延伸翼尖和六轮主起落架转向架。机身长度和高涵道比短舱比例是外部辨识重点。",
            lengthM: 73.9, wingspanM: 64.8, rangeDescription: "波音列出的标称航程约 13,650 公里（7,370 海里）。",
            configurations: [
                cabin("sq-264", "新加坡航空", "264 座四舱", "依据新航公开的 4 座头等、48 座商务、28 座优选经济及 184 座经济布局。经济舱例采用 3–3–3。", [
                    zone("头等舱", 1, [1, 2, 1], 8.7, 11.2),
                    zone("商务舱", 12, [1, 2, 1], 12.7, 31.3),
                    zone("优选经济舱", 4, [2, 4, 2], 32.5, 37.6, last: [2, 0, 2]),
                    zone("经济舱", 21, [3, 3, 3], 39.1, 61.7, last: [2, 0, 2])
                ])
            ],
            sources: [AtlasSource(title: "波音 · 777-300ER 技术数据", url: "https://www.boeing.com/commercial/777/design-highlights"), AtlasSource(title: "新加坡航空 · 777-300ER 264 座座位图", url: "https://www.singaporeair.com/saar5/pdf/OurFleet/777-300ER.pdf")]
        ),
        AircraftProfile(
            id: "b787-9", modelName: "787-9", manufacturer: .boeing, series: "787 梦想飞机 · 双通道",
            description: "787-9 是 787-8 的加长衍生型，使用大量碳纤维复合材料，典型外观包括柔性后掠翼和带锯齿后缘的发动机短舱。澳航的三舱布局是长途客舱示例。",
            lengthM: 62.8, wingspanM: 60.1, rangeDescription: "波音现行技术页列出最长约 15,370 公里（8,300 海里），取决于重量与任务条件。",
            configurations: [
                cabin("qf-236", "澳洲航空", "236 座三舱", "依据澳航公开座位图，对照 42 个商务舱、28 个高端经济舱和 166 个经济舱座位。", [
                    zone("商务舱", 11, [1, 2, 1], 7.6, 22.5, last: [1, 0, 1]),
                    zone("高端经济舱", 4, [2, 3, 2], 24.0, 28.2),
                    zone("经济舱", 19, [3, 3, 3], 29.8, 53.7, last: [2, 0, 2])
                ])
            ],
            sources: [AtlasSource(title: "波音 · 787 Dreamliner 技术数据", url: "https://www.boeing.com/commercial/787/"), AtlasSource(title: "澳洲航空 · 787-9 机队和 236 座座位图", url: "https://www.qantas.com/en-au/onboard/fleet/787")]
        ),
        AircraftProfile(
            id: "b747-8i", modelName: "747-8 Intercontinental", manufacturer: .boeing, series: "747 系列 · 局部双层客机",
            description: "747-8 Intercontinental 是 747-8 的客运版，采用四台 GEnx-2B，并延长了机头后方的上层客舱。主层贯穿机身，上层集中在前段，形成典型的机背轮廓。",
            lengthM: 76.3, wingspanM: 68.4, rangeDescription: "波音公布的设计航程约 14,310 公里（7,730 海里，最大起飞重量与满载旅客条件）。",
            configurations: [
                cabin("lh-364", "德国汉莎航空", "364 座双层四舱", "参考汉莎 8 头等、80 商务、32 高端经济、244 经济的舱位图，其中 32 个商务座位位于机首上层。", [
                    zone("主层 · 头等舱", 4, [1, 1], 8.2, 14.2),
                    zone("主层 · 商务舱", 8, [2, 2, 2], 15.6, 30.5),
                    zone("主层 · 高端经济舱", 4, [2, 4, 2], 31.8, 36.8),
                    zone("主层 · 经济舱", 25, [3, 4, 3], 38.4, 65.4, last: [2, 0, 2]),
                    zone("上层 · 商务舱", 8, [2, 2], 10.3, 23.2, deck: 1)
                ])
            ],
            sources: [AtlasSource(title: "波音 · 747-8 Intercontinental 机场规划与航程", url: "https://www.boeing.com/content/dam/boeing/boeingdotcom/company/about_bca/startup/pdf/historical/747-8I_-_passenger.pdf"), AtlasSource(title: "汉莎航空 · 747-8 的 364 座双层座位图", url: "https://www.lufthansa.com/fi/en/74h"), AtlasSource(title: "汉莎航空 · 747-8 上层商务舱座位数", url: "https://www.lufthansa.com/content/dam/lh/documents/discover-lufthansa/lufthansa-magazin/lufthansa-magazin-02-2020.pdf")]
        ),
        AircraftProfile(
            id: "c919", modelName: "C919", manufacturer: .comac, series: "C919 · 单通道干线客机",
            description: "C919 是中国商飞研制的双发单通道客机。商飞公布的座级为 158–192 座，公开机场规划手册区分标准型与延程型。",
            lengthM: 38.90, wingspanM: 35.80, rangeDescription: "中国商飞公布系列航程约 4,075–5,555 公里。",
            configurations: [
                cabin("reference", "图鉴示例", "164 座代表性两舱", "座位总数参考商飞公布的首架交付构型，8 座商务舱与 156 座经济舱。座位排布和涂装为图鉴示意。", [
                    zone("商务舱", 2, [2, 2], 6.1, 8.6),
                    zone("经济舱", 26, [3, 3], 9.9, 34.0)
                ])
            ],
            sources: [AtlasSource(title: "中国商飞 · C919 机场规划手册", url: "https://www.comac.cc/fujian/c919acap_cn.pdf"), AtlasSource(title: "中国商飞 · C919 载客量和航程", url: "https://www.comac.cc/xwzx/gsxw/202602/03/t20260203_7405054.shtml"), AtlasSource(title: "中国商飞 · 首架交付 C919 的两舱容量", url: "https://english.comac.cc/news/latest/202301/11/t20230111_7355061.shtml")]
        ),
        AircraftProfile(
            id: "e195-e2", modelName: "E195-E2", manufacturer: .embraer, series: "E2 系列 · 单通道",
            description: "E195-E2 是 E-Jets E2 系列中容量最大的型号，采用齿轮传动涡扇发动机和高展弦比机翼。典型客舱为每排 2–2，无中间座位。",
            lengthM: 41.60, wingspanM: 35.12, rangeDescription: "巴航工业列出的满载旅客航程约 5,556 公里（3,000 海里，按该厂公布的巡航及备降条件）。",
            configurations: [
                cabin("reference", "图鉴示例", "120 座三节距布局", "参考巴航工业 120 座厂商样例，三段腿部空间不同，分别为 12、24 与 84 座。", [
                    zone("前部大间距区", 3, [2, 2], 6.2, 8.8),
                    zone("中部加长间距区", 6, [2, 2], 9.8, 15.0),
                    zone("标准间距区", 21, [2, 2], 16.0, 35.2)
                ]),
                cabin("reference-132", "图鉴示例", "132 座单舱布局", "参考巴航工业 132 座单舱样例，采用 2–2 座椅。", [
                    zone("单通道客舱", 33, [2, 2], 6.1, 35.2)
                ])
            ],
            sources: [AtlasSource(title: "巴航工业 · E-Jets E2 机场规划手册", url: "https://www.embraer.com/media/vmsjxvk5/e-jets-e2_apm_e-jetse2.pdf"), AtlasSource(title: "巴航工业 · E195-E2 技术规格与厂商座位图", url: "https://www.embraer.com/media/5kybbwea/e195-e2-spec-1.pdf")]
        )
    ]

    private static let airbusExpansion: [AircraftProfile] = [
        AircraftProfile(
            id: "a220-300", modelName: "A220-300", manufacturer: .airbus, series: "A220 系列 · 单通道",
            description: "A220-300 的窄体客舱采用非对称的 2–3 经济舱排布，两台普惠 PW1500G 齿轮传动涡扇发动机位于翼下。",
            lengthM: 38.70, wingspanM: 35.10, rangeDescription: "空客列出的航程约 6,300 公里（3,400 海里）。",
            configurations: [
                deltaCabin(130, "三分区", [
                    zone("国内头等舱", 3, [2, 2], 6.0, 9.4),
                    zone("舒适经济区", 9, [2, 3], 10.4, 18.6, last: [1, 2]),
                    zone("主客舱", 15, [2, 3], 19.6, 31.6)
                ])
            ],
            sources: [AtlasSource(title: "空中客车 · A220 系列尺寸、发动机与航程", url: "https://mediaassets.airbus.com/pm_38_914_914151-otwj0mvcnm.pdf"),
                      deltaSeatMap("A220-300", "airbus/a220-300")]
        ),
        AircraftProfile(
            id: "a319", modelName: "A319-100", manufacturer: .airbus, series: "A320ceo 系列 · 缩短型",
            description: "A319 缩短了 A320 的机身，保留 3–3 经济舱及 CFM56-5B 或 IAE V2500 发动机选项。此处展示达美的翼尖翼栅构型。",
            lengthM: 33.84, wingspanM: 33.86, rangeDescription: "达美列出的机队航程约 4,560 公里。空客对带鲨鳍翼梢的版本公布约 6,950 公里。",
            configurations: [
                deltaCabin(132, "三分区", [
                    zone("国内头等舱", 3, [2, 2], 6.0, 8.9),
                    zone("舒适经济区", 4, [3, 3], 9.9, 13.4),
                    zone("主客舱", 16, [3, 3], 14.4, 27.8)
                ])
            ],
            sources: [airbusNarrowbody, deltaSeatMap("A319-100", "airbus/a319")]
        ),
        AircraftProfile(
            id: "a320ceo", modelName: "A320-200 (ceo)", manufacturer: .airbus, series: "A320ceo 系列 · 单通道",
            description: "最早投入航线运营的 A320 基础系列，采用数字电传飞控。此处展示带翼尖翼栅的机型，可与 A320neo 的鲨鳍翼梢和更大发动机短舱对照。",
            lengthM: 37.57, wingspanM: 33.86, rangeDescription: "达美列出的机队航程约 3,490 公里。空客对带鲨鳍翼梢的版本公布约 6,200 公里。",
            configurations: [
                deltaCabin(157, "三分区", [
                    zone("国内头等舱", 4, [2, 2], 6.1, 10.2),
                    zone("舒适经济区", 3, [3, 3], 11.1, 13.8),
                    zone("主客舱", 21, [3, 3], 14.7, 31.0, last: [1, 2])
                ])
            ],
            sources: [airbusNarrowbody, deltaSeatMap("A320-200", "airbus/a320")]
        ),
        AircraftProfile(
            id: "a321ceo", modelName: "A321-200 (ceo)", manufacturer: .airbus, series: "A320ceo 系列 · 加长型",
            description: "A321-200 延长了 A320 机身，提供更大的客舱容量。达美的此构型带鲨鳍翼梢，可以与同长度的 A321neo 对比。",
            lengthM: 44.51, wingspanM: 35.80, rangeDescription: "空客资料列出的航程约 5,950 公里（3,200 海里）。",
            configurations: [
                deltaCabin(191, "三分区", [
                    zone("国内头等舱", 5, [2, 2], 6.1, 11.0),
                    zone("舒适经济区", 6, [3, 3], 12.0, 17.5, last: [2, 3]),
                    zone("主客舱", 23, [3, 3], 18.5, 36.8, last: [2, 2])
                ])
            ],
            sources: [airbusNarrowbody, deltaSeatMap("A321-200", "airbus/a321")]
        ),
        AircraftProfile(
            id: "a330-200", modelName: "A330-200", manufacturer: .airbus, series: "A330 系列 · 缩短延程型",
            description: "A330-200 采用短于 A330-300 的机身，同系列的机翼以及较高的垂直尾翼。客舱保留 A330 常见的 2–4–2 经济舱排布。",
            lengthM: 58.82, wingspanM: 60.30, rangeDescription: "空客列出的航程约 13,450 公里（7,250 海里）。",
            configurations: [
                deltaCabin(223, "四分区", [
                    zone("Delta One 商务舱", 9, [1, 2, 1], 7.8, 20.0, last: [1, 0, 1]),
                    zone("尊尚经济舱", 3, [2, 3, 2], 21.1, 25.0),
                    zone("舒适经济区", 4, [2, 4, 2], 26.1, 30.4),
                    zone("主客舱", 17, [2, 4, 2], 31.5, 48.7)
                ])
            ],
            sources: [airbusA330, deltaSeatMap("A330-200", "airbus/a330-200")]
        ),
        AircraftProfile(
            id: "a330-300", modelName: "A330-300", manufacturer: .airbus, series: "A330 系列 · 双通道",
            description: "A330-300 是率先投入运营的 A330 型号。其机身和 A330-900 等长，此处可观察两代机型的翼尖、翼展和发动机短舱差别。",
            lengthM: 63.66, wingspanM: 60.30, rangeDescription: "空客列出的航程约 11,750 公里（6,350 海里）。",
            configurations: [
                deltaCabin(282, "四分区", [
                    zone("Delta One 商务舱", 9, [1, 2, 1], 7.8, 21.0, last: [1, 0, 1]),
                    zone("尊尚经济舱", 3, [2, 3, 2], 22.1, 26.1),
                    zone("舒适经济区", 3, [2, 4, 2], 27.1, 30.6),
                    zone("主客舱", 26, [2, 4, 2], 31.8, 52.7, last: [1, 1, 1])
                ])
            ],
            sources: [airbusA330, deltaSeatMap("A330-300", "airbus/a330-300")]
        ),
        AircraftProfile(
            id: "a350-1000", modelName: "A350-1000", manufacturer: .airbus, series: "A350 系列 · 加长型",
            description: "A350-1000 比 A350-900 长约七米，采用 Trent XWB-97 发动机。其左右主起落架各有三轴六轮，机翼后缘也经过修改。",
            lengthM: 73.78, wingspanM: 64.75, rangeDescription: "空客 2026 年 6 月技术资料给出的在役构型航程约 15,000 公里（8,100 海里）。",
            configurations: [
                cabin("cx-334", "国泰航空", "334 座三舱", "参考国泰公开的 46 座公务舱、32 座特选经济舱与 256 座经济舱。", [
                    zone("公务舱", 12, [1, 2, 1], 8.8, 26.2, last: [1, 0, 1]),
                    zone("特选经济舱", 4, [2, 4, 2], 27.7, 32.7),
                    zone("经济舱", 29, [3, 3, 3], 34.0, 60.9, last: [2, 0, 2])
                ])
            ],
            sources: [AtlasSource(title: "空中客车 · A350 系列尺寸及各重量版本航程", url: "https://mediaassets.airbus.com/pm_38_914_914160-5r00v49u0t.pdf?fileName=airbus-a350-family-facts-and-figures-june-2026.pdf"),
                      AtlasSource(title: "空中客车 · A350-1000 六轮主起落架", url: "https://www.aircraft.airbus.com/sites/g/files/jlcbta126/files/2025-07/AC_A350_20250715.pdf"),
                      AtlasSource(title: "国泰航空 · A350-1000 客舱与座位图", url: "https://www.cathaypacific.com/cx/sc_CN/flying-with-us/aircraft-and-fleet/airbus-a350/1000.html")]
        )
    ]

    private static let boeingExpansion: [AircraftProfile] = [
        AircraftProfile(
            id: "b737-700", modelName: "737-700", manufacturer: .boeing, series: "新一代 737 · 缩短型",
            description: "737-700 是 737 NG 家族的较短型号，使用两台 CFM56-7B 发动机。此处以带上翘翼梢小翼的构型展示西南航空的全经济舱。",
            lengthM: 33.60, wingspanM: 35.80, rangeDescription: "波音 737 NG 技术页列出至多约 5,370 公里（2,900 海里）。",
            configurations: [
                cabin("wn-137", "美国西南航空", "137 座单舱", "参考西南航空公布的 137 座容量和每排 3–3 的单舱，未重现具体座位节距。", [
                    zone("单通道客舱", 23, [3, 3], 6.6, 27.8, last: [2, 3])
                ])
            ],
            sources: [boeingNG, AtlasSource(title: "美国西南航空 · 737-700 客舱规格", url: "https://support.southwest.com/helpcenter/article/airplane-specifications")]
        ),
        AircraftProfile(
            id: "b737-900er", modelName: "737-900ER", manufacturer: .boeing, series: "新一代 737 · 加长延程型",
            description: "737-900ER 采用 737 NG 系列最长的机身。同样采用 CFM56-7B 的 737-800 可用于对比长度和机舱分区。",
            lengthM: 42.11, wingspanM: 35.79, rangeDescription: "波音参考指南给出的高密度两舱满载设计航程为约 4,820 公里（2,600 海里，带翼梢小翼的高重量构型）。",
            configurations: [
                deltaCabin(180, "三分区", [
                    zone("国内头等舱", 5, [2, 2], 6.6, 11.3),
                    zone("舒适经济区", 5, [3, 3], 12.2, 16.8, last: [0, 3]),
                    zone("主客舱", 23, [3, 3], 17.8, 34.9, last: [1, 0])
                ])
            ],
            sources: [boeingReference, AtlasSource(title: "波音 · 737-900ER 尺寸与翼梢小翼", url: "https://www.boeing.com/commercial/737ng/737-next-generation-design-highlights"),
                      deltaSeatMap("737-900ER", "boeing/737-900er")]
        ),
        AircraftProfile(
            id: "b737-max9", modelName: "737 MAX 9", manufacturer: .boeing, series: "737 MAX 系列 · 加长型",
            description: "亦称 737-9，机身比 MAX 8 长约 2.6 米。发动机采用 LEAP-1B，外部可对照分叉翼尖、发动机后缘锯齿与不同的前后机舱长度。",
            lengthM: 42.10, wingspanM: 35.90, rangeDescription: "波音技术页列出的最长航程约 6,110 公里（3,300 海里）。",
            configurations: [
                cabin("as-178", "阿拉斯加航空", "178 座三分区", "参考航司机队页面列出的 16 座头等舱、42 座优选舱与 120 座主客舱构型。", [
                    zone("国内头等舱", 4, [2, 2], 6.6, 10.8),
                    zone("优选经济区", 7, [3, 3], 11.8, 18.1),
                    zone("主客舱", 20, [3, 3], 19.0, 34.9)
                ])
            ],
            sources: [AtlasSource(title: "波音 · 737 MAX 系列技术规格", url: "https://www.boeing.com/commercial/737max"),
                      AtlasSource(title: "阿拉斯加航空 · 机队和客舱容量", url: "https://news.alaskaair.com/current-fleet/")]
        ),
        AircraftProfile(
            id: "b747-400", modelName: "747-400", manufacturer: .boeing, series: "747 系列 · 局部双层客机",
            description: "747-400 客机保留四台翼下发动机和机首上层客舱，并配有上翘翼梢小翼。汉莎的构型使用四台 GE CF6-80C2，可与 747-8 的后掠翼尖和新一代发动机比较。",
            lengthM: 70.66, wingspanM: 64.44, rangeDescription: "汉莎公布的机队数据为约 12,200 公里。波音的设计航程按发动机与起飞重量分别列出。",
            configurations: [
                cabin("lh-371", "德国汉莎航空", "371 座双层三舱", "参考汉莎公布的 67 座商务、32 座高端经济与 272 座经济布局。商务舱分布在两层。", [
                    zone("主层 · 商务舱", 8, [2, 2, 2], 9.2, 24.3, last: [1, 1, 1]),
                    zone("主层 · 高端经济舱", 4, [2, 4, 2], 25.7, 30.8),
                    zone("主层 · 经济舱", 28, [3, 4, 3], 32.1, 58.4, last: [1, 0, 1]),
                    zone("上层 · 商务舱", 6, [2, 2], 10.9, 21.6, last: [1, 1], deck: 1)
                ])
            ],
            sources: [AtlasSource(title: "德国汉莎航空 · 747-400 双层座位图与尺寸", url: "https://www.lufthansa.com/de/en/74e"),
                      AtlasSource(title: "波音 · 747-400 各发动机版本性能", url: "https://www.boeing.com/content/dam/boeing/boeingdotcom/company/about_bca/startup/pdf/historical/747-400-passenger.pdf")]
        ),
        AircraftProfile(
            id: "b757-200", modelName: "757-200", manufacturer: .boeing, series: "757 系列 · 双发单通道",
            description: "757-200 是机身细长、起落架较高的单通道客机，与 767 同期开发。这里展示带翼梢小翼的达美 757-200。",
            lengthM: 47.32, wingspanM: 41.07, rangeDescription: "波音历史资料给出的代表性航程约 7,220 公里（3,900 海里）。机队构型的实际数据不同。",
            configurations: [
                deltaCabin(199, "三分区", [
                    zone("国内头等舱", 5, [2, 2], 6.9, 12.4),
                    zone("舒适经济区", 6, [3, 3], 13.4, 19.1, last: [2, 3]),
                    zone("主客舱", 24, [3, 3], 20.2, 39.0)
                ])
            ],
            sources: [AtlasSource(title: "波音 · 757-200 历史资料和公开尺寸", url: "https://www.boeing.com/content/dam/boeing/v2/company/history/pdf/Boeing_Products.pdf"),
                      deltaSeatMap("757-200", "boeing/757-200")]
        ),
        AircraftProfile(
            id: "b767-300er", modelName: "767-300ER", manufacturer: .boeing, series: "767 系列 · 加长延程型",
            description: "767-300ER 采用双发宽体设计，常见经济舱座位为 2–3–2。图鉴展示带翼梢小翼的达美 216 座构型。",
            lengthM: 54.94, wingspanM: 50.60, rangeDescription: "波音参考指南给出的旅客与行李设计航程约 8,060–10,010 公里，随重量版本变化。",
            configurations: [
                deltaCabin(216, "四分区", [
                    zone("Delta One 商务舱", 7, [1, 2, 1], 7.6, 17.4, last: [1, 0, 1]),
                    zone("尊尚经济舱", 3, [2, 2, 2], 18.5, 22.4),
                    zone("舒适经济区", 5, [2, 3, 2], 23.5, 28.0, last: [0, 1, 0]),
                    zone("主客舱", 21, [2, 3, 2], 29.0, 45.5, last: [1, 1, 1])
                ])
            ],
            sources: [boeingReference, deltaSeatMap("767-300ER", "boeing/767-300er")]
        ),
        AircraftProfile(
            id: "b777-200er", modelName: "777-200ER", manufacturer: .boeing, series: "777 系列 · 延程型",
            description: "777-200ER 保留基础型 777-200 的机身长度，主要变化在航程和起飞重量。与 777-300ER 相比可观察较短的机身和较小翼展。",
            lengthM: 63.70, wingspanM: 60.90, rangeDescription: "波音技术页列出的最长航程约 13,890 公里（7,500 海里）。",
            configurations: [
                cabin("aa-273", "美国航空", "273 座四分区", "参考美国航空公开的 37 座商务舱、24 座高端经济舱、66 座额外空间主客舱和 146 座主客舱。", [
                    zone("商务舱", 10, [1, 2, 1], 8.8, 23.0, last: [0, 1, 0]),
                    zone("高端经济舱", 3, [2, 4, 2], 24.1, 28.0),
                    zone("额外空间主客舱", 7, [3, 4, 3], 29.0, 35.5, last: [2, 2, 2]),
                    zone("主客舱", 15, [3, 4, 3], 36.7, 52.8, last: [2, 2, 2])
                ])
            ],
            sources: [AtlasSource(title: "波音 · 777 系列技术规格", url: "https://www.boeing.com/commercial/777"), americanFleet]
        ),
        AircraftProfile(
            id: "b787-8", modelName: "787-8", manufacturer: .boeing, series: "787 梦想飞机 · 基础型",
            description: "787-8 是 787 系列最先投入航线运营的型号。它和 787-9、787-10 使用相同的翼展和发动机系列，机身较短。",
            lengthM: 56.70, wingspanM: 60.10, rangeDescription: "波音技术页列出的最长航程约 14,820 公里（8,000 海里）。",
            configurations: [
                cabin("aa-234", "美国航空", "234 座四分区", "参考美国航空公开的 20 座商务舱、28 座高端经济舱、48 座额外空间主客舱和 138 座主客舱。", [
                    zone("商务舱", 5, [1, 2, 1], 8.5, 16.0),
                    zone("高端经济舱", 4, [2, 3, 2], 17.0, 21.8),
                    zone("额外空间主客舱", 6, [3, 3, 3], 22.8, 28.0, last: [1, 1, 1]),
                    zone("主客舱", 16, [3, 3, 3], 29.1, 47.0, last: [1, 1, 1])
                ])
            ],
            sources: [boeing787, americanFleet]
        ),
        AircraftProfile(
            id: "b787-10", modelName: "787-10", manufacturer: .boeing, series: "787 梦想飞机 · 加长型",
            description: "787-10 是 787 系列机身最长的型号，保留 787 的后掠翼尖与锯齿短舱。新航的区域机队用 1–2–1 商务舱和 3–3–3 经济舱。",
            lengthM: 68.30, wingspanM: 60.10, rangeDescription: "波音技术页列出的最长航程约 13,890 公里（7,500 海里）。",
            configurations: [
                cabin("sq-337", "新加坡航空", "337 座两舱", "以新航公开的 36 座商务舱和 301 座经济舱为参考。", [
                    zone("商务舱", 9, [1, 2, 1], 8.7, 22.3),
                    zone("经济舱", 34, [3, 3, 3], 23.6, 56.6, last: [2, 0, 2])
                ])
            ],
            sources: [boeing787, AtlasSource(title: "新加坡航空 · 787-10 公开座位图", url: "https://www.singaporeair.com/saar5/pdf/OurFleet/boeing787-10.pdf")]
        )
    ]

    private static let airbusNarrowbody = AtlasSource(
        title: "空中客车 · A320 系列尺寸与技术数据（2026 年 6 月）",
        url: "https://mediaassets.airbus.com/pm_38_914_914157-tlwvtuuhjj.pdf?fileName=airbus-a320-family-facts-and-figures-june-2026.pdf"
    )

    private static let airbusA330 = AtlasSource(title: "空中客车 · A330 系列尺寸与航程", url: "https://mediaassets.airbus.com/pm_38_896_896589-6vwqkjd9gw.pdf?fileName=airbus-a330-family-facts-and-figures-april-2026.pdf")
    private static let boeingNG = AtlasSource(title: "波音 · 737 Next Generation 技术规格", url: "https://www.boeing.com/commercial/737ng")
    private static let boeingReference = AtlasSource(title: "波音 · 民用飞机技术参考指南", url: "https://www.boeing.com/productstory/Commercial_Airplanes_Reference_Guide.pdf")
    private static let boeing787 = AtlasSource(title: "波音 · 787 系列技术规格", url: "https://www.boeing.com/commercial/787")
    private static let americanFleet = AtlasSource(title: "美国航空 · 机队及分舱容量", url: "https://www.aa.com/web/i18n/travel-info/experience/planes/planes.html")

    private static func deltaSeatMap(_ model: String, _ path: String) -> AtlasSource {
        AtlasSource(title: "达美航空 · \(model) 公开座位图", url: "https://www.delta.com/us/en/aircraft/\(path)")
    }

    private static func deltaCabin(_ seats: Int, _ layout: String, _ zones: [AircraftCabinZone]) -> AircraftConfiguration {
        cabin("dl-\(seats)", "达美航空", "\(seats) 座\(layout)", "按达美公开的分区容量绘制。", zones)
    }

    private static func cabin(_ id: String, _ airline: String, _ name: String, _ description: String, _ seats: [AircraftCabinZone]) -> AircraftConfiguration {
        AircraftConfiguration(
            id: id, airline: airline, name: name,
            cabinDescription: "\(description)图鉴简化了座号、设备和外部饰带。",
            seats: seats, isIllustrative: true
        )
    }

    private static func zone(_ label: String, _ rows: Int, _ groups: [Int], _ start: Float, _ end: Float, last: [Int]? = nil, deck: Int = 0) -> AircraftCabinZone {
        AircraftCabinZone(label: label, numberOfRows: rows, seatGroups: groups, startM: start, endM: end, partialLastRow: last, deck: deck)
    }
}
