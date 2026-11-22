import MapKit
import simd
import SwiftUI

struct FlightSimulatorArc: Equatable {
    private static let earthRadius = 6_371_000.0
    let origin: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    private let start: SIMD3<Double>
    private let direction: SIMD3<Double>
    private let angle: Double
    private let departureCourse: Double?
    private let arrivalCourse: Double?
    private let departure: RunwayTransition?
    private let arrival: RunwayTransition?

    init(origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D,
         departureCourse: Double? = nil, arrivalCourse: Double? = nil) {
        self.origin = origin
        self.destination = destination
        let start = Self.vector(origin)
        let end = Self.vector(destination)
        let shared = simd_dot(start, end)
        let perpendicular = end - start * shared
        let length = simd_length(perpendicular)
        self.start = start
        let angle = atan2(length, shared)
        self.angle = angle
        // Antipodal endpoints admit multiple great circles. Pick a stable perpendicular.
        let axis = abs(start.z) < 0.9 ? SIMD3<Double>(0, 0, 1) : SIMD3<Double>(1, 0, 0)
        let direction = length > 1e-12 ? perpendicular / length : simd_normalize(axis - start * simd_dot(start, axis))
        self.direction = direction
        self.departureCourse = departureCourse.flatMap { $0.isFinite ? $0 : nil }
        self.arrivalCourse = arrivalCourse.flatMap { $0.isFinite ? $0 : nil }
        let transition = min(9_000 / Self.earthRadius, angle * 0.22)
        let proportion = angle > 1e-8 ? transition / angle : 0
        let startJoin = start * cos(transition) + direction * sin(transition)
        let startTangent = direction * cos(transition) - start * sin(transition)
        let endJoin = start * cos(angle - transition) + direction * sin(angle - transition)
        let endTangent = direction * cos(angle - transition) - start * sin(angle - transition)
        // Simulated turns near the endpoints connect the runway directions to the en-route great circle.
        departure = self.departureCourse.flatMap { course in
            RunwayTransition(fraction: proportion, length: transition, start: start, end: startJoin,
                             entry: Self.tangent(at: origin, course: course), exit: startTangent)
        }
        arrival = self.arrivalCourse.flatMap { course in
            RunwayTransition(fraction: proportion, length: transition, start: endJoin, end: end,
                             entry: endTangent, exit: Self.tangent(at: destination, course: course))
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.origin.latitude == rhs.origin.latitude && lhs.origin.longitude == rhs.origin.longitude
            && lhs.destination.latitude == rhs.destination.latitude && lhs.destination.longitude == rhs.destination.longitude
            && lhs.departureCourse == rhs.departureCourse && lhs.arrivalCourse == rhs.arrivalCourse
    }

    func coordinate(at progress: Double) -> CLLocationCoordinate2D {
        if progress <= 0 { return origin }
        if progress >= 1 { return destination }
        if let transition = runwayTransition(at: progress) {
            return Self.coordinate(transition.curve.point(at: transition.fraction))
        }
        let traveled = angle * progress
        return Self.coordinate(start * cos(traveled) + direction * sin(traveled))
    }

    func heading(at progress: Double) -> Double {
        let (north, east) = Self.directions(at: coordinate(at: progress))
        let traveled = progress * angle
        let tangent: SIMD3<Double>
        if let transition = runwayTransition(at: progress) {
            tangent = transition.curve.direction(at: transition.fraction)
        } else {
            tangent = direction * cos(traveled) - start * sin(traveled)
        }
        return atan2(simd_dot(tangent, east), simd_dot(tangent, north)) * 180 / .pi
    }

    private func runwayTransition(at progress: Double) -> (curve: RunwayTransition, fraction: Double)? {
        if let departure, progress <= departure.fraction {
            return (departure, progress / departure.fraction)
        }
        if let arrival, progress >= 1 - arrival.fraction {
            return (arrival, 1 - (1 - progress) / arrival.fraction)
        }
        return nil
    }

    private struct RunwayTransition {
        let fraction: Double
        let start: SIMD3<Double>
        let end: SIMD3<Double>
        let entry: SIMD3<Double>
        let exit: SIMD3<Double>
        let bend: SIMD3<Double>

        init?(fraction: Double, length: Double, start: SIMD3<Double>, end: SIMD3<Double>,
              entry: SIMD3<Double>, exit: SIMD3<Double>) {
            guard fraction > 0 else { return nil }
            self.fraction = fraction
            self.start = start
            self.end = end
            self.entry = entry * length * 0.85
            self.exit = exit * length * 0.85
            let tangent = end - start
            let backward = min(simd_dot(simd_normalize(tangent), entry), simd_dot(simd_normalize(tangent), exit))
            // A nearly opposite heading needs lateral room to turn without doubling back along the same line.
            bend = simd_normalize(simd_cross(start, tangent)) * (length * max(0, -backward - 0.70))
        }

        func point(at t: Double) -> SIMD3<Double> {
            let s = 1 - t
            let a = s * s * (1 + 2 * t)
            let b = t * s * s
            let c = t * t * (3 - 2 * t)
            let d = -t * t * s
            return start * a + entry * b + end * c + exit * d + bend * (16 * t * t * s * s)
        }

        func direction(at t: Double) -> SIMD3<Double> {
            let s = 1 - t
            return (end - start) * (6 * t * s) + entry * (s * (1 - 3 * t))
                + exit * (t * (3 * t - 2)) + bend * (32 * t * s * (1 - 2 * t))
        }
    }

    /// MapKit and the aircraft share the same sampled great circle. Split wrapped pieces at the exact seam.
    func segments() -> [[CLLocationCoordinate2D]] {
        let count = max(2, Int(ceil(angle / (.pi / 36))))
        let liftoff = departure?.fraction ?? 0
        let approach = 1 - (arrival?.fraction ?? 0)
        var samples = liftoff > 0 ? Self.sampleFractions(from: 0, to: liftoff, count: 36) : []
        samples += Self.sampleFractions(from: liftoff, to: approach, count: count)
        if approach < 1 { samples += Self.sampleFractions(from: approach, to: 1, count: 36) }
        var segments: [[CLLocationCoordinate2D]] = []
        var segment = [origin]
        var previous = origin
        var previousFraction = 0.0
        for fraction in samples {
            let point = coordinate(at: fraction)
            let delta = point.longitude - previous.longitude
            if abs(delta) > 180 {
                let seam = delta < 0 ? 180.0 : -180.0
                let latitude = seamLatitude(from: previousFraction, to: fraction,
                                            near: previous.longitude, seam: seam)
                segment.append(CLLocationCoordinate2D(latitude: latitude, longitude: seam))
                segments.append(segment)
                segment = [CLLocationCoordinate2D(latitude: latitude, longitude: -seam)]
            }
            segment.append(point)
            previous = point
            previousFraction = fraction
        }
        segments.append(segment)
        return segments
    }

    private static func sampleFractions(from start: Double, to end: Double, count: Int) -> [Double] {
        (1...count).map { $0 == count ? end : start + (end - start) * Double($0) / Double(count) }
    }

    private func seamLatitude(from startFraction: Double, to endFraction: Double, near reference: Double, seam: Double) -> Double {
        var start = startFraction
        var end = endFraction
        let eastbound = seam > 0
        for _ in 0..<32 {
            let mid = (start + end) / 2
            let longitude = coordinate(at: mid).longitude
            let delta = longitude - reference
            let unwrapped = longitude - (delta / 360).rounded() * 360
            if (unwrapped < seam) == eastbound { start = mid }
            else { end = mid }
        }
        return coordinate(at: (start + end) / 2).latitude
    }

    func overviewCamera(aspect: CGFloat, padding: CGFloat = 1) -> MapCamera {
        let diameter = Self.earthRadius * angle
        let fit = Double(padding) * max(2.35, 2.35 / Double(max(0.6, aspect)))
        let horizon = Self.earthRadius * (1 / cos(min(1.46, angle / 2 + 0.08)) - 1)
        let distance = min(53_000_000, max(24_000, diameter * fit, horizon))
        return MapCamera(centerCoordinate: coordinate(at: 0.5), distance: distance)
    }

    func globalCamera(aspect: CGFloat, at progress: Double) -> MapCamera {
        let fit = max(1, min(1.42, 1.3 / Double(aspect)))
        let distance = 37_000_000 * fit
        let safeRadius = min(.pi * 0.32, acos(Self.earthRadius / (Self.earthRadius + distance)) - .pi / 12)
        let window = safeRadius / max(1e-9, angle)
        // Hold the midpoint on shorter tracks. On longer tracks rotate only enough to keep the aircraft on the front.
        let center = max(progress - window, min(0.5, progress + window))
        return MapCamera(centerCoordinate: coordinate(at: center), distance: distance)
    }

    func followCamera(at progress: Double, groundCoordinate: CLLocationCoordinate2D?) -> MapCamera {
        if let groundCoordinate {
            return MapCamera(centerCoordinate: groundCoordinate, distance: 4_500, pitch: 26)
        }
        let regional = min(2_200_000, max(24_000, Self.earthRadius * angle * 0.19))
        let blend = min(1, min(progress, 1 - progress) / 0.10)
        let smooth = blend * blend * (3 - 2 * blend)
        return MapCamera(centerCoordinate: coordinate(at: progress), distance: 4_500 + (regional - 4_500) * smooth,
                         pitch: 26 * (1 - smooth))
    }

    struct Observer {
        private let position: SIMD3<Double>

        init(camera: MapCamera) {
            let center = FlightSimulatorArc.vector(camera.centerCoordinate)
            let tangent = FlightSimulatorArc.tangent(at: camera.centerCoordinate, course: camera.heading)
            let pitch = camera.pitch * .pi / 180
            let range = camera.distance / FlightSimulatorArc.earthRadius
            position = center + (center * cos(pitch) - tangent * sin(pitch)) * range
        }

        func sees(_ coordinate: CLLocationCoordinate2D) -> Bool {
            // For a unit sphere, the outward normal must face the observer: dot(surface, observer) >= 1.
            simd_dot(FlightSimulatorArc.vector(coordinate), position) >= 1 - 1e-9
        }
    }

    static func offset(from coordinate: CLLocationCoordinate2D, course: Double, meters: Double) -> CLLocationCoordinate2D {
        let distance = meters / earthRadius
        return Self.coordinate(vector(coordinate) * cos(distance) + tangent(at: coordinate, course: course) * sin(distance))
    }

    static func angularDistance(_ point: CLLocationCoordinate2D, _ next: CLLocationCoordinate2D) -> Double {
        let start = vector(point)
        let end = vector(next)
        return atan2(simd_length(simd_cross(start, end)), simd_dot(start, end))
    }

    private static func tangent(at coordinate: CLLocationCoordinate2D, course: Double) -> SIMD3<Double> {
        let (north, east) = directions(at: coordinate)
        let angle = course * .pi / 180
        return north * cos(angle) + east * sin(angle)
    }

    private static func directions(at coordinate: CLLocationCoordinate2D) -> (north: SIMD3<Double>, east: SIMD3<Double>) {
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        let north = SIMD3<Double>(-sin(latitude) * cos(longitude), -sin(latitude) * sin(longitude), cos(latitude))
        let east = SIMD3<Double>(-sin(longitude), cos(longitude), 0)
        return (north, east)
    }

    private static func vector(_ coordinate: CLLocationCoordinate2D) -> SIMD3<Double> {
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        return SIMD3(cos(latitude) * cos(longitude), cos(latitude) * sin(longitude), sin(latitude))
    }

    private static func coordinate(_ point: SIMD3<Double>) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: atan2(point.z, hypot(point.x, point.y)) * 180 / .pi,
                               longitude: atan2(point.y, point.x) * 180 / .pi)
    }
}
