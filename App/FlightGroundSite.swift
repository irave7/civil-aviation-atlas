import CoreLocation
import Foundation
import simd

extension FlightGroundPose {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    init(airport: Airport) {
        self.init(latitude: airport.lat, longitude: airport.lon, heading: 0)
    }
}

extension FlightGroundRoute {
    init?(airport: Airport, runway: Runway?, operation: Operation, otherAirport: Airport) {
        let location = FlightGroundPose(airport: airport)
        guard CLLocationCoordinate2DIsValid(location.coordinate) else { return nil }

        let other = FlightGroundPose(airport: otherAirport)
        let course = CLLocationCoordinate2DIsValid(other.coordinate)
            ? (operation == .departure ? location.course(to: other) : other.course(to: location)) : 90
        let runwayHeading = runway?.heading.flatMap { $0.isFinite ? FlightGroundPose.normalize($0) : nil }
        let identifiers = runway?.id.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let designation = identifiers.first.flatMap { Int($0.prefix(while: \.isNumber)) }
            .flatMap { (1...36).contains($0) ? Double($0 * 10) : nil }
        let heading = runwayHeading ?? designation ?? course
        let reversed = abs(FlightGroundPose.headingChange(from: heading, to: course)) > 90
        let bearing = FlightGroundPose.normalize(heading + (reversed ? 180 : 0))
        let length = runway.flatMap { (2...15_000).contains($0.lengthM) ? $0.lengthM : nil } ?? 3_000
        let width = runway?.widthM.flatMap { (15...100).contains($0) ? $0 : nil } ?? 45
        let runwayLocation = runway.flatMap { record -> FlightGroundPose? in
            guard let latitude = record.lat, let longitude = record.lon else { return nil }
            let point = FlightGroundPose(latitude: latitude, longitude: longitude, heading: bearing)
            return CLLocationCoordinate2DIsValid(point.coordinate) && point.distance(to: location) <= 15_000 ? point : nil
        }

        let start = (runwayLocation ?? location).displaced(by: -length / 2, toward: bearing)
        threshold = start
        runwayLengthM = length
        directionName = (reversed && identifiers.count > 1 ? identifiers.last : identifiers.first) ?? "参考跑道"
        recordedAxis = runwayLocation != nil && runwayHeading != nil
        usesOpenStreetMapRunway = recordedAxis && AirportSiteCatalog.usesSupplementalRunways(for: airport)
        connectors = recordedAxis ? FlightTaxiwayGraph(airport: airport, threshold: start)
            .connectors(runwayLength: length, width: width, operation: operation) : []
    }

    var sources: [AtlasSource] {
        var sources: [AtlasSource] = recordedAxis && !usesOpenStreetMapRunway
            ? [AtlasSource(title: "OurAirports · 机场及跑道基础资料", url: "https://ourairports.com/data/")] : []
        if usesOpenStreetMapRunway || !connectors.isEmpty { sources.append(AirportSiteCatalog.source) }
        return sources
    }
}

private struct FlightTaxiwayGraph {
    private struct PointKey: Hashable {
        let along: Int
        let side: Int

        init(_ point: SIMD2<Double>) {
            along = Int((point.x / 3).rounded())
            side = Int((point.y / 3).rounded())
        }
    }

    private struct Node {
        let position: SIMD2<Double>
        let pose: FlightGroundPose
        var links: [Int] = []
    }

    private struct Entry {
        let runwayDistance: Double
        let firstNode: Int
        let lateralDistance: Double
    }

    private let threshold: FlightGroundPose
    private let nodes: [Node]

    init(airport: Airport, threshold: FlightGroundPose) {
        self.threshold = threshold
        var nodes: [Node] = []
        var nodeNumber: [PointKey: Int] = [:]
        let lines = AirportSiteCatalog.taxiwayCenterlines(for: airport)

        for line in lines {
            var previous: Int?
            for pair in line.points {
                guard pair.count == 2 else {
                    previous = nil
                    continue
                }
                let pose = FlightGroundPose(latitude: pair[0], longitude: pair[1], heading: 0)
                guard CLLocationCoordinate2DIsValid(pose.coordinate) else {
                    previous = nil
                    continue
                }
                let distance = threshold.distance(to: pose)
                guard distance <= 15_000 else {
                    previous = nil
                    continue
                }
                let angle = (threshold.course(to: pose) - threshold.heading) * .pi / 180
                let position = SIMD2<Double>(distance * cos(angle), distance * sin(angle))
                let key = PointKey(position)
                let index: Int
                if let current = nodeNumber[key] {
                    index = current
                } else {
                    index = nodes.count
                    nodeNumber[key] = index
                    nodes.append(Node(position: position, pose: pose))
                }
                if let previous, previous != index, !nodes[previous].links.contains(index) {
                    nodes[previous].links.append(index)
                    nodes[index].links.append(previous)
                }
                previous = index
            }
        }
        self.nodes = nodes
    }

    func connectors(runwayLength: Double, width: Double, operation: FlightGroundRoute.Operation) -> [FlightGroundRoute.Connector] {
        let bounds: ClosedRange<Double>
        switch operation {
        case .departure: bounds = 0...min(460, runwayLength * 0.20)
        case .arrival:
            let firstExit = min(350, runwayLength * 0.12) + 110
            guard runwayLength > firstExit + 35 else { return [] }
            bounds = firstExit...(runwayLength - 35)
        }

        let pavementEdge = width / 2
        var candidates: [Entry] = []
        for (index, node) in nodes.enumerated() {
            for neighbor in node.links where index < neighbor {
                let a = node.position, b = nodes[neighbor].position
                let delta = b - a
                guard abs(delta.y) > 5, abs(delta.y) > abs(delta.x) * 0.12 else { continue }
                let position = a + delta * min(1, max(0, -a.y / delta.y))
                guard bounds.contains(position.x), abs(position.y) <= pavementEdge + 6 else { continue }

                for outside in [index, neighbor] {
                    let point = nodes[outside].position
                    guard abs(point.y) >= pavementEdge + 10, abs(point.y) <= 170,
                          abs(point.x - position.x) <= 160 else { continue }
                    candidates.append(Entry(runwayDistance: position.x, firstNode: outside, lateralDistance: abs(position.y)))
                }
            }
        }

        var result: [FlightGroundRoute.Connector] = []
        for candidate in candidates.sorted(by: Self.precedes) {
            if result.contains(where: { abs($0.runwayDistanceM - candidate.runwayDistance) < 75 }) { continue }
            guard let centerline = pathOutward(from: candidate.firstNode, minimumLateral: pavementEdge - 4) else { continue }
            let entry = threshold.displaced(by: candidate.runwayDistance, toward: threshold.heading)
            result.append(FlightGroundRoute.Connector(runwayDistanceM: candidate.runwayDistance, outwardPath: [entry] + centerline))
            if result.count == (operation == .departure ? 1 : 16) { break }
        }
        return result
    }

    private static func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.runwayDistance != rhs.runwayDistance { return lhs.runwayDistance < rhs.runwayDistance }
        if lhs.lateralDistance != rhs.lateralDistance { return lhs.lateralDistance < rhs.lateralDistance }
        return lhs.firstNode < rhs.firstNode
    }

    private func pathOutward(from first: Int, minimumLateral: Double) -> [FlightGroundPose]? {
        struct Visit { let node: Int; let previous: Int?; let distance: Double }
        let side = nodes[first].position.y < 0 ? -1.0 : 1.0
        var visits = [Visit(node: first, previous: nil, distance: 0)]
        var visited: Set<Int> = [first]
        var current = 0
        var best = 0
        while current < visits.count, current < 240 {
            let visit = visits[current]
            let start = nodes[visit.node]
            for next in start.links where !visited.contains(next) {
                let destination = nodes[next]
                let distance = visit.distance + simd_distance(start.position, destination.position)
                guard destination.position.y * side >= minimumLateral, distance <= 570 else { continue }
                visited.insert(next)
                visits.append(Visit(node: next, previous: current, distance: distance))
                if distance > visits[best].distance { best = visits.count - 1 }
            }
            current += 1
        }
        guard visits[best].distance >= 85 else { return nil }

        var path: [FlightGroundPose] = []
        var index: Int? = best
        while let current = index {
            let visit = visits[current]
            path.append(nodes[visit.node].pose)
            index = visit.previous
        }
        return Array(path.reversed())
    }
}
