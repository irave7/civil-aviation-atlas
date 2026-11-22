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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: ExplorationAircraftScene?

    private var modelKey: String { "\(profile.id)|\(livery.id)" }
    private var fraction: Double { min(1, max(0, progress)) }

    var body: some View {
        GeometryReader { geometry in
            let aspect = Float(geometry.size.width / max(1, geometry.size.height))
            let drift = reduceMotion ? 0.5 : fraction
            let displayedPitch = reduceMotion ? 0 : pitch
            let displayedBank = reduceMotion ? 0 : bank
            ZStack {
                ExplorationAircraftBackdrop(progress: drift, altitude: sin(.pi * drift))
                if let scene, scene.modelKey == modelKey {
                    RealityView { content in
                        content.camera = .virtual
                        content.renderingEffects.motionBlur = .disabled
                        content.add(scene.world)
                        scene.pose(progress: drift, pitch: displayedPitch, bank: displayedBank, gearDown: gearDown, aspect: aspect)
                    } update: { _ in
                        scene.pose(progress: drift, pitch: displayedPitch, bank: displayedBank, gearDown: gearDown, aspect: aspect)
                    }
                    .id(modelKey)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("三维飞行外观，\(profile.displayName)，\(livery.name)")
        .accessibilityValue(gearDown ? "起落架放下" : "起落架收起")
        .accessibilityIdentifier("exploration-aircraft-3d")
        .task(id: modelKey) {
            guard scene?.modelKey != modelKey, let cabin = profile.configurations.first else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            scene = ExplorationAircraftScene(
                modelKey: modelKey,
                model: AircraftModels.make(aircraft: profile, configuration: cabin, livery: livery),
                length: Float(profile.lengthM), span: Float(profile.wingspanM)
            )
        }
    }
}

@MainActor
private final class ExplorationAircraftScene {
    let modelKey: String
    let world = Entity()

    private let camera = PerspectiveCamera()
    private let aircraft: Entity
    private let target: SIMD3<Float>
    private let landingGear: Entity?
    private let length: Float
    private let span: Float
    private var lastAspect: Float?
    private static let fieldOfView: Float = 34

    init(modelKey: String, model: AtlasModel, length: Float, span: Float) {
        self.modelKey = modelKey
        self.length = length
        self.span = span
        aircraft = model.root
        target = model.overviewTarget
        let parts = model.parts.flatMap(\.hierarchy)
        landingGear = parts.first { $0.id == "landing-gear" }?.entity
        for part in parts {
            if part.interiorOnly { part.entity.removeFromParent() }
            part.shell?.isEnabled = true
            part.interior?.removeFromParent()
            part.section?.removeFromParent()
        }
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

    func pose(progress: Double, pitch: Double, bank: Double, gearDown: Bool, aspect: Float) {
        let travel = Float(progress)
        let extent = max(length, span)
        aircraft.position = [length * (0.095 - travel * 0.19), extent * sin(.pi * travel) * 0.085, 0]
        let radians = Float(min(25, max(-25, pitch))) * Float.pi / 180
        let bankRadians = Float(bank) * Float.pi / 180
        aircraft.orientation = simd_quatf(angle: -radians, axis: [0, 0, 1])
            * simd_quatf(angle: bankRadians, axis: [1, 0, 0])
        landingGear?.isEnabled = gearDown

        guard lastAspect != aspect else { return }
        lastAspect = aspect
        let frustumFactor = 2 * tan(Self.fieldOfView * .pi / 360)
        let widthDistance = (length * 1.10 + span * 0.24) / (frustumFactor * max(0.25, aspect) * 0.82)
        let heightDistance = (span * 0.30 + length * 0.27) / (frustumFactor * 0.80)
        let distance = max(extent * 1.20, widthDistance, heightDistance)
        let direction = simd_normalize(SIMD3<Float>(-0.27, 0.28, -1))
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
    let altitude: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.12, blue: 0.23),
                         Color(red: 0.10, green: 0.33, blue: 0.48),
                         Color(red: 0.21, green: 0.50, blue: 0.53),
                         Color(red: 0.06, green: 0.19, blue: 0.27)],
                startPoint: .top, endPoint: .bottom
            )
            Canvas { context, size in
                let horizon = size.height * (0.70 + altitude * 0.16)
                let bounds = CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)
                context.fill(Path(bounds), with: .linearGradient(
                    Gradient(colors: [.black.opacity(0.02), .black.opacity(0.21)]),
                    startPoint: CGPoint(x: 0, y: horizon),
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
                for cloud in Self.clouds {
                    let x = (cloud.x - progress * cloud.speed) * size.width
                    let y = (cloud.y + altitude * 0.055) * size.height
                    let frame = CGRect(x: x, y: y, width: cloud.width * size.width, height: cloud.height * size.height)
                    context.fill(Capsule().path(in: frame), with: .linearGradient(
                        Gradient(colors: [.white.opacity(0.02), .white.opacity(cloud.opacity), .white.opacity(0.015)]),
                        startPoint: frame.origin,
                        endPoint: CGPoint(x: frame.maxX, y: frame.maxY)
                    ))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private static let clouds: [(x: Double, y: Double, width: Double, height: Double, speed: Double, opacity: Double)] = [
        (0.19, 0.22, 0.28, 0.042, 0.23, 0.10),
        (0.65, 0.34, 0.40, 0.055, 0.28, 0.15),
        (0.34, 0.71, 0.50, 0.045, 0.38, 0.23),
        (0.83, 0.62, 0.36, 0.035, 0.27, 0.13),
        (0.08, 0.83, 0.42, 0.026, 0.49, 0.14)
    ]
}
