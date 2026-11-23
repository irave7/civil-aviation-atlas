import RealityKit
import UIKit
import simd

// Shared batched meshes for the inspection model and the meter-scale flight scene.
enum AirfieldGeometry {
    static let runwayGlyphs: [Character: [Int]] = [
        "0": [7, 5, 5, 5, 7], "1": [2, 6, 2, 2, 7], "2": [7, 1, 7, 4, 7], "3": [7, 1, 7, 1, 7],
        "4": [5, 5, 7, 1, 1], "5": [7, 4, 7, 1, 7], "6": [7, 4, 7, 5, 7], "7": [7, 1, 2, 2, 2],
        "8": [7, 5, 7, 5, 7], "9": [7, 5, 7, 1, 7], "A": [7, 5, 7, 5, 5], "C": [7, 4, 4, 4, 7],
        "L": [4, 4, 4, 4, 7], "R": [6, 5, 6, 5, 5]
    ]

    enum Paint: UInt32, CaseIterable {
        case deepWater = 0x203e51
        case waterGrid = 0x2c5163
        case retainingWall = 0x415d56
        case coastTrim = 0x82978a
        case mownGrass = 0x779473
        case islandGrass = 0x6d8c6c
        case grassStrip = 0x8ba487
        case bareEarth = 0x948870
        case asphalt = 0x344650
        case asphaltEdge = 0x566b72
        case runwayWhite = 0xf0f3e8
        case taxiPavement = 0x667575
        case taxiYellow = 0xe8bf67
        case apron = 0x929c98
        case standStripe = 0xe5ddab
        case buildingWall = 0x69858d
        case concreteTrim = 0xc3c7ba
        case roofCool = 0xbbd4dc
        case roofWhite = 0xe5ece7
        case roofSeam = 0x90a6ad
        case terminalGlass = 0x55818d
        case skylight = 0x88c6d8
        case steel = 0xa8bcc3
        case deepSteel = 0x406071
        case polishedFloor = 0xdde8e0
        case floorJoint = 0xacbfbb
        case screen = 0x438bb0
        case navy = 0x233f5d
        case amber = 0xf3ad53
        case signalRed = 0xb85549

        @MainActor var material: PhysicallyBasedMaterial {
            let color = UIColor(red: CGFloat((rawValue >> 16) & 255) / 255, green: CGFloat((rawValue >> 8) & 255) / 255, blue: CGFloat(rawValue & 255) / 255, alpha: 1)
            switch self {
            case .steel, .roofCool, .roofWhite, .roofSeam:
                return AtlasGeometry.material(color, roughness: 0.62, metallic: 0.13)
            case .skylight, .terminalGlass, .screen:
                return AtlasGeometry.material(color, roughness: 0.36, metallic: 0.08)
            default:
                return AtlasGeometry.material(color, roughness: 0.81)
            }
        }
    }

    /// Batches small primitives by material so hundreds of windows, ribs and runway marks
    /// remain individual geometry without hundreds of scene graph nodes or draw calls.
    final class BatchSet {
        private struct Buffer {
            var vertices: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var indices: [UInt32] = []

            mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
                let cross = simd_cross(b - a, c - a)
                guard simd_length_squared(cross) > 1e-19 else { return }
                let normal = simd_normalize(cross)
                let start = UInt32(vertices.count)
                vertices.append(contentsOf: [a, b, c])
                normals.append(contentsOf: [normal, normal, normal])
                indices.append(contentsOf: [start, start + 1, start + 2])
            }
        }

        private var buffers: [Paint: Buffer] = [:]

        func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ paint: Paint, twoSided: Bool = false) {
            buffers[paint, default: Buffer()].triangle(a, b, c)
            if twoSided { buffers[paint, default: Buffer()].triangle(a, c, b) }
        }

        func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, _ paint: Paint, twoSided: Bool = false) {
            triangle(a, b, c, paint, twoSided: twoSided)
            triangle(a, c, d, paint, twoSided: twoSided)
        }

        func box(_ dimensions: SIMD3<Float>, _ position: SIMD3<Float>, _ paint: Paint) {
            prism(position: position, xAxis: [dimensions.x * 0.5, 0, 0], yAxis: [0, dimensions.y * 0.5, 0], zAxis: [0, 0, dimensions.z * 0.5], paint: paint)
        }

        func line(_ start: SIMD3<Float>, _ end: SIMD3<Float>, width: Float, height: Float, _ paint: Paint) {
            let diff = end - start
            let length = simd_length(diff)
            guard length > 0.0001 else { return }
            let direction = diff / length
            let up: SIMD3<Float> = abs(direction.y) > 0.96 ? [0, 0, 1] : [0, 1, 0]
            let orthogonal = simd_normalize(simd_cross(direction, up))
            let vertical = simd_normalize(simd_cross(orthogonal, direction))
            prism(position: (start + end) * 0.5, xAxis: diff * 0.5, yAxis: vertical * (height * 0.5), zAxis: orthogonal * (width * 0.5), paint: paint)
        }

        private func prism(position p: SIMD3<Float>, xAxis x: SIMD3<Float>, yAxis y: SIMD3<Float>, zAxis z: SIMD3<Float>, paint: Paint) {
            let a = p - x - y - z
            let b = p + x - y - z
            let c = p + x + y - z
            let d = p - x + y - z
            let e = p - x - y + z
            let f = p + x - y + z
            let g = p + x + y + z
            let h = p - x + y + z
            quad(b, a, d, c, paint)
            quad(e, f, g, h, paint)
            quad(a, e, h, d, paint)
            quad(f, b, c, g, paint)
            quad(d, h, g, c, paint)
            quad(a, b, f, e, paint)
        }

        func taper(y1: Float, y2: Float, radius1: Float, radius2: Float, segments: Int, paint: Paint) {
            for i in 0..<segments {
                let a = Float(i) / Float(segments) * .pi * 2
                let b = Float(i + 1) / Float(segments) * .pi * 2
                let lowA: SIMD3<Float> = [cos(a) * radius1, y1, sin(a) * radius1]
                let lowB: SIMD3<Float> = [cos(b) * radius1, y1, sin(b) * radius1]
                let highA: SIMD3<Float> = [cos(a) * radius2, y2, sin(a) * radius2]
                let highB: SIMD3<Float> = [cos(b) * radius2, y2, sin(b) * radius2]
                quad(lowA, highA, highB, lowB, paint)
                triangle([0, y2, 0], highB, highA, paint)
            }
        }

        func flatPolygon(_ points: [SIMD2<Float>], y: Float, paint: Paint) {
            guard points.count >= 3 else { return }
            func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
                let u = b - a
                let v = c - a
                return u.x * v.y - u.y * v.x
            }
            func vertex(_ point: SIMD2<Float>) -> SIMD3<Float> { [point.x, y, point.y] }
            var indices = Array(points.indices)
            let area = indices.reduce(Float(0)) { accumulated, i in
                let a = points[i]
                let b = points[(i + 1) % points.count]
                return accumulated + a.x * b.y - a.y * b.x
            }
            if area < 0 { indices.reverse() }
            while indices.count > 2 {
                var ear: Int?
                for i in indices.indices {
                    let l = indices[(i + indices.count - 1) % indices.count]
                    let m = indices[i]
                    let r = indices[(i + 1) % indices.count]
                    let a = points[l]
                    let b = points[m]
                    let c = points[r]
                    guard cross(a, b, c) > 0.00001 else { continue }
                    let inside = indices.contains { id in
                        guard id != l && id != m && id != r else { return false }
                        let candidate = points[id]
                        return cross(a, b, candidate) >= 0 && cross(b, c, candidate) >= 0 && cross(c, a, candidate) >= 0
                    }
                    if !inside {
                        triangle(vertex(a), vertex(c), vertex(b), paint)
                        ear = i
                        break
                    }
                }
                guard let ear else { break }
                indices.remove(at: ear)
            }
        }

        @MainActor
        func install(on parent: Entity, label: String) {
            for paint in Paint.allCases {
                guard let data = buffers[paint], !data.indices.isEmpty else { continue }
                var description = MeshDescriptor(name: label)
                description.positions = MeshBuffers.Positions(data.vertices)
                description.normals = MeshBuffers.Normals(data.normals)
                description.primitives = .triangles(data.indices)
                guard let mesh = try? MeshResource.generate(from: [description]) else { continue }
                let entity = ModelEntity(mesh: mesh, materials: [paint.material])
                entity.name = label
                parent.addChild(entity)
            }
        }
    }
}
