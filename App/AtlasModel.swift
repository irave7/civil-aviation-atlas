import RealityKit
import SwiftUI
import UIKit

struct AtlasModel {
    let root: Entity
    let parts: [AtlasPart]
    let overviewTarget: SIMD3<Float>
    let overviewDistance: Float
    let metersPerUnit: Float
    let sourceNote: String
    var context: Entity? = nil
    var stageSurface: AtlasStageSurface = .studio
    var stageGroundY: Float? = nil
}

struct AtlasPart: Identifiable {
    let id: String
    let label: String
    let symbol: String
    let detail: String
    let entity: Entity
    let focus: SIMD3<Float>
    let focusDistance: Float
    var shell: Entity? = nil
    var interior: Entity? = nil
    var section: Entity? = nil
    var explodeOffset: SIMD3<Float> = .zero
    var children: [AtlasPart] = []
    var sizeText: String? = nil
    var interiorOnly = false

    var hierarchy: [AtlasPart] { [self] + children.flatMap(\.hierarchy) }
}

@MainActor
enum AtlasGeometry {
    static func material(_ color: UIColor, roughness: Float = 0.55, metallic: Float = 0) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)
        if color.cgColor.alpha < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: Float(color.cgColor.alpha)))
        }
        return material
    }

    static func box(_ size: SIMD3<Float>, at point: SIMD3<Float>, color: UIColor, roughness: Float = 0.55, metallic: Float = 0) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material(color, roughness: roughness, metallic: metallic)])
        entity.position = point
        return entity
    }

    static func partCollider(_ part: Entity, size: SIMD3<Float>, center: SIMD3<Float> = .zero) {
        part.components.set(CollisionComponent(shapes: [.generateBox(size: size).offsetBy(translation: center)]))
        part.components.set(InputTargetComponent())
    }

    static func cylinder(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float, color: UIColor, unlit: Bool = false) -> ModelEntity {
        let direction = end - start
        let length = simd_length(direction)
        let surface: any RealityKit.Material = unlit ? UnlitMaterial(color: color) : material(color)
        let entity = ModelEntity(mesh: .generateCylinder(height: max(length, 0.0001), radius: radius), materials: [surface])
        entity.position = (start + end) * 0.5
        if length > 0.0001 {
            entity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction / length)
        }
        return entity
    }
}
