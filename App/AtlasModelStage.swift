import RealityKit
import SwiftUI
import UIKit

enum AtlasStageSurface: String {
    case studio
    case land
    case water

    var elevation: Float {
        switch self {
        case .studio: -6
        case .land: -0.025
        case .water: -0.467
        }
    }

    fileprivate var tint: UIColor {
        switch self {
        case .studio: UIColor(red: 0.24, green: 0.30, blue: 0.37, alpha: 1)
        case .land: UIColor(red: 0.35, green: 0.43, blue: 0.34, alpha: 1)
        case .water: UIColor(red: 0.125, green: 0.244, blue: 0.318, alpha: 1)
        }
    }
}

@MainActor
enum AtlasModelStage {
    static let backdrop = LinearGradient(
        colors: [Color(red: 0.082, green: 0.121, blue: 0.182), Color(red: 0.044, green: 0.069, blue: 0.104)],
        startPoint: .top, endPoint: .bottom
    )

    private static let plane = MeshResource.generatePlane(width: 1, depth: 1)
    private static var materials: [AtlasStageSurface: UnlitMaterial] = [:]

    static func make(for model: AtlasModel) -> ModelEntity? {
        let style = model.stageSurface
        guard let material = material(for: style) else { return nil }
        let ground = ModelEntity(mesh: plane, materials: [material])
        ground.name = "model-stage-surface"
        ground.position = [model.overviewTarget.x, model.stageGroundY ?? style.elevation, model.overviewTarget.z]
        let diameter = max(24, model.overviewDistance * 7.6)
        ground.scale = [diameter, 1, diameter]
        return ground
    }

    private static func material(for style: AtlasStageSurface) -> UnlitMaterial? {
        if let cached = materials[style] { return cached }
        guard let image = drawSurface(style).cgImage,
              let texture = try? TextureResource(image: image, withName: "atlas-stage-\(style.rawValue)",
                                                 options: .init(semantic: .color)) else { return nil }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        material.writesDepth = false
        materials[style] = material
        return material
    }

    private static func drawSurface(_ style: AtlasStageSurface) -> UIImage {
        let size: CGFloat = 256
        let center = CGPoint(x: size / 2, y: size / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { surface in
            let context = surface.cgContext
            let tint = style.tint
            let innerAlpha: CGFloat = style == .studio ? 0.65 : 0.93
            let colors = [innerAlpha, innerAlpha, innerAlpha * 0.6, innerAlpha * 0.20, 0]
                .map { tint.withAlphaComponent($0).cgColor }
            radial(in: context, at: center, radius: size / 2, colors: colors, stops: [0, 0.17, 0.48, 0.76, 1])

            if style == .studio {
                // A soft, grounded studio pool underneath the aircraft keeps the silhouette readable.
                context.saveGState()
                context.translateBy(x: center.x, y: center.y)
                context.scaleBy(x: 1, y: 0.54)
                let colors = [0.34, 0.13, 0].map { UIColor.black.withAlphaComponent($0).cgColor }
                radial(in: context, at: .zero, radius: 23, colors: colors, stops: [0, 0.54, 1])
                context.restoreGState()
            }
        }
    }

    private static func radial(in context: CGContext, at center: CGPoint, radius: CGFloat, colors: [CGColor], stops: [CGFloat]) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: stops)
        else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
}
