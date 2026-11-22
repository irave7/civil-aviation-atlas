import RealityKit
import SwiftUI
import UIKit

struct FlightSimulatorAircraftMarker: Equatable {
    let profile: AircraftProfile
    let livery: AircraftLivery
    let pitch: Double
    let bank: Double
    let gearDown: Bool
    var flaps: FlightSimulation.Flaps = .retracted
}

@MainActor
struct FlightSimulatorMapAircraft: View {
    let marker: FlightSimulatorAircraftMarker
    let heading: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: FlightMapAircraftScene?

    private var key: FlightMapAircraftScene.Key {
        .init(profileID: marker.profile.id, palette: marker.livery.palette)
    }

    var body: some View {
        GeometryReader { geometry in
            let aspect = Float(geometry.size.width / max(1, geometry.size.height))
            ZStack {
                Ellipse()
                    .fill(.black.opacity(0.25))
                    .frame(width: geometry.size.width * 0.66, height: geometry.size.height * 0.53)
                    .blur(radius: 5)
                if let scene, scene.key == key {
                    let pitch = reduceMotion ? 0 : marker.pitch
                    let bank = reduceMotion ? 0 : marker.bank
                    RealityView { content in
                        content.camera = .virtual
                        content.renderingEffects.motionBlur = .disabled
                        content.add(scene.world)
                        scene.update(heading: heading, pitch: pitch, bank: bank, gearDown: marker.gearDown,
                                     flaps: marker.flaps, animated: !reduceMotion, aspect: aspect)
                    } update: { _ in
                        scene.update(heading: heading, pitch: pitch, bank: bank, gearDown: marker.gearDown,
                                     flaps: marker.flaps, animated: !reduceMotion, aspect: aspect)
                    }
                    .id(key)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("地图客机三维模型，\(marker.profile.displayName)，\(marker.livery.name)")
                    .accessibilityValue(marker.gearDown ? "起落架放下" : "起落架收起")
                    .accessibilityIdentifier("simulator-map-aircraft-3d")
                } else {
                    Image(systemName: "airplane")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(heading - 90))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .task(id: key) {
            guard scene?.key != key, let configuration = marker.profile.configurations.first else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            scene = FlightMapAircraftScene(key: key, profile: marker.profile, configuration: configuration,
                                          livery: marker.livery)
        }
    }
}

@MainActor
private final class FlightMapAircraftScene {
    struct Key: Hashable {
        let profileID: String
        let palette: AircraftLivery.Palette
    }

    let key: Key
    let world = Entity()

    private let camera = PerspectiveCamera()
    private let aircraft: Entity
    private let exterior: FlightAircraftExterior
    private let extent: Float
    private var lastAspect: Float?
    private static let fieldOfView: Float = 36

    init(key: Key, profile: AircraftProfile, configuration: AircraftConfiguration, livery: AircraftLivery) {
        self.key = key
        exterior = AircraftModels.makeFlightExterior(aircraft: profile, configuration: configuration, livery: livery)
        aircraft = exterior.root
        extent = Float(max(profile.wingspanM, profile.lengthM))
        camera.camera = PerspectiveCameraComponent(near: 0.1, far: extent * 8,
            fieldOfViewInDegrees: Self.fieldOfView, fieldOfViewOrientation: .vertical)
        world.addChild(aircraft)
        world.addChild(camera)
        addLight(at: [-4, 8, -3], intensity: 3_300, color: .white)
        addLight(at: [4, 3, 5], intensity: 2_150, color: UIColor(red: 0.83, green: 0.94, blue: 1, alpha: 1))
    }

    func update(heading: Double, pitch: Double, bank: Double, gearDown: Bool,
                flaps: FlightSimulation.Flaps, animated: Bool, aspect: Float) {
        let radians = Float.pi / 180
        let yaw = simd_quatf(angle: -Float(heading + 90) * radians, axis: [0, 1, 0])
        let pitch = simd_quatf(angle: -Float(pitch) * radians, axis: [0, 0, 1])
        let roll = simd_quatf(angle: Float(bank) * radians, axis: [1, 0, 0])
        aircraft.orientation = yaw * pitch * roll
        exterior.update(flaps: flaps, gearDown: gearDown, animated: animated)

        guard aspect != lastAspect else { return }
        lastAspect = aspect
        let frustum = 2 * tan(Self.fieldOfView * .pi / 360)
        let distance = extent * 1.18 / (frustum * min(1, max(0.4, aspect)))
        let target = SIMD3<Float>(0, extent * 0.012, 0)
        let direction = simd_normalize(SIMD3<Float>(0, 1, 0.32))
        camera.look(at: target, from: target + direction * distance, relativeTo: world)
    }

    private func addLight(at position: SIMD3<Float>, intensity: Float, color: UIColor) {
        let light = DirectionalLight()
        light.light.intensity = intensity
        light.light.color = color
        light.look(at: .zero, from: position, relativeTo: nil)
        world.addChild(light)
    }
}
