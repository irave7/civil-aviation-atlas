import Foundation
import RealityKit

@MainActor
enum AirportTerrainModels {
    static func make(for airport: Airport) -> AtlasModel {
        let root = Entity()
        root.name = "airport-site"
        let terrain = Entity()
        terrain.name = "site-terrain"
        root.addChild(terrain)
        let grid = AirportSiteCatalog.terrain(for: airport)
        let horizontal = Float(grid?.halfSpanM ?? 1_500) / AirportSiteCatalog.metersPerUnit
        let minimum = grid?.elevationsM.min() ?? 0
        let midpoint = grid.map { $0.elevationsM[$0.elevationsM.count / 2] } ?? minimum
        let centerAltitude = Float(midpoint - minimum) / AirportSiteCatalog.metersPerUnit
        let earth = AirportModels.BatchSet()
        earth.box([horizontal * 2.03, 0.29, horizontal * 2.03], [0, -0.19, 0], .deepWater)
        if let grid {
            drawTerrain(grid, halfSpan: horizontal, minimum: minimum, batch: earth, collisionEntity: terrain)
        } else {
            earth.box([horizontal * 2, 0.055, horizontal * 2], [0, -0.036, 0], .islandGrass)
        }
        earth.install(on: terrain, label: "airport-reference-terrain")

        let local = Entity()
        local.name = "site-location"
        local.position = [0, centerAltitude, 0]
        root.addChild(local)
        let mark = AirportModels.BatchSet()
        mark.taper(y1: 0, y2: 0.028, radius1: 0.63, radius2: 0.63, segments: 24, paint: .terminalGlass)
        mark.taper(y1: 0.028, y2: 0.039, radius1: 0.48, radius2: 0.48, segments: 24, paint: .roofWhite)
        mark.taper(y1: 0.039, y2: 0.07, radius1: 0.31, radius2: 0.31, segments: 18, paint: .navy)
        mark.taper(y1: 0.055, y2: 0.73, radius1: 0.026, radius2: 0.026, segments: 12, paint: .roofWhite)
        mark.taper(y1: 0.73, y2: 0.99, radius1: 0.049, radius2: 0.20, segments: 12, paint: .amber)
        mark.taper(y1: 0.99, y2: 1.13, radius1: 0.20, radius2: 0.024, segments: 12, paint: .amber)
        mark.install(on: local, label: "published-airport-reference-point")
        AtlasGeometry.partCollider(local, size: [1.26, 1.13, 1.26], center: [0, 0.565, 0])

        let elevation = airport.elevationFt.map { " · 场址海拔 \(Int((Double($0) * 0.3048).rounded())) 米" } ?? ""
        let referencePosition = "\(airport.lat.formatted(.number.precision(.fractionLength(5))))°, \(airport.lon.formatted(.number.precision(.fractionLength(5))))°\(elevation)"
        let parts = [
            AtlasPart(id: terrain.name, label: grid == nil ? "场址基准面" : "场址地形", symbol: "mountain.2",
                      detail: grid == nil ? "按公开坐标显示机场位置。" : "根据开放高程数据绘制，反映机场周边的大尺度起伏。",
                      entity: terrain, focus: [0, centerAltitude * 0.6, 0], focusDistance: horizontal * 3.3),
            AtlasPart(id: local.name, label: "机场参考点", symbol: "mappin.circle",
                      detail: "参考点采用 OurAirports 机场坐标。点状标记表示公开场址位置。",
                      entity: local, focus: local.position + [0, 0.36, 0], focusDistance: 4.4,
                      explodeOffset: [0, max(1, horizontal * 0.30), 0], sizeText: referencePosition)
        ]
        let note = grid == nil
            ? "机场坐标来自 OurAirports。场址用基准面和位置标记呈现。请切换「卫星实景」查看在线影像。"
            : "地形由开放高程栅格生成，场址位置来自 OurAirports。此机场以地形与位置为主，跑道和建筑可切换「卫星实景」查看。"
        return AtlasModel(root: root, parts: parts, overviewTarget: [0, centerAltitude * 0.55, 0],
                          overviewDistance: horizontal * 3.6, metersPerUnit: grid == nil ? 0 : AirportSiteCatalog.metersPerUnit,
                          sourceNote: note, stageSurface: .land, stageGroundY: -0.14)
    }

    private static func drawTerrain(
        _ grid: AirportTerrainGrid, halfSpan: Float, minimum: Int, batch: AirportModels.BatchSet, collisionEntity: Entity
    ) {
        let step = 2 * halfSpan / Float(grid.size - 1)
        let range = max(24, (grid.elevationsM.max() ?? minimum) - minimum)
        let vertices: [SIMD3<Float>] = grid.elevationsM.enumerated().map { index, height in
            let row = index / grid.size
            let column = index % grid.size
            let y = Float(height - minimum) / AirportSiteCatalog.metersPerUnit
            return [-halfSpan + Float(column) * step, y, -halfSpan + Float(row) * step]
        }
        var indices: [UInt16] = []
        for row in 0..<(grid.size - 1) {
            for column in 0..<(grid.size - 1) {
                let start = row * grid.size + column
                let nextRow = start + grid.size
                let a = vertices[start]
                let b = vertices[start + 1]
                let c = vertices[nextRow + 1]
                let d = vertices[nextRow]
                let level = (a.y + b.y + c.y + d.y) * 25
                let tint: AirportModels.Paint = level > Float(range) * 0.72 ? .bareEarth : level > Float(range) * 0.37 ? .grassStrip : .islandGrass
                batch.triangle(a, d, c, tint)
                batch.triangle(a, c, b, tint)
                indices.append(contentsOf: [UInt16(start), UInt16(nextRow), UInt16(nextRow + 1),
                                           UInt16(start), UInt16(nextRow + 1), UInt16(start + 1)])
                if row == 0 { addEdge(a, b, to: batch) }
                if row == grid.size - 2 { addEdge(c, d, to: batch) }
                if column == 0 { addEdge(d, a, to: batch) }
                if column == grid.size - 2 { addEdge(b, c, to: batch) }
            }
        }
        Task { [weak collisionEntity] in
            guard let shape = try? await ShapeResource.generateStaticMesh(positions: vertices, faceIndices: indices) else { return }
            collisionEntity?.components.set(CollisionComponent(shapes: [shape]))
            collisionEntity?.components.set(InputTargetComponent())
        }
    }

    private static func addEdge(_ a: SIMD3<Float>, _ b: SIMD3<Float>, to batch: AirportModels.BatchSet) {
        batch.quad(a, b, [b.x, -0.06, b.z], [a.x, -0.06, a.z], .retainingWall, twoSided: true)
    }
}
