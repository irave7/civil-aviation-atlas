import SwiftUI

@MainActor
struct FlightSimulatorCockpit<Terrain: View>: View {
    let profile: AircraftProfile
    let flight: FlightSimulation
    let runway: String?
    let taxiing: Bool
    let showsTerrain: Bool
    let showsAirfield: Bool
    @ViewBuilder let terrain: Terrain
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layout: FlightCockpitLayout { FlightCockpitLayout(profile: profile) }

    var body: some View {
        let scenery = FlightCockpitScenery(flight: flight, taxiing: taxiing)
        VStack(spacing: 0) {
            ZStack {
                terrain
                scenery
                    .animation(reduceMotion ? nil : .linear(duration: 0.07), value: scenery.animatableData)
                    .opacity(showsTerrain ? 0 : 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Canvas { context, size in
                    let frameWidth = max(9, size.width * 0.035)
                    var pillars = Path()
                    pillars.move(to: CGPoint(x: frameWidth * 0.85, y: 0))
                    pillars.addLine(to: CGPoint(x: frameWidth * 2, y: size.height))
                    pillars.move(to: CGPoint(x: size.width - frameWidth * 0.85, y: 0))
                    pillars.addLine(to: CGPoint(x: size.width - frameWidth * 2, y: size.height))
                    if layout.console != .airbusWide {
                        let center = size.width * (layout.column == .sideStick ? 0.55 : 0.50)
                        pillars.move(to: CGPoint(x: center + 4, y: 0))
                        pillars.addLine(to: CGPoint(x: center - 5, y: size.height * 0.77))
                    }
                    context.stroke(pillars, with: .color(Color(white: 0.11)), style: StrokeStyle(lineWidth: frameWidth))
                }
                .padding(.bottom, showsTerrain ? 20 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.modelName).font(.system(.headline, design: .monospaced).weight(.bold))
                    let mode = showsAirfield ? "三维机场" : (showsTerrain ? "实景地形" : "模拟前视")
                    Text(runway.map { "\($0) · \(mode)" } ?? mode)
                        .font(AtlasTypography.font(.caption))
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer(minLength: 4)
                Text("\(Int(flight.airspeed.rounded())) kt")
                    .font(.system(.headline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color(red: 0.52, green: 0.95, blue: 0.82))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(Color(white: 0.10))
        }
        .background(Color(white: 0.10))
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(profile.displayName) 驾驶舱前视")
        .accessibilityValue(showsAirfield ? "三维机场" : (showsTerrain ? "实景地形" : "模拟前视"))
        .accessibilityIdentifier("simulator-cockpit-view")
    }
}

private struct FlightCockpitScenery: View, Animatable {
    let showsPavement: Bool
    let taxiing: Bool
    var pitch: Double
    var bank: Double
    var distance: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(flight: FlightSimulation, taxiing: Bool) {
        showsPavement = flight.onGround || flight.phase == .landing
        self.taxiing = taxiing
        pitch = flight.effectivePitch
        bank = flight.effectiveBank
        distance = taxiing ? flight.taxiDistanceM : flight.runwayUsed + flight.landingRollM
    }

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(pitch, AnimatablePair(bank, distance)) }
        set { (pitch, bank, distance) = (newValue.first, newValue.second.first, newValue.second.second) }
    }

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let horizon = size.height * 0.41 + size.height * pitch / 100
            let pivot = CGPoint(x: size.width / 2, y: horizon)
            var world = context
            if !reduceMotion {
                world.translateBy(x: pivot.x, y: pivot.y)
                world.rotate(by: .degrees(-bank))
                world.translateBy(x: -pivot.x, y: -pivot.y)
            }
            let overscan = max(size.width, size.height)
            let sky = CGRect(x: -overscan, y: -overscan, width: size.width + overscan * 2, height: horizon + overscan)
            world.fill(Path(sky), with: .linearGradient(
                Gradient(colors: [Color(red: 0.18, green: 0.43, blue: 0.65), Color(red: 0.71, green: 0.85, blue: 0.91)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
            let ground = CGRect(x: -overscan, y: horizon, width: size.width + overscan * 2, height: size.height + overscan)
            world.fill(Path(ground), with: .linearGradient(
                Gradient(colors: [Color(red: 0.35, green: 0.48, blue: 0.42), Color(red: 0.22, green: 0.34, blue: 0.25)]),
                startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: size.height)))
            if showsPavement {
                drawSurface(in: world, bounds: bounds, horizon: horizon)
            } else {
                for offset in [-0.32, -0.05, 0.24] {
                    let cloud = CGRect(x: pivot.x + size.width * offset, y: horizon - 15 - abs(offset) * 22,
                                       width: size.width * 0.16, height: max(3, size.height * 0.02))
                    world.fill(Capsule().path(in: cloud), with: .color(.white.opacity(0.45)))
                }
            }
        }
    }

    private func drawSurface(in context: GraphicsContext, bounds: CGRect, horizon: CGFloat) {
        let near = bounds.maxY
        let far = horizon + max(5, bounds.height * 0.045)
        let horizonX = bounds.midX - (taxiing ? bounds.width * 0.08 : 0)
        let halfWidth = bounds.width * (taxiing ? 0.24 : 0.35)
        let nearLeft = CGPoint(x: bounds.midX - halfWidth, y: near)
        let nearRight = CGPoint(x: bounds.midX + halfWidth, y: near)
        let farLeft = CGPoint(x: horizonX - halfWidth * 0.055, y: far)
        let farRight = CGPoint(x: horizonX + halfWidth * 0.055, y: far)
        var pavement = Path()
        pavement.addLines([nearLeft, farLeft, farRight, nearRight])
        pavement.closeSubpath()
        context.fill(pavement, with: .color(Color(white: 0.29)))
        for (start, end) in [(nearLeft, farLeft), (nearRight, farRight)] {
            var edge = Path()
            edge.addLines([start, end])
            context.stroke(edge, with: .color(.white.opacity(0.76)), lineWidth: 1.4)
        }
        let travel = reduceMotion ? 0 : distance.truncatingRemainder(dividingBy: 30) / 30
        for index in 0..<10 {
            let fraction = (Double(index) + travel) / 10
            let start = perspective(fraction, near: near, far: far, center: bounds.midX, horizonX: horizonX)
            let end = perspective(min(1, fraction + 0.045), near: near, far: far, center: bounds.midX, horizonX: horizonX)
            var stripe = Path()
            stripe.addLines([start, end])
            context.stroke(stripe, with: .color(taxiing ? .yellow : .white), lineWidth: max(0.7, fraction * 3))
        }
    }

    private func perspective(_ fraction: Double, near: CGFloat, far: CGFloat, center: CGFloat, horizonX: CGFloat) -> CGPoint {
        let v = fraction * fraction
        return CGPoint(x: horizonX + (center - horizonX) * v, y: far + (near - far) * v)
    }
}

@MainActor
struct FlightCockpitControls: View {
    let profile: AircraftProfile
    let assisted: Bool
    @Binding var flight: FlightSimulation
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedScreen = FlightCockpitLayout.Screen.attitude

    private var layout: FlightCockpitLayout { FlightCockpitLayout(profile: profile) }
    private let instrumentInk = Color(red: 0.55, green: 0.96, blue: 0.83)
    private var panel: Color {
        switch layout.console {
        case .airbus: Color(red: 0.13, green: 0.19, blue: 0.25)
        case .airbusWide: Color(red: 0.10, green: 0.17, blue: 0.22)
        case .boeingClassic: Color(red: 0.23, green: 0.19, blue: 0.17)
        case .boeingDigital: Color(red: 0.18, green: 0.21, blue: 0.23)
        case .regional: Color(red: 0.20, green: 0.21, blue: 0.22)
        case .comac: Color(red: 0.11, green: 0.19, blue: 0.22)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("\(profile.modelName) 驾驶舱")
                .font(AtlasTypography.font(.headline, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text("\(layout.family) · \(layout.column.rawValue)")
                .font(AtlasTypography.font(.subheadline))
                .foregroundStyle(.white.opacity(0.78))
            instrumentPanel
            console
                .disabled(assisted)
            Text("按公开的机型布局重绘。仪表和开关联动本航程。")
                .font(AtlasTypography.font(.footnote))
                .foregroundStyle(.white.opacity(0.77))
            if let reference = layout.reference {
                Link("查看布局资料", destination: reference)
                    .font(AtlasTypography.font(.footnote, weight: .semibold))
                    .foregroundStyle(instrumentInk)
            }
        }
        .foregroundStyle(.white)
        .tint(instrumentInk)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panel, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("simulator-cockpit-controls")
    }

    private var instrumentPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 136 : 93), spacing: 6)], spacing: 6) {
                ForEach(layout.screens) { screen in
                    Button {
                        selectedScreen = screen
                    } label: {
                        Text(screen.rawValue)
                            .font(AtlasTypography.font(.caption, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(selectedScreen == screen ? instrumentInk.opacity(0.18) : .black.opacity(0.28),
                                        in: .rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedScreen == screen ? .isSelected : [])
                    .accessibilityIdentifier("cockpit-display-\(screen)")
                }
            }
            if selectedScreen == .attitude {
                attitudeIndicator
            } else {
                Text(displayReadout)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(instrumentInk)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .accessibilityIdentifier("cockpit-display-readout")
            }
        }
        .padding(9)
        .background(Color(white: 0.065), in: .rect(cornerRadius: 10))
    }

    private var attitudeIndicator: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let reach = max(size.width, size.height) * 2
                let pitchScale = size.height / 45
                var horizon = context
                horizon.translateBy(x: center.x, y: center.y)
                horizon.rotate(by: .degrees(-flight.effectiveBank))
                horizon.translateBy(x: 0, y: flight.effectivePitch * pitchScale)
                horizon.fill(Path(CGRect(x: -reach, y: -reach, width: reach * 2, height: reach)),
                             with: .color(Color(red: 0.14, green: 0.37, blue: 0.56)))
                horizon.fill(Path(CGRect(x: -reach, y: 0, width: reach * 2, height: reach)),
                             with: .color(Color(red: 0.44, green: 0.32, blue: 0.22)))
                var ladder = Path()
                for angle in stride(from: -30, through: 30, by: 5) {
                    let y = -CGFloat(angle) * pitchScale
                    let width: CGFloat = angle == 0 ? reach : (angle.isMultiple(of: 10) ? 18 : 9)
                    ladder.move(to: CGPoint(x: -width, y: y))
                    ladder.addLine(to: CGPoint(x: width, y: y))
                }
                horizon.stroke(ladder, with: .color(.white.opacity(0.85)), lineWidth: 1)
                var wings = Path()
                for sign: CGFloat in [-1, 1] {
                    wings.move(to: CGPoint(x: center.x + sign * 30, y: center.y))
                    wings.addLine(to: CGPoint(x: center.x + sign * 10, y: center.y))
                    wings.addLine(to: CGPoint(x: center.x + sign * 6, y: center.y + 4))
                }
                context.stroke(wings, with: .color(.black.opacity(0.6)), lineWidth: 4.5)
                context.stroke(wings, with: .color(.yellow), lineWidth: 2)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)),
                             with: .color(.yellow))
            }
            .frame(height: 82)
            .clipShape(.rect(cornerRadius: 6))
            .accessibilityHidden(true)
            Text("\(read(flight.airspeed)) kt  ·  \(read(flight.altitude)) ft\n俯仰 \(read(flight.effectivePitch))°  ·  坡度 \(read(flight.effectiveBank))°")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(instrumentInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("cockpit-display-readout")
        }
    }

    private var displayReadout: String {
        switch selectedScreen {
        case .attitude: ""
        case .navigation: "航程 \(Int(flight.progress * 100))%\n\(flight.phase.title)"
        case .engines:
            (1...layout.engines).map { "发动机 \($0)  \(read(flight.throttle))%" }.joined(separator: "\n")
        case .systems: "\(flight.gearDown ? "起落架放下" : "起落架收起") · 襟翼\(flight.flaps.title)\n\(flight.brake ? "刹车已设" : "刹车已松")"
        case .standby: "\(read(flight.airspeed)) kt\n\(read(flight.altitude)) ft"
        case .flightData: "垂直速度 \(read(flight.verticalSpeed)) ft/min\n地速 \(read(flight.groundSpeedKnots)) kt"
        }
    }

    private var console: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlColumn(column: layout.column, pitch: $flight.pitch, bank: $flight.bank)
            VStack(alignment: .leading, spacing: 6) {
                Text("推力 \(read(flight.throttle))%").font(AtlasTypography.font(.subheadline, weight: .semibold))
                throttleQuadrant
                Slider(value: $flight.throttle, in: 0...100) { Text("推力") }
                    .accessibilityIdentifier("cockpit-throttle")
                    .accessibilityValue("\(read(flight.throttle))%")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("襟翼卡位").font(AtlasTypography.font(.subheadline, weight: .semibold))
                Picker("襟翼卡位", selection: $flight.flaps) {
                    ForEach(FlightSimulation.Flaps.allCases) { flap in Text(flap.title).tag(flap) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("cockpit-flaps")
            }
            deckSwitch("起落架", systemImage: "arrow.down.to.line", active: flight.gearDown, id: "gear") {
                flight.gearDown.toggle()
            }
            .disabled(flight.onGround && flight.gearDown)
            deckSwitch("驻车刹车", systemImage: "parkinglight", active: flight.brake, id: "brake") {
                flight.brake.toggle()
            }
            if flight.canUseReverseThrust {
                deckSwitch("反推", systemImage: "arrow.uturn.backward", active: flight.reverseThrust, id: "reverse") {
                    flight.reverseThrust.toggle()
                }
            }
        }
    }

    private var throttleQuadrant: some View {
        GeometryReader { geometry in
            let travel = max(0, geometry.size.height - 15)
            HStack(spacing: 5) {
                ForEach(0..<layout.engines, id: \.self) { _ in
                    Capsule().fill(.black.opacity(0.55))
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(.linearGradient(colors: [.white.opacity(0.92), .gray], startPoint: .top, endPoint: .bottom))
                                .frame(height: 15)
                                .offset(y: -travel * flight.throttle / 100)
                        }
                }
            }
            .padding(.horizontal, 10)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                flight.throttle = min(100, max(0, 100 * (geometry.size.height - value.location.y) / geometry.size.height))
            })
        }
        .frame(maxWidth: 160)
        .frame(height: 58)
        .padding(5)
        .background(.black.opacity(0.18), in: .rect(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func deckSwitch(_ label: String, systemImage: String, active: Bool, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: systemImage)
                Spacer(minLength: 7)
                Text(active ? "已设" : "解除")
                    .font(AtlasTypography.font(.caption, weight: .semibold))
                    .foregroundStyle(active ? instrumentInk : .white.opacity(0.74))
            }
            .font(AtlasTypography.font(.subheadline, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(minHeight: 44)
            .background(.black.opacity(0.26), in: .rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityValue(active ? "已设" : "解除")
        .accessibilityIdentifier("cockpit-\(id)")
    }

    private func read(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
}

private struct ControlColumn: View {
    let column: FlightCockpitLayout.Column
    @Binding var pitch: Double
    @Binding var bank: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(column.rawValue).font(AtlasTypography.font(.subheadline, weight: .semibold))
            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.32))
                    Image(systemName: column == .sideStick ? "joystick" : "steeringwheel")
                        .font(.system(size: 32, weight: .semibold))
                        .rotationEffect(.degrees(column == .sideStick ? 0 : bank))
                        .position(x: center.x + bank * 0.82, y: center.y - pitch * 0.70)
                }
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0).onChanged { touch in
                    bank = min(30, max(-30, (touch.location.x - center.x) * 60 / geometry.size.width))
                    pitch = min(20, max(-20, (center.y - touch.location.y) * 40 / geometry.size.height))
                })
            }
            .frame(maxWidth: 170)
            .frame(height: 72)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            Slider(value: $pitch, in: -20...20) { Text("俯仰") }
                .accessibilityIdentifier("cockpit-pitch")
            Slider(value: $bank, in: -30...30) { Text("横滚") }
                .accessibilityIdentifier("cockpit-bank")
        }
    }
}
