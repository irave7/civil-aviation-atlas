import SwiftUI

@MainActor
struct AtlasAircraftMissions: View {
    let library: AtlasLibrary
    let openAircraft: (AircraftProfile) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AtlasObservationProgress.aircraftKey) private var completed = ""
    @SceneStorage("atlas.exploration.selected-aircraft") private var expandedID: String?

    @State private var listening = ExplorationListening()

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        let available = AircraftMission.stages.compactMap { mission in
            library.aircraft(mission.id).map { (mission: mission, aircraft: $0) }
        }
        let marks = AtlasObservationProgress.completed(in: completed)
        let done = available.filter { marks.contains($0.mission.id) }.count
        LazyVStack(alignment: .leading, spacing: palette.contentGap) {
            ExplorationChapterHeader(title: "机型探索", done: done, total: available.count, unit: " 项", palette: palette)
                .accessibilityIdentifier("exploration-aircraft-progress")
            ForEach(available, id: \.aircraft.id) { entry in
                card(entry.mission, aircraft: entry.aircraft, isComplete: marks.contains(entry.mission.id))
            }
        }
        .foregroundStyle(palette.ink)
        .onDisappear(perform: listening.stop)
        .onChange(of: expandedID) { listening.stop() }
    }

    private func card(_ mission: AircraftMission, aircraft: AircraftProfile, isComplete: Bool) -> some View {
        let expanded = expandedID == mission.id
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.23)) {
                    expandedID = expanded ? nil : mission.id
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: isComplete ? "checkmark.circle.fill" : mission.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(palette.selectionInk)
                        .padding(10)
                        .background(palette.selection, in: .rect(cornerRadius: 9))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(aircraft.displayName)
                            .font(AtlasTypography.font(.subheadline, weight: .semibold))
                            .foregroundStyle(palette.accent)
                        Text(mission.title)
                            .font(AtlasTypography.font(.headline, weight: .bold))
                            .foregroundStyle(palette.ink)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                }
                .multilineTextAlignment(.leading)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exploration-aircraft-mission-\(mission.id)")
            .accessibilityValue(isComplete ? "已完成" : (expanded ? "已展开" : "待观察"))

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(mission.observation)
                        .font(AtlasTypography.font(.subheadline))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        listening.stop()
                        openAircraft(aircraft)
                    } label: {
                        Label("打开三维模型", systemImage: "cube")
                            .frame(minHeight: 38)
                    }
                    .buttonStyle(.bordered)
                    .tint(palette.accent)
                    .accessibilityIdentifier("exploration-aircraft-open-\(mission.id)")

                    let key = "aircraft-\(mission.id)"
                    ExplorationListenButton(player: listening, source: .observation(id: key, fallback: mission.observation),
                                            accessibilityID: "exploration-aircraft-listen-\(mission.id)")
                        .tint(palette.accent)
                    ExplorationVoiceCaption(player: listening, id: key)

                    AtlasObservationMission(
                        id: "aircraft-\(mission.id)", question: mission.question,
                        completed: isComplete, palette: palette
                    ) {
                        completed = AtlasObservationProgress.marking(mission.id, in: completed)
                    }

                    if let source = aircraft.sources.first, let url = URL(string: source.url) {
                        Link(destination: url) {
                            Label(source.title, systemImage: "arrow.up.right.square")
                                .font(AtlasTypography.font(.caption))
                        }
                        .foregroundStyle(palette.accent)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .atlasPanel(palette)
    }
}

private struct AircraftMission {
    let id: String
    let title: String
    let symbol: String
    let observation: String
    let question: AtlasObservationQuestion

    static let stages: [Self] = [
        .init(id: "c919", title: "从客舱里找通道", symbol: "rectangle.split.2x1",
              observation: "在模型中打开透视或内部视图。从机头朝机尾观察座椅之间贯通客舱的走道。",
              question: .init("C919 的代表性经济舱有几条纵向通道？",
                              ["两条", "一条", "三条"], answer: 1,
                              explanation: "图鉴的 C919 经济舱每排左右各三张座椅，中间留一条纵向通道。")),
        .init(id: "a320neo", title: "找翼尖的小翼", symbol: "airplane",
              observation: "转动模型到斜前方，顺着机翼的前缘找到最外侧。",
              question: .init("鲨鳍式翼梢装在什么位置？",
                              ["机翼最外端", "发动机短舱后方", "起落架下方"], answer: 0,
                              explanation: "鲨鳍式小翼位于主机翼的外端。")),
        .init(id: "a350-900", title: "看看宽体机的座椅", symbol: "rectangle.split.3x1",
              observation: "在模型里切到内部或透视视图，选中经济舱，从上方看座椅分成几组。",
              question: .init("图鉴里的 A350-900 典型经济舱每排怎样分组？",
                              ["2–2", "3–3", "3–3–3"], answer: 2,
                              explanation: "图鉴里的 A350-900 经济舱采用 3–3–3，中间一组座椅两侧各有一条过道。实际座位由航空公司配置。")),
        .init(id: "a380-800", title: "数数机翼下的发动机", symbol: "airplane",
              observation: "把飞机转到俯视，放大两侧机翼。留意机翼下伸出的圆筒形短舱。",
              question: .init("A380-800 一共装有几台发动机？",
                              ["两台", "三台", "四台"], answer: 2,
                              explanation: "四台发动机分别装在左右两侧的机翼下，每侧两台。")),
        .init(id: "b737-max8", title: "看分叉式翼梢", symbol: "airplane",
              observation: "转到机翼外侧，把模型放大到能看清翼尖轮廓。",
              question: .init("737 MAX 8 的翼梢朝哪里分开？",
                              ["只朝后", "分别向上和向下", "只朝向机身"], answer: 1,
                              explanation: "737 MAX 的翼梢有向上和向下延伸的部分。")),
        .init(id: "b747-8i", title: "找机背上的上层客舱", symbol: "square.split.1x2",
              observation: "从侧面观察机身轮廓，再用透视模式找到上层座位和主层座位。",
              question: .init("747-8 客运型的上层客舱主要在哪一段？",
                              ["机身前段", "靠近尾翼的一段", "整段机身"], answer: 0,
                              explanation: "上层客舱位于机身前段，因此从侧面能看到机头上方的隆起。")),
        .init(id: "b787-9", title: "比较机身和翼展", symbol: "ruler",
              observation: "打开机型资料，比较机长和翼展。翼展指从一侧主翼翼尖到另一侧主翼翼尖的距离。",
              question: .init("787-9 的机长和翼展，哪一个数值更大？",
                              ["翼展", "一样大", "机长"], answer: 2,
                              explanation: "图鉴收录的机长约 62.8 米，翼展约 60.1 米。")),
        .init(id: "e195-e2", title: "有没有中间座位", symbol: "chair.lounge",
              observation: "切换到客舱内部，观察一排窗边座位和过道座位之间是否还有座位。",
              question: .init("E195-E2 的图鉴客舱中，每排通道的左右两边各有几个座位？",
                              ["各两个", "各三个", "各四个"], answer: 0,
                              explanation: "图鉴展示的典型 E195-E2 为 2–2 布局，每侧只有窗边和过道两个座位。"))
    ]
}
