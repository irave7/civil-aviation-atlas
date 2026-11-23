import RealityKit
import simd

/// A meter-scale airport around the airport reference point, east +X and south +Z.
@MainActor
final class FlightAirfieldScenery {
    let root = Entity()
    let label: String

    init(airport: Airport, runway: Runway?, route: FlightGroundRoute?) {
        let batch = AirfieldGeometry.BatchSet()
        // The ground extends past the local camera's far plane at the airport.
        batch.box([80_000, 2, 80_000], [0, -1.30, 0], .islandGrass)
        let length = Float(route?.runwayLengthM ?? runway?.lengthM ?? 3000)
        let width = Float(runway?.widthM.flatMap { (5...150).contains($0) ? $0 : nil } ?? 45)
        let bearing = route.map { Float($0.runwayHeading) } ?? 90
        let radians = bearing * .pi / 180
        let along = SIMD2<Float>(sin(radians), -cos(radians))
        let threshold = route.map { Self.offset($0.threshold, airport: airport) } ?? -along * (length * 0.5)
        var ends = runway?.id.split(separator: "/").map(String.init) ?? []
        if ends.count == 2, route?.directionName == ends.last { ends.reverse() }
        Self.pave(from: threshold, along: along, length: length, width: width, names: ends, batch: batch)
        var hasStructures = false
        var attribution = ""
        #if !MAINLAND_DISTRIBUTION
        if airport.hasCoordinates {
            let plan = AirportSiteCatalog.plan(for: airport)
            let unit = AirportSiteCatalog.metersPerUnit
            for strip in plan.runways where strip.id != runway?.id && !strip.approximatePlacement {
                let ends = strip.ends
                Self.pave(from: ends[0] * unit, along: simd_normalize(ends[1] - ends[0]),
                          length: strip.length * unit, width: strip.width * unit, names: strip.id.split(separator: "/").map(String.init), batch: batch)
            }
            // Use the catalogue footprints directly. Combine materials across buildings for moving-camera use.
            for feature in plan.features {
                let source = feature.source
                guard source.kind != .boundary else { continue }
                var points = feature.points.map { $0 * unit }
                if points.count > 2, points.first == points.last { points.removeLast() }
                if source.kind.isBuilding, let center = points.first {
                    let height = Float(source.heightM.flatMap { (2...850).contains($0) ? $0 : nil }
                                       ?? (source.kind == .tower ? 38 : source.kind == .terminal ? 18 : 9))
                    if source.area && points.count >= 3 {
                        hasStructures = true
                        Self.structure(points, height: height, glass: source.kind == .terminal || source.kind == .tower, batch: batch)
                    } else if source.kind == .tower {
                        hasStructures = true
                        Self.tower(center, height: height, batch: batch)
                    }
                } else if source.area {
                    batch.flatPolygon(points, y: source.kind == .apron ? -0.22 : -0.15,
                                      paint: source.kind == .apron ? .apron : .taxiPavement)
                } else if source.kind == .taxiway {
                    for (a, b) in zip(points, points.dropFirst()) {
                        Self.strip(a, b, y: -0.12, width: Float(source.widthM ?? 20), height: 0.08, paint: .taxiPavement, batch: batch)
                        Self.strip(a, b, y: -0.06, width: 0.4, height: 0.025, paint: .taxiYellow, batch: batch)
                    }
                }
            }
            if plan.hasOpenStreetMapData { attribution = " · © OpenStreetMap" }
            if plan.hasOvertureData { attribution += " · Overture" }
        }
        #endif
        if !hasStructures {
            let side = SIMD2(-along.y, along.x)
            let center = threshold + along * (length * 0.38) + side * 330
            let corners = [center - along * 95 - side * 25, center + along * 95 - side * 25,
                           center + along * 95 + side * 25, center - along * 95 + side * 25]
            Self.structure(corners, height: 16, glass: true, batch: batch)
            Self.tower(center + along * 145, height: 33, batch: batch)
            Self.strip(center - along * 145 - side * 70, center + along * 145 - side * 70, y: -0.2,
                       width: 85, height: 0.08, paint: .apron, batch: batch)
        }
        let runwayNote = route?.recordedAxis == true ? "收录跑道" : "参考跑道"
        label = runwayNote + (hasStructures ? " · 建筑轮廓重建" : " · 示意航站楼") + attribution
        batch.install(on: root, label: "flight-airfield")
    }

    static func offset(_ pose: FlightGroundPose, airport: Airport) -> SIMD2<Float> {
        let delta = FlightGroundPose.headingChange(from: airport.lon, to: pose.longitude)
        return [Float(delta * 111_319.49 * cos(airport.lat * .pi / 180)), Float((airport.lat - pose.latitude) * 110_750)]
    }

    private static func pave(from origin: SIMD2<Float>, along: SIMD2<Float>, length: Float,
                             width: Float, names: [String], batch: AirfieldGeometry.BatchSet) {
        guard length.isFinite, width.isFinite, length > 1, width > 1 else { return }
        let side = SIMD2(-along.y, along.x)
        func line(_ start: Float, _ end: Float, _ offset: Float, _ thickness: Float, _ y: Float, _ paint: AirfieldGeometry.Paint) {
            strip(origin + along * start + side * offset, origin + along * end + side * offset, y: y,
                  width: thickness, height: 0.04, paint: paint, batch: batch)
        }
        for sign: Float in [-1, 1] {
            for index in 0..<4 {
                line(-24, length + 24, sign * (width / 2 + 13 + Float(index) * 23), 12, -0.27, .mownGrass)
            }
        }
        line(0, length, 0, width + 4, -0.10, .asphaltEdge)
        line(0, length, 0, width, -0.02, .asphalt)
        for sign: Float in [-1, 1] { line(0, length, sign * (width / 2 - 0.6), 0.55, 0.06, .runwayWhite) }
        for start in stride(from: Float(90), to: length - 85, by: 60) {
            line(start, min(start + 30, length), 0, 0.85, 0.06, .runwayWhite)
        }
        guard length > 180 else { return }
        for (index, name) in names.prefix(2).enumerated() {
            let cell = min(2.2, width * 0.52 / Float(max(1, name.count * 4 - 1)))
            let sign: Float = index == 0 ? 1 : -1
            let center: Float = index == 0 ? 60 : length - 60
            let halfWidth = Float(name.count * 4 - 2) * cell / 2
            for (letter, character) in name.enumerated() {
                guard let rows = AirfieldGeometry.runwayGlyphs[character] else { continue }
                for (row, bits) in rows.enumerated() {
                    for col in 0..<3 where bits & (1 << (2 - col)) != 0 {
                        let x = center + sign * Float(2 - row) * 3.1
                        let offset = sign * (Float(letter * 4 + col) * cell - halfWidth)
                        line(x - 1.56, x + 1.56, offset, cell, 0.06, .runwayWhite)
                    }
                }
            }
        }
        if length >= 1500 {
            let distance = min(300, length * 0.15)
            for sign: Float in [-1, 1] {
                line(distance, distance + 30, sign * width * 0.27, width * 0.10, 0.06, .runwayWhite)
                line(length - distance - 30, length - distance, sign * width * 0.27, width * 0.10, 0.06, .runwayWhite)
            }
        }
        for sign: Float in [-1, 1] {
            for index in 1...4 {
                let offset = sign * Float(index) * width * 0.09
                line(8, 37, offset, width * 0.035, 0.06, .runwayWhite)
                line(length - 37, length - 8, offset, width * 0.035, 0.06, .runwayWhite)
            }
        }
    }

    private static func structure(_ points: [SIMD2<Float>], height: Float, glass: Bool, batch: AirfieldGeometry.BatchSet) {
        batch.flatPolygon(points, y: height, paint: .roofCool)
        for (a, b) in zip(points, points.dropFirst() + [points[0]]) {
            batch.quad([a.x, -0.3, a.y], [b.x, -0.3, b.y], [b.x, height, b.y], [a.x, height, a.y], .buildingWall, twoSided: true)
            if glass {
                strip(a, b, y: height * 0.58, width: 0.35, height: height * 0.35, paint: .terminalGlass, batch: batch)
                strip(a, b, y: height, width: 1.3, height: 0.65, paint: .roofWhite, batch: batch)
                let length = simd_distance(a, b)
                let bays = min(32, Int(length / 9))
                if bays > 1 {
                    for bay in 1..<bays {
                        let p = a + (b - a) * (Float(bay) / Float(bays))
                        batch.box([0.65, height * 0.36, 0.65], [p.x, height * 0.58, p.y], .concreteTrim)
                    }
                }
            }
        }
    }

    private static func tower(_ p: SIMD2<Float>, height: Float, batch: AirfieldGeometry.BatchSet) {
        batch.box([7, height, 7], [p.x, height * 0.5, p.y], .concreteTrim)
        batch.box([13, 5, 13], [p.x, height - 2.5, p.y], .terminalGlass)
        batch.box([15, 1, 15], [p.x, height + 0.5, p.y], .roofWhite)
    }

    private static func strip(_ a: SIMD2<Float>, _ b: SIMD2<Float>, y: Float, width: Float, height: Float,
                              paint: AirfieldGeometry.Paint, batch: AirfieldGeometry.BatchSet) {
        batch.line([a.x, y, a.y], [b.x, y, b.y], width: width, height: height, paint)
    }
}
