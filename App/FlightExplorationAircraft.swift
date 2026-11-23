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
    var field: FlightAirfieldFrame?
    var cockpit = false
    var followZoom: CGFloat = 1
    var separateSource = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: ExplorationAircraftScene?
    @State private var loadedField: (id: String, scenery: FlightAirfieldScenery)?

    private var modelKey: String { "\(profile.id)|\(livery.id)" }
    private var scenery: FlightAirfieldScenery? { loadedField?.id == field?.sceneID ? loadedField?.scenery : nil }
    private var fraction: Double { min(1, max(0, progress)) }
    private var sourceDescription: String? {
        if field != nil { return scenery?.label ?? "三维机场" }
        return showsBackdrop ? "模拟景观" : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            canvas
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("飞行三维画面")
                .accessibilityIdentifier("simulator-exterior-canvas")
            if separateSource, let sourceDescription {
                let palette = AtlasPalette(scheme, contrast: contrast)
                Text(sourceDescription)
                    .font(AtlasTypography.font(.caption2, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.surface)
                    .accessibilityIdentifier("simulator-airfield-source")
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(["三维飞行外观", profile.displayName, livery.name,
                             field == nil ? nil : "三维机场", sourceDescription].compactMap { $0 }.joined(separator: "，"))
        .accessibilityValue(scene?.modelKey == modelKey && (field == nil || scenery != nil)
                            ? (gearDown ? "起落架放下" : "起落架收起") : "正在载入三维模型")
        .accessibilityIdentifier("exploration-aircraft-3d")
        .task(id: field?.sceneID) {
            guard let field else {
                loadedField = nil
                return
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            loadedField = (field.sceneID, FlightAirfieldScenery(airport: field.airport, runway: field.runway, route: field.route))
        }
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


    private var canvas: some View {
        GeometryReader { geometry in
            let aspect = Float(geometry.size.width / max(1, geometry.size.height))
            let drift = reduceMotion ? 0.5 : fraction
            let altitude = altitudeMeters.map { $0.isFinite ? max(0, $0) : 0 }
            ZStack {
                if showsBackdrop && (field?.visibility ?? 0) < 1 {
                    ExplorationAircraftBackdrop(progress: drift, altitudeMeters: altitude ?? 7_500 * sin(.pi * fraction))
                }
                if let field {
                    LinearGradient(colors: [Color(sceneryHex: 0x5085A8), Color(sceneryHex: 0xD0DBCF)],
                                   startPoint: .top, endPoint: .bottom)
                        .opacity(cockpit ? 1 : field.visibility)
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
                if !separateSource, let sourceDescription {
                    Text(sourceDescription)
                        .font(AtlasTypography.font(.caption2, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.66), in: .capsule)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                        .accessibilityIdentifier("simulator-airfield-source")
                }
            }
        }
        .clipped()
    }

    private func pose(_ scene: ExplorationAircraftScene, progress: Double, aspect: Float) {
        scene.pose(progress: progress, pitch: reduceMotion ? 0 : pitch, bank: reduceMotion ? 0 : bank,
                   gearDown: gearDown, flaps: flaps, animated: !reduceMotion, aspect: aspect,
                   field: field, scenery: scenery, cockpit: cockpit, zoom: Float(followZoom))
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
    private weak var installedSite: Entity?
    private var opacity: Float = 1
    private let groundClearance: Float
    private let framingCorners: [SIMD3<Float>]
    private static let fieldOfView: Float = 34

    init(modelKey: String, model: FlightAircraftExterior, length: Float, span: Float) {
        self.modelKey = modelKey
        self.length = length
        self.span = span
        aircraft = model.root
        groundClearance = max(0, -model.root.visualBounds(relativeTo: model.root).min.y)
        // Cache each component's bounds once. Its far corners carry the current aircraft's real dimensions.
        framingCorners = model.root.children.flatMap { part in
            let box = part.visualBounds(relativeTo: model.root)
            return [box.min.x, box.max.x].flatMap { x in
                [box.min.y, box.max.y].flatMap { y in [box.min.z, box.max.z].map { SIMD3(x, y, $0) } }
            }
        }
        exterior = model
        camera.camera = PerspectiveCameraComponent(
            near: 0.3, far: 24_000, fieldOfViewInDegrees: Self.fieldOfView,
            fieldOfViewOrientation: .vertical
        )
        world.addChild(camera)
        world.addChild(aircraft)
        addLight(from: [-160, 320, -240], intensity: 2_450,
                 color: UIColor(red: 1, green: 0.95, blue: 0.87, alpha: 1), castsShadow: true)
        addLight(from: [4, 3, -5], intensity: 1_300, color: UIColor(red: 0.68, green: 0.84, blue: 1, alpha: 1))
        addLight(from: [-2, 5, 5], intensity: 1_650, color: UIColor(red: 0.69, green: 0.96, blue: 1, alpha: 1))
    }

    func pose(progress: Double, pitch: Double, bank: Double, gearDown: Bool,
              flaps: FlightSimulation.Flaps, animated: Bool, aspect: Float, field: FlightAirfieldFrame?,
              scenery: FlightAirfieldScenery?, cockpit: Bool, zoom: Float) {
        if installedSite !== scenery?.root {
            installedSite?.removeFromParent()
            if let scenery { world.addChild(scenery.root) }
            installedSite = scenery?.root
            opacity = 1
        }
        let travel = Float(progress)
        let extent = max(length, span)
        aircraft.position = [length * (0.095 - travel * 0.19), extent * sin(.pi * travel) * 0.085, 0]
        let radians = Float(min(25, max(-25, pitch))) * Float.pi / 180
        let bankRadians = Float(bank) * Float.pi / 180
        aircraft.orientation = simd_quatf(angle: -radians, axis: [0, 0, 1])
            * simd_quatf(angle: bankRadians, axis: [1, 0, 0])
        exterior.update(flaps: flaps, gearDown: gearDown, animated: animated)

        aircraft.isEnabled = !cockpit
        if let field, let site = installedSite {
            // Keep the camera in aircraft coordinates and apply the inverse heading to the entire site.
            let inverseHeading = simd_quatf(angle: (field.heading + 90) * .pi / 180, axis: [0, 1, 0])
            site.orientation = inverseHeading
            site.position = inverseHeading.act(-field.position) - [0, groundClearance, 0]
            aircraft.position = .zero
            let weight = cockpit ? 1 : Float(field.visibility)
            if abs(weight - opacity) > 0.01 || (weight == 1 && weight != opacity) {
                site.components.set(OpacityComponent(opacity: weight))
                opacity = weight
            }
        }
        if cockpit {
            let eye = SIMD3<Float>(-length * 0.39, max(1.1, length * 0.04), 0)
            let forward = aircraft.orientation.act(SIMD3<Float>(-1, -0.035, 0))
            camera.look(at: eye + forward * 100, from: eye,
                        upVector: aircraft.orientation.act([0, 1, 0]), relativeTo: world)
            return
        }
        let proximity = Float(field?.visibility ?? 0)
        let direction = simd_normalize(SIMD3<Float>(0.84, 0.47 - 0.22 * proximity, -0.72))
        let right = simd_normalize(simd_cross([0, 1, 0], direction))
        let up = simd_cross(direction, right)
        let target = aircraft.position + SIMD3<Float>(0, extent * 0.04, 0)
        // Fit wing, body, tail and gear bounds inside the actual camera frustum. The nearest point
        // matters during rotation and banking. Only the camera moves, including while zooming.
        let typeWeight = pow(min(2, max(0.45, extent / 40)), 0.10)
        let coverage = min(0.82, max(0.46, 0.68 * typeWeight * zoom))
        let vertical = tan(Self.fieldOfView * .pi / 360) * coverage
        let horizontal = vertical * max(0.1, aspect)
        var distance = extent * 0.60
        for corner in framingCorners {
            let offset = aircraft.orientation.act(corner) + aircraft.position - target
            let front = simd_dot(offset, direction)
            distance = max(distance, front + abs(simd_dot(offset, right)) / horizontal,
                           front + abs(simd_dot(offset, up)) / vertical)
        }
        camera.look(at: target, from: target + direction * distance, relativeTo: world)
    }

    private func addLight(from position: SIMD3<Float>, intensity: Float, color: UIColor, castsShadow: Bool = false) {
        let light = DirectionalLight()
        light.light.color = color
        light.light.intensity = intensity
        if castsShadow {
            light.shadow = .init(shadowProjection: .fixed(zNear: 10, zFar: 900, orthographicScale: max(length, span) * 2),
                                 depthBias: 1)
        }
        light.look(at: .zero, from: position, relativeTo: nil)
        world.addChild(light)
    }
}

private struct ExplorationAircraftBackdrop: View {
    let progress: Double
    let altitudeMeters: Double

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, size in
            let altitude = min(1, altitudeMeters / 9_000)
            let horizon = size.height * (0.42 + altitude * 0.21)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Self.horizonSky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
            ))
            let haze = CGRect(x: 0, y: max(0, horizon - size.height * 0.075),
                              width: size.width, height: size.height * 0.23)
            context.fill(Path(haze), with: .linearGradient(
                Gradient(colors: [.white.opacity(0.01), .white.opacity(0.29), .white.opacity(0.01)]),
                startPoint: haze.origin, endPoint: CGPoint(x: 0, y: haze.maxY)
            ))
            drawClouds(context, size: size, opacity: 0.32 + altitude * 0.68,
                       skyline: horizon + altitude * size.height * 0.15)
        }
        .accessibilityHidden(true)
    }

    private static let horizonSky = Gradient(colors: [0x1D4F85, 0x609BC4, 0xD2E1DA, 0x628C9D].map(Color.init(sceneryHex:)))

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
