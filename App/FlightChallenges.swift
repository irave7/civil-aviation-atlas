import SwiftUI

struct FlightChallenge: Identifiable, Hashable {
    enum WindPreset: String, Hashable {
        case calm = "平稳天气", turbulence = "巡航气流", crosswind = "落地侧风"
    }

    let origin: String
    let destination: String
    let title: String
    let introduction: String
    let wind: WindPreset
    let referenceAircraft: String

    var id: String { "\(origin)-\(destination)" }

    var introductionAudio: URL? {
        let filename = "challenge-\(id)"
        return Bundle.main.url(forResource: filename, withExtension: "m4a", subdirectory: "ChallengeVoices")
            ?? Bundle.main.url(forResource: filename, withExtension: "m4a")
    }

    init(_ origin: String, _ destination: String, _ title: String, _ introduction: String,
         wind: WindPreset = .calm, aircraft: String = "a320neo") {
        self.origin = origin
        self.destination = destination
        self.title = title
        self.introduction = introduction
        self.wind = wind
        referenceAircraft = aircraft
    }

    @MainActor
    func leg(in library: AtlasLibrary) -> ExplorationLeg? {
        guard let start = library.airport(origin), let end = library.airport(destination) else { return nil }
        let published = library.routes(at: start).filter { $0.origin == origin && $0.destination == destination && $0.hasVerifiedNonstop }
        let observed = library.observedRoutes(at: start).first { $0.origin == origin && $0.destination == destination && $0.hasVerifiedNonstop }
        guard let route = published.first(where: { $0.flightNumber != nil && $0.aircraftID != nil }) ?? published.first ?? observed,
              let distance = route.distanceKm, distance > 0 else { return nil }
        return ExplorationLeg(start: start, end: end, evidence: route, distance: distance)
    }

    static let mainland: [Self] = [
        .init("SHA", "PEK", "京沪快线", "从虹桥搭乘国产 C919，看看客机如何从滑行切换到起飞。"),
        .init("SHA", "CGO", "飞往中原", "从长三角飞往郑州，留意爬升时何时该把起落架收起来。"),
        .init("SHA", "XMN", "沿海飞往厦门", "飞向海湾旁的厦门。进近时留意侧风怎样让飞机偏转。", wind: .crosswind),
        .init("PVG", "CAN", "两大三角洲", "从长江口飞往广州，巡航时试着让飞机在气流里保持平稳。", wind: .turbulence),
        .init("PKX", "TFU", "从大兴到天府", "两座大型机场都有多条跑道。航前看看选的是哪一条。", aircraft: "b787-9"),
        .init("PEK", "FOC", "京城到闽江口", "从北京飞到福州海边。看见跑道后，让机头对准跑道中线。", wind: .crosswind),
        .init("PEK", "CKG", "穿过山城上空", "飞向重庆。比较飞行高度和机场海拔，体会它们怎样影响下降。", wind: .turbulence),
        .init("PEK", "SYX", "南飞海南岛", "从北京一路南飞，抵达三亚时练习减速和放下襟翼。", wind: .crosswind),
        .init("PVG", "SZX", "长三角到湾区", "同样是靠海的机场，跑道方向会怎样影响起飞和降落？"),
        .init("TFU", "PVG", "从盆地到长江口", "先在地图上找成都和上海，再切到机外看看涂装与机翼。", aircraft: "a330-900")
    ]

    static let worldwide: [Self] = [
        .init("SHA", "HKG", "C919 飞越珠江口", "从虹桥飞到赤鱲角，比较两个机场跑道的方向。"),
        .init("PVG", "SIN", "飞向赤道", "搭乘收录班表中的新加坡航空客机，体验热带航线的模拟气流。", wind: .turbulence),
        .init("HND", "JFK", "跨越国际日期变更线", "从东京飞往纽约，把航图切到全球视角，观察航迹跨过太平洋。", wind: .turbulence),
        .init("HKG", "DFW", "由香港飞往得州", "观察 A350 的长机翼，比较全程航图和跟机视角里的飞行路线。"),
        .init("DXB", "LHR", "双层客机飞往伦敦", "A380 有四台发动机。切到机外数一数，再进驾驶舱看看推力杆。", wind: .crosswind),
        .init("SIN", "JFK", "超远程航班", "飞行时间在模拟中被缩短。看看完整航迹在地球上弯向哪里。", wind: .turbulence),
        .init("SIN", "PER", "飞往南半球", "出发后跨过赤道，最后看看客机怎样减速进近珀斯。"),
        .init("HKG", "SYD", "由东亚飞往澳洲", "从香港一路南下，抵达悉尼后留意接地和滑入的声音。", wind: .crosswind),
        .init("FRA", "IAD", "747-8 的商业首航", "沿汉莎航空的历史首航，从法兰克福飞往华盛顿。切到机外找找机身上的上层客舱。", wind: .turbulence),
        .init("GRU", "LIS", "横越南大西洋", "从巴西飞往葡萄牙，看看长距离航线怎样跨越海洋。", aircraft: "a330-900"),
        .init("AMS", "CPT", "一路向南到开普敦", "从欧洲飞往非洲南端，进近时练习顶住侧风。", wind: .crosswind, aircraft: "b787-9"),
        .init("SYD", "YVR", "从澳洲到加拿大", "跨过太平洋和赤道。在全球视角中找两个大洲的位置。", wind: .turbulence, aircraft: "b787-9")
    ]
}

enum FlightChallengeProgress {
    static let key = "atlas.simulator.completed-challenges.v1"

    static func contains(_ id: String, in stored: String) -> Bool {
        stored.split(separator: ",").contains(Substring(id))
    }

    static func completing(_ id: String, in stored: String) -> String {
        Set(stored.split(separator: ",").map(String.init) + [id]).sorted().joined(separator: ",")
    }
}

struct FlightChallengeBrowser: View {
    let library: AtlasLibrary
    let onSelect: (FlightChallenge, ExplorationLeg) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(FlightChallengeProgress.key) private var completed = ""
    @State private var region = Region.mainland
    @State private var listening = ExplorationListening()

    private enum Region: String, CaseIterable {
        case mainland = "中国大陆", worldwide = "全球"
    }

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker("范围", selection: $region) {
                ForEach(Region.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("flight-challenge-region")
            routes
        }
        .task { await library.prepareObservedRoutes() }
        .onDisappear(perform: listening.stop)
        .onChange(of: region) { listening.stop() }
    }

    private var routes: some View {
        let candidates = region == .mainland ? FlightChallenge.mainland : FlightChallenge.worldwide
        let ready = candidates.compactMap { challenge in challenge.leg(in: library).map { (challenge, $0) } }
        let done = ready.count { FlightChallengeProgress.contains($0.0.id, in: completed) }
        return LazyVStack(alignment: .leading, spacing: 11) {
            if !ready.isEmpty {
                ExplorationChapterHeader(title: "航线关卡", done: done, total: ready.count, unit: " 关", palette: palette)
                    .accessibilityIdentifier("flight-challenge-progress")
            }
            ForEach(ready, id: \.0.id) { challenge, leg in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        listening.stop()
                        onSelect(challenge, leg)
                    } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 10) {
                                Text(leg.start.displayCode)
                                HStack(spacing: 5) {
                                    Rectangle().fill(palette.line).frame(height: 1)
                                    Image(systemName: "airplane")
                                        .font(.footnote.weight(.semibold))
                                    Rectangle().fill(palette.line).frame(height: 1)
                                }
                                .frame(maxWidth: 82)
                                .accessibilityHidden(true)
                                Text(leg.end.displayCode)
                                Spacer(minLength: 2)
                                Image(systemName: FlightChallengeProgress.contains(challenge.id, in: completed)
                                      ? "checkmark.circle.fill" : "chevron.right.circle")
                                    .font(.title3)
                                    .accessibilityHidden(true)
                            }
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(palette.accent)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(leg.start.displayName)飞往\(leg.end.displayName)")
                            Text(challenge.title).font(AtlasTypography.font(.headline, weight: .bold))
                            Text(challenge.introduction)
                                .font(AtlasTypography.font(.subheadline))
                                .foregroundStyle(palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Divider()
                            Text([leg.evidence.flightNumber, leg.evidence.status,
                                  "\(Int(leg.distance.rounded()).formatted()) 公里", challenge.wind.rawValue]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(AtlasTypography.font(.footnote))
                                .foregroundStyle(palette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("flight-challenge-\(challenge.id)")
                    .accessibilityValue(FlightChallengeProgress.contains(challenge.id, in: completed) ? "已完成" : "未完成")
                    ExplorationListenButton(player: listening, source: .route(challenge),
                                            accessibilityID: "flight-challenge-listen-\(challenge.id)")
                        .tint(palette.accent)
                    ExplorationVoiceCaption(player: listening, id: challenge.id)
                }
                .padding(15)
                .atlasPanel(palette)
            }
        }
        .foregroundStyle(palette.ink)
    }

}
