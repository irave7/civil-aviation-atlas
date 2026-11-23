import CoreLocation
import SwiftUI

@MainActor
struct FlightSimulatorSession: View {
    let leg: ExplorationLeg
    let favorites: AtlasFavorites
    let challenge: FlightChallenge?
    let openAirport: (Airport) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("atlas.exploration.voice.v1") private var voice = ExplorationVoice.guide
    @AppStorage("atlas.simulator.narration.v1") private var narration = true
    @AppStorage("atlas.simulator.effects.v1") private var effects = true
    @AppStorage("atlas.simulator.cabin-voice.v1") private var cabinVoice = FlightCabinVoice.automatic
    @AppStorage("atlas.simulator.route-voice.v1") private var routeNarration = true
    @AppStorage(FlightChallengeProgress.key) private var completedChallenges = ""
    @State private var simulation = FlightSimulation()
    @State private var departure: Runway?
    @State private var arrival: Runway?
    @State private var scenario = Scenario.calm
    @State private var observedWind: ObservedWind?
    @State private var running = false
    @State private var assisted = true
    @State private var accelerated = false
    @State private var voiceInteraction = FlightVoiceInteraction()
    @State private var lastBroadcast: ExplorationNarrationCue?
    @State private var lastCabinBroadcast: FlightCabinVoice?
    @State private var cabinPreview: FlightCabinVoice?
    @State private var routeVoice = FlightRouteVoice()
    @State private var sound = FlightSimulatorSound()
    @State private var sheet: Panel?
    @State private var exteriorZoom: CGFloat = 1
    @GestureState private var liveExteriorMagnification: CGFloat = 1
    @State private var stageExpanded = false
    @State private var camera = Camera.map
    @State private var terrainReady: Camera?
    @State private var selectedProfile: AircraftProfile?
    @State private var customLivery: AircraftLivery?

    private let departureOptions: [Runway]
    private let arrivalOptions: [Runway]

    init(leg: ExplorationLeg, favorites: AtlasFavorites, challenge: FlightChallenge? = nil,
         openAirport: @escaping (Airport) -> Void) {
        self.leg = leg
        self.favorites = favorites
        self.challenge = challenge
        self.openAirport = openAirport
        let departures = Self.runways(at: leg.start)
        let arrivals = Self.runways(at: leg.end)
        departureOptions = departures
        arrivalOptions = arrivals
        _departure = State(initialValue: departures.first)
        _arrival = State(initialValue: arrivals.first)
        if let challenge {
            let preset: Scenario = switch challenge.wind {
            case .calm: .calm
            case .turbulence: .turbulence
            case .crosswind: .crosswind
            }
            _scenario = State(initialValue: preset)
            if leg.aircraftProfile == nil {
                _selectedProfile = State(initialValue: AircraftProfile.byID[challenge.referenceAircraft])
            }
        }
    }

    private enum Panel: Identifiable {
        case weather, aircraftType, voice, cabin, paint, imagery(Airport)

        var id: String {
            switch self {
            case .weather: "weather"
            case .aircraftType: "aircraft-type"
            case .voice: "voice"
            case .cabin: "cabin"
            case .paint: "paint"
            case .imagery(let airport): "imagery-\(airport.id)"
            }
        }
    }

    private enum Camera: String, CaseIterable, Identifiable {
        case map = "航图", cockpit = "驾驶舱", exterior = "机外"
        var id: Self { self }
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
    private var profile: AircraftProfile? { selectedProfile ?? leg.aircraftProfile ?? AircraftProfile.byID["a320neo"] }
    private var usesReferenceAircraft: Bool { profile?.id != leg.aircraftProfile?.id || leg.aircraftProfile == nil }
    private var originalLivery: AircraftLivery { (usesReferenceAircraft ? nil : leg.aircraftLivery) ?? AircraftLiveries.reference }
    private var livery: AircraftLivery { customLivery ?? originalLivery }
    private var startRunway: Runway? { departure ?? departureOptions.first }
    private var endRunway: Runway? { arrival ?? arrivalOptions.first }
    private var isArrival: Bool { [.approach, .landing, .arrived].contains(simulation.phase) }
    private var isTaxiing: Bool { simulation.groundStage == .taxiOut || simulation.groundStage == .taxiIn }
    private var activeRunwayName: String? { (isArrival ? endRunway : startRunway)?.id }
    private var allowsFlightAudio: Bool { sheet == nil || sheet?.id == Panel.voice.id }
    private var heightAboveGround: Double {
        let fieldElevation = (simulation.progress > 0.5 ? leg.end.elevationFt : leg.start.elevationFt) ?? 0
        return simulation.onGround ? 0 : max(0, (simulation.altitude - Double(fieldElevation)) * 0.3048)
    }
    private var activeCabinVoice: FlightCabinVoice? {
        switch cabinVoice {
        case .off: nil
        case .automatic:
            leg.evidence.origin == leg.start.id ? FlightCabinVoice.matching(operatorName: leg.evidence.airline) : nil
        default: cabinVoice
        }
    }

    private var aircraftMarker: FlightSimulatorAircraftMarker? {
        profile.map { profile in
            FlightSimulatorAircraftMarker(profile: profile, livery: livery,
                pitch: (simulation.effectivePitch * 2).rounded() / 2,
                bank: (simulation.effectiveBank * 2).rounded() / 2, gearDown: simulation.gearDown,
                flaps: simulation.flaps)
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
                let landscapeRoom = size.width >= 600 && size.width >= size.height * 1.40
                let wide = landscapeRoom || (size.width >= 700 && size.width >= size.height && !typeSize.isAccessibilitySize)
                let portraitStageHeight = camera == .exterior && typeSize.isAccessibilitySize
                    ? min(510, max(210, size.height * 0.60)) : min(380, max(145, size.height * 0.46))
                let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    stage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(height: wide || stageExpanded ? nil : portraitStageHeight)
                        .layoutPriority(1)
                    if !stageExpanded {
                        controlPanel
                            .background(palette.page)
                            .frame(width: wide ? min(410, max(260, size.width * 0.34)) : nil)
                            .transition(.opacity)
                    }
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    narrationButton
                    options
                }
            }
        }
        .accessibilityIdentifier("flight-simulator-session")
        .sheet(item: $sheet, content: panel)
        .onAppear {
            if simulation.phase == .briefing {
                updateBriefing()
                updateSound()
                play(.chime)
                announce()
            }
        }
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
                updateSound()
                if simulation.summary != nil || simulation.takeoffAborted { running = false }
            }
        }
        .onChange(of: scenePhase) { _, next in
            if next == .active {
                updateSound()
                if simulation.phase == .briefing && lastBroadcast == nil { announce() }
            } else {
                pause()
            }
        }
        .onChange(of: narrationCue) { _, _ in announce() }
        .onChange(of: voice) { _, _ in announce(sampleStyle: true) }
        .onChange(of: narration) { _, enabled in
            if enabled {
                announce()
            } else {
                voiceInteraction.stop(clear: true)
                lastBroadcast = nil
                lastCabinBroadcast = nil
            }
        }
        .onChange(of: scenario) { _, _ in simulation.wind = wind }
        .onChange(of: departure) { _, _ in updateBriefing() }
        .onChange(of: arrival) { _, _ in updateBriefing() }
        .onChange(of: camera) { _, _ in
            terrainReady = nil
            updateSound()
            play(.switchClick)
        }
        .onChange(of: effects) { _, _ in updateSound() }
        .onChange(of: sheet?.id) { previous, current in
            updateSound()
            if previous == Panel.cabin.id && current == nil {
                voiceInteraction.stop(clear: false)
                cabinPreview = nil
                if simulation.phase == .briefing || simulation.phase == .arrived { announce() }
            }
        }
        .onChange(of: running) { _, _ in updateSound() }
        .onChange(of: simulation.gearDown) { _, _ in play(.gear) }
        .onChange(of: simulation.flaps) { _, _ in play(.flaps) }
        .onChange(of: simulation.brake) { _, _ in play(.switchClick) }
        .onChange(of: simulation.reverseThrust) { _, active in if active { play(.reverse) } }
        .onChange(of: simulation.onGround) { _, ground in
            if ground && simulation.phase == .landing { play(.touchdown) }
        }
        .onChange(of: simulation.phase) { _, phase in
            if phase == .arrived { stageExpanded = false }
            if phase == .arrived, let challenge, simulation.summary?.landingRunwayExceeded == false {
                completedChallenges = FlightChallengeProgress.completing(challenge.id, in: completedChallenges)
            }
        }
        .onDisappear {
            voiceInteraction.stop(clear: true)
            sound.stop()
        }
    }

    private var stage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if profile != nil {
                    Picker("飞行视角", selection: $camera) {
                        ForEach(Camera.allCases) { view in Text(view.rawValue).tag(view) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("simulator-camera")
                } else {
                    Label("航图", systemImage: "map")
                        .font(AtlasTypography.font(.subheadline, weight: .semibold))
                    Spacer()
                }
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                        stageExpanded.toggle()
                    }
                } label: {
                    Image(systemName: stageExpanded
                          ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .accessibilityLabel(stageExpanded ? "显示飞行面板" : "展开飞行视图")
                .accessibilityIdentifier("simulator-expand-stage")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(palette.surface)
            stageScene
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: camera)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: terrainReady)
        }
    }

    private var stageScene: some View {
        ZStack {
            FlightSimulatorGlobe(origin: leg.start, destination: leg.end, progress: simulation.progress,
                                 aircraft: aircraftMarker, isFlying: simulation.phase != .briefing,
                                 groundPose: simulation.groundPose, departureAirStart: simulation.departureAirStart,
                                 arrivalAirEnd: simulation.arrivalAirEnd, groundTrack: simulation.groundTrack,
                                 runwayTrack: simulation.runwayTrack, isVisible: camera == .map)
                .opacity(camera == .map ? 1 : 0)
                .allowsHitTesting(camera == .map)
                .accessibilityHidden(camera != .map)
            if camera == .cockpit, let profile {
                let airportFrame = localAirfield
                FlightSimulatorCockpit(profile: profile, flight: simulation, runway: activeRunwayName,
                                       taxiing: isTaxiing, showsTerrain: airportFrame != nil || terrainReady == .cockpit,
                                       showsAirfield: airportFrame != nil) {
                    ZStack {
                        if preloadsRegionalTerrain(airportFrame) { terrain(for: .cockpit) }
                        if let airportFrame {
                            aircraftScene(profile, field: airportFrame, cockpit: true)
                                .opacity(airportFrame.visibility)
                        }
                    }
                }
                    .transition(.opacity)
            } else if camera == .exterior, let profile {
                GeometryReader { space in
                    let separate = typeSize.isAccessibilitySize || space.size.height < 180
                    VStack(spacing: 0) {
                        if separate {
                            HStack(spacing: 4) {
                                exteriorTelemetry
                                exteriorZoomButton
                            }
                            .padding(.horizontal, 6)
                            .background(palette.surface)
                        }
                        exteriorWorld(profile, separate: separate)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func exteriorWorld(_ profile: AircraftProfile, separate: Bool) -> some View {
        let field = localAirfield
        return ZStack {
            if preloadsRegionalTerrain(field) {
                terrain(for: .exterior).allowsHitTesting(false)
            }
            aircraftScene(profile, field: field, separateSource: separate)
                .allowsHitTesting(false)
                .accessibilityIdentifier("simulator-exterior-view")
        }
        .overlay {
            // The renderer and the regional imagery are behind the same gesture surface.
            // An MKMapView introduced during climb must never take the chase-camera pinch.
            Color.clear.contentShape(.rect)
                .gesture(MagnifyGesture()
                    .updating($liveExteriorMagnification) { value, live, _ in live = value.magnification }
                    .onEnded { value in exteriorZoom = boundedExteriorZoom(exteriorZoom * value.magnification) })
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            if !separate { exteriorZoomButton.padding(.trailing, 8) }
        }
        .overlay(alignment: .topLeading) {
            if !separate { exteriorTelemetry.padding(10) }
        }
    }

    private var exteriorTelemetry: some View {
        FlightExteriorOverlay(altitudeFeet: simulation.altitude, speedKnots: simulation.groundSpeedKnots)
    }

    private var exteriorZoomButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { exteriorZoom = 1 }
        } label: {
            Label(String(format: "%.2f×", effectiveExteriorZoom), systemImage: "viewfinder")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.68), in: .capsule)
                .frame(minWidth: 52, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("机外跟拍倍率")
        .accessibilityValue(String(format: "%.2f", effectiveExteriorZoom))
        .accessibilityHint("双指缩放，点按恢复标准视距")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: exteriorZoom = boundedExteriorZoom(exteriorZoom + 0.1)
            case .decrement: exteriorZoom = boundedExteriorZoom(exteriorZoom - 0.1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("simulator-exterior-zoom")
    }

    private func boundedExteriorZoom(_ value: CGFloat) -> CGFloat {
        value.isFinite ? min(1.18, max(0.72, value)) : 1
    }

    private var effectiveExteriorZoom: CGFloat { boundedExteriorZoom(exteriorZoom * liveExteriorMagnification) }

    private func aircraftScene(_ profile: AircraftProfile, field: FlightAirfieldFrame?, cockpit: Bool = false, separateSource: Bool = false) -> some View {
        FlightExplorationAircraft(profile: profile, livery: livery, progress: simulation.progress,
                                  pitch: simulation.onGround ? 0 : simulation.effectivePitch,
                                  bank: simulation.onGround ? 0 : simulation.effectiveBank,
                                  gearDown: simulation.gearDown, flaps: simulation.flaps,
                                  showsBackdrop: terrainReady != (cockpit ? .cockpit : .exterior),
                                  altitudeMeters: heightAboveGround, field: field, cockpit: cockpit, followZoom: effectiveExteriorZoom,
                                  separateSource: separateSource)
    }

    private var localAirfield: FlightAirfieldFrame? {
        let arriving = simulation.progress > 0.5
        return FlightAirfieldFrame(airport: arriving ? leg.end : leg.start,
                                  runway: arriving ? endRunway : startRunway,
                                  route: arriving ? simulation.arrivalGround : simulation.departureGround,
                                  pose: sceneryPose, flight: simulation, altitudeMeters: heightAboveGround,
                                  arriving: arriving)
    }

    private func preloadsRegionalTerrain(_ field: FlightAirfieldFrame?) -> Bool {
        (field?.visibility ?? 0) < 1 || !simulation.onGround ||
            (simulation.groundStage == .takeoffRoll && simulation.runwayUsed > 100)
    }

    @ViewBuilder
    private func terrain(for view: Camera) -> some View {
        #if !MAINLAND_DISTRIBUTION || MAINLAND_APPROVED_MAPS
        if DistributionPolicy.mapsAvailable, leg.start.hasCoordinates, leg.end.hasCoordinates {
            FlightSimulatorBackdrop(pose: sceneryPose, heightMeters: heightAboveGround,
                                    viewpoint: view == .cockpit ? .cockpit : .exterior) {
                if camera == view { terrainReady = view }
            }
            .accessibilityHidden(terrainReady != view)
            .onDisappear {
                if terrainReady == view { terrainReady = nil }
            }
        }
        #endif
    }

    private var sceneryPose: FlightGroundPose {
        if let ground = simulation.groundPose { return ground }
        let departure = simulation.departureAirStart
        let arrival = simulation.arrivalAirEnd
        let arc = FlightSimulatorArc(origin: departure?.coordinate ?? leg.start.coordinate,
                                     destination: arrival?.coordinate ?? leg.end.coordinate,
                                     departureCourse: departure?.heading, arrivalCourse: arrival?.heading)
        let point = arc.coordinate(at: simulation.progress)
        return FlightGroundPose(latitude: point.latitude, longitude: point.longitude, heading: arc.heading(at: simulation.progress))
    }

    private var controlPanel: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroll in
                ScrollView {
                    panelContent
                        .frame(maxWidth: 680, alignment: .leading)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .id("simulator-panel-start")
                }
                .clipped()
                .accessibilityIdentifier("simulator-control-scroll")
                .onChange(of: simulation.phase) { old, next in
                    if old == .briefing || next == .briefing || next == .arrived {
                        scroll.scrollTo("simulator-panel-start", anchor: .top)
                    }
                }
                .onChange(of: camera) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.20)) {
                        scroll.scrollTo("simulator-panel-start", anchor: .top)
                    }
                }
            }
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
    }

    @ViewBuilder
    private var panelContent: some View {
        if simulation.phase == .briefing {
            if let challenge { challengeBriefing(challenge) }
            if camera == .cockpit, let profile {
                FlightCockpitControls(profile: profile, assisted: false, flight: $simulation)
                    .id(profile.id)
            }
            FlightSimulatorBriefing(origin: leg.start, destination: leg.end, route: leg.evidence, distance: leg.distance,
                                    profile: profile, livery: livery, usesReferenceAircraft: usesReferenceAircraft,
                                    departureRunways: departureOptions, destinationRunways: arrivalOptions,
                                    departureRunway: $departure, destinationRunway: $arrival,
                                    guided: $assisted,
                                    windLabel: windLabel, showWeather: { present(.weather) },
                                    chooseAircraft: { present(.aircraftType) },
                                    showImagery: { present(.imagery($0)) })
        } else if let summary = simulation.summary {
            if challenge != nil {
                Label(summary.landingRunwayExceeded ? "已到达 · 可重飞挑战跑道内停稳" : "航线关卡已完成",
                      systemImage: summary.landingRunwayExceeded ? "flag" : "checkmark.circle.fill")
                    .font(AtlasTypography.font(.headline, weight: .bold))
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .atlasPanel(palette)
                    .accessibilityIdentifier("flight-challenge-result")
            }
            FlightSimulatorDebrief(summary: summary, destination: leg.end, restart: reset,
                                   openAirport: { openAirport(leg.end) })
        } else {
            flightControls
        }
    }

    private func challengeBriefing(_ challenge: FlightChallenge) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(challenge.title, systemImage: "flag.checkered")
                .font(AtlasTypography.font(.title3, weight: .bold))
                .foregroundStyle(palette.accent)
                .accessibilityAddTraits(.isHeader)
            Text(challenge.introduction).font(AtlasTypography.font(.subheadline))
            Text("完成起飞与着陆，在跑道范围内减速或滑入。\n\(challenge.wind.rawValue)")
                .font(AtlasTypography.font(.caption))
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .atlasPanel(palette)
        .accessibilityIdentifier("flight-challenge-briefing")
    }

    private var flightControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(simulation.groundStage == nil ? simulation.phase.title
                     : (isArrival ? "抵达 \(leg.end.displayCode)" : "出发 \(leg.start.displayCode)"))
                    .font(AtlasTypography.font(.title2, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("simulator-phase")
                Text(simulation.instruction)
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(palette.muted)
                    .accessibilityIdentifier("simulator-instruction")
                if let ground = simulation.groundStage {
                    Label(ground.title, systemImage: "road.lanes")
                        .font(AtlasTypography.font(.subheadline, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .accessibilityIdentifier("simulator-ground-stage")
                }
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
                            voiceButton
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) {
                            ViewThatFits(in: .horizontal) {
                                HStack { holdButton; rateButton }
                                    .fixedSize(horizontal: true, vertical: false)
                                VStack(alignment: .leading) { holdButton; rateButton }
                            }
                            voiceButton
                        }
                    }
                    Toggle("导览操作", isOn: $assisted)
                        .accessibilityHint("开启后由飞机示范操作。关闭后可以手动接手。")
                        .accessibilityIdentifier("simulator-assist")
                    if simulation.canGoAround {
                        Button("复飞", systemImage: "airplane.departure") { simulation.goAround() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("simulator-go-around")
                    }
                }
            }
            if camera != .cockpit || simulation.groundStage != nil { instrumentPanel }
            if !simulation.takeoffAborted {
                if camera == .cockpit, let profile {
                    FlightCockpitControls(profile: profile, assisted: assisted, flight: $simulation)
                        .id(profile.id)
                } else {
                    manualControls
                }
                checklist
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("simulator-flight-controls")
    }

    private var holdButton: some View {
        Button {
            if running { pause() } else {
                running = true
                announce()
            }
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
            if let ground = simulation.groundStage {
                instrument("地速", value: simulation.groundSpeedKnots, unit: "kt", id: "ground-speed")
                let distance = isTaxiing ? simulation.taxiDistanceM :
                    ground == .takeoffRoll ? simulation.runwayUsed : simulation.landingRollM
                instrument(isTaxiing ? "滑行里程" : "跑道已用", value: distance, unit: "m", id: "runway-used")
                if let source = simulation.groundSourceLabel {
                    Text(source).font(AtlasTypography.font(.footnote)).foregroundStyle(palette.muted)
                }
            } else if simulation.phase == .takeoff || simulation.phase == .landing {
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
            if simulation.canUseReverseThrust {
                Toggle("反推", isOn: $simulation.reverseThrust).accessibilityIdentifier("simulator-reverse")
            }
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
                Button("自定义涂装", systemImage: "paintpalette") { present(.paint) }
                    .accessibilityIdentifier("simulator-open-livery")
            }
            if simulation.phase == .briefing {
                Button("选择模拟机型", systemImage: "airplane") { present(.aircraftType) }
                    .accessibilityIdentifier("simulator-choose-aircraft")
            }
            if DistributionPolicy.mapsAvailable {
                Button("出发机场实景", systemImage: "airplane.departure") { present(.imagery(leg.start)) }
                Button("抵达机场实景", systemImage: "airplane.arrival") { present(.imagery(leg.end)) }
            }
            Button(weatherTitle, systemImage: "cloud.sun") { present(.weather) }
                .accessibilityIdentifier("simulator-open-weather")
            Toggle("环境与设备音效", isOn: $effects)
                .accessibilityIdentifier("simulator-effects")
            Button("语音互动", systemImage: "waveform.bubble") { sheet = .voice }
                .accessibilityIdentifier("simulator-open-voice")
            Button("航司广播", systemImage: "airplane.circle") { present(.cabin) }
                .accessibilityIdentifier("simulator-cabin-announcements")
            if simulation.phase != .briefing {
                Button("重开航程", systemImage: "arrow.counterclockwise", action: reset)
            }
        }
        .accessibilityIdentifier("simulator-options")
    }

    private var voiceButton: some View {
        Button("语音互动", systemImage: "waveform.bubble") { sheet = .voice }
            .buttonStyle(.glass)
            .accessibilityIdentifier("simulator-flight-voice")
    }

    private var narrationButton: some View {
        let status = narration ? [
            "已开启", voice.title,
            lastBroadcast.map { "最近播报 \($0.phaseLabel)" },
            lastCabinBroadcast.map { "\($0.title)广播" }
        ].compactMap { $0 }.joined(separator: "，") : "已关闭"
        return Button(narration ? "关闭语音播报" : "开启语音播报",
               systemImage: narration ? "speaker.wave.2.fill" : "speaker.slash") {
            narration.toggle()
        }
        .labelStyle(.iconOnly)
        .accessibilityIdentifier("simulator-narration")
        .accessibilityLabel("\(narration ? "关闭语音播报" : "开启语音播报")，\(status)")
        .accessibilityValue(status)
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
        case .aircraftType:
            sheetPage("选择模拟机型") {
                let aircraft = AircraftProfile.byID.values.sorted { $0.displayName < $1.displayName }
                let saved = aircraft.filter { favorites.aircraftIDs.contains($0.id) }
                List {
                    if !saved.isEmpty {
                        Section {
                            ForEach(saved, content: aircraftChoice)
                        } header: {
                            Text("收藏的机型").accessibilityIdentifier("simulator-favorite-aircraft")
                        }
                    }
                    Section(saved.isEmpty ? "全部机型" : "其他机型") {
                        ForEach(aircraft.filter { !favorites.aircraftIDs.contains($0.id) }, content: aircraftChoice)
                    }
                }
            }
        case .cabin:
            sheetPage("航司广播") { cabinSettings }
        case .voice:
            sheetPage("语音互动") {
                ScrollView {
                    VStack(spacing: 6) {
                        Picker("语音风格", selection: $voice) {
                            ForEach(ExplorationVoice.allCases) { style in
                                Text(style.selectorTitle).tag(style)
                                    .accessibilityIdentifier("simulator-voice-style-\(style.rawValue)")
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("simulator-voice-style")
                        FlightVoiceDeck(interaction: voiceInteraction, narration: $narration, voice: voice, sound: sound,
                                        questions: FlightVoiceQuestion.flightQuestions(for: simulation,
                                                    origin: leg.start.displayName, destination: leg.end.displayName))
                    }
                    .padding(14)
                }
                .accessibilityIdentifier("simulator-voice-scroll")
                .background(palette.page)
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

    private func aircraftChoice(_ aircraft: AircraftProfile) -> some View {
        Button {
            if profile?.id != aircraft.id {
                selectedProfile = aircraft
                customLivery = nil
                updateBriefing()
            }
            sheet = nil
        } label: {
            HStack {
                Text(aircraft.displayName)
                Spacer(minLength: 6)
                if profile?.id == aircraft.id { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
        }
        .accessibilityIdentifier("simulator-select-\(aircraft.id)")
        .accessibilityAddTraits(profile?.id == aircraft.id ? .isSelected : [])
    }

    private var cabinSettings: some View {
        List {
            Section {
                cabinChoice(.automatic)
                cabinChoice(.off)
                Toggle("机场情景播报", isOn: $routeNarration)
                    .accessibilityIdentifier("simulator-route-announcements")
                if let carrier = activeCabinVoice, let sample = carrier.recording(for: .briefing) {
                    Button("试听航前广播", systemImage: "play.circle") {
                        cabinPreview = nil
                        voiceInteraction.previewCabin(sample) {
                            Task { @MainActor in
                                if sheet?.id == Panel.cabin.id && activeCabinVoice == carrier { cabinPreview = carrier }
                            }
                        }
                    }
                    .accessibilityIdentifier("simulator-cabin-preview")
                    .accessibilityLabel(cabinPreview == carrier ? "试听航前广播，已播放\(carrier.title)" : "试听航前广播")
                }
            } footer: {
                Text("采用原创模拟台词和 AI 配音。机场情景播报在航前和落地后换用本次航程的台词。")
            }
            Section("国内航司 · 普通话") { ForEach(FlightCabinVoice.domestic, content: cabinChoice) }
            Section("国际航司 · 英语") { ForEach(FlightCabinVoice.international, content: cabinChoice) }
        }
        .tint(palette.accent)
    }

    private func cabinChoice(_ choice: FlightCabinVoice) -> some View {
        Button {
            voiceInteraction.stop(clear: false)
            cabinPreview = nil
            lastCabinBroadcast = nil
            cabinVoice = choice
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(choice.title)
                    if choice == .automatic {
                        let matching = FlightCabinVoice.matching(operatorName: leg.evidence.airline)
                        Text(leg.evidence.origin == leg.start.id ? matching?.title ?? "当前航线暂无航司广播" : "当前航线暂无航司广播")
                            .font(.footnote)
                            .foregroundStyle(palette.muted)
                    }
                }
                Spacer(minLength: 6)
                if cabinVoice == choice { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
        }
        .accessibilityIdentifier("simulator-cabin-\(choice.rawValue)")
        .accessibilityAddTraits(cabinVoice == choice ? .isSelected : [])
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
        let startGround = FlightGroundRoute(airport: leg.start, runway: startRunway,
                                            operation: .departure, otherAirport: leg.end)
        let endGround = FlightGroundRoute(airport: leg.end, runway: endRunway,
                                          operation: .arrival, otherAirport: leg.start)
        var value = FlightSimulation(wingspanM: profile?.wingspanM, runwayLengthM: startRunway?.lengthM,
                                     originElevationFt: leg.start.elevationFt, destinationElevationFt: leg.end.elevationFt,
                                     distanceKm: leg.distance, departureRunwayHeading: startRunway?.heading,
                                     destinationRunwayHeading: endRunway?.heading, destinationRunwayLengthM: endRunway?.lengthM,
                                     departureGround: startGround, arrivalGround: endGround)
        value.wind = wind
        return value
    }

    private func start() {
        simulation.start()
        running = true
        play(.chime)
    }

    private func updateBriefing() {
        guard simulation.phase == .briefing else { return }
        var updated = makeSimulation()
        updated.throttle = simulation.throttle
        updated.pitch = simulation.pitch
        updated.bank = simulation.bank
        updated.flaps = simulation.flaps
        updated.brake = simulation.brake
        simulation = updated
    }

    private func reset() {
        pause()
        voiceInteraction.stop(clear: true)
        routeVoice = routeVoice.nextFlight()
        lastBroadcast = nil
        lastCabinBroadcast = nil
        simulation = makeSimulation()
    }

    private func pause() {
        running = false
        voiceInteraction.stop(clear: false)
        sound.stop()
    }

    private var narrationCue: ExplorationNarrationCue {
        switch simulation.phase {
        case .briefing: .briefing
        case .takeoff: simulation.groundStage == .taxiOut ? .taxiOut : .roll
        case .climb: .gearUp
        case .cruise: .cruise
        case .approach: .approach
        case .landing:
            if simulation.groundStage == .taxiIn { .taxiIn }
            else if simulation.onGround { .touchdown }
            else { .gearDown }
        case .arrived: .arrived
        }
    }

    private func announce(sampleStyle: Bool = false) {
        guard narration, scenePhase == .active, allowsFlightAudio else { return }
        let cue = narrationCue
        let carrier = activeCabinVoice
        let cabin = sampleStyle ? nil : FlightCabinVoice.Phase(cue: cue).flatMap { carrier?.recording(for: $0) }
        let localAudio = routeNarration && !sampleStyle
            ? (cue == .briefing ? challenge?.introductionAudio : nil) ?? routeVoice.recording(for: cue, leg: leg) : nil
        let localText = routeNarration
            ? (cue == .briefing ? challenge?.introduction : nil) ?? routeVoice.spokenText(for: cue, leg: leg) : nil
        voiceInteraction.play(cue, voice: voice, text: localText ?? simulation.instruction,
                              recording: localAudio, cabin: cabin, cabinTitle: carrier?.title, sound: sound,
                              onStarted: {
                                  if narration && cue == narrationCue { lastBroadcast = cue }
                              }, onCabinStarted: {
                                  if narration && cue == narrationCue && carrier == activeCabinVoice {
                                      lastCabinBroadcast = carrier
                                  }
                              })
    }

    private func play(_ effect: FlightSimulatorSound.Effect) {
        guard effects, scenePhase == .active, allowsFlightAudio else { return }
        sound.play(effect)
    }

    private func updateSound() {
        guard effects, scenePhase == .active, allowsFlightAudio else {
            sound.stop()
            return
        }
        let audible = running || simulation.phase == .briefing || simulation.phase == .arrived
        sound.update(throttle: simulation.throttle, airspeed: simulation.airspeed, groundSpeed: simulation.groundSpeedKnots,
                     onGround: simulation.onGround, inCockpit: camera == .cockpit, running: audible)
    }

    private func reading(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }

    private static func runways(at airport: Airport) -> [Runway] {
        AirportSiteCatalog.runwayRecords(for: airport)
            .filter { (2...15_000).contains($0.lengthM) && $0.status?.lowercased() != "closed" }
            .sorted { lhs, rhs in lhs.lengthM == rhs.lengthM ? lhs.id < rhs.id : lhs.lengthM > rhs.lengthM }
    }
}
