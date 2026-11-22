import SwiftUI

@MainActor
struct FlightSimulatorSession: View {
    let leg: ExplorationLeg
    let openAirport: (Airport) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("atlas.exploration.voice.v1") private var voice = ExplorationVoice.guide
    @State private var simulation = FlightSimulation()
    @State private var departure: Runway?
    @State private var arrival: Runway?
    @State private var scenario = Scenario.calm
    @State private var observedWind: ObservedWind?
    @State private var running = false
    @State private var assisted = false
    @State private var accelerated = false
    @State private var narration = false
    @State private var speaker = ExplorationNarrator()
    @State private var sheet: Panel?
    @State private var customLivery: AircraftLivery?

    private let departureOptions: [Runway]
    private let arrivalOptions: [Runway]

    init(leg: ExplorationLeg, openAirport: @escaping (Airport) -> Void) {
        self.leg = leg
        self.openAirport = openAirport
        let departures = Self.runways(at: leg.start)
        let arrivals = Self.runways(at: leg.end)
        departureOptions = departures
        arrivalOptions = arrivals
        _departure = State(initialValue: departures.first)
        _arrival = State(initialValue: arrivals.first)
    }

    private enum Panel: Identifiable {
        case weather, aircraft, paint, imagery(Airport)

        var id: String {
            switch self {
            case .weather: "weather"
            case .aircraft: "aircraft"
            case .paint: "paint"
            case .imagery(let airport): "imagery-\(airport.id)"
            }
        }
    }

    private enum Scenario: String, CaseIterable, Identifiable {
        case calm = "平稳", turbulence = "巡航颠簸", crosswind = "进近侧风", observed = "机场观测风"
        var id: Self { self }
    }

    private struct ObservedWind {
        let knots: Double
        let direction: Double?
        let station: String
    }

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }
    private var profile: AircraftProfile? { leg.aircraftProfile ?? AircraftProfile.byID["a320neo"] }
    private var originalLivery: AircraftLivery { leg.aircraftLivery ?? AircraftLiveries.reference }
    private var livery: AircraftLivery { customLivery ?? originalLivery }
    private var aircraftMarker: FlightSimulatorAircraftMarker? {
        profile.map { profile in
            FlightSimulatorAircraftMarker(profile: profile, livery: livery,
                pitch: (simulation.effectivePitch * 2).rounded() / 2,
                bank: (simulation.effectiveBank * 2).rounded() / 2, gearDown: simulation.gearDown)
        }
    }

    private var wind: FlightSimulation.Wind {
        switch scenario {
        case .calm: .calm
        case .turbulence: .turbulence
        case .crosswind: .crosswind
        case .observed:
            observedWind.map {
                let airport: FlightSimulation.WindAirport = $0.station.caseInsensitiveCompare(leg.start.icao) == .orderedSame
                    ? .departure : .arrival
                return .observed(knots: $0.knots, directionDegrees: $0.direction, airport: airport)
            } ?? .calm
        }
    }

    private var windLabel: String {
        guard scenario == .observed, let observation = observedWind else { return scenario.rawValue }
        return "\(observation.station) 观测风 · \(observation.knots.formatted()) 节"
    }

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                let size = viewport.size
                let landscapeRoom = size.width >= 600 && size.width >= size.height * 1.4
                let wide = landscapeRoom || (size.width >= 700 && !typeSize.isAccessibilitySize)
                let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    FlightSimulatorGlobe(origin: leg.start, destination: leg.end, progress: simulation.progress,
                                         aircraft: aircraftMarker, isFlying: simulation.phase != .briefing)
                        .frame(maxWidth: .infinity, maxHeight: wide ? .infinity : nil)
                        .frame(height: wide ? nil : min(330, max(145, size.height * 0.46)))
                        .layoutPriority(1)
                    controlPanel
                    .background(palette.page)
                    .frame(width: wide ? min(410, max(300, viewport.size.width * 0.34)) : nil)
                }
            }
            .background(palette.page)
            .foregroundStyle(palette.ink)
            .tint(palette.accent)
            .navigationTitle("\(leg.start.displayCode) → \(leg.end.displayCode)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.surface, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭模拟", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) { options }
            }
        }
        .accessibilityIdentifier("flight-simulator-session")
        .sheet(item: $sheet, content: panel)
        .task(id: running) {
            guard running else { return }
            let clock = ContinuousClock()
            var previous = clock.now
            while running && !Task.isCancelled {
                do { try await clock.sleep(for: .milliseconds(65)) } catch { return }
                guard running, !Task.isCancelled else { return }
                let now = clock.now
                let elapsed = previous.duration(to: now).components
                previous = now
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                if assisted { simulation.applyRecommendedControls() }
                simulation.advance(by: min(0.25, seconds) * (accelerated ? 2 : 1))
                if simulation.summary != nil || simulation.takeoffAborted { running = false }
            }
        }
        .onChange(of: scenePhase) { _, next in
            if next != .active { pause() }
        }
        .onChange(of: simulation.phase) { _, next in announce(next) }
        .onChange(of: voice) { _, _ in announce(simulation.phase) }
        .onChange(of: narration) { _, enabled in
            if enabled { announce(simulation.phase) } else { speaker.stop() }
        }
        .onChange(of: scenario) { _, _ in simulation.wind = wind }
        .onDisappear { speaker.stop() }
    }

    private var controlPanel: some View {
        ScrollViewReader { scroll in
            ScrollView {
                panelContent
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .id("simulator-panel-start")
            }
            .accessibilityIdentifier("simulator-control-scroll")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if simulation.phase == .briefing {
                    Button(action: start) {
                        Label("开始模拟飞行", systemImage: "airplane.departure")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(palette.onAccent)
                    .accessibilityIdentifier("exploration-simulator-start")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(palette.surface)
                    .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1).accessibilityHidden(true) }
                }
            }
            .onChange(of: simulation.phase) { old, next in
                if old == .briefing || next == .briefing || next == .arrived {
                    scroll.scrollTo("simulator-panel-start", anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        if simulation.phase == .briefing {
            FlightSimulatorBriefing(origin: leg.start, destination: leg.end, route: leg.evidence, distance: leg.distance,
                                    profile: profile, livery: livery, usesReferenceAircraft: leg.aircraftProfile == nil,
                                    departureRunways: departureOptions, destinationRunways: arrivalOptions,
                                    departureRunway: $departure, destinationRunway: $arrival,
                                    windLabel: windLabel, showWeather: { present(.weather) },
                                    showImagery: { present(.imagery($0)) })
        } else if let summary = simulation.summary {
            FlightSimulatorDebrief(summary: summary, destination: leg.end, restart: reset,
                                   openAirport: { openAirport(leg.end) })
        } else {
            flightControls
        }
    }

    private var flightControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(simulation.phase.title)
                    .font(AtlasTypography.font(.title2, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("simulator-phase")
                Text(simulation.instruction)
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(palette.muted)
                    .accessibilityIdentifier("simulator-instruction")
                ProgressView(value: simulation.phaseProgress)
                    .accessibilityLabel("当前阶段进度")
                    .accessibilityIdentifier("simulator-phase-progress")
                if simulation.takeoffAborted {
                    Button("返回航前准备", systemImage: "arrow.counterclockwise", action: reset)
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(palette.onAccent)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            holdButton
                            rateButton
                        }
                        VStack(alignment: .leading) {
                            holdButton
                            rateButton
                        }
                    }
                    Toggle("辅助驾驶", isOn: $assisted)
                        .accessibilityHint("按当前阶段调整模拟操纵，用于学习操作顺序")
                        .accessibilityIdentifier("simulator-assist")
                    if simulation.canGoAround {
                        Button("复飞", systemImage: "airplane.departure") { simulation.goAround() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("simulator-go-around")
                    }
                }
            }
            instrumentPanel
            if !simulation.takeoffAborted {
                manualControls
                checklist
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("simulator-flight-controls")
    }

    private var holdButton: some View {
        Button {
            if running { pause() } else { running = true }
        } label: {
            Label(running ? "暂停" : "继续", systemImage: running ? "pause.fill" : "play.fill")
                .foregroundStyle(palette.onAccent)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("simulator-pause")
    }

    private var rateButton: some View {
        Button(accelerated ? "时间 2×" : "时间 1×", systemImage: "forward") { accelerated.toggle() }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("simulator-rate")
    }

    private var instrumentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("飞行仪表").font(AtlasTypography.font(.headline, weight: .bold))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    instrument("空速", value: simulation.airspeed, unit: "kt", id: "airspeed")
                    instrument("高度", value: simulation.altitude, unit: "ft", id: "altitude")
                }
                GridRow {
                    instrument("垂直速度", value: simulation.verticalSpeed, unit: "ft/min", id: "vertical-speed")
                    instrument("坡度", value: simulation.effectiveBank, unit: "°", id: "bank")
                }
            }
            if simulation.phase == .takeoff || simulation.phase == .landing {
                let used = simulation.phase == .takeoff ? simulation.runwayUsed : simulation.landingRollM
                instrument("跑道已用", value: used, unit: "m", id: "runway-used")
            }
            if simulation.phase == .takeoff {
                Text("抬轮参考速度 \(reading(simulation.rotationSpeed)) kt")
                    .font(AtlasTypography.font(.footnote)).foregroundStyle(palette.muted)
            } else if simulation.canGoAround {
                Text("进近参考速度 \(reading(simulation.referenceApproachSpeed)) kt")
                    .font(AtlasTypography.font(.footnote)).foregroundStyle(palette.muted)
            }
            if let crosswind = simulation.crosswindKnots, let headwind = simulation.headwindKnots {
                Text("跑道风 · 顶风 \(reading(headwind)) kt · 侧风 \(reading(crosswind)) kt")
                    .font(AtlasTypography.font(.footnote)).foregroundStyle(palette.muted)
            }
        }
        .padding(13)
        .atlasPanel(palette)
    }

    private func instrument(_ label: String, value: Double, unit: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(AtlasTypography.font(.footnote)).foregroundStyle(palette.muted)
            Text("\(reading(value)) \(unit)")
                .font(palette.readout(.body, weight: .bold))
                .contentTransition(.identity)
                .foregroundStyle(palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("simulator-\(id)")
    }

    private var manualControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("操纵").font(AtlasTypography.font(.headline, weight: .bold))
            input("推力", value: $simulation.throttle, range: 0...100, unit: "%", id: "throttle")
            input("俯仰", value: $simulation.pitch, range: -20...20, unit: "°", id: "pitch")
            input("横滚", value: $simulation.bank, range: -30...30, unit: "°", id: "roll")
            LabeledContent("襟翼") {
                Picker("襟翼", selection: $simulation.flaps) {
                    ForEach(FlightSimulation.Flaps.allCases) { flap in Text(flap.title).tag(flap) }
                }
                .labelsHidden()
                .accessibilityIdentifier("simulator-flaps")
            }
            Toggle("放下起落架", isOn: $simulation.gearDown).accessibilityIdentifier("simulator-gear")
            Toggle("刹车", isOn: $simulation.brake).accessibilityIdentifier("simulator-brake")
        }
        .disabled(assisted)
        .padding(13)
        .atlasPanel(palette)
    }

    private func input(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label) \(reading(value.wrappedValue)) \(unit)")
                .font(AtlasTypography.font(.subheadline, weight: .semibold)).monospacedDigit()
                .accessibilityHidden(true)
            Slider(value: value, in: range) { Text(label) }
                .accessibilityValue("\(reading(value.wrappedValue)) \(unit)")
                .accessibilityIdentifier("simulator-\(id)")
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("阶段检查单").font(AtlasTypography.font(.headline, weight: .bold))
            ForEach(simulation.checklist) { item in
                Label(item.title, systemImage: item.complete ? "checkmark.circle.fill" : "circle")
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(item.complete ? palette.accent : palette.ink)
                    .accessibilityValue(item.complete ? "已满足" : "待完成")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .atlasPanel(palette)
    }

    private var options: some View {
        Menu("模拟选项", systemImage: "ellipsis.circle") {
            if profile != nil {
                Button("查看客机 3D", systemImage: "cube") { present(.aircraft) }
                Button("自定义涂装", systemImage: "paintpalette") { present(.paint) }
            }
            if DistributionPolicy.mapsAvailable {
                Button("出发机场实景", systemImage: "airplane.departure") { present(.imagery(leg.start)) }
                Button("抵达机场实景", systemImage: "airplane.arrival") { present(.imagery(leg.end)) }
            }
            Button(weatherTitle, systemImage: "cloud.sun") { present(.weather) }
            Toggle("航程语音", isOn: $narration)
            Picker("语音风格", selection: $voice) {
                ForEach(ExplorationVoice.allCases) { Text($0.selectorTitle).tag($0) }
            }
            if simulation.phase != .briefing {
                Button("重开航程", systemImage: "arrow.counterclockwise", action: reset)
            }
        }
        .accessibilityIdentifier("simulator-options")
    }

    private var weatherTitle: String { DistributionPolicy.liveFlightsAvailable ? "天气与实际航班" : "天气情境" }

    @ViewBuilder
    private func panel(_ item: Panel) -> some View {
        switch item {
        case .weather:
            sheetPage(weatherTitle) {
                VStack(spacing: 0) {
                    Picker("模拟天气", selection: $scenario) {
                        ForEach(Scenario.allCases.filter { $0 != .observed || observedWind != nil }) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .padding(14)
                    .accessibilityIdentifier("simulator-weather-scenario")
                    FlightExplorationReality(origin: leg.start, destination: leg.end, route: leg.evidence) { knots, direction, station in
                        observedWind = ObservedWind(knots: knots, direction: direction, station: station)
                        scenario = .observed
                        simulation.wind = wind
                        sheet = nil
                    }
                }
            }
        case .aircraft:
            if let profile {
                sheetPage("客机外观 · \(profile.modelName)") {
                    FlightExplorationAircraft(profile: profile, livery: livery, progress: simulation.progress,
                                              pitch: simulation.effectivePitch, bank: simulation.effectiveBank,
                                              gearDown: simulation.gearDown)
                }
            }
        case .paint:
            if let profile {
                ExplorationLiveryEditor(profile: profile, baseline: originalLivery) { selection in
                    customLivery = selection.id == originalLivery.id ? nil : selection
                    sheet = nil
                }
            }
        case .imagery(let airport):
            sheetPage(airport.displayName) { AirportImagery(airport: airport) }
        }
    }

    private func sheetPage<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
        }
    }

    private func present(_ panel: Panel) {
        pause()
        sheet = panel
    }

    private func makeSimulation() -> FlightSimulation {
        let startRunway = departure ?? departureOptions.first
        let endRunway = arrival ?? arrivalOptions.first
        var value = FlightSimulation(wingspanM: profile?.wingspanM, runwayLengthM: startRunway?.lengthM,
                                     originElevationFt: leg.start.elevationFt, destinationElevationFt: leg.end.elevationFt,
                                     distanceKm: leg.distance, departureRunwayHeading: startRunway?.heading,
                                     destinationRunwayHeading: endRunway?.heading, destinationRunwayLengthM: endRunway?.lengthM)
        value.wind = wind
        return value
    }

    private func start() {
        simulation = makeSimulation()
        simulation.start()
        running = true
    }

    private func reset() {
        pause()
        assisted = false
        simulation = makeSimulation()
    }

    private func pause() {
        running = false
        speaker.stop()
    }

    private func announce(_ phase: FlightSimulation.Phase) {
        guard narration else { return }
        let cue: ExplorationNarrationCue = switch phase {
        case .briefing, .takeoff: .departing
        case .climb: .gearUp
        case .cruise: .cruise
        case .approach: .approach
        case .landing: .gearDown
        case .arrived: .arrived
        }
        speaker.speak(cue, voice: voice, fallback: simulation.instruction)
    }

    private func reading(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }

    private static func runways(at airport: Airport) -> [Runway] {
        AirportSiteCatalog.runwayRecords(for: airport)
            .filter { (2...15_000).contains($0.lengthM) && $0.status?.lowercased() != "closed" }
            .sorted { lhs, rhs in lhs.lengthM == rhs.lengthM ? lhs.id < rhs.id : lhs.lengthM > rhs.lengthM }
    }
}
