import RealityKit
import SwiftUI
import UIKit

@MainActor
struct FlightExplorationAircraft: View {
    let profile: AircraftProfile
    let livery: AircraftLivery
    let progress: Double
    let pitch: Double
    var bank: Double = 0
    let gearDown: Bool
    var flaps: FlightSimulation.Flaps = .retracted
    var showsBackdrop = true
    var altitudeMeters: Double?
    var speedKnots: Double = 0
    var groundDistanceMeters: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: ExplorationAircraftScene?

    private var modelKey: String { "\(profile.id)|\(livery.id)" }
    private var fraction: Double { min(1, max(0, progress)) }

    var body: some View {
        GeometryReader { geometry in
            let aspect = Float(geometry.size.width / max(1, geometry.size.height))
            let drift = reduceMotion ? 0.5 : fraction
            let altitude = altitudeMeters.map { $0.isFinite ? max(0, $0) : 0 }
            ZStack {
                if showsBackdrop {
                    ExplorationAircraftBackdrop(progress: drift, altitudeMeters: altitude ?? 7_500 * sin(.pi * fraction),
                                                speedKnots: speedKnots,
                                                groundDistanceMeters: reduceMotion ? 0 : groundDistanceMeters)
                }
                if let altitude, altitude < 230 {
                    Ellipse()
                        .fill(.black.opacity(0.31 * (1 - altitude / 230)))
                        .frame(width: geometry.size.width * 0.46, height: geometry.size.height * 0.14)
                        .blur(radius: 9 + altitude * 0.025)
                        .offset(x: geometry.size.width * 0.035, y: geometry.size.height * 0.16)
                        .accessibilityHidden(true)
                }
                if let scene, scene.modelKey == modelKey {
                    RealityView { content in
                        content.camera = .virtual
                        content.renderingEffects.motionBlur = .disabled
                        content.add(scene.world)
                        pose(scene, progress: altitude == nil ? drift : 0.5, aspect: aspect)
                    } update: { _ in
                        pose(scene, progress: altitude == nil ? drift : 0.5, aspect: aspect)
                    }
                    .id(modelKey)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomLeading) {
                if showsBackdrop && altitude != nil {
                    Text("模拟景观")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.66), in: .capsule)
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("三维飞行外观，\(profile.displayName)，\(livery.name)\(showsBackdrop ? "，模拟景观" : "")")
        .accessibilityValue(scene?.modelKey == modelKey ? (gearDown ? "起落架放下" : "起落架收起") : "正在载入三维模型")
        .accessibilityIdentifier("exploration-aircraft-3d")
        .task(id: modelKey) {
            guard scene?.modelKey != modelKey, let cabin = profile.configurations.first else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            scene = ExplorationAircraftScene(
                modelKey: modelKey,
                model: AircraftModels.makeFlightExterior(aircraft: profile, configuration: cabin, livery: livery),
                length: Float(profile.lengthM), span: Float(profile.wingspanM)
            )
        }
    }

    private func pose(_ scene: ExplorationAircraftScene, progress: Double, aspect: Float) {
        scene.pose(progress: progress, pitch: reduceMotion ? 0 : pitch, bank: reduceMotion ? 0 : bank,
                   gearDown: gearDown, flaps: flaps, animated: !reduceMotion, aspect: aspect)
    }
}

@MainActor
private final class ExplorationAircraftScene {
    let modelKey: String
    let world = Entity()

    private let camera = PerspectiveCamera()
    private let aircraft: Entity
    private let exterior: FlightAircraftExterior
    private let length: Float
    private let span: Float
    private var lastAspect: Float?
    private static let fieldOfView: Float = 34

    init(modelKey: String, model: FlightAircraftExterior, length: Float, span: Float) {
        self.modelKey = modelKey
        self.length = length
        self.span = span
        aircraft = model.root
        exterior = model
        camera.camera = PerspectiveCameraComponent(
            near: 0.1, far: max(length, span) * 12, fieldOfViewInDegrees: Self.fieldOfView,
            fieldOfViewOrientation: .vertical
        )
        world.addChild(camera)
        world.addChild(aircraft)
        addLight(from: [-4, 8, -6], intensity: 2_450, color: UIColor(red: 1, green: 0.95, blue: 0.87, alpha: 1))
        addLight(from: [4, 3, -5], intensity: 1_300, color: UIColor(red: 0.68, green: 0.84, blue: 1, alpha: 1))
        addLight(from: [-2, 5, 5], intensity: 1_650, color: UIColor(red: 0.69, green: 0.96, blue: 1, alpha: 1))
    }

    func pose(progress: Double, pitch: Double, bank: Double, gearDown: Bool,
              flaps: FlightSimulation.Flaps, animated: Bool, aspect: Float) {
        let travel = Float(progress)
        let extent = max(length, span)
        aircraft.position = [length * (0.095 - travel * 0.19), extent * sin(.pi * travel) * 0.085, 0]
        let radians = Float(min(25, max(-25, pitch))) * Float.pi / 180
        let bankRadians = Float(bank) * Float.pi / 180
        aircraft.orientation = simd_quatf(angle: -radians, axis: [0, 0, 1])
            * simd_quatf(angle: bankRadians, axis: [1, 0, 0])
        exterior.update(flaps: flaps, gearDown: gearDown, animated: animated)

        guard lastAspect != aspect else { return }
        lastAspect = aspect
        let frustumFactor = 2 * tan(Self.fieldOfView * .pi / 360)
        let direction = simd_normalize(SIMD3<Float>(0.84, 0.47, -0.72))
        let lateral = simd_length(SIMD2(direction.x, direction.z))
        let width = (abs(direction.z) * length + abs(direction.x) * span) / lateral
        let depth = (abs(direction.x) * length + abs(direction.z) * span) / lateral
        let height = depth * direction.y + extent * 0.19
        let distance = max(extent * 1.18, width / (frustumFactor * max(0.28, aspect) * 0.80),
                           height / (frustumFactor * 0.72))
        let target: SIMD3<Float> = [0, extent * 0.024, 0]
        camera.look(at: target, from: target + direction * distance, relativeTo: world)
    }

    private func addLight(from position: SIMD3<Float>, intensity: Float, color: UIColor) {
        let light = DirectionalLight()
        light.light.color = color
        light.light.intensity = intensity
        light.look(at: .zero, from: position, relativeTo: nil)
        world.addChild(light)
    }
}

private struct ExplorationAircraftBackdrop: View {
    let progress: Double
    let altitudeMeters: Double
    let speedKnots: Double
    let groundDistanceMeters: Double

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, size in
            let altitude = min(1, altitudeMeters / 9_000)
            let horizon = size.height * (0.42 + altitude * 0.21)
            let groundWeight = max(0, 1 - altitudeMeters / 1_600)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Self.horizonSky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
            ))
            let haze = CGRect(x: 0, y: max(0, horizon - size.height * 0.075),
                              width: size.width, height: size.height * 0.23)
            context.fill(Path(haze), with: .linearGradient(
                Gradient(colors: [.white.opacity(0.01), .white.opacity(0.29), .white.opacity(0.01)]),
                startPoint: haze.origin, endPoint: CGPoint(x: 0, y: haze.maxY)
            ))
            if groundWeight > 0 {
                var terrain = context
                terrain.opacity = groundWeight
                drawGround(terrain, size: size, top: horizon)
            }
            drawClouds(context, size: size, opacity: 0.32 + altitude * 0.68,
                       skyline: horizon + altitude * size.height * 0.15)
        }
        .accessibilityHidden(true)
    }

    private func drawGround(_ context: GraphicsContext, size: CGSize, top: CGFloat) {
        let bottom = size.height
        let depth = bottom - top
        let field = CGRect(x: 0, y: top, width: size.width, height: depth)
        let pace = (groundDistanceMeters.isFinite ? groundDistanceMeters : 0)
            .truncatingRemainder(dividingBy: 30) / 30
        let rolling = min(1, max(0, speedKnots.isFinite ? speedKnots / 140 : 0))
        context.fill(Path(field), with: .linearGradient(
            Self.grass, startPoint: field.origin, endPoint: CGPoint(x: 0, y: bottom)
        ))

        // Bands in depth keep the ground readable at small stage sizes.
        for section in 0..<12 {
            let fraction = (Double(section) + pace) / 12
            let y = top + depth * fraction * fraction
            let height = depth * fraction * 0.036
            let strip = CGRect(x: 0, y: y, width: size.width, height: height)
            context.fill(Path(strip), with: .color(Color(sceneryHex: 0xAFB17E).opacity(0.17 - rolling * 0.05)))
        }

        let nearCenter = size.width * 0.50
        let farCenter = size.width * 0.52
        let nearSpan = size.width * 0.55
        let farSpan = nearSpan * 0.08
        func coordinate(_ rawDepth: Double, lateral: Double) -> CGPoint {
            let fraction = rawDepth * rawDepth
            return CGPoint(
                x: farCenter + (nearCenter - farCenter) * fraction + lateral * (farSpan + (nearSpan - farSpan) * fraction),
                y: top + depth * fraction
            )
        }
        func ribbon(from: Double, to: Double, left: Double, right: Double) -> Path {
            Path { path in
                path.move(to: coordinate(from, lateral: left))
                path.addLine(to: coordinate(from, lateral: right))
                path.addLine(to: coordinate(to, lateral: right))
                path.addLine(to: coordinate(to, lateral: left))
                path.closeSubpath()
            }
        }
        context.fill(ribbon(from: 0, to: 1, left: -1.08, right: 1.08), with: .color(Color(sceneryHex: 0x818075)))
        context.fill(ribbon(from: 0, to: 1, left: -1, right: 1), with: .linearGradient(
            Self.pavement, startPoint: field.origin, endPoint: CGPoint(x: 0, y: bottom)
        ))
        for side in [-1.0, 1.0] {
            context.fill(ribbon(from: 0, to: 1, left: side * 0.90 - 0.012, right: side * 0.90 + 0.012),
                         with: .color(.white.opacity(0.67)))
        }
        for stripe in 0..<11 {
            let start = max(0, (Double(stripe) + pace - 0.55) / 10)
            let end = min(1, start + 0.038)
            guard end > start else { continue }
            context.fill(ribbon(from: start, to: end, left: -0.024, right: 0.024),
                         with: .color(.white.opacity(0.82)))
        }
    }

    private static let horizonSky = Gradient(colors: [0x1D4F85, 0x609BC4, 0xD2E1DA, 0x628C9D].map(Color.init(sceneryHex:)))
    private static let grass = Gradient(colors: [0x889271, 0x53694D, 0x354F43].map(Color.init(sceneryHex:)))
    private static let pavement = Gradient(colors: [0x777C7B, 0x484F54, 0x343E42].map(Color.init(sceneryHex:)))

    private func drawClouds(_ context: GraphicsContext, size: CGSize, opacity: Double, skyline: CGFloat) {
        guard opacity > 0.015 else { return }
        for cloud in Self.clouds {
            let x = (cloud.x - progress * cloud.speed) * size.width
            let y = cloud.y * skyline
            let width = cloud.width * size.width
            let height = cloud.height * size.height
            var layer = Path()
            layer.addEllipse(in: CGRect(x: x + width * 0.10, y: y + height * 0.27, width: width * 0.72, height: height * 0.66))
            layer.addEllipse(in: CGRect(x: x + width * 0.28, y: y, width: width * 0.35, height: height * 0.91))
            layer.addEllipse(in: CGRect(x: x + width * 0.53, y: y + height * 0.06, width: width * 0.38, height: height * 0.86))
            context.fill(layer, with: .radialGradient(
                Gradient(colors: [.white.opacity(opacity * cloud.opacity), .white.opacity(0.015)]),
                center: CGPoint(x: x + width * 0.51, y: y + height * 0.48),
                startRadius: min(width, height) * 0.17, endRadius: max(width, height) * 0.46
            ))
        }
    }

    private static let clouds: [(x: Double, y: Double, width: Double, height: Double, speed: Double, opacity: Double)] = [
        (0.18, 0.20, 0.20, 0.045, 0.16, 0.43),
        (0.67, 0.31, 0.31, 0.052, 0.20, 0.51),
        (0.36, 0.69, 0.43, 0.054, 0.30, 0.55),
        (0.85, 0.59, 0.34, 0.042, 0.35, 0.58),
        (0.09, 0.87, 0.46, 0.071, 0.48, 0.48)
    ]
}

private extension Color {
    init(sceneryHex hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}
