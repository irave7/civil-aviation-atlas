import RealityKit
import SwiftUI
import UIKit

@MainActor
enum AircraftModels {
    static func make(aircraft: AircraftProfile, configuration: AircraftConfiguration,
                     livery: AircraftLivery = AircraftLiveries.reference) -> AtlasModel {
        let builder = AircraftBuilder(length: Float(aircraft.lengthM), span: Float(aircraft.wingspanM),
                                      configuration: configuration, palette: livery.palette, exteriorOnly: false)
        if let dimensions = AircraftBuilder.Variant(aircraft.id) {
            return builder.buildVariant(dimensions)
        }
        return builder.build()
    }

    static func makeFlightExterior(aircraft: AircraftProfile, configuration: AircraftConfiguration,
                                   livery: AircraftLivery) -> (root: Entity, landingGear: Entity) {
        let builder = AircraftBuilder(length: Float(aircraft.lengthM), span: Float(aircraft.wingspanM),
                                      configuration: configuration, palette: livery.palette, exteriorOnly: true)
        return builder.buildFlightExterior(variant: AircraftBuilder.Variant(aircraft.id))
    }
}

@MainActor
private struct AircraftBuilder {
    typealias Point = SIMD3<Float>

    private struct Station {
        let x: Float
        let centerY: Float
        let height: Float
        let halfWidth: Float

        init(_ x: Float, _ centerY: Float, _ height: Float, _ halfWidth: Float) {
            self.x = x
            self.centerY = centerY
            self.height = height
            self.halfWidth = halfWidth
        }
    }

    private struct WingStation {
        let span: Float
        let front: Float
        let rear: Float
        let height: Float
        let thickness: Float

        init(_ span: Float, _ front: Float, _ rear: Float, _ height: Float, _ thickness: Float) {
            self.span = span
            self.front = front
            self.rear = rear
            self.height = height
            self.thickness = thickness
        }
    }

    private struct Finish {
        let color: UIColor
        var roughness: Float = 0.53
        var metallic: Float = 0

        @MainActor var material: PhysicallyBasedMaterial {
            AtlasGeometry.material(color, roughness: roughness, metallic: metallic)
        }
    }

    private struct Mesh {
        var vertices: [Point] = []
        var normals: [Point] = []
        var triangles: [UInt32] = []

        mutating func face(_ points: [Point], normal: Point) {
            let start = UInt32(vertices.count)
            vertices.append(contentsOf: points)
            normals.append(contentsOf: repeatElement(normal, count: points.count))
            let forward = simd_dot(simd_cross(points[1] - points[0], points[2] - points[0]), normal) >= 0
            for index in 1..<(points.count - 1) {
                let a = start + UInt32(index)
                let b = a + 1
                triangles.append(contentsOf: forward ? [start, a, b] : [start, b, a])
            }
        }

        mutating func box(center: Point, size: Point) {
            let half = size / 2
            let x = Point(half.x, 0, 0)
            let y = Point(0, half.y, 0)
            let z = Point(0, 0, half.z)
            let c = center
            face([c + x - y - z, c + x + y - z, c + x + y + z, c + x - y + z], normal: [1, 0, 0])
            face([c - x - y - z, c - x + y - z, c - x + y + z, c - x - y + z], normal: [-1, 0, 0])
            face([c - x + y - z, c + x + y - z, c + x + y + z, c - x + y + z], normal: [0, 1, 0])
            face([c - x - y - z, c + x - y - z, c + x - y + z, c - x - y + z], normal: [0, -1, 0])
            face([c - x - y + z, c + x - y + z, c + x + y + z, c - x + y + z], normal: [0, 0, 1])
            face([c - x - y - z, c + x - y - z, c + x + y - z, c - x + y - z], normal: [0, 0, -1])
        }

        @MainActor func entity(_ finish: Finish) -> Entity {
            guard !triangles.isEmpty else { return Entity() }
            var descriptor = MeshDescriptor()
            descriptor.positions = .init(vertices)
            descriptor.normals = .init(normals)
            descriptor.primitives = .triangles(triangles)
            guard let resource = try? MeshResource.generate(from: [descriptor]) else { return Entity() }
            return ModelEntity(mesh: resource, materials: [finish.material])
        }
    }

    let length: Float
    let span: Float
    let configuration: AircraftConfiguration
    let palette: AircraftLivery.Palette
    let exteriorOnly: Bool

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    private var fuselageFinish: Finish { Finish(color: palette.bodyUIColor, roughness: 0.30, metallic: 0.10) }
    private let wingFinish = Finish(color: Self.color(0.58, 0.65, 0.69), roughness: 0.42, metallic: 0.34)
    private let controlFinish = Finish(color: Self.color(0.70, 0.75, 0.77), roughness: 0.39, metallic: 0.25)
    private let darkGlass = Finish(color: Self.color(0.035, 0.10, 0.15), roughness: 0.18, metallic: 0.26)
    private let metal = Finish(color: Self.color(0.62, 0.72, 0.77), roughness: 0.30, metallic: 0.79)
    private let carbon = Finish(color: Self.color(0.11, 0.17, 0.21), roughness: 0.44, metallic: 0.54)
    private let interiorWhite = Finish(color: Self.color(0.83, 0.85, 0.82), roughness: 0.67)
    private let cabinFloor = Self.color(0.15, 0.20, 0.24)
    private let edgeColor = Self.color(0.96, 0.54, 0.21)

    private var cabinPaint: Finish {
        let color = switch configuration.id.split(separator: "-").first {
        case "cx": Self.color(0.015, 0.28, 0.29)
        case "lh": Self.color(0.025, 0.12, 0.24)
        case "dl": Self.color(0.065, 0.12, 0.27)
        case "qf": Self.color(0.74, 0.08, 0.15)
        case "aa": Self.color(0.10, 0.29, 0.47)
        case "as": Self.color(0.027, 0.18, 0.31)
        case "wn": Self.color(0.10, 0.22, 0.64)
        case "reference": Self.color(0.095, 0.28, 0.34)
        default: Self.color(0.06, 0.13, 0.32)
        }
        return Finish(color: color, roughness: 0.36, metallic: 0.09)
    }

    private var primaryPaint: Finish { Finish(color: palette.primaryUIColor, roughness: 0.36, metallic: 0.09) }
    private var accentPaint: Finish { Finish(color: palette.accentUIColor, roughness: 0.42, metallic: 0.07) }
    private var nacelleSeam: Finish {
        Finish(color: Self.color(0.35, 0.39, 0.42), roughness: 0.56, metallic: 0.23)
    }
    private var nacelleFinish: Finish { palette.pattern == .wideBelly || palette.pattern == .fullBody ? primaryPaint : fuselageFinish }

    private var fuselageStations: [Station] {
        [Station(0, -0.19, 0.035, 0.035), Station(0.25, -0.19, 0.51, 0.54), Station(0.68, -0.14, 0.96, 0.96),
         Station(1.28, -0.08, 1.44, 1.35), Station(2.12, 0.05, 1.94, 1.78), Station(3.10, 0.19, 2.40, 2.17),
         Station(4.20, 0.18, 2.67, 2.48), Station(5.34, 0.12, 2.82, 2.69), Station(6.65, 0.06, 2.93, 2.85),
         Station(8.3, 0.015, 2.98, 2.95), Station(10.1, 0, 2.98, 2.98), Station(14.0, 0, 2.98, 2.98),
         Station(23, 0, 2.98, 2.98), Station(34, 0, 2.98, 2.98), Station(43.6, 0, 2.98, 2.98),
         Station(49.8, 0, 2.98, 2.98), Station(52.5, 0.04, 2.92, 2.91), Station(54.7, 0.13, 2.76, 2.72),
         Station(56.9, 0.26, 2.44, 2.39), Station(59.0, 0.54, 2.01, 1.91), Station(61.1, 0.83, 1.53, 1.39),
         Station(63.0, 1.14, 1.04, 0.85), Station(64.9, 1.34, 0.52, 0.48), Station(65.85, 1.40, 0.27, 0.26),
         Station(length, 1.45, 0.08, 0.10)]
    }

    func build() -> AtlasModel {
        let root = Entity()
        let parts = standardParts() + [landingGear()]
        for part in parts { root.addChild(part.entity) }
        return AtlasModel(root: root, parts: parts, overviewTarget: p(length / 2, 1), overviewDistance: 114,
                          metersPerUnit: 1,
                          sourceNote: "按空客公开尺寸和航司公开客舱资料制作的比例模型。客舱、涂装和机械细节为简化示意，测距基于模型几何。", stageGroundY: -5.56)
    }

    func buildFlightExterior(variant: Variant?) -> (root: Entity, landingGear: Entity) {
        let root = Entity()
        let parts: [AtlasPart]
        let gear: AtlasPart
        if let variant {
            parts = variantParts(variant)
            gear = variantLandingGear(variant)
        } else {
            parts = standardParts()
            gear = landingGear()
        }
        for part in parts + [gear] {
            part.entity.name = part.id
            root.addChild(part.entity)
        }
        return (root, gear.entity)
    }

    private func standardParts() -> [AtlasPart] {
        [body(), wing(side: -1), wing(side: 1), engine(side: -1), engine(side: 1), tail()]
    }

    private func p(_ x: Float, _ y: Float = 0, _ z: Float = 0) -> Point {
        [x - length / 2, y, z]
    }

    private func part(_ id: String, _ label: String, _ symbol: String, _ detail: String, entity: Entity, focus: Point,
                      distance: Float, bounds: Point? = nil, shell: Entity? = nil, interior: Entity? = nil,
                      section: Entity? = nil, explode: Point = .zero, children: [AtlasPart] = [], size: String? = nil, interiorOnly: Bool = false) -> AtlasPart {
        if !exteriorOnly, let bounds { AtlasGeometry.partCollider(entity, size: bounds, center: focus) }
        return AtlasPart(id: id, label: label, symbol: symbol, detail: detail, entity: entity, focus: focus,
                         focusDistance: distance, shell: shell, interior: interior, section: section, explodeOffset: explode,
                         children: children, sizeText: size, interiorOnly: interiorOnly)
    }

    private func shape(_ group: Entity, _ size: Point, _ x: Float, _ y: Float, _ z: Float, _ finish: Finish) {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [finish.material])
        entity.position = p(x, y, z)
        group.addChild(entity)
    }

    private func line(_ group: Entity, _ a: Point, _ b: Point, radius: Float, color: UIColor) {
        group.addChild(AtlasGeometry.cylinder(from: a, to: b, radius: radius, color: color))
    }

    private func station(at x: Float, padding: Float = 0) -> Station {
        let profiles = fuselageStations
        for (a, b) in zip(profiles, profiles.dropFirst()) where x >= a.x && x <= b.x {
            let t = (x - a.x) / (b.x - a.x)
            return Station(x, a.centerY + (b.centerY - a.centerY) * t,
                           a.height + (b.height - a.height) * t + padding,
                           a.halfWidth + (b.halfWidth - a.halfWidth) * t + padding)
        }
        return profiles.last ?? Station(x, 0, 1, 1)
    }

    private func bodyPoint(_ x: Float, _ angle: Float, _ padding: Float = 0) -> Point {
        let profile = station(at: x, padding: padding)
        return p(x, profile.centerY + profile.height * cos(angle), profile.halfWidth * sin(angle))
    }

    private func tube(_ profiles: [Station], z: Float = 0, start: Float = 0, end: Float = .pi * 2,
                      slices: Int = 52, inner: Bool = false, finish: Finish) -> Entity {
        var mesh = Mesh()
        let step = (end - start) / Float(slices)
        for (index, profile) in profiles.enumerated() {
            let previous = profiles[max(0, index - 1)]
            let next = profiles[min(profiles.count - 1, index + 1)]
            let run = max(0.001, next.x - previous.x)
            let rise = (next.centerY - previous.centerY) / run
            let dHeight = (next.height - previous.height) / run
            let dWidth = (next.halfWidth - previous.halfWidth) / run
            for ring in 0...slices {
                let angle = start + Float(ring) * step
                let cosine = cos(angle)
                let sine = sin(angle)
                mesh.vertices.append(p(profile.x, profile.centerY + profile.height * cosine, z + profile.halfWidth * sine))
                let axial = Point(1, rise + dHeight * cosine, dWidth * sine)
                let tangent = Point(0, -profile.height * sine, profile.halfWidth * cosine)
                let normal = simd_normalize(simd_cross(tangent, axial))
                mesh.normals.append(inner ? -normal : normal)
            }
        }
        let stride = slices + 1
        for row in 0..<(profiles.count - 1) {
            for col in 0..<slices {
                let a = UInt32(row * stride + col)
                let b = UInt32((row + 1) * stride + col)
                mesh.triangles.append(contentsOf: inner ? [a, b, b + 1, a, b + 1, a + 1] : [a, a + 1, b + 1, a, b + 1, b])
            }
        }
        return mesh.entity(finish)
    }

    private func addFuselageLivery(to group: Entity, stations: [Station], visible: ClosedRange<Float> = 0...(2 * Float.pi)) {
        func band(_ run: ClosedRange<Float>, mirror: Bool = true, accent: Bool = false, angles: (Float) -> ClosedRange<Float>) {
            addPaintBand(to: group, stations: stations, run: run, visible: visible, mirror: mirror,
                         finish: accent ? accentPaint : primaryPaint, padding: accent ? 0.022 : 0.014, angles: angles)
        }

        switch palette.pattern {
        case .lowStripe:
            band(0.066...0.966) { _ in 1.46...1.55 }
            band(0.089...0.95, accent: true) { _ in 1.58...1.63 }
        case .tailSweep:
            band(0.56...0.998, mirror: false) { t in
                let start: Float = 3.12 - 2.92 * t * t
                return start...(2 * .pi - start)
            }
            band(0.58...0.962, accent: true) { t in
                let sweep: Float = 2.99 - 2.31 * t * t
                return (sweep - 0.08)...(sweep + 0.05 + t * 0.13)
            }
        case .wideBelly:
            band(0.038...0.989, mirror: false) { t in
                let edge: Float = 1.71 + 0.65 * pow(abs(t * 2 - 1), 5)
                return edge...(2 * .pi - edge)
            }
            band(0.14...0.94, accent: true) { t in
                let edge: Float = 1.62 + 0.56 * pow(abs(t * 2 - 1), 5)
                return edge...(edge + 0.075)
            }
        case .ribbon:
            band(0.05...0.975) { t in
                let rise: Float = 1.86 - 0.64 * sin(t * .pi * 1.23)
                return rise...(rise + 0.16 + 0.23 * sin(t * .pi))
            }
            band(0.105...0.965, accent: true) { t in
                let rise: Float = 1.82 - 0.65 * sin(t * .pi * 1.28)
                return (rise - 0.19)...(rise - 0.035)
            }
        case .fullBody:
            band(0.034...0.993, mirror: false) { t in
                let edge: Float = 1.86 - 0.34 * sin(t * .pi * 1.2)
                return edge...(2 * .pi - edge)
            }
            band(0.085...0.966, accent: true) { t in
                let edge: Float = 1.82 - 0.34 * sin(t * .pi * 1.15)
                return (edge - 0.11)...edge
            }
        }
    }

    private func addPaintBand(to group: Entity, stations: [Station], run: ClosedRange<Float>, visible: ClosedRange<Float>,
                              mirror: Bool, finish: Finish, padding: Float, angles: (Float) -> ClosedRange<Float>) {
        let start = length * run.lowerBound, end = length * run.upperBound
        let sampleCount = 28, slices = 24
        let samples = (0...sampleCount).map { start + (end - start) * Float($0) / Float(sampleCount) }
        let rows = Set(samples + stations.map(\.x).filter { $0 > start && $0 < end }).sorted()
        let turn = 2 * Float.pi
        for side in 0..<(mirror ? 2 : 1) {
            var mesh = Mesh()
            var offsets: [Float] = []
            for x in rows {
                let sector = angles((x - start) / (end - start))
                let low = side == 0 ? sector.lowerBound : turn - sector.upperBound
                let high = side == 0 ? sector.upperBound : turn - sector.lowerBound
                let a = min(visible.upperBound, max(visible.lowerBound, low))
                let b = min(visible.upperBound, max(visible.lowerBound, high))
                offsets.append(b - a)
                for slice in 0...slices {
                    let angle = a + (b - a) * Float(slice) / Float(slices)
                    mesh.vertices.append(variantSurface(stations, x: x, angle: angle, padding: padding))
                    mesh.normals.append([0, cos(angle), sin(angle)])
                }
            }
            for row in 0..<(rows.count - 1) where offsets[row] > 0 || offsets[row + 1] > 0 {
                for slice in 0..<slices {
                    let a = UInt32(row * (slices + 1) + slice)
                    let b = a + UInt32(slices + 1)
                    mesh.triangles.append(contentsOf: [a, a + 1, b + 1, a, b + 1, b])
                }
            }
            if !mesh.triangles.isEmpty { group.addChild(mesh.entity(finish)) }
        }
    }

    private func body() -> AtlasPart {
        let exterior = Entity()
        exterior.addChild(tube(fuselageStations, finish: fuselageFinish))
        installTubeColliders(on: exterior, stations: fuselageStations)
        addFuselageLivery(to: exterior, stations: fuselageStations)
        addCockpitGlass(to: exterior)
        addCabinWindows(to: exterior)
        addDoors(to: exterior)
        if exteriorOnly {
            return part("fuselage", "机身", "airplane", "机身外壳", entity: exterior, focus: p(32, 0.1), distance: 79)
        }

        let entity = Entity()
        let inside = Entity()
        let cut = Entity()
        let rimAngles: [Float] = [2.74, 6.10]
        cut.addChild(tube(fuselageStations, start: rimAngles[0], end: rimAngles[1], finish: fuselageFinish))
        addFuselageLivery(to: cut, stations: fuselageStations, visible: rimAngles[0]...rimAngles[1])
        let cutProfiles = fuselageStations.map { Station($0.x, $0.centerY, max(0.025, $0.height - 0.09), max(0.025, $0.halfWidth - 0.09)) }
        cut.addChild(tube(cutProfiles, start: rimAngles[0], end: rimAngles[1], inner: true, finish: interiorWhite))
        for angle in rimAngles {
            cut.addChild(tube(fuselageStations, start: angle - 0.018, end: angle + 0.018, slices: 2, finish: Finish(color: edgeColor)))
        }
        for x: Float in [10, 17, 24, 32, 40, 48, 54] {
            let profiles = [station(at: x, padding: -0.13), station(at: x + 0.08, padding: -0.13)]
            cut.addChild(tube(profiles, start: 2.8, end: 6.05, slices: 24, inner: true, finish: metal))
        }
        cut.isEnabled = false
        let flightDeck = cockpit()
        let cabin = passengerCabin()
        let holds = cargo()
        for child in [flightDeck, cabin, holds] { inside.addChild(child.entity) }
        inside.isEnabled = false
        entity.addChild(exterior)
        entity.addChild(inside)
        entity.addChild(cut)
        return part("fuselage", "机身", "airplane", "机身容纳驾驶舱、客舱和下层货舱。切换内部、透视或剖视可查看分层布置。",
                    entity: entity, focus: p(32, 0.1), distance: 79, shell: exterior, interior: inside,
                    section: cut, children: [flightDeck, cabin, holds], size: "长 \(length.formatted(.number.precision(.fractionLength(1)))) m")
    }

    private func addCabinWindows(to exterior: Entity) {
        var panes = Mesh()
        var borders = Mesh()
        let doors: [Float] = [8.15, 22.65, 39.3, 53.5]
        for seatRow in 0..<66 {
            let x = 8.8 + Float(seatRow) * 0.69
            if doors.contains(where: { abs(x - $0) < 0.82 }) { continue }
            for side: Float in [1, -1] {
                for (outline, boundary) in [(true, Float(0.022)), (false, Float(0.048))] {
                    let center = side * 1.29
                    let arc = (0..<16).map { index -> Point in
                        let t = Float(index) * .pi / 8
                        let dx = (outline ? Float(0.142) : 0.111) * cos(t)
                        let dy = (outline ? Float(0.197) : 0.155) * sin(t)
                        return bodyPoint(x + dx, center + dy / 2.98, boundary)
                    }
                    if outline { borders.face(arc, normal: [0, 0.27, side]) }
                    else { panes.face(arc, normal: [0, 0.27, side]) }
                }
            }
        }
        exterior.addChild(borders.entity(wingFinish))
        exterior.addChild(panes.entity(darkGlass))
    }

    private func addDoors(to exterior: Entity) {
        let labels: [Float] = [8.15, 22.65, 39.3, 53.5]
        for x in labels {
            for side: Float in [1, -1] {
                let boundary: [(Float, Float)] = [(x - 0.47, 1.05), (x - 0.35, 0.99), (x + 0.35, 0.99), (x + 0.48, 1.06),
                                                    (x + 0.48, 1.77), (x + 0.35, 1.82), (x - 0.36, 1.82), (x - 0.47, 1.77), (x - 0.47, 1.05)]
                for (a, b) in zip(boundary, boundary.dropFirst()) {
                    line(exterior, bodyPoint(a.0, side * a.1, 0.034), bodyPoint(b.0, side * b.1, 0.034), radius: 0.014,
                         color: Self.color(0.40, 0.47, 0.49))
                }
                line(exterior, bodyPoint(x + 0.15, side * 1.46, 0.071), bodyPoint(x + 0.35, side * 1.46, 0.071), radius: 0.027,
                     color: Self.color(0.25, 0.31, 0.34))
            }
        }
    }

    private func addCockpitGlass(to exterior: Entity) {
        var border = Mesh()
        var glass = Mesh()
        typealias Coordinate = SIMD2<Float>
        let windowPatches: [[Coordinate]] = [
            [[2.08, 0.09], [3.23, 0.10], [3.65, 0.44], [2.53, 0.51]],
            [[2.61, 0.59], [3.72, 0.50], [4.28, 0.71], [3.09, 0.81]],
            [[3.21, 0.86], [4.38, 0.76], [4.87, 0.95], [3.85, 1.06]],
        ]
        let mask: [[Coordinate]] = [
            [[1.99, 0.041], [3.33, 0.047], [4.30, 0.65], [2.57, 0.67]],
            [[2.57, 0.67], [4.30, 0.65], [4.97, 1.01], [3.81, 1.11]],
        ]
        for side: Float in [1, -1] {
            func addPatch(_ patch: [Coordinate], offset: Float, to mesh: inout Mesh) {
                let samples = 9
                func location(_ t: Float, _ v: Float) -> Point {
                    let near = patch[0] + (patch[1] - patch[0]) * t
                    let far = patch[3] + (patch[2] - patch[3]) * t
                    let local = near + (far - near) * v
                    return bodyPoint(local.x, local.y * side, offset)
                }
                for row in 0..<samples {
                    for column in 0..<samples {
                        let u = Float(row) / Float(samples)
                        let uNext = Float(row + 1) / Float(samples)
                        let v = Float(column) / Float(samples)
                        let vNext = Float(column + 1) / Float(samples)
                        let corners = [location(u, v), location(uNext, v), location(uNext, vNext), location(u, vNext)]
                        mesh.face(corners, normal: simd_normalize([-0.36, 0.69, 0.63 * side]))
                    }
                }
            }
            for patch in mask { addPatch(patch, offset: 0.021, to: &border) }
            for patch in windowPatches { addPatch(patch, offset: 0.035, to: &glass) }
        }
        exterior.addChild(border.entity(Finish(color: Self.color(0.045, 0.064, 0.08), roughness: 0.41)))
        exterior.addChild(glass.entity(Finish(color: Self.color(0.10, 0.21, 0.26), roughness: 0.19, metallic: 0.37)))
    }

    private func installTubeColliders(on entity: Entity, stations: [Station], sideOffset: Float = 0) {
        guard !exteriorOnly else { return }
        let groups = stride(from: 0, to: stations.count - 1, by: 5).map { start in
            stations[start...min(start + 5, stations.count - 1)]
        }
        let convexSections = groups.map { cluster in
            let points: [Point] = cluster.flatMap { item in
                (0..<20).map { index in
                    let degree = 2 * Float.pi * Float(index) / 20
                    return p(item.x, item.centerY + item.height * cos(degree), sideOffset + item.halfWidth * sin(degree))
                }
            }
            return ShapeResource.generateConvex(from: points)
        }
        entity.components.set(CollisionComponent(shapes: convexSections))
        entity.components.set(InputTargetComponent())
    }

    private func cockpit() -> AtlasPart {
        let entity = Entity()
        shape(entity, [4.5, 0.13, 3.10], 5.0, -0.72, 0, Finish(color: cabinFloor))
        shape(entity, [0.26, 1.48, 2.62], 4.01, 0.20, 0, carbon)
        shape(entity, [0.80, 0.39, 2.58], 4.40, 0.56, 0, carbon)
        shape(entity, [1.40, 0.66, 0.47], 5.62, -0.39, 0, wingFinish)
        for side: Float in [1, -1] {
            let z = side * 0.74
            shape(entity, [0.67, 0.20, 0.61], 5.75, -0.29, z, cabinPaint)
            shape(entity, [0.17, 0.89, 0.58], 6.04, 0.25, z, cabinPaint)
            shape(entity, [0.15, 0.24, 0.33], 6.04, 0.77, z, interiorWhite)
            shape(entity, [0.70, 0.23, 0.21], 5.81, 0.10, z + side * 0.33, metal)
            for i in 0..<3 {
                let screenZ = side * (0.24 + Float(i) * 0.37)
                shape(entity, [0.042, 0.30, 0.31], 4.18, 0.28, screenZ, darkGlass)
                shape(entity, [0.047, 0.042, 0.24], 4.21, 0.33, screenZ, accentPaint)
            }
        }
        return part("cockpit", "驾驶舱", "gauge.with.dots.needle.50percent", "两席主驾驶位置、仪表屏、中央操纵台与侧杆为布局示意。",
                    entity: entity, focus: p(5.3, 0.15), distance: 9.8, bounds: [4.4, 2.2, 3.7], explode: [-6, 5.5, 0], interiorOnly: true)
    }

    private func passengerCabin() -> AtlasPart {
        let entity = Entity()
        shape(entity, [47.2, 0.15, 5.35], 31.5, -0.77, 0, Finish(color: cabinFloor))
        for side: Float in [1, -1] {
            shape(entity, [45.8, 0.28, 0.48], 31.5, 1.97, side * 2.12, interiorWhite)
            shape(entity, [45.8, 0.035, 0.043], 31.5, 1.80, side * 2.0, Finish(color: Self.color(0.72, 0.88, 1)))
        }
        var subparts: [AtlasPart] = []
        for (index, zone) in configuration.seats.enumerated() {
            let section = Entity()
            let run = zone.endM - zone.startM
            guard run > 0, zone.numberOfRows > 0, !zone.seatGroups.isEmpty else { continue }
            let pitch = run / Float(zone.numberOfRows)
            let berths = zone.seatGroups.reduce(0, +)
            let width: Float = berths <= 4 ? 0.73 : 0.47
            let gap: Float = berths <= 4 ? 0.65 : 0.47
            let total = Float(berths) * (width + 0.055) + Float(zone.seatGroups.count - 1) * gap
            var frames = Mesh()
            var cushions = Mesh()
            var accents = Mesh()
            for rowIndex in 0..<zone.numberOfRows {
                let x = zone.startM + (Float(rowIndex) + 0.5) * pitch
                let row = rowIndex == zone.numberOfRows - 1 ? zone.partialLastRow ?? zone.seatGroups : zone.seatGroups
                var currentZ = -total / 2
                for (block, capacity) in zip(row, zone.seatGroups) {
                    for slot in 0..<capacity {
                        let z = currentZ + width / 2
                        currentZ += width + 0.055
                        guard slot < block else { continue }
                        let seatLength = min(pitch * 0.48, berths <= 4 ? 0.67 : 0.42)
                        frames.box(center: p(x, -0.57, z), size: [seatLength * 1.11, 0.31, width * 0.88])
                        cushions.box(center: p(x, -0.35, z), size: [seatLength, 0.15, width * 0.87])
                        cushions.box(center: p(x + seatLength * 0.48, 0.04, z), size: [0.15, 0.81, width * 0.88])
                        accents.box(center: p(x + seatLength * 0.48, 0.42, z), size: [0.18, 0.17, width * 0.66])
                        if berths <= 4 {
                            frames.box(center: p(x + 0.05, -0.15, z - width * 0.53), size: [seatLength * 1.32, 0.78, 0.075])
                        }
                    }
                    currentZ += gap
                }
            }
            section.addChild(frames.entity(interiorWhite))
            section.addChild(cushions.entity(index.isMultiple(of: 2) ? cabinPaint : Finish(color: Self.color(0.17, 0.29, 0.35))))
            section.addChild(accents.entity(accentPaint))
            entity.addChild(section)
            subparts.append(part("cabin-zone-\(index)", zone.label, "seat.fill", "根据当前配置展示座位分组与相对位置。",
                                 entity: section, focus: p((zone.startM + zone.endM) / 2, 0), distance: min(38, max(11, run * 1.37)),
                                 bounds: [run, 1.35, 5.1], explode: [Float(index) * 2 - 4, 4.2, 2 + Float(index) * 1.7],
                                 size: "\(zone.seatCount) 座 · \(zone.seatGroups.map(String.init).joined(separator: "–")) 布局"))
        }
        for x: Float in [9.0, 22.65, 39.3, 53.5] {
            for side: Float in [1, -1] {
                shape(entity, [0.65, 1.84, 0.53], x, 0.20, side * 2.19, interiorWhite)
            }
        }
        return part("cabin", "客舱", "seat.fill", configuration.cabinDescription, entity: entity, focus: p(30, 0.6), distance: 62,
                    bounds: [46, 1.9, 5.1], explode: [0, 6.2, 5.0], children: subparts, interiorOnly: true)
    }

    private func cargo() -> AtlasPart {
        let entity = Entity()
        var containers = Mesh()
        var doors = Mesh()
        for x: Float in [14, 16, 18, 20, 22, 38, 40, 42, 44, 46, 48, 50] {
            for side: Float in [1, -1] {
                containers.box(center: p(x, -1.72, side * 0.91), size: [1.57, 1.05, 1.47])
                doors.box(center: p(x, -1.75, side * 1.655), size: [1.42, 0.83, 0.031])
            }
        }
        entity.addChild(containers.entity(metal))
        entity.addChild(doors.entity(wingFinish))
        shape(entity, [38, 0.09, 3.3], 32, -2.32, 0, Finish(color: cabinFloor))
        return part("cargo", "下层货舱", "shippingbox.fill", "客舱下方的前、后货舱展示航空集装箱和承载地板。",
                    entity: entity, focus: p(31, -1.65), distance: 56, bounds: [39, 1.4, 3.2], explode: [0, -6.5, -2.5], interiorOnly: true)
    }

    private func airfoil(_ stations: [WingStation], range: ClosedRange<Float> = 0...1, samples: Int = 10,
                         finish: Finish, position: (WingStation, Float, Float) -> Point) -> Entity {
        var mesh = Mesh()
        for sign: Float in [1, -1] {
            for (one, two) in zip(stations, stations.dropFirst()) {
                for segment in 0..<samples {
                    let progress = Float(segment) / Float(samples)
                    let next = Float(segment + 1) / Float(samples)
                    let lower = range.lowerBound
                    let width = range.upperBound - lower
                    let a = lower + progress * width
                    let b = lower + next * width
                    let corners = [position(one, a, sign), position(one, b, sign), position(two, b, sign), position(two, a, sign)]
                    let edge = corners[1] - corners[0]
                    let across = corners[3] - corners[0]
                    let cross = simd_cross(edge, across)
                    guard simd_length_squared(cross) > 0.0000001 else { continue }
                    var normal = simd_normalize(cross)
                    let up = position(one, (a + b) / 2, 1.2) - position(one, (a + b) / 2, 0)
                    if simd_dot(normal, up) * sign < 0 { normal = -normal }
                    mesh.face(corners, normal: normal)
                }
            }
        }
        return mesh.entity(finish)
    }

    private func airfoilY(_ fraction: Float, depth: Float, surface: Float) -> Float {
        let f = max(0.001, min(0.999, fraction))
        let t = 4 * sqrt(f) * (1 - f) * (1 - f / 2)
        return depth * t * surface + depth * sin(f * .pi) * 0.25
    }

    private func wing(side: Float) -> AtlasPart {
        let entity = Entity()
        let identifier = side < 0 ? "wing-right" : "wing-left"
        let wingLabel = side < 0 ? "右机翼" : "左机翼"
        let tip = span / 2
        let profiles = [WingStation(1.62, 22.5, 39.55, -1.09, 0.61), WingStation(3.2, 23.0, 39.3, -1.22, 0.64),
                        WingStation(8.6, 26.7, 42.10, -0.83, 0.46), WingStation(13.5, 30.35, 44.0, -0.38, 0.34),
                        WingStation(20.8, 35.35, 47.3, 0.20, 0.24), WingStation(26.0, 39.35, 49.0, 0.81, 0.18),
                        WingStation(tip - 3.9, 41.8, 49.85, 1.22, 0.16)]
        let wingletProfile = [profiles[profiles.count - 1], WingStation(tip - 2.2, 43.3, 49.9, 1.49, 0.11),
                              WingStation(tip - 0.96, 45.3, 50.04, 2.0, 0.083), WingStation(tip - 0.32, 47.1, 50.51, 2.59, 0.052),
                              WingStation(tip, 49.05, 50.84, 3.35, 0.034)]
        let position: (WingStation, Float, Float) -> Point = { station, fraction, surface in
            let x = station.front + (station.rear - station.front) * fraction
            return p(x, station.height + airfoilY(fraction, depth: station.thickness, surface: surface), side * station.span)
        }
        entity.addChild(airfoil(profiles, range: 0.003...0.78, finish: wingFinish, position: position))
        entity.addChild(airfoil(profiles, range: 0...0.105, finish: metal, position: { s, f, sign in
            position(s, f, sign * 1.028) + Point(0, sign * 0.006, 0)
        }))
        let flaps = Entity()
        flaps.addChild(airfoil(Array(profiles.prefix(5)), range: 0.789...1, finish: controlFinish, position: position))
        for (x, y, z) in [(36.5 as Float, -1.00 as Float, 8.9 as Float), (40.0, -0.81, 13.7), (44.4, -0.39, 19.1)] {
            let radius: Float = 0.19
            let fairings = [Station(x - 1.8, y, 0.025, 0.025), Station(x - 0.7, y, radius, radius),
                            Station(x + 1.2, y, radius * 0.89, radius * 0.85), Station(x + 2.7, y + 0.1, 0.035, 0.03)]
            flaps.addChild(tube(fairings, z: z * side, slices: 16, finish: wingFinish))
        }
        let flapsPart = part(identifier + "-flaps", "内侧襟翼", "airplane", "后缘内侧的增升翼面。翼下的细长整流罩覆盖部分襟翼机构。",
                             entity: flaps, focus: p(39, -0.57, 11 * side), distance: 28, bounds: [14, 1.1, 18.1], explode: [4, -3.2, 2 * side])
        let outer = Entity()
        outer.addChild(airfoil(Array(profiles.suffix(3)), range: 0.793...1, finish: controlFinish, position: position))
        let outerPart = part(identifier + "-aileron", "外侧副翼", "airplane", "后缘外侧的活动翼面用于滚转控制。模型中与主翼独立。",
                             entity: outer, focus: p(46.6, 0.8, 25.7 * side), distance: 16, bounds: [6.7, 0.75, 8], explode: [5, 2, 3.4 * side])
        let winglet = Entity()
        winglet.addChild(airfoil(wingletProfile, finish: primaryPaint, position: position))
        let navigation = ModelEntity(mesh: .generateSphere(radius: 0.13), materials: [UnlitMaterial(color: side < 0 ? .systemGreen : .systemRed)])
        navigation.position = p(49.25, 3.32, (tip - 0.06) * side)
        winglet.addChild(navigation)
        let wingletPart = part(identifier + "-tip", "翼梢小翼", "arrow.up.right", "向外扫掠并上翘的翼梢减弱翼尖涡流。航行灯为右绿左红。",
                               entity: winglet, focus: p(47.3, 2.3, (tip - 1.85) * side), distance: 10, bounds: [7.7, 3.0, 4.8], explode: [0.7, 3, 6 * side])
        for child in [flapsPart, outerPart, wingletPart] { entity.addChild(child.entity) }
        return part(identifier, wingLabel, "airplane", "后掠翼采用渐变翼型和上翘翼梢。可单独查看襟翼、副翼与翼梢小翼。",
                    entity: entity, focus: p(36, 0, 15.9 * side), distance: 51, bounds: [22, 2.0, 23],
                    explode: [0, 0.7, 10.4 * side], children: [flapsPart, outerPart, wingletPart],
                    size: "全机翼展 \(span.formatted(.number.precision(.fractionLength(2)))) m")
    }

    private func engine(side: Float) -> AtlasPart {
        let identifier = side < 0 ? "engine-right" : "engine-left"
        let z = side * 10.15
        let y: Float = -2.65
        let x: Float = 23.3
        let entity = Entity()
        let profiles = [Station(x, y, 1.58, 1.58), Station(x + 0.19, y, 1.74, 1.76), Station(x + 0.64, y, 1.88, 1.86),
                        Station(x + 1.72, y + 0.04, 1.93, 1.90), Station(x + 3.55, y + 0.11, 1.81, 1.79),
                        Station(x + 5.65, y + 0.18, 1.43, 1.40), Station(x + 6.35, y + 0.22, 1.22, 1.22)]
        let entry = [Station(x - 0.015, y, 1.51, 1.51), Station(x + 0.17, y, 1.70, 1.71), Station(x + 0.43, y, 1.84, 1.83)]
        let duct = [Station(x - 0.02, y, 1.51, 1.51), Station(x + 0.22, y, 1.55, 1.55), Station(x + 1.25, y, 1.52, 1.52)]
        let shell = Entity()
        shell.addChild(tube(profiles, z: z, slices: 76, finish: nacelleFinish))
        shell.addChild(tube([
            Station(x + 1.64, y + 0.037, 1.939, 1.908),
            Station(x + 1.73, y + 0.041, 1.945, 1.915),
            Station(x + 1.77, y + 0.042, 1.941, 1.910)
        ], z: z, slices: 76, finish: nacelleSeam))
        installTubeColliders(on: shell, stations: profiles, sideOffset: z)
        shell.addChild(tube(entry, z: z, finish: metal))
        shell.addChild(tube(duct, z: z, inner: true, finish: carbon))
        let pylons = [WingStation(8.25, x + 2.0, x + 6.7, -1.1, 0.16), WingStation(10.15, x + 1.35, x + 7.1, -0.85, 0.34),
                      WingStation(11.59, x + 2.0, x + 6.85, -1.14, 0.16)]
        shell.addChild(airfoil(pylons, finish: wingFinish) { width, fraction, sign in
            p(width.front + (width.rear - width.front) * fraction, width.height + self.airfoilY(fraction, depth: width.thickness, surface: sign), width.span * side)
        })
        shape(shell, [4.5, 0.73, 0.56], x + 4.05, -1.26, z, wingFinish)

        let fan = Entity()
        fan.addChild(bladeDisk(x: x + 0.71, y: y, z: z, root: 0.31, radius: 1.49, count: 22, finish: metal))
        fan.addChild(tube([Station(x + 0.16, y, 0.035, 0.035), Station(x + 0.42, y, 0.18, 0.18), Station(x + 0.88, y, 0.34, 0.34),
                           Station(x + 1.0, y, 0.35, 0.35)], z: z, slices: 36, finish: carbon))
        let nozzle = tube([Station(x + 6.33, y + 0.22, 1.21, 1.21), Station(x + 6.55, y + 0.22, 0.99, 0.99),
                           Station(x + 7.08, y + 0.14, 0.53, 0.53), Station(x + 7.65, y + 0.12, 0.15, 0.15)], z: z, finish: carbon)
        shell.addChild(nozzle)
        if exteriorOnly {
            entity.addChild(shell)
            entity.addChild(fan)
            return part(identifier, side < 0 ? "右发动机" : "左发动机", "fanblades.fill", "Rolls-Royce Trent XWB",
                        entity: entity, focus: p(x + 3, y, z), distance: 16)
        }

        let fanPart = part(identifier + "-fan", "进气风扇", "fanblades.fill", "风扇将空气导入发动机，大部分气流沿外涵道流过。独立叶片的造型为教学示意。",
                           entity: fan, focus: p(x + 0.72, y, z), distance: 6.7, bounds: [0.55, 3.0, 3.0], explode: [-5.0, 1.3, 0])

        let inside = Entity()
        let compressor = Entity()
        compressor.addChild(tube([Station(x + 1.18, y, 0.7, 0.7), Station(x + 3.56, y, 0.46, 0.46), Station(x + 4.2, y, 0.58, 0.58)],
                                 z: z, finish: carbon))
        for i in 0..<8 {
            let stage = Float(i)
            compressor.addChild(bladeDisk(x: x + 1.49 + stage * 0.27, y: y, z: z, root: 0.4,
                                          radius: 0.94 - stage * 0.043, count: 24, finish: metal))
        }
        let compressorPart = part(identifier + "-compressor", "压气机", "circle.dotted.circle.fill", "多级叶片向燃烧室提供压缩空气。各叶盘和中心轴的数量与细节为示意。",
                                  entity: compressor, focus: p(x + 2.33, y, z), distance: 5.7, bounds: [2.7, 1.8, 1.8], explode: [-1.75, 3.3, -0.4 * side], interiorOnly: true)
        let combustor = Entity()
        let bronze = Finish(color: Self.color(0.72, 0.42, 0.21), roughness: 0.49, metallic: 0.52)
        combustor.addChild(tube([Station(x + 3.5, y, 0.48, 0.48), Station(x + 3.8, y, 0.61, 0.61), Station(x + 4.45, y, 0.58, 0.58)], z: z, finish: bronze))
        for index in 0..<12 {
            let angle = Float(index) * .pi / 6
            let c = p(x + 4.1, y + 0.594 * cos(angle), z + 0.594 * sin(angle))
            line(combustor, c + Point(-0.45, 0, 0), c + Point(0.24, 0, 0), radius: 0.085, color: bronze.color)
        }
        let combustionPart = part(identifier + "-combustor", "环形燃烧室", "flame.fill", "示意压缩空气、燃烧和涡轮之间的位置关系。",
                                  entity: combustor, focus: p(x + 4.03, y, z), distance: 3.9, bounds: [0.93, 1.29, 1.29], explode: [0.30, 4.8, 1.35 * side], interiorOnly: true)
        let turbine = Entity()
        turbine.addChild(tube([Station(x + 4.40, y, 0.47, 0.47), Station(x + 5.82, y, 0.67, 0.67), Station(x + 6.95, y, 0.37, 0.37),
                               Station(x + 7.64, y, 0.13, 0.13)], z: z, finish: carbon))
        for i in 0..<5 {
            let stage = Float(i)
            turbine.addChild(bladeDisk(x: x + 4.52 + stage * 0.25, y: y, z: z, root: 0.46,
                                       radius: 0.73 + stage * 0.055, count: 25, finish: metal))
        }
        let turbinePart = part(identifier + "-turbine", "涡轮与尾喷管", "circle.hexagongrid.fill", "涡轮从热气流提取能量驱动风扇和压气机。尾部喷管引导流体排出。",
                               entity: turbine, focus: p(x + 5.75, y, z), distance: 6.7, bounds: [3.4, 1.6, 1.6], explode: [4.7, 2.4, 0], interiorOnly: true)
        for child in [compressorPart, combustionPart, turbinePart] { inside.addChild(child.entity) }
        let section = Entity()
        section.addChild(tube(profiles, z: z, start: 2.93, end: 6.0, finish: nacelleFinish))
        section.addChild(tube(duct, z: z, start: 2.93, end: 6.0, inner: true, finish: metal))
        for angle: Float in [2.93, 6.0] {
            section.addChild(tube(profiles, z: z, start: angle - 0.028, end: angle + 0.028, slices: 2, finish: Finish(color: edgeColor)))
        }
        inside.isEnabled = false
        section.isEnabled = false
        for element in [shell, fan, inside, section] { entity.addChild(element) }
        return part(identifier, side < 0 ? "右发动机" : "左发动机", "fanblades.fill", "A350-900 配备两台 Rolls-Royce Trent XWB。示意模型可拆分查看风扇、压气机、燃烧室和涡轮。",
                    entity: entity, focus: p(x + 3, y, z), distance: 16, shell: shell, interior: inside,
                    section: section, explode: [0, -5.2, 4 * side], children: [fanPart, compressorPart, combustionPart, turbinePart])
    }

    private func bladeDisk(x: Float, y: Float, z: Float, root: Float, radius: Float, count: Int, finish: Finish) -> Entity {
        var blades = Mesh()
        let angleStep = 2 * Float.pi / Float(count)
        for blade in 0..<count {
            let base = Float(blade) * angleStep
            let inside = p(x + 0.25, y + root * cos(base), z + root * sin(base))
            let insideBack = p(x + 0.52, y + root * cos(base + angleStep * 0.58), z + root * sin(base + angleStep * 0.58))
            let outsideAngle = base + angleStep * 0.85
            let outside = p(x - 0.10, y + radius * cos(outsideAngle), z + radius * sin(outsideAngle))
            let outsideBack = p(x + 0.21, y + radius * cos(outsideAngle + angleStep * 0.68), z + radius * sin(outsideAngle + angleStep * 0.68))
            let direction = simd_normalize(Point(-0.86, cos(base) * 0.38, sin(base) * 0.38))
            blades.face([inside, outside, outsideBack, insideBack], normal: direction)
            blades.face([inside, insideBack, outsideBack, outside], normal: -direction)
        }
        return blades.entity(finish)
    }

    private func addFinLivery(to fin: Entity, stations: [WingStation], position: (WingStation, Float, Float) -> Point) {
        fin.addChild(airfoil(stations, range: 0...0.75, finish: primaryPaint, position: position))
        guard let first = stations.first, let last = stations.last else { return }
        let shape: (start: Float, width: Float, sweep: Float) = switch palette.pattern {
        case .lowStripe: (0.24, 0.12, 0.24)
        case .tailSweep: (0.13, 0.24, 0.34)
        case .wideBelly: (0.46, 0.17, -0.27)
        case .ribbon: (0.29, 0.24, 0.16)
        case .fullBody: (0.14, 0.31, 0.21)
        }
        fin.addChild(airfoil(stations, range: 0...1, finish: accentPaint) { station, fraction, side in
            let rise = (station.span - first.span) / max(0.001, last.span - first.span)
            let chord = shape.start + shape.sweep * rise + shape.width * fraction
            return position(station, chord, side) + Point(0, 0, side * 0.017)
        })
    }

    private func tail() -> AtlasPart {
        let entity = Entity()
        let vertical = [WingStation(2.0, 49.0, 63.1, 0, 0.61), WingStation(3.7, 51.3, 62.9, 0, 0.46),
                        WingStation(6.8, 55.4, 63.15, 0, 0.32), WingStation(10.9, 59.0, 64.15, 0, 0.17),
                        WingStation(11.45, 59.85, 64.06, 0, 0.105)]
        let finPosition: (WingStation, Float, Float) -> Point = { station, fraction, surface in
            p(station.front + (station.rear - station.front) * fraction, station.span,
              airfoilY(fraction, depth: station.thickness, surface: surface))
        }
        let fin = Entity()
        addFinLivery(to: fin, stations: vertical, position: finPosition)
        let finPart = part("tail-fin", "垂直安定面", "triangle", "垂直安定面帮助飞机在偏航方向恢复稳定。涂装使用代表性色带。",
                           entity: fin, focus: p(57, 7.2), distance: 18, bounds: [13.8, 9.3, 1.1], explode: [-0.5, 4, -0.8])
        let rudder = airfoil(vertical, range: 0.76...1, finish: primaryPaint, position: finPosition)
        let rudderPart = part("tail-rudder", "方向舵", "arrow.left.and.right", "安装在垂尾后缘的方向舵控制偏航。",
                             entity: rudder, focus: p(62, 7), distance: 14, bounds: [3.2, 8.8, 0.50], explode: [5.2, 4, 2.8])
        let horizontal = Entity()
        let hProfiles = [WingStation(0.93, 55.7, 64.1, 0.3, 0.29), WingStation(3.4, 57.2, 64.7, 0.63, 0.21),
                         WingStation(7.4, 59.2, 65.4, 1.1, 0.125), WingStation(10.4, 61.9, 66.15, 1.43, 0.057)]
        for side: Float in [1, -1] {
            horizontal.addChild(airfoil(hProfiles, range: 0...0.78, finish: wingFinish) { s, f, sign in
                p(s.front + (s.rear - s.front) * f, s.height + airfoilY(f, depth: s.thickness, surface: sign), s.span * side)
            })
            horizontal.addChild(airfoil(hProfiles, range: 0.79...1, finish: controlFinish) { s, f, sign in
                p(s.front + (s.rear - s.front) * f, s.height + airfoilY(f, depth: s.thickness, surface: sign), s.span * side)
            })
        }
        let horizontalPart = part("tail-horizontal", "水平安定面与升降舵", "arrow.up.and.down", "尾部两侧的水平翼面稳定飞机俯仰，后缘升降舵用于俯仰控制。",
                                  entity: horizontal, focus: p(61.5, 1), distance: 28, bounds: [10.6, 1.6, 21], explode: [7, 0, -3])
        for child in [finPart, rudderPart, horizontalPart] { entity.addChild(child.entity) }
        return part("tail", "尾翼", "paperplane.fill", "尾翼由垂直安定面、方向舵、水平安定面及升降舵组成。",
                    entity: entity, focus: p(59, 5), distance: 30, explode: [8.0, 1.4, 0], children: [finPart, rudderPart, horizontalPart])
    }

    private func landingGear() -> AtlasPart {
        let entity = Entity()
        let front = wheelTruck(x: 10.5, z: 0, front: true)
        let left = wheelTruck(x: 35.4, z: 4.8, front: false)
        let right = wheelTruck(x: 35.4, z: -4.8, front: false)
        let frontPart = part("nose-gear", "前起落架", "circle.circle", "双轮前起落架可转向，收起后位于机鼻的轮舱内。",
                             entity: front, focus: p(10.5, -4.1), distance: 6.7, bounds: [2.1, 3.2, 1.8], explode: [-3, -2.2, 0])
        let leftPart = part("main-gear-left", "左主起落架", "circle.circle", "四轮转向架示意 A350-900 主起落架的轮组、主要支柱与支撑连杆。",
                            entity: left, focus: p(35.4, -4.1, 4.8), distance: 8, bounds: [3.5, 3.2, 2.4], explode: [3, -2.6, 3.7])
        let rightPart = part("main-gear-right", "右主起落架", "circle.circle", "四轮转向架示意 A350-900 主起落架的轮组、主要支柱与支撑连杆。",
                             entity: right, focus: p(35.4, -4.1, -4.8), distance: 8, bounds: [3.5, 3.2, 2.4], explode: [3, -2.6, -3.7])
        for child in [frontPart, leftPart, rightPart] { entity.addChild(child.entity) }
        return part("landing-gear", "起落架", "gearshape.2.fill", "起落架处于放下状态，可独立查看前起落架及两侧主起落架。",
                    entity: entity, focus: p(24.3, -3.3), distance: 39, explode: [0, -6.7, 0], children: [frontPart, leftPart, rightPart])
    }

    private func wheelTruck(x: Float, z: Float, front: Bool) -> Entity {
        let entity = Entity()
        let y: Float = front ? -4.93 : -4.84
        let radius: Float = front ? 0.44 : 0.70
        let axleHalf: Float = front ? 0.56 : 0.96
        let axles = front ? [x] : [x - 0.81, x + 0.81]
        let strutTop: Float = front ? -2.2 : -1.5
        line(entity, p(x - 0.35, strutTop, z * 0.86), p(x, y + 0.22, z), radius: front ? 0.105 : 0.17, color: metal.color)
        line(entity, p(x + 1.55, strutTop + 0.05, z * 0.73), p(x, y + 0.52, z), radius: front ? 0.062 : 0.105, color: wingFinish.color)
        if !front {
            line(entity, p(x - 1.10, y + 0.18, z), p(x + 1.10, y + 0.18, z), radius: 0.16, color: metal.color)
        }
        for axle in axles {
            line(entity, p(axle, y, z - axleHalf), p(axle, y, z + axleHalf), radius: 0.12, color: metal.color)
            for side: Float in [1, -1] {
                let centerZ = z + axleHalf * 0.78 * side
                let width: Float = front ? 0.31 : 0.43
                line(entity, p(axle, y, centerZ - width / 2), p(axle, y, centerZ + width / 2), radius: radius,
                     color: Self.color(0.04, 0.05, 0.065))
                let hubZ = centerZ + (width / 2 + 0.035) * side
                line(entity, p(axle, y, hubZ - 0.055), p(axle, y, hubZ + 0.055), radius: radius * 0.53, color: metal.color)
                line(entity, p(axle, y, hubZ - 0.071), p(axle, y, hubZ + 0.071), radius: radius * 0.24, color: carbon.color)
            }
        }
        return entity
    }
}

private extension AircraftBuilder {
    struct Variant {
        enum Body { case rounded, tapered, pointed, fullDeck, hump }
        enum Tip { case sharklet, blended, canted, split, raked, fence, plain }
        let body: Body
        let tip: Tip
        let width: Float
        let bodyHeight: Float
        let height: Float
        let nose: Float
        let wingRoot: Float
        let wingChord: Float
        let sweep: Float
        let mainAxles: Int
        let bodyAxles: Int
        let engineRadius: Float
        let engineLength: Float
        let engineName: String
        let flatNacelle: Bool
        let chevrons: Bool
        let groundClearance: Float
        let humpEnd: Float
        let cockpitMask: Bool

        var hasUpperDeck: Bool { body == .fullDeck || body == .hump }
        var fourEngines: Bool { hasUpperDeck }
        var groundY: Float { -(bodyHeight / 2 + groundClearance) }
        var upperFloorY: Float { body == .fullDeck ? 1.08 : 1.86 }
        var cabinFloorY: Float { hasUpperDeck ? -1.10 : -bodyHeight * 0.21 }
        var upperDeckEnd: Float { body == .hump ? humpEnd - 0.073 : 0.83 }

        init?(_ id: String) {
            switch id {
            case "a220-300":
                self.init(.tapered, .canted, 3.50, 3.70, 11.50, 5.9, 0.341, 0.275, 0.40, 1, 0, 1.28, 4.10, "Pratt & Whitney PW1500G")
            case "a319":
                self.init(.rounded, .fence, 3.95, 4.14, 11.76, 5.5, 0.301, 0.351, 0.43, 1, 0, 1.11, 3.48, "CFM56-5B 或 IAE V2500")
            case "a320ceo":
                self.init(.rounded, .fence, 3.95, 4.14, 11.76, 5.5, 0.326, 0.322, 0.43, 1, 0, 1.11, 3.48, "CFM56-5B 或 IAE V2500")
            case "a321ceo":
                self.init(.rounded, .sharklet, 3.95, 4.14, 11.76, 5.5, 0.348, 0.307, 0.43, 1, 0, 1.11, 3.48, "CFM56-5B 或 IAE V2500")
            case "a320neo":
                self.init(.rounded, .sharklet, 3.95, 4.14, 11.76, 5.5, 0.326, 0.322, 0.43, 1, 0, 1.28, 4.20, "CFM LEAP-1A 或 Pratt & Whitney PW1100G-JM")
            case "a321neo":
                self.init(.rounded, .sharklet, 3.95, 4.14, 11.76, 5.5, 0.348, 0.307, 0.43, 1, 0, 1.28, 4.20, "CFM LEAP-1A 或 Pratt & Whitney PW1100G-JM")
            case "a330-200":
                self.init(.rounded, .canted, 5.64, 5.65, 17.39, 7.4, 0.295, 0.355, 0.66, 2, 0, 1.59, 6.25, "GE CF6-80E1、Pratt & Whitney PW4000 或 Rolls-Royce Trent 700")
            case "a330-300":
                self.init(.rounded, .canted, 5.64, 5.65, 16.79, 7.4, 0.310, 0.335, 0.66, 2, 0, 1.59, 6.25, "GE CF6-80E1、Pratt & Whitney PW4000 或 Rolls-Royce Trent 700")
            case "a330-900":
                self.init(.rounded, .sharklet, 5.64, 5.65, 16.79, 7.4, 0.310, 0.335, 0.66, 2, 0, 1.83, 7.01, "Rolls-Royce Trent 7000")
            case "a350-1000":
                self.init(.tapered, .sharklet, 5.94, 5.96, 17.08, 8.2, 0.325, 0.334, 0.66, 3, 0, 1.90, 7.18, "Rolls-Royce Trent XWB-97", cockpitMask: true)
            case "a380-800":
                self.init(.fullDeck, .fence, 7.14, 8.40, 24.09, 9.1, 0.308, 0.390, 0.66, 2, 3, 1.91, 7.14, "Rolls-Royce Trent 900 或 Engine Alliance GP7200")
            case "b737-700":
                self.init(.pointed, .blended, 3.76, 4.04, 12.55, 6.05, 0.310, 0.343, 0.46, 1, 0, 1.09, 3.63, "CFM56-7B", flatNacelle: true)
            case "b737-800":
                self.init(.pointed, .blended, 3.76, 4.04, 12.55, 6.05, 0.323, 0.296, 0.46, 1, 0, 1.09, 3.63, "CFM56-7B", flatNacelle: true)
            case "b737-900er":
                self.init(.pointed, .blended, 3.76, 4.04, 12.55, 6.05, 0.334, 0.279, 0.46, 1, 0, 1.09, 3.63, "CFM56-7B", flatNacelle: true)
            case "b737-max8":
                self.init(.pointed, .split, 3.76, 4.04, 12.30, 6.05, 0.322, 0.296, 0.46, 1, 0, 1.18, 4.05, "CFM LEAP-1B", flatNacelle: true, chevrons: true)
            case "b737-max9":
                self.init(.pointed, .split, 3.76, 4.04, 12.30, 6.05, 0.333, 0.279, 0.46, 1, 0, 1.18, 4.05, "CFM LEAP-1B", flatNacelle: true, chevrons: true)
            case "b747-400":
                self.init(.hump, .blended, 6.50, 6.45, 19.40, 8.75, 0.312, 0.365, 0.71, 2, 2, 1.61, 6.42, "GE Aerospace CF6-80C2", humpEnd: 0.40)
            case "b757-200":
                self.init(.tapered, .blended, 3.76, 4.01, 13.56, 6.65, 0.333, 0.290, 0.51, 2, 0, 1.36, 5.16, "Rolls-Royce RB211-535 或 Pratt & Whitney PW2000", groundClearance: 2.20)
            case "b767-300er":
                self.init(.rounded, .blended, 5.03, 5.42, 15.85, 7.3, 0.317, 0.341, 0.57, 2, 0, 1.60, 6.20, "GE CF6-80C2、Pratt & Whitney PW4000 或 Rolls-Royce RB211")
            case "b777-200er":
                self.init(.pointed, .plain, 6.20, 6.15, 18.50, 8.65, 0.302, 0.365, 0.71, 3, 0, 1.77, 7.18, "GE90、Pratt & Whitney PW4000 或 Rolls-Royce Trent 800")
            case "b777-300er":
                self.init(.pointed, .raked, 6.20, 6.15, 18.51, 8.65, 0.317, 0.325, 0.71, 3, 0, 2.02, 8.04, "GE Aerospace GE90-115B")
            case "b787-8":
                self.init(.tapered, .raked, 5.77, 5.77, 16.90, 8.3, 0.301, 0.366, 0.67, 2, 0, 1.82, 6.70, "GE Aerospace GEnx-1B 或 Rolls-Royce Trent 1000", chevrons: true)
            case "b787-9":
                self.init(.tapered, .raked, 5.77, 5.77, 17.02, 8.3, 0.315, 0.338, 0.67, 2, 0, 1.82, 6.70, "GE Aerospace GEnx-1B 或 Rolls-Royce Trent 1000", chevrons: true)
            case "b787-10":
                self.init(.tapered, .raked, 5.77, 5.77, 17.02, 8.3, 0.328, 0.310, 0.67, 2, 0, 1.82, 6.70, "GE Aerospace GEnx-1B 或 Rolls-Royce Trent 1000", chevrons: true)
            case "b747-8i":
                self.init(.hump, .raked, 6.50, 6.45, 19.40, 8.75, 0.323, 0.354, 0.71, 2, 2, 1.77, 6.56, "GE Aerospace GEnx-2B", chevrons: true)
            case "c919":
                self.init(.tapered, .sharklet, 3.96, 4.13, 11.95, 6.65, 0.311, 0.302, 0.485, 1, 0, 1.26, 3.98, "CFM LEAP-1C")
            case "e195-e2":
                self.init(.tapered, .raked, 3.01, 3.50, 10.97, 5.55, 0.339, 0.256, 0.39, 1, 0, 1.12, 3.95, "Pratt & Whitney PW1900G")
            default:
                return nil
            }
        }

        private init(_ body: Body, _ tip: Tip, _ width: Float, _ bodyHeight: Float, _ height: Float, _ nose: Float,
                     _ wingRoot: Float, _ wingChord: Float, _ sweep: Float, _ mainAxles: Int, _ bodyAxles: Int,
                     _ engineRadius: Float, _ engineLength: Float, _ engineName: String,
                     flatNacelle: Bool = false, chevrons: Bool = false, groundClearance: Float? = nil,
                     humpEnd: Float = 0.45, cockpitMask: Bool = false) {
            self.body = body
            self.tip = tip
            self.width = width
            self.bodyHeight = bodyHeight
            self.height = height
            self.nose = nose
            self.wingRoot = wingRoot
            self.wingChord = wingChord
            self.sweep = sweep
            self.mainAxles = mainAxles
            self.bodyAxles = bodyAxles
            self.engineRadius = engineRadius
            self.engineLength = engineLength
            self.engineName = engineName
            self.flatNacelle = flatNacelle
            self.chevrons = chevrons
            self.groundClearance = groundClearance ?? (width < 4.3 ? 1.42 : 2.05)
            self.humpEnd = humpEnd
            self.cockpitMask = cockpitMask
        }
    }

    func buildVariant(_ spec: Variant) -> AtlasModel {
        let root = Entity()
        let parts = variantParts(spec) + [variantLandingGear(spec)]
        for part in parts { root.addChild(part.entity) }
        return AtlasModel(root: root, parts: parts, overviewTarget: p(length / 2, spec.hasUpperDeck ? 1.4 : 0.75),
                          overviewDistance: max(length, span) * 1.72, metersPerUnit: 1,
                          sourceNote: "按制造商公布机长与翼展制作的比例示意。客舱、起落架、发动机内部与航司配色用于说明整体布局，测距基于模型几何。", stageGroundY: spec.groundY - 0.025)
    }

    private func variantParts(_ spec: Variant) -> [AtlasPart] {
        let wingStations = variantWingStations(spec)
        var parts = [variantBody(spec), variantWing(spec, wingStations, side: -1), variantWing(spec, wingStations, side: 1)]
        for side: Float in [-1, 1] {
            parts.append(variantEngine(spec, wingStations, side: side, outboard: false))
            if spec.fourEngines { parts.append(variantEngine(spec, wingStations, side: side, outboard: true)) }
        }
        parts.append(variantTail(spec))
        return parts
    }

    private func variantFuselage(_ spec: Variant) -> [Station] {
        let half = spec.width * 0.5
        let vertical = spec.bodyHeight * 0.5
        let nose: [(Float, Float, Float)]
        switch spec.body {
        case .rounded, .fullDeck:
            nose = [(0, 0.015, 0.015), (0.06, 0.34, 0.31), (0.16, 0.58, 0.53), (0.31, 0.79, 0.73),
                    (0.50, 0.92, 0.86), (0.73, 0.98, 0.96), (1, 1, 1)]
        case .pointed, .hump:
            nose = [(0, 0.014, 0.014), (0.08, 0.28, 0.25), (0.21, 0.51, 0.46), (0.39, 0.73, 0.65),
                    (0.57, 0.88, 0.83), (0.81, 0.97, 0.96), (1, 1, 1)]
        case .tapered:
            nose = [(0, 0.012, 0.012), (0.055, 0.22, 0.19), (0.16, 0.47, 0.39), (0.34, 0.78, 0.65),
                    (0.57, 0.9, 0.86), (0.80, 0.98, 0.97), (1, 1, 1)]
        }
        var stations = nose.map { fraction, height, width in
            let noseOffset = (1 - fraction) * (spec.body == .fullDeck ? -0.63 : -0.24)
            return Station(spec.nose * fraction, noseOffset, vertical * height, half * width)
        }
        let bodyEnd = length * (spec.body == .fullDeck ? 0.80 : 0.78)
        let trunk = [spec.nose + 0.60, length * 0.21, length * 0.29, length * 0.36, length * 0.44,
                     length * 0.52, length * 0.60, length * 0.69, bodyEnd].sorted()
        stations.append(contentsOf: trunk.filter { $0 > spec.nose + 0.025 }.map { Station($0, 0, vertical, half) })
        let tail: [(Float, Float, Float)] = [(0.13, 0.97, 0.98), (0.27, 0.89, 0.92), (0.47, 0.68, 0.71),
                                            (0.64, 0.47, 0.49), (0.79, 0.27, 0.29), (0.91, 0.13, 0.12), (1, 0.025, 0.03)]
        stations.append(contentsOf: tail.map { along, h, w in
            Station(bodyEnd + along * (length - bodyEnd), along * vertical * 0.47, vertical * h, half * w)
        })
        if spec.body == .hump {
            stations = stations.map { station in
                let point = station.x / length
                let rise = min(1, point / 0.085) * max(0, min(1, (spec.humpEnd - point) / 0.154)) * 2.20
                return Station(station.x, station.centerY + rise / 2, station.height + rise / 2, station.halfWidth)
            }
        }
        return stations
    }

    private func variantSurface(_ positions: [Station], x: Float, angle: Float, padding: Float = 0) -> Point {
        for (a, b) in zip(positions, positions.dropFirst()) where x >= a.x && x <= b.x {
            let t = (x - a.x) / max(b.x - a.x, 0.001)
            let y = a.centerY + (b.centerY - a.centerY) * t
            let h = a.height + (b.height - a.height) * t + padding
            let w = a.halfWidth + (b.halfWidth - a.halfWidth) * t + padding
            return p(x, y + h * cos(angle), w * sin(angle))
        }
        return p(x)
    }

    private func variantBody(_ spec: Variant) -> AtlasPart {
        let shell = Entity()
        let stations = variantFuselage(spec)
        shell.addChild(tube(stations, finish: fuselageFinish))
        installTubeColliders(on: shell, stations: stations)
        addFuselageLivery(to: shell, stations: stations)
        addVariantWindows(spec, profiles: stations, to: shell)
        if exteriorOnly {
            return part("fuselage", "机身", "airplane", "机身外壳", entity: shell,
                        focus: p(length * 0.48, 0.2), distance: length * 1.24)
        }

        let entity = Entity(), interior = Entity(), cut = Entity()
        let cutStart: Float = 2.81
        let cutEnd: Float = 6.03
        cut.addChild(tube(stations, start: cutStart, end: cutEnd, finish: fuselageFinish))
        addFuselageLivery(to: cut, stations: stations, visible: cutStart...cutEnd)
        let lining = stations.map { Station($0.x, $0.centerY, max(0.015, $0.height - 0.095), max(0.015, $0.halfWidth - 0.095)) }
        cut.addChild(tube(lining, start: cutStart, end: cutEnd, inner: true, finish: interiorWhite))
        for angle in [cutStart, cutEnd] {
            cut.addChild(tube(stations, start: angle - 0.015, end: angle + 0.015, slices: 2, finish: Finish(color: edgeColor)))
        }
        let flightDeck = variantCockpit(spec)
        let lowerCabin = variantCabin(spec, upper: false)
        let cargoHold = variantCargo(spec)
        var parts = [flightDeck, lowerCabin, cargoHold]
        if spec.hasUpperDeck { parts.insert(variantCabin(spec, upper: true), at: 2) }
        for part in parts { interior.addChild(part.entity) }
        interior.isEnabled = false
        cut.isEnabled = false
        for group in [shell, interior, cut] { entity.addChild(group) }
        return part("fuselage", "机身", "airplane", spec.hasUpperDeck ? "机身采用双层客舱结构，可按楼层选择并查看剖视。" : "机身内部可分开查看驾驶舱、客舱以及下层货舱。",
                    entity: entity, focus: p(length * 0.48, 0.2), distance: length * 1.24, shell: shell, interior: interior, section: cut,
                    children: parts, size: "长 \(length.formatted(.number.precision(.fractionLength(2)))) m")
    }

    private func addVariantWindows(_ spec: Variant, profiles: [Station], to shell: Entity) {
        var frames = Mesh(), panes = Mesh(), cockpitWindows = Mesh(), cockpitBorder = Mesh()
        func windows(from start: Float, through end: Float, angle: Float) {
            let pitch: Float = spec.width > 4.5 ? 0.70 : 0.59
            let positions = stride(from: start, through: end, by: pitch).map { $0 }
            let doorXs = spec.hasUpperDeck ? [start + 0.58, length * 0.31, length * 0.51, length * 0.75] : [start + 0.58, length * 0.46, length * 0.76]
            for x in positions where !doorXs.contains(where: { abs(x - $0) < 0.49 }) {
                for side: Float in [1, -1] {
                    for (outline, inset) in [(true, Float(0.028)), (false, Float(0.052))] {
                        let polygon = (0..<12).map { index -> Point in
                            let phase = Float(index) * .pi / 6
                            let dx = (outline ? Float(0.156) : 0.127) * cos(phase)
                            let dy = (outline ? Float(0.173) : 0.145) * sin(phase) / (spec.bodyHeight * 0.5)
                            return variantSurface(profiles, x: x + dx, angle: side * (angle + dy), padding: inset)
                        }
                        let normal = simd_normalize(Point(0, cos(angle), side * sin(angle)))
                        if outline { frames.face(polygon, normal: normal) } else { panes.face(polygon, normal: normal) }
                    }
                }
            }
            for x in doorXs where x < end {
                for side: Float in [1, -1] {
                    let spread: Float = 0.7 / (spec.bodyHeight * 0.5)
                    let outline: [(Float, Float)] = [(x - 0.38, angle - spread), (x + 0.40, angle - spread), (x + 0.4, angle + spread), (x - 0.38, angle + spread), (x - 0.38, angle - spread)]
                    for (a, b) in zip(outline, outline.dropFirst()) {
                        line(shell, variantSurface(profiles, x: a.0, angle: side * a.1, padding: 0.037),
                             variantSurface(profiles, x: b.0, angle: side * b.1, padding: 0.037), radius: 0.017, color: carbon.color)
                    }
                }
            }
        }
        windows(from: spec.nose + 0.40, through: length * 0.81, angle: spec.hasUpperDeck ? 1.53 : 1.30)
        if spec.hasUpperDeck {
            windows(from: spec.nose * 0.94, through: length * (spec.upperDeckEnd - (spec.body == .hump ? 0.002 : 0.03)), angle: spec.body == .hump ? 1.02 : 0.94)
        }
        for side: Float in [1, -1] {
            for pane in 0..<3 {
                let index = Float(pane), bound = 0.12 + index * 0.27
                let base = spec.nose * (0.35 + 0.065 * index)
                let end = base + spec.nose * 0.21
                for row in 0..<6 {
                    for column in 0..<6 {
                        let u = Float(row) / 6, v = Float(column) / 6
                        let next = Float(1) / 6
                        let corners: [Point] = [(u, v), (u + next, v), (u + next, v + next), (u, v + next)].map { along, up in
                            let x = base + (end - base) * along + 0.48 * up
                            return variantSurface(profiles, x: x, angle: side * (bound + up * 0.221), padding: 0.031)
                        }
                        cockpitWindows.face(corners, normal: simd_normalize(Point(-0.47, 0.73, 0.60 * side)))
                    }
                }
            }
            if spec.cockpitMask {
                func borderPoint(_ angleFraction: Float, _ lengthFraction: Float) -> Point {
                    let angle = 0.075 + angleFraction * 0.85
                    let front = spec.nose * (0.304 + angleFraction * 0.202)
                    let back = spec.nose * (0.60 + angleFraction * 0.18)
                    return variantSurface(profiles, x: front + (back - front) * lengthFraction, angle: angle * side, padding: 0.023)
                }
                let normal = simd_normalize(Point(-0.47, 0.73, 0.60 * side))
                for row in 0..<12 {
                    let v = Float(row) / 12, nextV = Float(row + 1) / 12
                    for column in 0..<10 {
                        let u = Float(column) / 10, nextU = Float(column + 1) / 10
                        cockpitBorder.face([borderPoint(v, u), borderPoint(v, nextU), borderPoint(nextV, nextU), borderPoint(nextV, u)], normal: normal)
                    }
                }
            }
        }
        shell.addChild(frames.entity(wingFinish))
        shell.addChild(panes.entity(darkGlass))
        if spec.cockpitMask {
            shell.addChild(cockpitBorder.entity(Finish(color: Self.color(0.045, 0.064, 0.08), roughness: 0.41)))
        }
        shell.addChild(cockpitWindows.entity(spec.cockpitMask ? Finish(color: Self.color(0.10, 0.21, 0.26), roughness: 0.19, metallic: 0.37) : darkGlass))
    }

    private func variantCockpit(_ spec: Variant) -> AtlasPart {
        let entity = Entity()
        let nose = spec.nose
        let floor: Float = spec.body == .hump ? 1.72 : (spec.body == .fullDeck ? 0.22 : spec.cabinFloorY)
        let cabWidth = min(spec.width * 0.68, 3.3)
        shape(entity, [nose * 0.63, 0.12, cabWidth], nose * 0.70, floor, 0, Finish(color: cabinFloor))
        shape(entity, [0.23, 0.78, cabWidth * 0.89], nose * 0.53, floor + 0.67, 0, carbon)
        shape(entity, [1.0, 0.48, 0.36], nose * 0.82, floor + 0.34, 0, wingFinish)
        for side: Float in [1, -1] {
            let z = cabWidth * 0.25 * side
            shape(entity, [0.57, 0.20, 0.53], nose * 0.81, floor + 0.41, z, cabinPaint)
            shape(entity, [0.13, 0.74, 0.50], nose * 0.81 + 0.28, floor + 0.83, z, cabinPaint)
            shape(entity, [0.15, 0.23, 0.35], nose * 0.81 + 0.28, floor + 1.27, z, interiorWhite)
            for display in 0..<3 {
                shape(entity, [0.045, 0.24, cabWidth * 0.10], nose * 0.53 + 0.135, floor + 0.81, (0.16 + Float(display) * 0.27) * side, darkGlass)
                shape(entity, [0.051, 0.026, cabWidth * 0.07], nose * 0.53 + 0.16, floor + 0.85, (0.16 + Float(display) * 0.27) * side, accentPaint)
            }
        }
        return part("cockpit", "驾驶舱", "gauge.with.dots.needle.50percent", "驾驶座席、仪表屏与中央操作台的空间示意。",
                    entity: entity, focus: p(nose * 0.73, floor + 0.69), distance: max(6, nose * 1.2), bounds: [nose * 0.7, 1.65, cabWidth],
                    explode: [-4, 4.3, 0], interiorOnly: true)
    }

    private func variantCabin(_ spec: Variant, upper: Bool) -> AtlasPart {
        let entity = Entity()
        let deck = upper ? 1 : 0
        let floor = upper ? spec.upperFloorY : spec.cabinFloorY
        let cabinStart = spec.nose + (upper && spec.body == .hump ? 2.0 : 0.28)
        let cabinEnd = length * (upper ? spec.upperDeckEnd : 0.83)
        let width = spec.width * (upper ? (spec.body == .hump ? 0.68 : 0.77) : 0.90)
        let hullEnd = max(cabinStart + 1, cabinEnd)
        let floorCenter = (cabinStart + hullEnd) * 0.5
        let floorRun = hullEnd - cabinStart
        shape(entity, [floorRun, 0.12, width], floorCenter, floor, 0, Finish(color: cabinFloor))
        for side: Float in [1, -1] {
            let edge = width * 0.40 * side
            shape(entity, [floorRun * 0.98, 0.25, 0.32], floorCenter, floor + 1.82, edge, interiorWhite)
            shape(entity, [floorRun * 0.98, 0.034, 0.045], floorCenter, floor + 1.67, edge, Finish(color: Self.color(0.72, 0.88, 1)))
        }
        let childParts = configuration.seats.enumerated().compactMap { index, zone -> AtlasPart? in
            guard zone.deck == deck, zone.numberOfRows > 0, !zone.seatGroups.isEmpty else { return nil }
            let start = max(cabinStart, min(zone.startM, hullEnd))
            let end = min(hullEnd, zone.endM)
            guard end - start > 0.2 else { return nil }
            let berthCount = zone.seatGroups.reduce(0, +)
            guard berthCount > 0 else { return nil }
            let rowSpacing = (end - start) / Float(zone.numberOfRows)
            let walkway: Float = spec.width < 4.3 ? 0.49 : 0.48
            let gaps = Float(zone.seatGroups.count - 1) * walkway
            let seatPitch = min(berthCount <= 4 ? 0.82 : 0.56, (width * 0.96 - gaps) / Float(berthCount))
            let lateralSize = Float(berthCount) * seatPitch + gaps
            guard seatPitch > 0.15 else { return nil }
            var frames = Mesh(), cushions = Mesh(), headrests = Mesh()
            for index in 0..<zone.numberOfRows {
                let row = index == zone.numberOfRows - 1 ? zone.partialLastRow ?? zone.seatGroups : zone.seatGroups
                let x = start + (Float(index) + 0.5) * rowSpacing
                var z = -lateralSize * 0.5 + seatPitch * 0.5
                for (occupied, capacity) in zip(row, zone.seatGroups) {
                    for slot in 0..<capacity {
                        if slot < occupied {
                            let depth = min(rowSpacing * 0.49, berthCount <= 4 ? 0.62 : 0.42)
                            frames.box(center: p(x, floor + 0.20, z), size: [depth, 0.30, seatPitch * 0.86])
                            cushions.box(center: p(x, floor + 0.41, z), size: [depth, 0.16, seatPitch * 0.85])
                            cushions.box(center: p(x + depth * 0.42, floor + 0.71, z), size: [0.12, 0.74, seatPitch * 0.84])
                            headrests.box(center: p(x + depth * 0.42, floor + 1.12, z), size: [0.15, 0.16, seatPitch * 0.67])
                            if berthCount <= 4 && spec.width > 4.3 {
                                frames.box(center: p(x, floor + 0.57, z - seatPitch * 0.46), size: [depth * 1.27, 0.64, 0.06])
                            }
                        }
                        z += seatPitch
                    }
                    z += walkway
                }
            }
            let section = Entity()
            section.addChild(frames.entity(interiorWhite))
            section.addChild(cushions.entity(index.isMultiple(of: 2) ? cabinPaint : Finish(color: Self.color(0.17, 0.29, 0.35))))
            section.addChild(headrests.entity(accentPaint))
            entity.addChild(section)
            return part("cabin-zone-\(index)", zone.label, "seat.fill", "按所选客舱配置绘制座位分组与相对位置。",
                        entity: section, focus: p((start + end) / 2, floor + 0.53), distance: max(8, (end - start) * 1.35),
                        bounds: [end - start, 1.2, lateralSize], explode: [2.5, 3.8, 2.2],
                        children: [], size: "\(zone.seatCount) 座 · \(zone.seatGroups.map(String.init).joined(separator: "–")) 布局")
        }
        for x in [cabinStart + 0.1, hullEnd - 0.28] {
            for side: Float in [1, -1] {
                shape(entity, [0.62, 1.59, 0.43], x, floor + 0.82, width * 0.40 * side, interiorWhite)
            }
        }
        let title = upper ? "上层客舱" : (spec.hasUpperDeck ? "主层客舱" : "客舱")
        let explanation = upper && childParts.isEmpty ? "上层甲板的空间示意。该配置暂缺上层座位图资料。" : configuration.cabinDescription
        return part(upper ? "cabin-upper" : "cabin", title, "seat.fill", explanation,
                    entity: entity, focus: p(floorCenter, floor + 0.62), distance: floorRun * 1.30,
                    bounds: [floorRun, 1.85, width], explode: [0, upper ? 9.2 : 4.6, upper ? -5 : 4.5], children: childParts, interiorOnly: true)
    }

    private func variantCargo(_ spec: Variant) -> AtlasPart {
        let entity = Entity()
        let y = -(spec.bodyHeight * 0.39)
        let width = spec.width * 0.63
        let x = length * 0.48
        shape(entity, [length * 0.56, 0.1, width], x, y - 0.58, 0, Finish(color: cabinFloor))
        var compartments = Mesh()
        for index in 0..<11 where ![4, 5, 6].contains(index) {
            let long = length * (0.21 + Float(index) * 0.052)
            for side: Float in [1, -1] {
                compartments.box(center: p(long, y, width * side * 0.25), size: [1.29, 1, width * 0.39])
            }
        }
        entity.addChild(compartments.entity(metal))
        return part("cargo", "下层货舱", "shippingbox.fill", "展示客舱下方的前后货舱和载货空间。",
                    entity: entity, focus: p(x, y), distance: length * 0.78, bounds: [length * 0.58, 1.19, width],
                    explode: [0, -6.1, -3.3], interiorOnly: true)
    }

    private func variantWingStations(_ spec: Variant) -> [WingStation] {
        let half = span * 0.5
        let root = spec.width * 0.37
        let mainSpan = half * (spec.tip == .raked ? 0.85 : 0.93) - root
        let rootChord = length * spec.wingChord
        let rootLeading = length * spec.wingRoot
        let wingY = -spec.bodyHeight * 0.21
        let stations: [(Float, Float)] = [(0, 1), (0.11, 0.85), (0.28, 0.65), (0.46, 0.48), (0.65, 0.34), (0.82, 0.26), (1, 0.18)]
        return stations.map { fraction, chord in
            let z = root + mainSpan * fraction
            let leading = rootLeading + (z - root) * spec.sweep * (1 - 0.09 * fraction)
            let rise = (z - root) * (spec.tip == .raked ? 0.085 : 0.075) + fraction * fraction * (spec.tip == .raked ? 0.69 : 0.22)
            return WingStation(z, leading, leading + rootChord * chord, wingY + rise, max(0.062, spec.width * 0.11 * chord))
        }
    }

    private func variantWing(_ spec: Variant, _ profiles: [WingStation], side: Float) -> AtlasPart {
        let entity = Entity(), flaps = Entity(), aileron = Entity(), tip = Entity()
        let id = side < 0 ? "wing-right" : "wing-left"
        let tipEnd = profiles[profiles.count - 1]
        let wingPosition: (WingStation, Float, Float) -> Point = { profile, chord, face in
            p(profile.front + (profile.rear - profile.front) * chord,
              profile.height + airfoilY(chord, depth: profile.thickness, surface: face), side * profile.span)
        }
        entity.addChild(airfoil(profiles, range: 0...0.79, finish: wingFinish, position: wingPosition))
        entity.addChild(airfoil(profiles, range: 0...0.09, finish: metal) { station, chord, face in
            wingPosition(station, chord, face * 1.022) + Point(0, face * 0.012, 0)
        })
        let flapProfiles = Array(profiles.prefix(5))
        let aileronProfiles = Array(profiles.suffix(3))
        flaps.addChild(airfoil(flapProfiles, range: 0.798...1, finish: controlFinish, position: wingPosition))
        for station in flapProfiles.dropFirst().dropLast() {
            let x = station.rear - 0.69
            let y = station.height - 0.31
            let points = [Station(x - 1.05, y, 0.03, 0.04), Station(x - 0.52, y, 0.17, 0.23), Station(x + 0.8, y, 0.13, 0.13), Station(x + 1.48, y, 0.025, 0.03)]
            flaps.addChild(tube(points, z: station.span * side, slices: 14, finish: wingFinish))
        }
        aileron.addChild(airfoil(aileronProfiles, range: 0.798...1, finish: controlFinish, position: wingPosition))
        let half = span / 2
        let tipHeight: Float
        switch spec.tip {
        case .sharklet: tipHeight = spec.width > 4.4 ? 2.8 : 2.26
        case .blended: tipHeight = 2.25
        case .canted: tipHeight = spec.width > 4.4 ? 1.67 : 1.42
        case .split: tipHeight = 1.70
        case .raked: tipHeight = spec.engineName.contains("GEnx-1B") ? 1.85 : 0.81
        case .fence: tipHeight = 0.88
        case .plain: tipHeight = 0.18
        }
        let swept: Float = spec.tip == .raked ? (half - tipEnd.span) * 1.20 : (spec.tip == .plain ? 0.58 : 1.35)
        let upperTip = [tipEnd,
                        WingStation((half + tipEnd.span) * 0.5, tipEnd.front + swept * 0.40, tipEnd.rear + swept * 0.33, tipEnd.height + tipHeight * 0.18, 0.081),
                        WingStation(half - 0.35, tipEnd.front + swept * 0.72, tipEnd.rear + swept * 0.52, tipEnd.height + tipHeight * 0.66, 0.048),
                        WingStation(half, tipEnd.front + swept, tipEnd.front + swept + (spec.tip == .raked ? 0.23 : 0.51), tipEnd.height + tipHeight, 0.027)]
        let tipFinish = spec.tip == .raked || spec.tip == .plain ? wingFinish : primaryPaint
        tip.addChild(airfoil(upperTip, finish: tipFinish, position: wingPosition))
        if spec.tip == .split || spec.tip == .fence {
            let branch: Float = spec.tip == .split ? 1.15 : 0.48
            let lower = [WingStation(tipEnd.span + 0.18, tipEnd.front + 0.19, tipEnd.rear - 0.30, tipEnd.height, 0.07),
                         WingStation(half - 0.16, tipEnd.front + 1.18, tipEnd.rear - 0.71, tipEnd.height - branch, 0.032)]
            tip.addChild(airfoil(lower, finish: primaryPaint, position: wingPosition))
        }
        let lamp = ModelEntity(mesh: .generateSphere(radius: 0.095), materials: [UnlitMaterial(color: side < 0 ? .systemGreen : .systemRed)])
        lamp.position = p(tipEnd.front + swept * 0.65, tipEnd.height + tipHeight * 0.20, (half - 0.37) * side)
        tip.addChild(lamp)
        let flapCenter = flapProfiles[2]
        let aileronCenter = aileronProfiles[1]
        let flapPart = part(id + "-flaps", "内侧襟翼", "airplane", "机翼后缘的增升翼面，可独立拆分查看。",
                            entity: flaps, focus: p(flapCenter.rear - 0.7, flapCenter.height, flapCenter.span * side), distance: half * 1.12,
                            bounds: [length * 0.16, 1.25, half * 0.64], explode: [3.5, -2.6, side * 2])
        let aileronPart = part(id + "-aileron", "外侧副翼", "airplane", "副翼用于控制横滚，位于翼尖附近的后缘。",
                               entity: aileron, focus: p(aileronCenter.rear, aileronCenter.height, aileronCenter.span * side), distance: half * 0.67,
                               bounds: [length * 0.13, 1.1, half * 0.31], explode: [3.1, 2, side * 2.6])
        let tipLabel: String
        switch spec.tip {
        case .raked: tipLabel = "后掠翼尖"
        case .split: tipLabel = "分叉式翼尖"
        case .fence: tipLabel = "翼尖翼栅"
        case .plain: tipLabel = "外侧翼尖"
        default: tipLabel = "上翘翼尖"
        }
        let tipPart = part(id + "-tip", tipLabel, "arrow.up.right", "不同机型采用不同翼尖构形。航行灯为右绿左红。",
                           entity: tip, focus: p(tipEnd.front + swept * 0.60, tipEnd.height + tipHeight * 0.44, (half - 0.5) * side),
                           distance: max(6, half * 0.31), bounds: [swept + 2.9, tipHeight + 1.35, half - tipEnd.span + 1.8], explode: [0.6, 2.3, side * 4.2])
        let children = [flapPart, aileronPart, tipPart]
        for child in children { entity.addChild(child.entity) }
        let center = profiles[3]
        return part(id, side < 0 ? "右机翼" : "左机翼", "airplane", "后掠机翼带有可独立查看的襟翼、副翼与翼尖。",
                    entity: entity, focus: p((center.front + center.rear) / 2, center.height, center.span * side), distance: half * 1.66,
                    bounds: [length * 0.33, 2.1, half * 0.75], explode: [0, 0.6, side * 8],
                    children: children, size: "全机翼展 \(span.formatted(.number.precision(.fractionLength(2)))) m")
    }

    private func variantEngine(_ spec: Variant, _ wing: [WingStation], side: Float, outboard: Bool) -> AtlasPart {
        let id = (side < 0 ? "engine-right" : "engine-left") + (outboard ? "-outboard" : "")
        let label = (side < 0 ? "右" : "左") + (spec.fourEngines ? (outboard ? "外侧" : "内侧") : "") + "发动机"
        let magnitude = span * (outboard ? 0.332 : (spec.fourEngines ? 0.192 : 0.161))
        let z = magnitude * side
        let radius = spec.engineRadius
        let size = spec.engineLength
        let positioned = zip(wing, wing.dropFirst()).first { a, b in a.span <= magnitude && magnitude <= b.span }
        let a = positioned?.0 ?? wing[1]
        let b = positioned?.1 ?? wing[2]
        let fraction = (magnitude - a.span) / max(0.01, b.span - a.span)
        let wingY = a.height + fraction * (b.height - a.height)
        let leading = a.front + fraction * (b.front - a.front)
        let x = leading - size * 0.46
        let y = max(spec.groundY + radius * (spec.flatNacelle ? 0.87 : 1) + 0.17, wingY - radius - 0.38)
        let entity = Entity(), shell = Entity()
        func ring(_ run: Float, _ factor: Float, rise: Float = 0, flat: Bool = false) -> Station {
            let r = radius * factor
            return Station(x + size * run, y + rise, r * (flat && spec.flatNacelle ? 0.86 : 1), r)
        }
        let nacelle = [ring(0, 0.85, flat: true), ring(0.038, 0.94, flat: true), ring(0.14, 1, flat: true),
                       ring(0.34, 1, flat: true), ring(0.66, 0.90, rise: 0.06, flat: true), ring(0.80, 0.73, rise: 0.08), ring(0.84, 0.67, rise: 0.08)]
        shell.addChild(tube(nacelle, z: z, slices: 76, finish: nacelleFinish))
        shell.addChild(tube([
            ring(0.300, 1.005, flat: true),
            ring(0.308, 1.007, flat: true),
            ring(0.312, 1.005, flat: true)
        ], z: z, slices: 76, finish: nacelleSeam))
        shell.addChild(tube([ring(-0.006, 0.79, flat: true), ring(0.02, 0.87, flat: true), ring(0.096, 0.98, flat: true)], z: z, finish: metal))
        let inlet = [ring(-0.008, 0.79, flat: true), ring(0.04, 0.82, flat: true), ring(0.24, 0.82, flat: true)]
        shell.addChild(tube(inlet, z: z, inner: true, finish: carbon))
        shell.addChild(tube([ring(0.82, 0.65), ring(0.91, 0.54), ring(0.98, 0.36), ring(1.02, 0.10)], z: z, finish: carbon))
        installTubeColliders(on: shell, stations: nacelle, sideOffset: z)
        let pylonTop = wingY + 0.14
        let pylonFloor = y + radius * 0.59
        let pylon = max(0.14, pylonTop - pylonFloor)
        shape(shell, [size * 0.54, pylon, radius * 0.43], x + size * 0.61, pylonFloor + pylon / 2, z, wingFinish)
        if spec.chevrons {
            var teeth = Mesh()
            for tooth in 0..<18 {
                let phase = 2 * Float.pi * Float(tooth) / 18
                let next = phase + Float.pi / 9
                let end = 0.5 * (phase + next)
                let r = radius * 0.672
                let a = p(x + size * 0.832, y + 0.08 + r * cos(phase), z + r * sin(phase))
                let b = p(x + size * 0.832, y + 0.08 + r * cos(next), z + r * sin(next))
                let c = p(x + size * 0.885, y + 0.08 + r * 0.87 * cos(end), z + r * 0.87 * sin(end))
                teeth.face([a, b, c], normal: [0, cos(end), sin(end)])
            }
            shell.addChild(teeth.entity(nacelleFinish))
        }
        let fan = Entity()
        fan.addChild(bladeDisk(x: x + size * 0.126, y: y, z: z, root: radius * 0.16, radius: radius * (spec.flatNacelle ? 0.71 : 0.80), count: 22, finish: metal))
        fan.addChild(tube([ring(0.052, 0.03), ring(0.105, 0.15), ring(0.23, 0.19)], z: z, slices: 30, finish: carbon))
        if exteriorOnly {
            entity.addChild(shell)
            entity.addChild(fan)
            return part(id, label, "fanblades.fill", spec.engineName,
                        entity: entity, focus: p(x + size * 0.49, y, z), distance: max(9, size * 2.16))
        }

        let interior = Entity(), section = Entity()
        let fanPart = part(id + "-fan", "进气风扇", "fanblades.fill", "风扇叶片将气流引向发动机的内涵道和外涵道。",
                           entity: fan, focus: p(x + size * 0.17, y, z), distance: radius * 4.3,
                           bounds: [size * 0.11, radius * 1.54, radius * 1.54], explode: [-size * 0.75, 1.1, 0])
        let compressor = Entity()
        compressor.addChild(tube([ring(0.22, 0.34), ring(0.40, 0.28), ring(0.56, 0.25)], z: z, slices: 26, finish: carbon))
        for i in 0..<7 {
            let run = Float(i)
            compressor.addChild(bladeDisk(x: x + size * (0.25 + 0.044 * run), y: y, z: z,
                                           root: radius * 0.20, radius: radius * (0.51 - 0.033 * run), count: 23, finish: metal))
        }
        let compressorPart = part(id + "-compressor", "压气机", "circle.dotted.circle.fill", "各级叶盘压缩气流并将其输送至燃烧室。叶盘数量为示意。",
                                   entity: compressor, focus: p(x + size * 0.40, y, z), distance: max(4, radius * 3.8),
                                   bounds: [size * 0.39, radius * 1.09, radius * 1.09], explode: [-1.7, 3.3, side * 0.3], interiorOnly: true)
        let combustor = Entity()
        let bronze = Finish(color: Self.color(0.71, 0.40, 0.20), roughness: 0.48, metallic: 0.49)
        combustor.addChild(tube([ring(0.52, 0.26), ring(0.57, 0.41), ring(0.65, 0.36), ring(0.68, 0.28)], z: z, slices: 30, finish: bronze))
        let combustorPart = part(id + "-combustor", "环形燃烧室", "flame.fill", "位于压气机与涡轮之间。结构位置为示意。",
                                  entity: combustor, focus: p(x + size * 0.60, y, z), distance: max(3.2, radius * 2.8),
                                  bounds: [size * 0.18, radius * 0.82, radius * 0.82], explode: [0.4, 4.5, side * 1.7], interiorOnly: true)
        let turbine = Entity()
        turbine.addChild(tube([ring(0.64, 0.28), ring(0.79, 0.37), ring(0.98, 0.15), ring(1.07, 0.055)], z: z, slices: 30, finish: carbon))
        for i in 0..<5 {
            let run = Float(i)
            turbine.addChild(bladeDisk(x: x + size * (0.65 + 0.037 * run), y: y, z: z,
                                        root: radius * 0.23, radius: radius * (0.37 + 0.036 * run), count: 25, finish: metal))
        }
        let turbinePart = part(id + "-turbine", "涡轮与尾喷管", "circle.hexagongrid.fill", "涡轮从热气流提取能量，尾喷管引导流体排出。",
                               entity: turbine, focus: p(x + size * 0.84, y, z), distance: max(4.2, radius * 4.1),
                               bounds: [size * 0.42, radius * 1.05, radius * 1.05], explode: [size * 0.59, 2.3, 0], interiorOnly: true)
        for subpart in [compressorPart, combustorPart, turbinePart] { interior.addChild(subpart.entity) }
        section.addChild(tube(nacelle, z: z, start: 2.93, end: 6.0, finish: nacelleFinish))
        section.addChild(tube(inlet, z: z, start: 2.93, end: 6.0, inner: true, finish: metal))
        for angle: Float in [2.93, 6.0] {
            section.addChild(tube(nacelle, z: z, start: angle - 0.027, end: angle + 0.027, slices: 2, finish: Finish(color: edgeColor)))
        }
        interior.isEnabled = false
        section.isEnabled = false
        for group in [shell, fan, interior, section] { entity.addChild(group) }
        return part(id, label, "fanblades.fill", "\(spec.engineName)。可拆分查看风扇、压气机、燃烧室与涡轮的示意结构。",
                    entity: entity, focus: p(x + size * 0.49, y, z), distance: max(9, size * 2.16), shell: shell,
                    interior: interior, section: section, explode: [0, outboard ? -7.2 : -4.3, side * (outboard ? 6.2 : 3.2)],
                    children: [fanPart, compressorPart, combustorPart, turbinePart])
    }

    private func variantTail(_ spec: Variant) -> AtlasPart {
        let entity = Entity(), fin = Entity(), horizontal = Entity()
        let footY = spec.bodyHeight * 0.29
        let topY = spec.height + spec.groundY
        let finStations = [WingStation(footY, length * 0.717, length * 0.936, 0, 0.44),
                           WingStation(footY + 0.27 * (topY - footY), length * 0.785, length * 0.938, 0, 0.34),
                           WingStation(footY + 0.64 * (topY - footY), length * 0.848, length * 0.944, 0, 0.23),
                           WingStation(footY + 0.94 * (topY - footY), length * 0.895, length * 0.953, 0, 0.12),
                           WingStation(topY, length * 0.912, length * 0.947, 0, 0.06)]
        let finPosition: (WingStation, Float, Float) -> Point = { station, chord, face in
            p(station.front + (station.rear - station.front) * chord, station.span, airfoilY(chord, depth: station.thickness, surface: face))
        }
        addFinLivery(to: fin, stations: finStations, position: finPosition)
        let rudder = airfoil(finStations, range: 0.764...1, finish: primaryPaint, position: finPosition)
        let tailHalf = spec.width * (spec.width > 4.3 ? 1.77 : 1.53)
        let stabProfiles = [WingStation(spec.width * 0.25, length * 0.812, length * 0.952, 0.15, 0.27),
                            WingStation(tailHalf * 0.43, length * 0.849, length * 0.961, 0.33, 0.18),
                            WingStation(tailHalf * 0.74, length * 0.895, length * 0.972, 0.59, 0.09),
                            WingStation(tailHalf, length * 0.938, length * 0.987, 0.79, 0.045)]
        for side: Float in [1, -1] {
            let position: (WingStation, Float, Float) -> Point = { station, chord, face in
                p(station.front + (station.rear - station.front) * chord,
                  station.height + airfoilY(chord, depth: station.thickness, surface: face), station.span * side)
            }
            horizontal.addChild(airfoil(stabProfiles, range: 0...0.79, finish: wingFinish, position: position))
            horizontal.addChild(airfoil(stabProfiles, range: 0.808...1, finish: controlFinish, position: position))
        }
        let finPart = part("tail-fin", "垂直安定面", "triangle", "过渡至机身尾段的垂直翼面，帮助稳定偏航。",
                           entity: fin, focus: p(length * 0.846, (footY + topY) * 0.55), distance: max(9, (topY - footY) * 1.8),
                           bounds: [length * 0.25, topY - footY, 1.04], explode: [0, 3.8, -0.85])
        let rudderPart = part("tail-rudder", "方向舵", "arrow.left.and.right", "尾翼后缘的独立活动翼面。",
                              entity: rudder, focus: p(length * 0.936, (footY + topY) * 0.55), distance: max(8, (topY - footY) * 1.57),
                              bounds: [length * 0.065, topY - footY, 0.56], explode: [4.5, 3.7, 2.7])
        let hPart = part("tail-horizontal", "水平安定面与升降舵", "arrow.up.and.down", "两侧尾翼帮助稳定并控制俯仰。",
                         entity: horizontal, focus: p(length * 0.915, 0.47), distance: tailHalf * 2.73,
                         bounds: [length * 0.20, 1.25, tailHalf * 2.1], explode: [5.2, 0, -2.8])
        let children = [finPart, rudderPart, hPart]
        for child in children { entity.addChild(child.entity) }
        return part("tail", "尾翼", "paperplane.fill", "可选择垂直安定面、方向舵及水平尾翼。",
                    entity: entity, focus: p(length * 0.864, (footY + topY) * 0.43), distance: tailHalf * 2.85, explode: [6.3, 1.1, 0], children: children)
    }

    private func variantLandingGear(_ spec: Variant) -> AtlasPart {
        let entity = Entity()
        let nose = spec.nose * 1.26
        let primaryX = length * (spec.wingRoot + spec.wingChord * 0.70)
        let primaryZ = spec.width * (spec.fourEngines ? 0.86 : 0.73)
        let ground = spec.groundY
        let desc = "可查看车轮、承力支柱和连杆的组合。"
        let bar: Float = spec.width < 4.3 ? 0.49 : 0.68
        let front = variantWheels(x: nose, z: 0, ground: ground, top: -spec.bodyHeight * 0.30, axles: 1, radius: bar * 0.69)
        var children = [part("nose-gear", "前起落架", "circle.circle", "双轮前起落架。\(desc)", entity: front,
                             focus: p(nose, ground + 0.90), distance: 5.8, bounds: [2.1, 2.6, 1.7], explode: [-2.6, -1.9, 0])]
        for side: Float in [1, -1] {
            let names = side < 0 ? ("right", "右") : ("left", "左")
            let wings = variantWheels(x: primaryX, z: primaryZ * side, ground: ground, top: -spec.bodyHeight * 0.27, axles: spec.mainAxles, radius: bar)
            children.append(part("main-gear-\(names.0)", "\(names.1)主起落架", "circle.circle", "每组 \(spec.mainAxles * 2) 个轮胎。\(desc)",
                                 entity: wings, focus: p(primaryX, ground + 1.34, primaryZ * side), distance: 8.5,
                                 bounds: [Float(spec.mainAxles) * bar * 2 + 1, 3.8, 2.5], explode: [2.2, -2.7, side * 3.1]))
            if spec.bodyAxles > 0 {
                let x = primaryX + spec.width * 0.78
                let z = spec.width * 0.32 * side
                let truck = variantWheels(x: x, z: z, ground: ground, top: -spec.bodyHeight * 0.36, axles: spec.bodyAxles, radius: bar)
                children.append(part("body-gear-\(names.0)", "\(names.1)机身主起落架", "circle.circle", "机腹起落架补充翼下主起落架的承重。\(desc)",
                                     entity: truck, focus: p(x, ground + 1.25, z), distance: 8.5,
                                     bounds: [Float(spec.bodyAxles) * bar * 2 + 1, 3.4, 2.0], explode: [4.1, -2.1, side * 1.5]))
            }
        }
        for component in children { entity.addChild(component.entity) }
        return part("landing-gear", "起落架", "gearshape.2.fill", "以放下的状态展示前起落架与主起落架。",
                    entity: entity, focus: p((primaryX + nose) / 2, ground + 1.4), distance: max(18, length * 0.84),
                    explode: [0, -6.4, 0], children: children)
    }

    private func variantWheels(x: Float, z: Float, ground: Float, top: Float, axles: Int, radius: Float) -> Entity {
        let assembly = Entity()
        let hubY = ground + radius
        let cross = radius * 1.32
        let width = radius * 0.67
        line(assembly, p(x - 0.21, top, z * 0.86), p(x, hubY + 0.16, z), radius: radius * 0.25, color: metal.color)
        line(assembly, p(x + 1.15, top - 0.12, z * 0.71), p(x, hubY + 0.36, z), radius: radius * 0.14, color: wingFinish.color)
        line(assembly, p(x - Float(axles - 1) * radius, hubY + 0.16, z), p(x + Float(axles - 1) * radius + 0.08, hubY + 0.16, z),
             radius: radius * 0.16, color: metal.color)
        for axle in 0..<axles {
            let station = x + (Float(axle) - Float(axles - 1) / 2) * radius * 2.16
            line(assembly, p(station, hubY, z - cross), p(station, hubY, z + cross), radius: radius * 0.19, color: metal.color)
            for side: Float in [1, -1] {
                let centralZ = z + cross * 0.83 * side
                line(assembly, p(station, hubY, centralZ - width / 2), p(station, hubY, centralZ + width / 2),
                     radius: radius, color: Self.color(0.045, 0.052, 0.064))
                let outward = centralZ + width * 0.54 * side
                line(assembly, p(station, hubY, outward - 0.038), p(station, hubY, outward + 0.038), radius: radius * 0.55, color: metal.color)
            }
        }
        return assembly
    }
}
