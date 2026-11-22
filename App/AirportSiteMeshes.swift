import RealityKit
import simd

@MainActor
enum AirportSiteMeshes {
    private typealias Batch = AirportModels.BatchSet

    private struct BuildingLayer {
        let kind: AirportSiteFeature.Kind
        let id: String
        let label: String
        let symbol: String
        let detail: String
        let height: Float
        let roof: AirportModels.Paint
        let spread: SIMD3<Float>
    }

    private static let buildings = [
        BuildingLayer(kind: .terminal, id: "site-terminals", label: "航站楼", symbol: "building.2",
                      detail: "按公开轮廓重建的主楼、候机廊和卫星楼。", height: 0.17, roof: .roofWhite, spread: [0.38, 1.85, -0.41]),
        BuildingLayer(kind: .tower, id: "site-towers", label: "塔台", symbol: "antenna.radiowaves.left.and.right",
                      detail: "采用公开图层标注的空管塔台位置和外部轮廓。", height: 0.42, roof: .roofWhite, spread: [-0.39, 2.3, -0.46]),
        BuildingLayer(kind: .hangar, id: "site-hangars", label: "机库", symbol: "door.garage.closed",
                      detail: "按公开航空设施资料标注的机库轮廓重建。", height: 0.10, roof: .steel, spread: [-0.71, 1.48, 0.37]),
        BuildingLayer(kind: .building, id: "site-buildings", label: "附属建筑", symbol: "building",
                      detail: "公开机场场区内的建筑轮廓。可逐幢选择和拆分。", height: 0.07, roof: .roofCool, spread: [0.67, 1.12, 0.57])
    ]

    static func addGround(on context: Entity, plan: AirportSitePlan) {
        let bounds = plan.bounds
        let center = bounds.center
        let span = max(8, bounds.span)
        let batch = Batch()
        batch.box([span * 2.3, 0.065, span * 2.3], [center.x, -0.11, center.y], .deepWater)
        let boundaries = plan.features.filter { $0.source.kind == .boundary && $0.source.area }
        if boundaries.isEmpty {
            batch.box([max(6, bounds.size.x) + 4, 0.04, max(6, bounds.size.y) + 4], [center.x, -0.021, center.y], .islandGrass)
        }
        for boundary in boundaries {
            batch.flatPolygon(boundary.points, y: -0.001, paint: .islandGrass)
            for (index, start) in boundary.points.enumerated() {
                let end = boundary.points[(index + 1) % boundary.points.count]
                batch.line([start.x, 0, start.y], [end.x, 0, end.y], width: 0.026, height: 0.01, .coastTrim)
            }
        }
        batch.install(on: context, label: "airfield-site-ground")
    }

    static func makeParts(plan: AirportSitePlan, on root: Entity) -> [AtlasPart] {
        let lift = max(0.45, plan.bounds.span * 0.13)
        let structures = buildings.compactMap { layer in
            let features = plan.features.filter { $0.source.kind == layer.kind && ($0.source.area || layer.kind == .tower) }
            return structureGroup(layer, features: features, on: root, lift: lift)
        }
        let taxiways = plan.features.filter { $0.source.kind == .taxiway }
        let aprons = plan.features.filter { $0.source.kind == .apron && $0.source.area }
        return structures + [
            pavementGroup("site-taxiways", label: "滑行道", symbol: "line.diagonal", features: taxiways, on: root, offset: [-lift * 0.77, lift * 0.53, -lift * 0.2], taxiway: true),
            pavementGroup("site-aprons", label: "停机坪", symbol: "rectangle.split.3x1", features: aprons, on: root, offset: [lift * 0.70, lift * 0.76, lift * 0.27], taxiway: false)
        ].compactMap { $0 }
    }

    private static func structureGroup(
        _ layer: BuildingLayer, features: [AirportSitePlan.Feature], on root: Entity, lift: Float
    ) -> AtlasPart? {
        guard !features.isEmpty else { return nil }
        let entity = group(layer.id, on: root)
        let bounds = AirportSitePlan.Bounds(features.flatMap(\.points))
        let structures = features.enumerated().map { index, feature in
            let child = group("\(layer.id)-\(feature.id)", on: entity)
            let center = feature.bounds.center
            child.position = [center.x, 0, center.y]
            let sourceHeight = feature.source.documentedHeight
            let height = sourceHeight ?? layer.height
            let batch = Batch()
            if feature.source.area {
                let local = feature.points.map { $0 - center }
                let base: Float = 0.015
                let ridge = base + height
                for (pointIndex, point) in local.enumerated() {
                    let next = local[(pointIndex + 1) % local.count]
                    batch.quad([point.x, base, point.y], [next.x, base, next.y], [next.x, ridge, next.y], [point.x, ridge, point.y], .buildingWall, twoSided: true)
                    if layer.kind == .terminal || layer.kind == .tower {
                        batch.line([point.x, ridge, point.y], [next.x, ridge, next.y], width: 0.008, height: 0.007, .roofSeam)
                    }
                }
                batch.flatPolygon(local, y: ridge, paint: layer.roof)
            } else {
                batch.taper(y1: 0.009, y2: height * 0.76, radius1: 0.052, radius2: 0.038, segments: 12, paint: .steel)
                batch.taper(y1: height * 0.76, y2: height * 0.96, radius1: 0.038, radius2: 0.088, segments: 12, paint: .terminalGlass)
                batch.taper(y1: height * 0.96, y2: height, radius1: 0.088, radius2: 0.072, segments: 12, paint: .roofWhite)
            }
            batch.install(on: child, label: "public-footprint-structure")
            let size = feature.bounds.size
            AtlasGeometry.partCollider(child, size: [max(0.14, size.x), height, max(0.14, size.y)], center: [0, height / 2, 0])
            let radial = center - bounds.center
            let separation = max(0.38, min(1.3, feature.bounds.span * 0.28))
            let detail = feature.source.area ? "建筑体量依据公开轮廓重建。" : "根据公开地图标注的位置绘制塔台体量示意。"
            let heightNote = sourceHeight == nil ? "高度按同类建筑体量估算。" : "高度取自公开地图记录。"
            return AtlasPart(
                id: child.name, label: feature.source.name ?? "\(layer.label) \(index + 1)", symbol: layer.symbol,
                detail: detail + heightNote, entity: child, focus: child.position + [0, height / 2, 0],
                focusDistance: max(1.2, feature.bounds.span * 2.3, height * 2.4),
                explodeOffset: [radial.x * 0.19, separation, radial.y * 0.19]
            )
        }
        let tallest = structures.map { $0.focus.y }.max() ?? 0
        return AtlasPart(
            id: layer.id, label: layer.label, symbol: layer.symbol, detail: layer.detail,
            entity: entity, focus: [bounds.center.x, max(0.08, tallest * 0.7), bounds.center.y],
            focusDistance: max(1.6, bounds.span * 2.1, tallest * 4.65),
            explodeOffset: layer.spread * lift, children: structures
        )
    }

    private static func pavementGroup(
        _ id: String, label: String, symbol: String, features: [AirportSitePlan.Feature], on root: Entity,
        offset: SIMD3<Float>, taxiway: Bool
    ) -> AtlasPart? {
        guard !features.isEmpty else { return nil }
        let entity = group(id, on: root)
        let bounds = AirportSitePlan.Bounds(features.flatMap(\.points))
        let batch = Batch()
        for feature in features {
            if feature.source.area {
                batch.flatPolygon(feature.points, y: taxiway ? 0.015 : 0.008, paint: taxiway ? .taxiPavement : .apron)
            } else if taxiway {
                let width = max(0.04, min(1.5, Float(feature.source.widthM ?? 18) / AirportSiteCatalog.metersPerUnit))
                for (a, b) in zip(feature.points, feature.points.dropFirst()) {
                    batch.line([a.x, 0.014, a.y], [b.x, 0.014, b.y], width: width, height: 0.01, .taxiPavement)
                    batch.line([a.x, 0.020, a.y], [b.x, 0.020, b.y], width: 0.008, height: 0.002, .taxiYellow)
                }
            }
        }
        batch.install(on: entity, label: "public-pavement-layout")
        return AtlasPart(
            id: id, label: label, symbol: symbol,
            detail: taxiway ? "依据公开滑行道中线和铺装轮廓绘制。缺少宽度时采用示意宽度。" : "依据公开停机坪轮廓绘制。",
            entity: entity, focus: [bounds.center.x, 0.01, bounds.center.y],
            focusDistance: max(1.8, bounds.span * 2.25), explodeOffset: offset
        )
    }

    private static func group(_ name: String, on parent: Entity) -> Entity {
        let entity = Entity()
        entity.name = name
        parent.addChild(entity)
        return entity
    }
}
