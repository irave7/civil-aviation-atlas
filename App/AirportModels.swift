import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum AirportModels {
    private static let metersPerUnit = AirportSiteCatalog.metersPerUnit

    static func make(for airport: Airport) -> AtlasModel {
        if airport.iata.uppercased() == "HKG" || airport.icao.uppercased() == "VHHH" {
            return hongKong()
        }
        let plan = AirportSiteCatalog.plan(for: airport)
        if plan.runways.isEmpty && !plan.features.contains(where: { $0.source.kind != .boundary }) {
            return AirportTerrainModels.make(for: airport)
        }
        return siteAtlas(for: airport, plan: plan)
    }

    private static func hongKong() -> AtlasModel {
        let root = Entity()
        root.name = "hong-kong-airfield"
        let context = layer("hong-kong-site-context", on: root)
        addWaterGrid(to: context, extent: 105)

        // Diagram-local +X follows published runway bearing 070.90° true.
        // Runway centrelines use midpoint projections of the published thresholds.
        let runwaySpecs = [
            RunwayShape(id: "07L/25R", name: "北跑道", center: [-9.60, -24.15], length: 38, width: 0.60, bearing: 90, displacedEnds: [1.74, 1.74]),
            RunwayShape(id: "07C/25C", name: "中跑道", center: [0.89, -7.70], length: 38, width: 0.60, bearing: 90, displacedEnds: [1.71, 1.71]),
            RunwayShape(id: "07R/25L", name: "南跑道", center: [-1.80, 7.70], length: 38, width: 0.60, bearing: 90, displacedEnds: [1.60, 0])
        ]

        let outline: [SIMD2<Float>] = [
            [-33, -26.0], [-30, -27.5], [12.4, -27.5], [15.1, -24.7], [15.7, -19.0],
            [18, -15.6], [22.6, -10.5], [23.9, -7.8], [27.3, -4.8], [29.6, 0.8],
            [28, 6], [23, 9.6], [22, 13.5], [18.7, 16.0], [6, 17.4], [-3.4, 14.3],
            [-18, 11.9], [-24, 10.1], [-24.4, 7.6], [-20.0, 3.0], [-18.7, -0.5],
            [-20.5, -5.0], [-24.0, -7.8], [-19.9, -11.6], [-11, -12.0], [-9.4, -16.8],
            [-10.1, -20.9], [-31.3, -20.9], [-33, -22.2]
        ]
        addIsland(outline, to: context)
        addHongKongPavement(to: context, runways: runwaySpecs)

        let runwayGroup = windowPart("hkg-runways", on: root, at: .zero)
        let runwayOffsets: [SIMD3<Float>] = [[-1.6, 2.0, -4.0], [0, 3.0, 0], [1.6, 2.0, 4.0]]
        let runwayChildren = zip(runwaySpecs, runwayOffsets).map { spec, offset in
            makeRunway(spec, on: runwayGroup, prefix: "hkg", official: true, widthVerified: true, explodeOffset: offset)
        }
        let runways = AtlasPart(
            id: runwayGroup.name, label: "三条跑道", symbol: "road.lanes", detail: "香港民航处公布的跑道数据。三条平行沥青跑道均为 3,800 米长、60 米宽，模型按公布尺寸与真方位相对排布。", entity: runwayGroup,
            focus: [-3, 0, -8.5], focusDistance: 65, explodeOffset: [-2.0, 1.4, 0], children: runwayChildren,
            sizeText: "3 × 3,800 米 · 每条宽 60 米"
        )
        let terminalExterior = licensedTerminalExterior()
        let terminal = makeTerminal(on: root, officialExterior: terminalExterior)
        let tower = makeTowers(on: root)
        let exteriorSource = terminalExterior == nil
            ? "航站楼外观依据公开图示原创重建。"
            : "T1 主厅与候机廊外观使用香港特别行政区政府地政总署可视化三维地图（单体化模型），经 DATA.GOV.HK 开放数据平台发布，已转换坐标并应用图鉴材质。"
        return AtlasModel(
            root: root, parts: [terminal, tower, runways], overviewTarget: [-2.5, 0, -5.3], overviewDistance: 79,
            metersPerUnit: metersPerUnit,
            sourceNote: "跑道尺寸与方向见香港民航处 AIP VHHH AD 2.12（2026-10-29）。\(exteriorSource)机场岛、机坪及塔台依据公开图示重建，室内是公开旅客区的空间示意。",
            context: context, stageSurface: .water, stageGroundY: -0.468
        )
    }

    private static func licensedTerminalExterior() -> Entity? {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: "HKG-T1-Exterior", withExtension: "usdz")
                ?? bundle.url(forResource: "HKG-T1-Exterior", withExtension: "usdz", subdirectory: "Resources") else { return nil }
        return try? Entity.load(contentsOf: url)
    }

    private static func makeTerminal(on root: Entity, officialExterior: Entity?) -> AtlasPart {
        let terminal = windowPart("hkg-terminal", on: root, at: [14.9, 0, 0.5])
        let shell = layer("terminal-shell", on: terminal)
        let interior = layer("terminal-interior", on: terminal)
        let section = layer("terminal-section", on: terminal)

        let sections = [
            Concourse(start: [7.10, -2.05], end: [7.10, 1.70], width: 2.22, wall: 0.258, arch: 0.102),
            Concourse(start: [5.40, -0.31], end: [-1.18, -0.31], width: 0.48, wall: 0.172, arch: 0.067),
            Concourse(start: [-1.11, -0.38], end: [-4.72, -3.92], width: 0.54, wall: 0.176, arch: 0.073),
            Concourse(start: [-1.10, -0.26], end: [-4.75, 3.15], width: 0.54, wall: 0.176, arch: 0.073),
            Concourse(start: [8.27, -2.25], end: [8.27, 1.88], width: 0.25, wall: 0.205, arch: 0.075)
        ]
        let lower = BatchSet()
        let façade = BatchSet()
        let cover = BatchSet()
        let cut = BatchSet()
        for concourse in sections {
            addConcourse(concourse, foundation: lower, façade: façade, roof: cover, cut: cut)
        }
        lower.install(on: terminal, label: "terminal-foundations")
        if let officialExterior {
            shell.addChild(officialExterior)
        } else {
            façade.install(on: shell, label: "terminal-glazing")
            cover.install(on: shell, label: "terminal-vaults")
        }
        cut.install(on: section, label: "terminal-architectural-section")

        let annexes = BatchSet()
        for annex in [
            Concourse(start: [0.35, -4.24], end: [3.45, -4.24], width: 0.65, wall: 0.19, arch: 0.075),
            Concourse(start: [-15.75, -4.1], end: [-15.75, 3.8], width: 0.73, wall: 0.175, arch: 0.085)
        ] {
            addConcourse(annex, foundation: annexes, façade: annexes, roof: annexes, cut: nil)
            addGates(from: annex.start, to: annex.end, width: annex.width, to: annexes)
        }
        // Elevated Sky Bridge and the representative gates of the main terminal.
        annexes.line([2.28, 0.39, -4.10], [2.28, 0.39, -0.61], width: 0.15, height: 0.12, .terminalGlass)
        annexes.line([2.28, 0.46, -4.10], [2.28, 0.46, -0.61], width: 0.19, height: 0.025, .roofWhite)
        for z in [-4.10, -3.10, -1.60] as [Float] {
            annexes.box([0.065, 0.34, 0.07], [2.28, 0.18, z], .concreteTrim)
        }
        if officialExterior == nil {
            for part in sections.dropFirst().prefix(3) {
                addGates(from: part.start, to: part.end, width: part.width, to: annexes)
            }
        }
        annexes.install(on: shell, label: "terminal-satellites-and-bridges")

        let structural = BatchSet()
        for z in stride(from: Float(-1.93), through: 1.63, by: 0.30) {
            for side in [-1, 1] as [Float] {
                structural.box([0.041, 0.23, 0.041], [7.10 + side * 0.62, 0.15, z], .concreteTrim)
                structural.box([0.070, 0.012, 0.07], [7.10 + side * 0.62, 0.04, z], .terminalGlass)
            }
        }
        structural.install(on: interior, label: "terminal-column-grid")

        let checkIn = makeCheckIn(on: terminal, parentPosition: terminal.position)
        let gateHall = makeGateHall(on: terminal, parentPosition: terminal.position)
        AtlasGeometry.partCollider(terminal, size: [14.65, 0.37, 8.0], center: [1.73, 0.19, -0.5])
        let quality = officialExterior == nil ? "建筑外观与内部为原创重建。" : "主厅及候机廊采用地政总署发布的外部几何，室内与剖面为原创重建。"
        return AtlasPart(
            id: terminal.name, label: "一号客运大楼", symbol: "building.2", detail: "一号客运大楼由主厅、分叉候机长廊和卫星部分组成。\(quality)", entity: terminal,
            focus: terminal.position + [1.2, 0.16, -0.32], focusDistance: 21, shell: shell, interior: interior, section: section,
            explodeOffset: [2.5, 6.0, 1.0], children: [checkIn, gateHall], sizeText: "主航站楼约 1.3 千米长（香港工程师学会）"
        )
    }

    private struct Concourse {
        let start: SIMD2<Float>
        let end: SIMD2<Float>
        let width: Float
        let wall: Float
        let arch: Float
    }

    private static func addConcourse(_ spec: Concourse, foundation: BatchSet, façade: BatchSet, roof: BatchSet, cut: BatchSet?) {
        let direction = simd_normalize(spec.end - spec.start)
        let side = SIMD2<Float>(-direction.y, direction.x)
        let distance = simd_distance(spec.start, spec.end)
        func point(_ t: Float, _ lateral: Float, _ y: Float) -> SIMD3<Float> {
            let ground = spec.start + direction * t + side * lateral
            return [ground.x, y, ground.y]
        }
        let half = spec.width / 2
        foundation.line(point(-0.02, 0, 0.024), point(distance + 0.02, 0, 0.024), width: spec.width + 0.045, height: 0.048, .polishedFloor)
        for sign in [-1, 1] as [Float] {
            let boundary = half * sign
            façade.line(point(0, boundary, spec.wall * 0.50), point(distance, boundary, spec.wall * 0.50), width: 0.018, height: spec.wall - 0.035, .terminalGlass)
            façade.line(point(0, boundary, spec.wall - 0.028), point(distance, boundary, spec.wall - 0.028), width: 0.024, height: 0.025, .roofWhite)
            façade.line(point(0, boundary, spec.wall * 0.45), point(distance, boundary, spec.wall * 0.45), width: 0.019, height: 0.014, .deepSteel)
            for x in stride(from: Float(0.03), through: distance, by: 0.095) {
                façade.box([0.012, spec.wall - 0.032, 0.013], point(x, boundary, spec.wall * 0.50), .steel)
            }
        }
        for t in [Float(0), distance] {
            façade.line(point(t, -half, spec.wall * 0.50), point(t, half, spec.wall * 0.50), width: 0.023, height: spec.wall - 0.035, .terminalGlass)
            for lateral in stride(from: -half, through: half, by: 0.11) {
                façade.box([0.011, spec.wall - 0.03, 0.011], point(t, lateral, spec.wall * 0.50), .steel)
            }
        }
        let strips = 14
        for i in 0..<strips {
            let a = Float(i) / Float(strips) * .pi
            let b = Float(i + 1) / Float(strips) * .pi
            let y1 = spec.wall + sin(a) * spec.arch
            let y2 = spec.wall + sin(b) * spec.arch
            let s1 = cos(a) * (half + 0.023)
            let s2 = cos(b) * (half + 0.023)
            let tone: Paint = (i == 6 || i == 7) ? .skylight : (i.isMultiple(of: 2) ? .roofWhite : .roofCool)
            roof.quad(point(-0.035, s1, y1), point(distance + 0.035, s1, y1), point(distance + 0.035, s2, y2), point(-0.035, s2, y2), tone, twoSided: true)
            for t in stride(from: Float(0.035), through: distance, by: 0.19) {
                roof.line(point(t, s1, y1 + 0.002), point(t, s2, y2 + 0.002), width: 0.012, height: 0.009, .roofSeam)
            }
            if i < 4, let cut {
                cut.quad(point(-0.035, s1, y1), point(distance + 0.035, s1, y1), point(distance + 0.035, s2, y2), point(-0.035, s2, y2), tone, twoSided: true)
                cut.line(point(distance + 0.016, s1, y1), point(distance + 0.016, s2, y2), width: 0.013, height: 0.012, .amber)
            }
        }
        if let cut {
            cut.line(point(0, half, 0.10), point(distance, half, 0.10), width: 0.019, height: 0.15, .terminalGlass)
            cut.line(point(0, half, 0.038), point(distance, half, 0.038), width: 0.023, height: 0.017, .amber)
        }
    }

    private static func addGates(from start: SIMD2<Float>, to end: SIMD2<Float>, width: Float, to surfaces: BatchSet) {
        let direction = simd_normalize(end - start)
        let side = SIMD2<Float>(-direction.y, direction.x)
        let length = simd_distance(start, end)
        for t in stride(from: Float(0.48), to: length - 0.28, by: 0.59) {
            for sign in [-1, 1] as [Float] {
                let origin = start + direction * t + side * (width * 0.5 * sign)
                let join = origin + side * (0.20 * sign)
                let gate = join + side * (0.25 * sign) + direction * 0.13
                surfaces.line([origin.x, 0.105, origin.y], [join.x, 0.105, join.y], width: 0.046, height: 0.06, .terminalGlass)
                surfaces.line([join.x, 0.10, join.y], [gate.x, 0.079, gate.y], width: 0.041, height: 0.048, .roofCool)
                surfaces.box([0.027, 0.073, 0.027], [join.x, 0.040, join.y], .deepSteel)
                let stand = gate + side * (0.52 * sign)
                surfaces.line([gate.x, 0.015, gate.y], [stand.x, 0.015, stand.y], width: 0.011, height: 0.004, .taxiYellow)
                if Int(t * 10).isMultiple(of: 3) {
                    addParkedAircraft(at: stand, direction: side * sign, to: surfaces)
                }
            }
        }
    }

    private static func addParkedAircraft(at position: SIMD2<Float>, direction: SIMD2<Float>, to surfaces: BatchSet) {
        let side = SIMD2<Float>(-direction.y, direction.x)
        func p(_ along: Float, _ lateral: Float, _ height: Float) -> SIMD3<Float> {
            let v = position + direction * along + side * lateral
            return [v.x, height, v.y]
        }
        surfaces.line(p(-0.23, 0, 0.065), p(0.25, 0, 0.065), width: 0.043, height: 0.042, .roofWhite)
        surfaces.quad(p(-0.03, 0, 0.063), p(0.15, -0.24, 0.061), p(0.19, -0.24, 0.061), p(0.083, 0, 0.064), .roofCool, twoSided: true)
        surfaces.quad(p(-0.03, 0, 0.063), p(0.083, 0, 0.064), p(0.19, 0.24, 0.061), p(0.15, 0.24, 0.061), .roofCool, twoSided: true)
        surfaces.triangle(p(0.13, 0, 0.082), p(0.24, 0, 0.15), p(0.26, 0, 0.08), .navy, twoSided: true)
    }

    private static func makeCheckIn(on terminal: Entity, parentPosition: SIMD3<Float>) -> AtlasPart {
        let part = windowPart("hkg-checkin", on: terminal, at: [7.1, 0.046, -0.18])
        let fixtures = BatchSet()
        fixtures.box([0.81, 0.013, 0.60], [0, 0.008, 0], .polishedFloor)
        for x in stride(from: Float(-0.38), through: 0.40, by: 0.037) {
            fixtures.box([0.0014, 0.002, 0.60], [x, 0.016, 0], .floorJoint)
        }
        for z in stride(from: Float(-0.28), through: 0.30, by: 0.037) {
            fixtures.box([0.81, 0.002, 0.0014], [0, 0.016, z], .floorJoint)
        }
        for row in [-0.196, -0.045, 0.112] as [Float] {
            fixtures.box([0.55, 0.016, 0.033], [0, 0.024, row], .deepSteel)
            for counter in 0..<12 {
                let x = (Float(counter) - 5.5) * 0.044
                fixtures.box([0.037, 0.014, 0.025], [x, 0.026, row - 0.02], .terminalGlass)
                fixtures.box([0.039, 0.004, 0.030], [x, 0.035, row - 0.025], .roofWhite)
                fixtures.box([0.012, 0.009, 0.004], [x, 0.042, row - 0.023], .screen)
            }
            for x in stride(from: Float(-0.24), through: 0.25, by: 0.055) {
                fixtures.box([0.0025, 0.011, 0.0025], [x, 0.021, row + 0.046], .steel)
            }
            fixtures.box([0.495, 0.0023, 0.0020], [0, 0.026, row + 0.046], .navy)
            fixtures.box([0.042, 0.011, 0.004], [-0.273, 0.073, row], .screen)
        }
        for x in [-0.34, 0.34] as [Float] {
            for z in [-0.24, 0, 0.24] as [Float] {
                fixtures.box([0.021, 0.105, 0.021], [x, 0.064, z], .concreteTrim)
                fixtures.box([0.032, 0.005, 0.032], [x, 0.018, z], .steel)
            }
        }
        for x in [-0.15, 0, 0.15] as [Float] {
            fixtures.box([0.009, 0.014, 0.010], [x, 0.025, 0.23], .screen)
        }
        fixtures.install(on: part, label: "check-in-counters-queues-and-columns")
        AtlasGeometry.partCollider(part, size: [0.81, 0.085, 0.60], center: [0, 0.041, 0])
        return AtlasPart(id: part.name, label: "值机大堂", symbol: "person.crop.rectangle", detail: "公开出发大厅的局部示意。可观察岛式值机柜台、排队动线、显示屏、地面分缝和高柱。", entity: part, focus: parentPosition + part.position + [0, 0.045, 0], focusDistance: 0.91, explodeOffset: [0.24, 0.72, 0.5], interiorOnly: true)
    }

    private static func makeGateHall(on terminal: Entity, parentPosition: SIMD3<Float>) -> AtlasPart {
        let part = windowPart("hkg-gate-hall", on: terminal, at: [0.92, 0.051, -0.28])
        let fixtures = BatchSet()
        fixtures.box([0.64, 0.010, 0.46], [0, 0.004, 0], .polishedFloor)
        fixtures.box([0.64, 0.006, 0.055], [0, 0.012, -0.187], .floorJoint)
        for row in [-0.112, -0.045, 0.045, 0.112] as [Float] {
            for seat in 0..<12 {
                let x = (Float(seat) - 5.5) * 0.029
                fixtures.box([0.023, 0.007, 0.024], [x, 0.024, row], .deepSteel)
                fixtures.box([0.022, 0.015, 0.004], [x, 0.034, row - 0.011], .terminalGlass)
                fixtures.box([0.004, 0.014, 0.012], [x, 0.017, row], .steel)
            }
        }
        fixtures.box([0.065, 0.014, 0.040], [-0.23, 0.022, -0.11], .terminalGlass)
        fixtures.box([0.046, 0.028, 0.004], [-0.228, 0.067, -0.110], .screen)
        fixtures.box([0.010, 0.050, 0.009], [-0.228, 0.030, -0.113], .deepSteel)
        fixtures.box([0.028, 0.019, 0.051], [0.22, 0.024, 0.05], .roofWhite)
        fixtures.box([0.038, 0.033, 0.015], [0.281, 0.036, 0.10], .terminalGlass)
        fixtures.box([0.105, 0.026, 0.035], [0.32, 0.032, 0.10], .roofCool)
        fixtures.box([0.58, 0.038, 0.007], [0, 0.037, 0.211], .terminalGlass)
        for x in stride(from: Float(-0.28), through: 0.29, by: 0.055) {
            fixtures.box([0.007, 0.044, 0.008], [x, 0.037, 0.213], .steel)
        }
        fixtures.install(on: part, label: "gate-lounge-seating-and-boarding-bridge")
        AtlasGeometry.partCollider(part, size: [0.65, 0.085, 0.46], center: [0, 0.039, 0])
        return AtlasPart(id: part.name, label: "候机长廊", symbol: "chair.lounge", detail: "代表性的公开候机区。可观察成排座椅、登机口信息屏、玻璃边界和通往登机桥的动线。", entity: part, focus: parentPosition + part.position + [0, 0.038, 0], focusDistance: 0.73, explodeOffset: [-0.24, 0.52, -0.43], interiorOnly: true)
    }

    private static func makeTowers(on root: Entity) -> AtlasPart {
        let group = windowPart("hkg-towers", on: root, at: .zero)
        let north = makeTower(on: group, id: "hkg-tower-north", name: "北塔台", at: [5.22, 0, -14.9], height: 1.02, newTower: true)
        let south = makeTower(on: group, id: "hkg-tower-south", name: "南塔台", at: [6.98, 0, 1.92], height: 0.78, newTower: false)
        return AtlasPart(id: group.name, label: "航空交通管制塔台", symbol: "antenna.radiowaves.left.and.right", detail: "分别观察南、北塔台的塔身、观察层与屋面。北塔台公开高度为 102 米，内部未建模。", entity: group, focus: [6.09, 0.4, -6.49], focusDistance: 23, explodeOffset: [2.0, 7.5, -1.1], children: [north, south])
    }

    private static func makeTower(on parent: Entity, id: String, name: String, at point: SIMD3<Float>, height: Float, newTower: Bool) -> AtlasPart {
        let group = windowPart(id, on: parent, at: point)
        let shell = layer("tower-exterior", on: group)
        let geometry = BatchSet()
        geometry.box([0.54, 0.077, 0.59], [0, 0.0385, 0], .concreteTrim)
        geometry.box([0.58, 0.02, 0.62], [0, 0.086, 0], .roofCool)
        let levels: [(Float, Float, Paint)] = [
            (0.090, 0.134, .concreteTrim), (0.18 * height, 0.111, .roofWhite),
            (0.71 * height, 0.107, .concreteTrim), (0.77 * height, 0.133, .roofCool),
            (0.785 * height, 0.154, .deepSteel), (0.91 * height, 0.209, .terminalGlass),
            (0.94 * height, 0.206, .roofWhite), (height, 0.153, .roofCool)
        ]
        for index in 0..<(levels.count - 1) {
            let start = levels[index]
            let end = levels[index + 1]
            geometry.taper(y1: start.0, y2: end.0, radius1: start.1, radius2: end.1, segments: newTower ? 16 : 12, paint: start.2)
        }
        let frameCount = newTower ? 16 : 12
        for i in 0..<frameCount {
            let angle = Float(i) * .pi * 2 / Float(frameCount)
            geometry.line([cos(angle) * 0.155, height * 0.785, sin(angle) * 0.155], [cos(angle) * 0.210, height * 0.914, sin(angle) * 0.210], width: 0.011, height: 0.012, .deepSteel)
            geometry.line([cos(angle) * 0.11, height * 0.21, sin(angle) * 0.11], [cos(angle) * 0.108, height * 0.70, sin(angle) * 0.108], width: 0.006, height: 0.007, .roofCool)
        }
        geometry.box([0.014, 0.095, 0.014], [0.012, height + 0.05, 0.023], .deepSteel)
        geometry.box([0.093, 0.01, 0.016], [0.012, height + 0.066, 0.023], .concreteTrim)
        geometry.box([0.021, 0.015, 0.021], [0.012, height + 0.103, 0.023], .signalRed)
        geometry.install(on: shell, label: "tower-shaft-cab-and-antenna")
        AtlasGeometry.partCollider(group, size: [0.59, height, 0.63], center: [0, height * 0.5, 0])
        let detail = newTower ? "公开资料记录新塔台高 102 米，2024 年三跑道系统全面投入运作前启用。外观原创重建。" : "根据公开照片观察塔身和玻璃管制室比例后重建，南塔台在此仅提供外观示意。"
        let separation: SIMD3<Float> = newTower ? [-0.25, 1.9, -0.8] : [0.25, 0.9, 0.8]
        return AtlasPart(id: id, label: name, symbol: "dot.radiowaves.up.forward", detail: detail, entity: group, focus: point + [0, height * 0.55, 0], focusDistance: 1.94, shell: shell, explodeOffset: separation, sizeText: newTower ? "公开高度 102 米（不含示意天线）" : nil)
    }

    private struct RunwayShape {
        let id: String
        let name: String
        let center: SIMD2<Float>
        let length: Float
        let width: Float
        let bearing: Float
        let displacedEnds: [Float]
    }

    private static func makeRunway(
        _ spec: RunwayShape, on root: Entity, prefix: String, official: Bool, widthVerified: Bool, explodeOffset: SIMD3<Float>
    ) -> AtlasPart {
        let safeID = spec.id.replacingOccurrences(of: "/", with: "-")
        let runway = windowPart("\(prefix)-runway-\(safeID)", on: root, at: [spec.center.x, 0, spec.center.y])
        // Geographic north is −Z. A positive Y rotation turns the runway's +X axis toward north.
        runway.orientation = simd_quatf(angle: (90 - spec.bearing) * .pi / 180, axis: [0, 1, 0])
        let shell = layer("runway-surface", on: runway)
        let markings = layer("\(runway.name)-markings", on: runway)
        let pavement = BatchSet()
        let marks = BatchSet()
        let length = spec.length
        let width = spec.width
        let half = length * 0.5
        pavement.box([length, 0.036, width], [0, 0.021, 0], .asphalt)
        pavement.box([length, 0.012, width + 0.12], [0, 0.006, 0], .asphaltEdge)
        let lineWidth = min(width * 0.035, 0.013)
        for z in [-1, 1] as [Float] {
            marks.box([length * 0.989, 0.0028, lineWidth], [0, 0.041, z * (width / 2 - lineWidth * 1.65)], .runwayWhite)
        }
        let centreLimit = max(0, half - 2.55)
        for x in stride(from: -centreLimit, through: centreLimit, by: 0.55) {
            marks.box([min(length * 0.12, 0.30), 0.0027, max(width * 0.030, 0.013)], [x, 0.043, 0], .runwayWhite)
        }
        let endLabels = spec.id.split(separator: "/", omittingEmptySubsequences: true)
        for (index, sign) in [Float(-1), 1].enumerated() {
            let threshold = max(0, half - min(spec.displacedEnds[index], length * 0.19) - 0.2)
            for stripe in [-5, -4, -3, -2, -1, 1, 2, 3, 4, 5] {
                let z = Float(stripe) * width * 0.071
                marks.box([min(0.32, length * 0.10), 0.003, width * 0.042], [sign * threshold, 0.042, z], .runwayWhite)
            }
            if index < endLabels.count {
                addRunwayNumber(String(endLabels[index]), at: sign * max(0, threshold - 0.41), width: width * 0.51, mirror: sign > 0, to: marks)
            }
            for z in [-1, 1] as [Float] {
                marks.box([min(0.42, length * 0.10), 0.003, width * 0.144], [sign * max(0, threshold - 1.45), 0.042, z * width * 0.22], .runwayWhite)
            }
        }
        pavement.install(on: shell, label: "runway-pavement")
        marks.install(on: markings, label: "runway-markings")
        AtlasGeometry.partCollider(runway, size: [length, 0.08, width + 0.035], center: [0, 0.02, 0])
        let meters = Int((length * metersPerUnit).rounded())
        let reportedWidth = Int((width * metersPerUnit).rounded())
        let size = widthVerified ? "\(meters.formatted()) × \(reportedWidth) 米" : "公布长度 \(meters.formatted()) 米"
        let detail = official ? "按香港民航处公布数据构建。跑道几何长度及宽度按米制表示，标线和铺装纹理经简化。" : "依据公开目录绘制。跑道定位和方位受原始记录覆盖影响，铺装与标线为示意。"
        let focus = runway.position + [0, 0.04, 0]
        let framing = max(1.3, length * 1.44)
        let markingsPart = AtlasPart(
            id: markings.name, label: "跑道标线", symbol: "line.3.horizontal",
            detail: "跑道识别号、中线和入口标线的示意层。", entity: markings, focus: focus,
            focusDistance: framing, explodeOffset: [0, max(0.11, min(1.25, length * 0.09)), 0]
        )
        return AtlasPart(id: runway.name, label: spec.name, symbol: "road.lanes", detail: detail, entity: runway, focus: focus, focusDistance: framing, shell: shell, explodeOffset: explodeOffset, children: [markingsPart], sizeText: size)
    }

    private static func addRunwayNumber(_ text: String, at x: Float, width: Float, mirror: Bool, to batch: BatchSet) {
        let count = max(1, text.count)
        let cell = width / Float(count * 4 - 1)
        let sign: Float = mirror ? -1 : 1
        for (letter, character) in text.enumerated() {
            guard let rows = AirfieldGeometry.runwayGlyphs[character] else { continue }
            for (row, bits) in rows.enumerated() {
                for column in 0..<3 where bits & (1 << (2 - column)) != 0 {
                    let z = Float(letter * 4 + column) * cell - width / 2
                    let a = x + sign * (Float(2 - row) * 0.049)
                    batch.box([0.048, 0.003, cell * 0.96], [a, 0.043, z * sign], .runwayWhite)
                }
            }
        }
    }

    private static func addHongKongPavement(to root: Entity, runways: [RunwayShape]) {
        let paved = BatchSet()
        for (index, runway) in runways.enumerated() {
            let start = runway.center.x - runway.length / 2
            let end = runway.center.x + runway.length / 2
            let z = runway.center.y
            paved.box([runway.length + 1.55, 0.015, 1.55], [runway.center.x, 0.007, z], .grassStrip)
            let offsets: [Float] = index == 0 ? [1.04, 2.2] : [-1.14, 1.30, 2.25]
            for offset in offsets {
                taxi([start + 0.04, z + offset], [end - 0.06, z + offset], width: 0.25, to: paved)
                for fraction in [0.05, 0.12, 0.32, 0.58, 0.81, 0.96] as [Float] {
                    let x = start + runway.length * fraction
                    taxi([x, z], [x + (fraction < 0.5 ? 0.7 : -0.65), z + offset], width: 0.24, to: paved)
                }
            }
        }
        for (start, end) in [([-5.1, -22.2], [-5.1, -8.8]), ([13.3, -22.2], [13.3, -8.9]), ([-16.3, -5.5], [-16.3, 5.5]), ([-8.5, -5.6], [-8.5, 5.55]), ([3.4, -5.6], [3.4, 5.2]), ([19.0, -5.45], [19.0, 4.85])] as [(SIMD2<Float>, SIMD2<Float>)] {
            taxi(start, end, width: 0.28, to: paved)
        }
        paved.box([33.6, 0.012, 9.02], [2.05, 0.0063, -0.02], .apron)
        paved.box([20.25, 0.013, 3.55], [8.6, 0.007, 11.55], .apron)
        paved.box([11.1, 0.010, 7.1], [5.22, 0.0055, -16.55], .bareEarth)
        paved.box([4.85, 0.014, 3.0], [22.17, 0.009, -0.15], .apron)
        for x in stride(from: Float(-14.5), through: 19.5, by: 0.55) {
            for z in [-4.11, 4.17] as [Float] {
                paved.box([0.010, 0.003, 0.46], [x, 0.014, z], .standStripe)
            }
        }
        let concourse = BatchSet()
        for (x, z, wide, long) in [(-14, -3.65, 1.6, 1.15), (-11.8, 2.93, 1.8, 1.8), (14, 12.43, 2.2, 1.0), (17.7, 12.67, 2.3, 1.6), (7.52, 12.6, 2.8, 1.3), (4.3, 12.5, 1.9, 1.6), (2, 11.78, 1.55, 1.1), (24.55, -1.7, 1.35, 1.4)] as [(Float, Float, Float, Float)] {
            concourse.box([wide, 0.18, long], [x, 0.09, z], .buildingWall)
            concourse.box([wide + 0.06, 0.028, long + 0.06], [x, 0.184, z], .roofCool)
            for dx in stride(from: -wide / 2 + 0.12, to: wide / 2, by: 0.18) {
                concourse.box([0.021, 0.009, long], [x + dx, 0.203, z], .roofSeam)
            }
        }
        paved.install(on: root, label: "taxiways-and-apron")
        concourse.install(on: root, label: "airport-context-buildings")
    }

    private static func taxi(_ start: SIMD2<Float>, _ end: SIMD2<Float>, width: Float, to paved: BatchSet) {
        paved.line([start.x, 0.0116, start.y], [end.x, 0.0116, end.y], width: width, height: 0.011, .taxiPavement)
        paved.line([start.x, 0.0178, start.y], [end.x, 0.0178, end.y], width: 0.010, height: 0.002, .taxiYellow)
    }

    private static func siteAtlas(for airport: Airport, plan: AirportSitePlan) -> AtlasModel {
        let root = Entity()
        root.name = "\(airport.id)-site-overview"
        let context = layer("airfield-site-context", on: root)
        AirportSiteMeshes.addGround(on: context, plan: plan)

        let center = plan.bounds.center
        let span = max(3.8, plan.bounds.span)
        let runwayParts = plan.runways.enumerated().map { index, runway in
            let shape = RunwayShape(id: runway.id, name: runway.id, center: runway.center, length: runway.length, width: runway.width, bearing: runway.bearing, displacedEnds: [0, 0])
            let outward = (runway.center - center) * 0.19
            let lift = max(0.25, span * 0.075) * (0.65 + 0.65 * Float(index) / Float(max(1, plan.runways.count - 1)))
            return makeRunway(
                shape, on: root, prefix: "\(airport.id)-\(index)", official: false, widthVerified: runway.widthVerified,
                explodeOffset: [outward.x, lift, outward.y]
            )
        }
        let siteParts = AirportSiteMeshes.makeParts(plan: plan, on: root)
        let supplemental = AirportSiteCatalog.usesSupplementalRunways(for: airport)
        let runwayNote = plan.runways.isEmpty ? "" : supplemental
            ? "跑道依据 OpenStreetMap 绘制，部分尺寸为地图几何估算。"
            : "跑道依据公开机场资料绘制，缺失的位置、方位或宽度以示意呈现。"
        let siteNote = siteParts.isEmpty
            ? "本模型展示可查的跑道资料。"
            : "设施依据公开地图重建。缺失的高度和铺装细节为示意。"
        let attribution = [
            plan.hasOpenStreetMapData || supplemental ? AirportSiteCatalog.source.title : nil,
            plan.hasOvertureData ? AirportSiteCatalog.overtureSource.title : nil
        ].compactMap { $0 }.joined(separator: " · ")
        let tallest = plan.tallestBuilding
        return AtlasModel(root: root, parts: siteParts + runwayParts, overviewTarget: [center.x, tallest * 0.38, center.y],
                          overviewDistance: max(5.8, span * 1.48, tallest * 2.45), metersPerUnit: metersPerUnit,
                          sourceNote: siteNote + runwayNote + (attribution.isEmpty ? "" : "\n" + attribution), context: context, stageSurface: .land, stageGroundY: -0.033)
    }

    private static func addIsland(_ points: [SIMD2<Float>], to root: Entity) {
        let batch = BatchSet()
        batch.flatPolygon(points, y: 0, paint: .islandGrass)
        for (index, a) in points.enumerated() {
            let b = points[(index + 1) % points.count]
            batch.quad([a.x, 0, a.y], [a.x, -0.45, a.y], [b.x, -0.45, b.y], [b.x, 0, b.y], .retainingWall, twoSided: true)
            batch.line([a.x, 0.012, a.y], [b.x, 0.012, b.y], width: 0.057, height: 0.017, .coastTrim)
        }
        batch.install(on: root, label: "airport-island-and-seawall")
    }

    private static func addWaterGrid(to root: Entity, extent: Float) {
        let batch = BatchSet()
        let span = extent * 0.494
        let step = max(1.4, extent / 24)
        for p in stride(from: -span, through: span, by: step) {
            batch.box([0.018, 0.0015, span * 2], [p, -0.454, 0], .waterGrid)
            batch.box([span * 2, 0.0015, 0.018], [0, -0.454, p], .waterGrid)
        }
        batch.install(on: root, label: "coastal-water-and-projection-grid")
    }

    private static func windowPart(_ id: String, on parent: Entity, at point: SIMD3<Float>) -> Entity {
        let child = Entity()
        child.name = id
        child.position = point
        parent.addChild(child)
        return child
    }

    private static func layer(_ name: String, on parent: Entity) -> Entity {
        windowPart(name, on: parent, at: .zero)
    }

    typealias Paint = AirfieldGeometry.Paint
    typealias BatchSet = AirfieldGeometry.BatchSet
}
