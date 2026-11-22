import AVFoundation
import SwiftUI

@MainActor
struct FlightAirportChapters: View {
    let library: AtlasLibrary
    let domestic: Bool
    let openAirport: (Airport) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedID: String?
    @State private var playingID: String?
    @State private var previewSequence = 0
    @State private var previewTask: Task<Void, Never>?
    @State private var narrator = ExplorationNarrator()

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }
    private var modelAccess: Bool { DistributionPolicy.airportSiteModelsAvailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(domestic ? "中国大陆机场观察" : "全球机场观察")
                .font(AtlasTypography.font(.title2, weight: .bold))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("flight-airport-chapters")
            if DistributionPolicy.isMainlandReview {
                Text("中国大陆分发版提供机场资料")
                    .font(AtlasTypography.font(.footnote))
                    .foregroundStyle(palette.muted)
            }
            ForEach(domestic ? AirportChapter.domestic : AirportChapter.global) { chapter in
                if let airport = library.airport(chapter.id) {
                    card(chapter, airport: airport)
                }
            }
        }
        .onDisappear(perform: stopPreview)
        .onChange(of: domestic) {
            stopPreview()
            expandedID = nil
        }
    }

    private func card(_ chapter: AirportChapter, airport: Airport) -> some View {
        let expanded = expandedID == chapter.id
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                stopPreview()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.23)) {
                    expandedID = expanded ? nil : chapter.id
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Text(airport.displayCode)
                        .font(palette.readout(.subheadline, weight: .bold))
                        .foregroundStyle(palette.selectionInk)
                        .padding(8)
                        .background(palette.selection, in: .rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(airport.displayName)
                            .font(AtlasTypography.font(.headline, weight: .bold))
                            .foregroundStyle(palette.ink)
                        Text(chapter.title)
                            .font(AtlasTypography.font(.subheadline))
                            .foregroundStyle(palette.muted)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("flight-airport-chapter-\(chapter.id)")
            .accessibilityValue(expanded ? "已展开" : "已收起")

            if expanded {
                chapterDetails(chapter, airport: airport)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .atlasPanel(palette)
    }

    private func chapterDetails(_ chapter: AirportChapter, airport: Airport) -> some View {
        let recording = Self.previewURL(for: airport.displayCode)
        return VStack(alignment: .leading, spacing: 11) {
            Text(chapter.idea)
                .font(AtlasTypography.font(.body))
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if modelAccess {
                if let sketch = ChapterRunwaySketch(airport: airport) {
                    AirportChapterDiagram(sketch: sketch, palette: palette, replay: previewSequence)
                }
                Text(chapter.lookFor)
                    .font(AtlasTypography.font(.subheadline, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let fact = chapter.fact(for: airport, library: library) {
                    Text(fact)
                        .font(palette.readout(.footnote))
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { actions(airport, recording: recording) }
                VStack(alignment: .leading, spacing: 8) { actions(airport, recording: recording) }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(palette.accent)

            if modelAccess && DistributionPolicy.mapsAvailable {
                Text("进入机场后可切换到平面图")
                    .font(AtlasTypography.font(.footnote))
                    .foregroundStyle(palette.muted)
            }
            if let source = source(for: airport), let url = URL(string: source.url) {
                Link(destination: url) {
                    Label(source.title, systemImage: "arrow.up.right.square")
                        .font(AtlasTypography.font(.caption))
                }
                .foregroundStyle(palette.accent)
                .accessibilityHint("打开机场资料来源")
            }
        }
    }

    @ViewBuilder
    private func actions(_ airport: Airport, recording: URL?) -> some View {
        Button {
            stopPreview()
            openAirport(airport)
        } label: {
            Label(modelAccess ? "看三维模型" : "读机场资料", systemImage: modelAccess ? "cube" : "book")
        }
        .accessibilityIdentifier("flight-airport-open-\(airport.id)")

        if let recording {
            let playing = playingID == airport.id
            Button {
                togglePreview(recording, airportID: airport.id)
            } label: {
                Label(playing ? "停止试听" : "听 AI 广播", systemImage: playing ? "stop.circle" : "speaker.wave.2")
            }
            .accessibilityIdentifier("flight-airport-listen-\(airport.id)")
        }
    }

    private func source(for airport: Airport) -> AtlasSource? {
        let catalogueSources = library.catalog?.sources ?? []
        if DistributionPolicy.isMainlandReview && airport.countryCode == "CN" {
            return catalogueSources.first { $0.url.hasPrefix("https://www.caac.gov.cn/") }
        }
        return airport.sources?.first ?? catalogueSources.first { $0.url == "https://ourairports.com/data/" }
    }

    private static func previewURL(for code: String) -> URL? {
        let name = "route-\(code)-departure-0"
        return Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "RouteVoices")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "Resources/RouteVoices")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    private func togglePreview(_ url: URL, airportID: String) {
        let wasPlaying = playingID == airportID
        stopPreview()
        guard !wasPlaying else { return }
        playingID = airportID
        previewTask = Task {
            let duration = try? await AVURLAsset(url: url).load(.duration).seconds
            guard !Task.isCancelled else { return }
            narrator.previewCabin(url)
            previewSequence &+= 1
            try? await Task.sleep(for: .seconds(duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 6))
            guard !Task.isCancelled else { return }
            playingID = nil
            previewTask = nil
        }
    }

    private func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        playingID = nil
        narrator.stop()
    }
}

private struct AirportChapter: Identifiable {
    enum Fact { case designations, lengths, elevation, terminal }

    let id: String
    let title: String
    let idea: String
    let lookFor: String
    let highlights: Fact

    static let domestic: [Self] = [
        .init(id: "SHA", title: "一条跑道，两头有名字",
              idea: "一条跑道的两端面向相反的方向，所以两头会写不同的数字。",
              lookFor: "找找 18 和 36。它们写在同一条跑道的哪两头？", highlights: .designations),
        .init(id: "PEK", title: "谁在左边，谁在右边",
              idea: "看向两条平行跑道时，可以用 L 认左边，用 R 认右边。",
              lookFor: "找找编号里有 18L 和 18R 的两条跑道。", highlights: .designations),
        .init(id: "PKX", title: "跑道都朝同一边吗",
              idea: "机场可以有不同方向的跑道，就像路口的几条路各自伸向不同的地方。",
              lookFor: "找找 11L/29R 跑道。它和另外几条跑道的方向有什么不同？", highlights: .designations),
        .init(id: "PVG", title: "给跑道排个队",
              idea: "同一座机场的跑道也有长短。可以用米数比较，找出最长的那一条。",
              lookFor: "数一数资料里收录了几条跑道，再找出最长的一条。", highlights: .lengths),
        .init(id: "FOC", title: "从停机位怎么到跑道",
              idea: "飞机沿滑行道在机场地面移动，跑道主要供飞机起飞和着陆。",
              lookFor: "打开机场模型或平面图。沿跑道边缘找找通往停机坪的滑行道。", highlights: .designations),
        .init(id: "TFU", title: "机场也有海拔",
              idea: "海拔表示一个地方比海平面高多少。两个机场相隔很远，高度也可能相差很多。",
              lookFor: "比较成都天府和上海虹桥的海拔。哪一座高一些？", highlights: .elevation),
    ]

    static let global: [Self] = [
        .init(id: "HND", title: "把相近方向的跑道分一组",
              idea: "可以像整理彩笔一样，先把方向相近的跑道归到一起。",
              lookFor: "试着把羽田的跑道分成两组，再比较两组的方向。", highlights: .designations),
        .init(id: "SIN", title: "从航站楼走向登机口",
              idea: "航站楼是旅客办手续、候机和到达的建筑。登机口是旅客走向飞机的入口。",
              lookFor: "找找一号和二号航站楼。你会怎样确认自己该去哪一座？", highlights: .terminal),
        .init(id: "JFK", title: "两组跑道像哪种角",
              idea: "把两组跑道沿着各自的方向延长，看看它们张开的角度。",
              lookFor: "找找以 04 和 13 开头的两组跑道。它们的方向接近直角吗？", highlights: .designations),
        .init(id: "LHR", title: "用跑道编号猜东西",
              idea: "跑道上的数字能提示大致方向。09 大约朝东，27 大约朝西。",
              lookFor: "在图里找找跑道的两头，再用指北标记分辨东和西。", highlights: .designations),
        .init(id: "DXB", title: "两条跑道差多长",
              idea: "看上去差不多长的两条跑道，也能用数字比出差别。",
              lookFor: "用较长跑道的米数减去较短跑道的米数，算算相差多少。", highlights: .lengths),
        .init(id: "HKG", title: "跑道编号里的 C",
              idea: "三条平行跑道可以用 L、C、R 区分，C 提示中间的一条。",
              lookFor: "找出 07L、07C、07R，再试着指出中间的跑道。", highlights: .designations),
    ]

    @MainActor
    func fact(for airport: Airport, library: AtlasLibrary) -> String? {
        let runways = (airport.runways ?? []).filter { $0.lengthM > 0 }
        switch highlights {
        case .designations:
            return runways.isEmpty ? nil : "收录跑道 · \(runways.map(\.id).joined(separator: "、"))"
        case .lengths:
            return runways.isEmpty ? nil : runways.map { "\($0.id) · \(Int($0.lengthM.rounded()).formatted()) 米" }.joined(separator: "　")
        case .elevation:
            guard let height = airport.elevationFt else { return nil }
            let local = "天府约 \(Self.meters(fromFeet: height)) 米"
            return library.airport("SHA")?.elevationFt.map { "\(local) · 虹桥约 \(Self.meters(fromFeet: $0)) 米" } ?? local
        case .terminal:
            let names = airport.terminals?.prefix(2).map(\.name) ?? []
            return names.isEmpty ? nil : names.joined(separator: "、")
        }
    }

    private static func meters(fromFeet feet: Int) -> String {
        Int((Double(feet) * 0.3048).rounded()).formatted()
    }
}

private struct ChapterRunwaySketch {
    struct Line {
        let designations: [String]
        let start: CGPoint
        let end: CGPoint
    }

    let lines: [Line]
    let bounds: CGRect

    init?(airport: Airport) {
        guard airport.hasCoordinates else { return nil }
        let localLongitudeScale = cos(airport.lat * .pi / 180)
        lines = (airport.runways ?? []).sorted { $0.lengthM > $1.lengthM }.compactMap { runway in
            guard let lat = runway.lat, let lon = runway.lon,
                  lat.isFinite, lon.isFinite, runway.lengthM > 0,
                  let heading = runway.heading ?? Self.designationHeading(runway.id), heading.isFinite else { return nil }
            let center = CGPoint(x: (lon - airport.lon) * localLongitudeScale * 111_195,
                                 y: (airport.lat - lat) * 111_195)
            let radians = heading * .pi / 180
            let dx = sin(radians) * runway.lengthM / 2
            let dy = -cos(radians) * runway.lengthM / 2
            return Line(designations: runway.id.split(separator: "/").map(String.init),
                        start: CGPoint(x: center.x - dx, y: center.y - dy),
                        end: CGPoint(x: center.x + dx, y: center.y + dy))
        }
        guard !lines.isEmpty else { return nil }
        let points = lines.flatMap { [$0.start, $0.end] }
        let x = points.map(\.x)
        let y = points.map(\.y)
        let left = x.min() ?? 0, right = x.max() ?? 0
        let top = y.min() ?? 0, bottom = y.max() ?? 0
        bounds = CGRect(x: left, y: top, width: max(1, right - left), height: max(1, bottom - top))
    }

    func point(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let scale = min(max(1, size.width - 50) / bounds.width, max(1, size.height - 28) / bounds.height)
        return CGPoint(x: size.width / 2 + (point.x - bounds.midX) * scale,
                       y: size.height / 2 + (point.y - bounds.midY) * scale)
    }

    private static func designationHeading(_ id: String) -> Double? {
        Int(id.prefix(while: \.isNumber)).flatMap { (1...36).contains($0) ? Double($0 * 10) : nil }
    }
}

private struct AirportChapterDiagram: View {
    let sketch: ChapterRunwaySketch
    let palette: AtlasPalette
    let replay: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel = 0.15

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    for (index, line) in sketch.lines.enumerated() {
                        let start = sketch.point(line.start, in: size)
                        let end = sketch.point(line.end, in: size)
                        var path = Path()
                        path.move(to: start)
                        path.addLine(to: end)
                        context.stroke(path, with: .color(palette.line), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        context.stroke(path, with: .color(palette.accent.opacity(0.85)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        if index == 0, line.designations.count == 2 {
                            let angle = atan2(end.y - start.y, end.x - start.x)
                            let offset = CGVector(dx: -sin(angle) * 13, dy: cos(angle) * 13)
                            for (name, point) in zip(line.designations, [start, end]) {
                                let label = Text(name)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(palette.ink)
                                context.draw(label, at: CGPoint(x: point.x + offset.dx, y: point.y + offset.dy))
                            }
                        }
                    }
                }
                if let track = sketch.lines.first {
                    let start = sketch.point(track.start, in: geometry.size)
                    let end = sketch.point(track.end, in: geometry.size)
                    Image(systemName: "airplane")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(palette.onAccent)
                        .padding(5)
                        .background(palette.accent, in: .circle)
                        .rotationEffect(.radians(atan2(end.y - start.y, end.x - start.x)))
                        .position(x: start.x + (end.x - start.x) * travel, y: start.y + (end.y - start.y) * travel)
                }
                VStack(spacing: 1) {
                    Image(systemName: "arrow.up")
                    Text("北")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.muted)
                .padding(8)
            }
        }
        .frame(height: 112)
        .background(palette.subtle, in: .rect(cornerRadius: 10))
        .clipped()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("跑道方向示意")
        .task(id: replay) {
            travel = reduceMotion ? 0.70 : 0.15
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.8)) { travel = 0.83 }
        }
    }
}
