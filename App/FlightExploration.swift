import SwiftUI

private enum ExplorationScope: String, CaseIterable, Identifiable {
    case mainland = "中国大陆"
    case worldwide = "全球"

    var id: Self { self }
    var preferredOrigins: [String] {
        switch self {
        case .mainland: ["SHA", "FOC", "PEK", "TFU", "CAN", "SZX"]
        case .worldwide: ["PVG", "PEK", "CAN", "HKG", "SIN", "SFO", "JFK"]
        }
    }
}

private struct ExplorationLeg: Identifiable {
    let start: Airport
    let end: Airport
    let evidence: FlightRoute
    let distance: Double

    var id: String { "\(start.id)-\(end.id)" }

    var aircraftProfile: AircraftProfile? {
        guard evidence.origin == start.id, let aircraftID = evidence.aircraftID else { return nil }
        return AircraftProfile.byID[aircraftID]
    }

    var aircraftLivery: AircraftLivery? {
        guard let aircraftProfile else { return nil }
        return AircraftLiveries.options(for: aircraftProfile).first {
            $0.operatorName == evidence.airline && ($0.category == .domestic || $0.category == .international)
        }
    }
}

@MainActor
struct FlightExploration: View {
    let library: AtlasLibrary
    let openAirport: (Airport) -> Void

    @State private var scope = ExplorationScope.mainland
    @State private var originID = "SHA"
    @State private var picksOrigin = false
    @State private var origins: [Airport] = []
    @State private var destinationFilter = ""
    @State private var activeLeg: ExplorationLeg?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("沿航线探索")
                        .font(AtlasTypography.font(.largeTitle, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("选择两座机场，观看一段从起飞到抵达的航程。")
                        .foregroundStyle(.secondary)
                }
                Picker("探索范围", selection: $scope) {
                    ForEach(ExplorationScope.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("exploration-scope")

                if let origin = library.airport(originID) {
                    Button {
                        picksOrigin = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "airplane.departure")
                                .foregroundStyle(.teal)
                                .font(.title2)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("出发机场").font(.caption).foregroundStyle(.secondary)
                                Text("\(origin.displayCode) · \(origin.displayName)")
                                    .font(AtlasTypography.font(.headline))
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(15)
                        .background(.quaternary, in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("exploration-origin")
                    legsSection(for: origin)
                }
            }
            .atlasReadingWidth()
        }
        .accessibilityIdentifier("flight-exploration")
        .task(id: scope) {
            let currentScope = scope
            await library.prepareObservedRoutes()
            guard !Task.isCancelled, currentScope == scope else { return }
            origins = library.airports.filter { hasLegs(from: $0, scope: currentScope) }
                .sorted { $0.displayCode < $1.displayCode }
            if !origins.contains(where: { $0.id == originID }) {
                originID = currentScope.preferredOrigins.first { id in origins.contains { $0.id == id } }
                    ?? origins.first?.id ?? ""
            }
        }
        .onChange(of: scope) { _, next in
            origins = []
            destinationFilter = ""
            if let preferred = next.preferredOrigins.first { originID = preferred }
        }
        .sheet(isPresented: $picksOrigin) {
            ExplorationOriginPicker(airports: origins, preferred: scope.preferredOrigins) { airport in
                originID = airport.id
                destinationFilter = ""
                picksOrigin = false
            }
        }
        .fullScreenCover(item: $activeLeg) { leg in
            FlightExplorationPlayback(leg: leg) { airport in
                activeLeg = nil
                openAirport(airport)
            }
        }
    }

    @ViewBuilder
    private func legsSection(for origin: Airport) -> some View {
        let available = legs(from: origin, scope: scope)
        let search = destinationFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = search.isEmpty ? available : available.filter { leg in
            leg.end.nameSearchTerms.contains { $0.localizedStandardContains(search) }
        }
        VStack(alignment: .leading, spacing: 12) {
            Text("目的地").font(AtlasTypography.font(.title2, weight: .bold))
            if available.count > 7 {
                TextField("搜索目的地或机场代码", text: $destinationFilter)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
            if matches.isEmpty {
                ContentUnavailableView(
                    library.isPreparingObservedRoutes ? "正在载入航线" : "当前没有对应航线",
                    systemImage: "airplane.arrival"
                )
            }
            LazyVStack(spacing: 7) {
                ForEach(matches) { leg in
                    Button {
                        activeLeg = leg
                    } label: {
                        HStack(spacing: 12) {
                            Text(leg.end.displayCode)
                                .font(.system(.headline, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.teal)
                                .frame(minWidth: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(leg.end.displayName).font(AtlasTypography.font(.subheadline, weight: .semibold))
                                    .foregroundStyle(.primary)
                                if let model = leg.aircraftProfile, let livery = leg.aircraftLivery, let airline = livery.operatorName {
                                    Text("\(airline) · \(model.displayName)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(Int(leg.distance.rounded()).formatted()) 公里")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: "play.circle")
                                .foregroundStyle(.teal)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .background(.quaternary, in: .rect(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("exploration-route-\(leg.end.id)")
                }
            }
        }
    }

    private func hasLegs(from origin: Airport, scope: ExplorationScope) -> Bool {
        if scope == .mainland && origin.countryCode != "CN" { return false }
        return library.routes(at: origin).contains { destination(of: $0, from: origin, scope: scope) != nil }
            || library.observedRoutes(at: origin).contains { destination(of: $0, from: origin, scope: scope) != nil }
    }

    private func destination(of route: FlightRoute, from origin: Airport, scope: ExplorationScope) -> Airport? {
        let otherID = route.origin == origin.id ? route.destination : route.origin
        guard route.hasVerifiedNonstop, (route.distanceKm ?? 0) > 0,
              let end = library.airport(otherID), end.id != origin.id else { return nil }
        let domestic = origin.countryCode == "CN" && end.countryCode == "CN"
        return (scope == .mainland ? domestic : !domestic) ? end : nil
    }

    private func legs(from origin: Airport, scope: ExplorationScope) -> [ExplorationLeg] {
        if scope == .mainland && origin.countryCode != "CN" { return [] }
        let localRoutes = library.routes(at: origin)
        let aircraftEvidence = localRoutes.filter { $0.origin == origin.id && $0.aircraftID != nil }
        let remaining = localRoutes.filter { $0.origin != origin.id || $0.aircraftID == nil }
        var seen: Set<String> = []
        return (aircraftEvidence + remaining + library.observedRoutes(at: origin)).compactMap { route in
            guard let end = destination(of: route, from: origin, scope: scope),
                  let distance = route.distanceKm, seen.insert(end.id).inserted else { return nil }
            return ExplorationLeg(start: origin, end: end, evidence: route, distance: distance)
        }.sorted { lhs, rhs in
            let leftHasModel = lhs.aircraftProfile != nil
            let rightHasModel = rhs.aircraftProfile != nil
            if leftHasModel != rightHasModel { return leftHasModel }
            return lhs.end.displayCode < rhs.end.displayCode
        }
    }
}

private struct ExplorationOriginPicker: View {
    let airports: [Airport]
    let preferred: [String]
    let select: (Airport) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let featured = preferred.compactMap { id in airports.first { $0.id == id } }
        let choices = search.isEmpty ? airports.filter { !preferred.contains($0.id) } : airports.filter { airport in
            airport.nameSearchTerms.contains { $0.localizedStandardContains(search) }
        }
        NavigationStack {
            List {
                if search.isEmpty && !featured.isEmpty {
                    Section("精选出发机场") { ForEach(featured, content: airportButton) }
                }
                Section(search.isEmpty ? "全部出发机场" : "搜索结果") {
                    ForEach(choices, content: airportButton)
                }
            }
            .searchable(text: $query, prompt: "机场名称或代码")
            .navigationTitle("选择出发机场")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func airportButton(_ airport: Airport) -> some View {
        Button {
            select(airport)
        } label: {
            HStack {
                Text(airport.displayCode).font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.teal)
                    .frame(minWidth: 47, alignment: .leading)
                Text(airport.displayName).foregroundStyle(.primary)
            }
        }
        .accessibilityIdentifier("exploration-origin-\(airport.id)")
    }
}

private enum ExplorationControlMode: String, CaseIterable, Identifiable {
    case automatic = "自动观览"
    case interactive = "互动飞行"
    var id: Self { self }
}

private enum ExplorationWind: String, CaseIterable, Identifiable {
    case calm = "平稳"
    case turbulence = "巡航颠簸"
    case crosswind = "进近侧风"
    case observed = "机场观测风"

    var id: Self { self }

    func effect(progress: Double, observedKnots: Double) -> Double {
        switch self {
        case .calm: 0
        case .turbulence:
            sin(max(0, min(1, (progress - 0.21) / 0.56)) * .pi) * sin(progress * 180) * 4
        case .crosswind:
            sin(max(0, min(1, (progress - 0.77) / 0.23)) * .pi) * sin(progress * 98) * 5
        case .observed:
            sin(max(0, min(1, (progress - 0.77) / 0.23)) * .pi) * sin(progress * 105) * min(6, observedKnots / 5)
        }
    }
}

private enum ExplorationCheckpoint: Int, CaseIterable {
    case rotate, gearUp, gearDown

    var timeFraction: Double {
        switch self {
        case .rotate: 0.09
        case .gearUp: 0.24
        case .gearDown: 0.79
        }
    }

    var instruction: String {
        switch self {
        case .rotate: "调高机头，准备离地。"
        case .gearUp: "已离地。收起起落架，开始巡航。"
        case .gearDown: "即将着陆。放下起落架，继续进近。"
        }
    }

    var action: String {
        switch self {
        case .rotate: "确认抬头"
        case .gearUp: "收起起落架"
        case .gearDown: "放下起落架"
        }
    }
}

private enum ExplorationPhase: Int, CaseIterable {
    case departing, cruise, approach, arrived

    init(progress: Double) {
        switch progress {
        case 1...: self = .arrived
        case 0.77...: self = .approach
        case 0.21...: self = .cruise
        default: self = .departing
        }
    }

    var title: String {
        switch self {
        case .departing: "起飞与爬升"
        case .cruise: "巡航"
        case .approach: "进近与降落"
        case .arrived: "已抵达"
        }
    }

    func commentary(_ leg: ExplorationLeg) -> String {
        switch self {
        case .departing: "现在从\(leg.start.displayName)出发，前往\(leg.end.displayName)。"
        case .cruise: "进入巡航阶段。两座机场之间的大圆距离约\(Int(leg.distance.rounded()))公里。"
        case .approach: "即将抵达\(leg.end.displayName)，体验飞机进近和降落。"
        case .arrived: "已抵达\(leg.end.displayName)。现在可以查看这座机场的资料。"
        }
    }
}

private struct FlightExplorationPlayback: View {
    let leg: ExplorationLeg
    let openAirport: (Airport) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var accumulated = 0.0
    @State private var started: Date?
    @State private var narration = false
    @State private var speaker = ExplorationNarrator()
    @State private var mode = ExplorationControlMode.automatic
    @State private var completedSteps = 0
    @State private var checkpoint: ExplorationCheckpoint?
    @State private var pitch = 0.0
    @State private var gearDown = true
    @State private var wind = ExplorationWind.calm
    @State private var observedKnots: Double?
    @State private var speed = 1.0
    @State private var referenceAirport: Airport?
    @State private var showsReality = false
    @State private var showsLiveryEditor = false
    @State private var customizedLivery: AircraftLivery?

    private let duration = 23.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 8) {
                        endpoint(leg.start, alignment: .leading)
                        Image(systemName: "arrow.right").foregroundStyle(.teal).accessibilityHidden(true)
                        endpoint(leg.end, alignment: .trailing)
                    }
                    Picker("飞行方式", selection: $mode) {
                        ForEach(ExplorationControlMode.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, _ in reset() }
                    .accessibilityIdentifier("exploration-control-mode")

                    playbackStage
                    playbackControls
                    if mode == .interactive { interactionControls }
                    flightReference
                }
                .atlasReadingWidth()
            }
            .navigationTitle("模拟航程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(narration ? "关闭语音" : "开启语音", systemImage: narration ? "speaker.wave.2.fill" : "speaker.slash") {
                        narration.toggle()
                        if narration {
                            if let checkpoint { speak(checkpoint.instruction) }
                            else { announce(ExplorationPhase(progress: elapsed(at: .now) / duration)) }
                        } else {
                            speaker.stop()
                        }
                    }
                    .accessibilityIdentifier("exploration-narration")
                }
            }
        }
        .accessibilityIdentifier("exploration-playback")
        .sheet(item: $referenceAirport) { airport in
            NavigationStack {
                AirportImagery(airport: airport)
                    .navigationTitle(airport.displayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { referenceAirport = nil } } }
            }
        }
        .sheet(isPresented: $showsLiveryEditor) {
            if let profile = leg.aircraftProfile ?? AircraftProfile.byID["a320neo"] {
                ExplorationLiveryEditor(profile: profile, baseline: leg.aircraftLivery ?? AircraftLiveries.reference) { selection in
                    let baseline = leg.aircraftLivery ?? AircraftLiveries.reference
                    customizedLivery = selection.id == baseline.id ? nil : selection
                    showsLiveryEditor = false
                }
            }
        }
        .sheet(isPresented: $showsReality) {
            NavigationStack {
                FlightExplorationReality(origin: leg.start, destination: leg.end, route: leg.evidence) { knots in
                    observedKnots = max(0, knots)
                    wind = .observed
                    showsReality = false
                }
                .navigationTitle("实际航班与天气")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsReality = false } } }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pause() }
        }
        .onDisappear { speaker.stop() }
    }

    private var nextCheckpoint: ExplorationCheckpoint? {
        guard mode == .interactive else { return nil }
        return ExplorationCheckpoint(rawValue: completedSteps)
    }

    private var playbackStage: some View {
        let reference = leg.aircraftProfile ?? (customizedLivery == nil ? nil : AircraftProfile.byID["a320neo"])
        let livery = customizedLivery ?? leg.aircraftLivery ?? AircraftLiveries.reference
        return TimelineView(.animation(minimumInterval: 1 / 30, paused: started == nil)) { clock in
            let raw = min(1, max(0, elapsed(at: clock.date) / duration))
            let progress = min(raw, nextCheckpoint?.timeFraction ?? 1)
            let phase = ExplorationPhase(progress: progress)
            let pitchEffect = reduceMotion ? 0 : wind.effect(progress: progress, observedKnots: observedKnots ?? 0)
            let shownProgress = reduceMotion ? Double(phase.rawValue) / 3 : progress
            let basePitch = mode == .interactive ? pitch : 6 * sin(progress * 2 * .pi)
            let gear = mode == .interactive ? gearDown : progress < 0.23 || progress >= 0.82
            VStack(alignment: .leading, spacing: 14) {
                if let profile = reference {
                    FlightExplorationAircraft(profile: profile, livery: livery, progress: shownProgress,
                                              pitch: basePitch + pitchEffect, gearDown: gear)
                        .frame(height: 230)
                        .clipShape(.rect(cornerRadius: 22))
                } else {
                    ExplorationSky(progress: shownProgress, airborne: !gear, pitch: basePitch + pitchEffect)
                        .frame(height: 190)
                        .accessibilityHidden(true)
                }
                ProgressView(value: progress)
                    .accessibilityLabel("航程进度")
                Text(phase.title)
                    .font(AtlasTypography.font(.title2, weight: .bold))
                    .accessibilityIdentifier("exploration-phase")
                Text(checkpoint?.instruction ?? phase.commentary(leg))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("exploration-instruction")
            }
            .onChange(of: phase) { _, next in
                if checkpoint == nil { announce(next) }
                if next == .arrived {
                    accumulated = duration
                    started = nil
                }
            }
            .onChange(of: nextCheckpoint.map { raw >= $0.timeFraction } ?? false) { _, reached in
                if reached, let step = nextCheckpoint, checkpoint == nil {
                    accumulated = step.timeFraction * duration
                    started = nil
                    checkpoint = step
                    speak(step.instruction)
                }
            }
        }
    }

    private var playbackControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { playbackButtons }
            VStack(alignment: .leading, spacing: 8) { playbackButtons }
        }
    }

    @ViewBuilder
    private var playbackButtons: some View {
        let complete = accumulated >= duration
        Button(complete ? "重新播放" : started == nil ? (accumulated == 0 ? "开始模拟" : "继续") : "暂停",
               systemImage: complete ? "arrow.counterclockwise" : started == nil ? "play.fill" : "pause.fill") {
            if started == nil {
                if complete { reset() }
                if accumulated == 0 { announce(.departing) }
                started = .now
            } else {
                pause()
            }
        }
        .buttonStyle(.glassProminent)
        .disabled(checkpoint != nil)
        .accessibilityIdentifier("exploration-playback-control")
        Menu("速度 \(Int(speed))×", systemImage: "speedometer") {
            ForEach([1.0, 2.0], id: \.self) { multiplier in
                Button("\(Int(multiplier)) 倍速", systemImage: speed == multiplier ? "checkmark" : "forward") {
                    let now = Date.now
                    accumulated = min(duration, elapsed(at: now))
                    if started != nil { started = now }
                    speed = multiplier
                }
            }
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("exploration-speed")
        if complete {
            Button("查看抵达机场", systemImage: "airplane.arrival") { openAirport(leg.end) }
                .buttonStyle(.glass)
                .accessibilityIdentifier("exploration-arrival-airport")
        }
    }

    private var interactionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("飞行操纵").font(AtlasTypography.font(.headline))
            HStack {
                Text("机头俯仰")
                Spacer()
                Text("\(Int(pitch.rounded()))°").monospacedDigit()
            }.font(.subheadline)
            Slider(value: $pitch, in: -20...20, step: 1) {
                Text("机头俯仰")
            }
            .accessibilityIdentifier("exploration-pitch")
            Picker("气流情境", selection: $wind) {
                ForEach(ExplorationWind.allCases.filter { $0 != .observed || observedKnots != nil }) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .accessibilityIdentifier("exploration-wind")
            Text(wind == .observed ? "使用机场观测风速调整进近演示。"
                  : "气流由演示情境产生。实际颠簸和侧风需以航空气象资料为准。")
                .font(.caption).foregroundStyle(.secondary)
            if let checkpoint {
                Button(checkpoint.action, systemImage: checkpoint == .rotate ? "airplane.departure" : "gearshape.fill") {
                    completeCheckpoint(checkpoint)
                }
                .buttonStyle(.glassProminent)
                .disabled(checkpoint == .rotate && pitch < 5)
                .accessibilityIdentifier("exploration-action-\(checkpoint.rawValue)")
            }
        }
        .padding(14)
        .background(.quaternary, in: .rect(cornerRadius: 17))
    }

    private var flightReference: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("航程资料").font(AtlasTypography.font(.headline))
            Text("\(Int(leg.distance.rounded()).formatted()) 公里 · 机场间大圆距离")
                .font(.subheadline.weight(.semibold))
            Text("航迹、飞行操纵与用时为演示。实际安排以航空公司及机场公布为准。")
                .font(.footnote).foregroundStyle(.secondary)
            if let profile = leg.aircraftProfile {
                Text("\(leg.evidence.airline) · \(profile.displayName)")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("exploration-aircraft-reference")
                Text(leg.aircraftLivery.map { "参考涂装 \($0.name)" } ?? "图鉴基准涂装")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if leg.evidence.origin == leg.start.id, let number = leg.evidence.flightNumber {
                Text("资料航班 \(number) · \(leg.evidence.status ?? "收录示例")")
                    .font(.subheadline)
            }
            if let customizedLivery {
                let preview = leg.aircraftProfile ?? AircraftProfile.byID["a320neo"]
                Text("\(preview?.displayName ?? "") · \(customizedLivery.name)")
                    .font(.subheadline).foregroundStyle(.teal)
                    .accessibilityIdentifier("exploration-custom-livery")
            }
            Button("自定义涂装", systemImage: "paintpalette") {
                pause()
                showsLiveryEditor = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("exploration-livery-editor")
            if let stats = leg.evidence.observedStatistics?.first {
                Text("实飞资料统计期 \(stats.observation.period)").font(.footnote).foregroundStyle(.secondary)
            }
            if let source = leg.evidence.source, let url = URL(string: source.url) {
                Link(source.title, destination: url).font(.footnote)
            }
            if DistributionPolicy.mapsAvailable, leg.start.hasCoordinates, leg.end.hasCoordinates {
                ViewThatFits(in: .horizontal) {
                    HStack { imageryButtons }
                    VStack(alignment: .leading) { imageryButtons }
                }
            }
            if DistributionPolicy.liveFlightsAvailable {
                Button("实际航班与天气", systemImage: "wind") {
                    pause()
                    showsReality = true
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("exploration-reality")
            }
        }
    }

    @ViewBuilder
    private var imageryButtons: some View {
        Button("起点实景", systemImage: "airplane.departure") {
            pause()
            referenceAirport = leg.start
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("exploration-origin-imagery")
        Button("终点实景", systemImage: "airplane.arrival") {
            pause()
            referenceAirport = leg.end
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("exploration-destination-imagery")
    }

    private func completeCheckpoint(_ step: ExplorationCheckpoint) {
        if step == .gearUp { gearDown = false }
        if step == .gearDown { gearDown = true }
        completedSteps += 1
        checkpoint = nil
        started = .now
    }

    private func reset() {
        pause()
        accumulated = 0
        completedSteps = 0
        checkpoint = nil
        pitch = 0
        gearDown = true
    }

    private func endpoint(_ airport: Airport, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(airport.displayCode).font(.system(.title2, design: .monospaced).weight(.semibold))
            Text(airport.displayName).font(AtlasTypography.font(.caption)).foregroundStyle(.secondary)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func elapsed(at date: Date) -> Double {
        accumulated + (started.map { max(0, date.timeIntervalSince($0) * speed) } ?? 0)
    }

    private func pause() {
        accumulated = min(duration, elapsed(at: .now))
        started = nil
        speaker.stop()
    }

    private func announce(_ phase: ExplorationPhase) {
        speak(phase.commentary(leg))
    }

    private func speak(_ text: String) {
        if narration { speaker.speak(text) }
    }
}

private struct ExplorationSky: View {
    let progress: Double
    let airborne: Bool
    let pitch: Double

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let start = CGPoint(x: 28, y: size.height - 35)
            let end = CGPoint(x: size.width - 28, y: size.height - 35)
            let crest = size.height * 0.39
            let mid = CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y - crest * sin(.pi * progress))
            let angle = atan2(-crest * .pi * cos(.pi * progress), end.x - start.x)
            let track = Path { path in
                path.move(to: start)
                for fraction in 1...40 {
                    let t = Double(fraction) / 40
                    path.addLine(to: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y - crest * sin(.pi * t)))
                }
            }
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.17, blue: 0.28),
                                        Color(red: 0.11, green: 0.42, blue: 0.49),
                                        Color(red: 0.15, green: 0.29, blue: 0.31)],
                               startPoint: .topLeading, endPoint: .bottom)
                Capsule()
                    .fill(.white.opacity(0.11))
                    .frame(width: size.width * 0.42, height: 9)
                    .position(x: size.width * (0.72 - progress * 0.2), y: size.height * 0.24)
                Capsule()
                    .fill(.white.opacity(0.06))
                    .frame(width: size.width * 0.31, height: 13)
                    .position(x: size.width * (0.24 - progress * 0.14), y: size.height * 0.35)
                track.stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                track.trim(from: 0, to: progress).stroke(.mint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ForEach([start, end], id: \.x) { point in
                    Circle().fill(.mint).frame(width: 7, height: 7).position(point)
                }
                Image(systemName: "airplane")
                    .font(.system(size: airborne ? 28 : 25, weight: .semibold))
                    .rotationEffect(.radians(angle) - .degrees(pitch))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                    .position(mid)
            }
        }
        .clipShape(.rect(cornerRadius: 22))
    }
}
