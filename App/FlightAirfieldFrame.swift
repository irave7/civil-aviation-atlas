import simd

/// Meter coordinates shared by the runway, site geometry and moving aircraft.
struct FlightAirfieldFrame {
    let airport: Airport
    let runway: Runway?
    let route: FlightGroundRoute?
    let position: SIMD3<Float>
    let heading: Float
    let visibility: Double

    var sceneID: String { "\(airport.id)|\(runway?.id ?? "")|\(route?.directionName ?? "")" }

    @MainActor
    init?(airport: Airport, runway: Runway?, route: FlightGroundRoute?, pose: FlightGroundPose,
          flight: FlightSimulation, altitudeMeters: Double, arriving: Bool) {
        guard flight.phase != .cruise, altitudeMeters.isFinite, altitudeMeters < 420 else { return nil }
        self.airport = airport
        self.runway = runway
        self.route = route
        if airport.hasCoordinates, pose.latitude.isFinite, pose.longitude.isFinite, pose.heading.isFinite {
            let offset = FlightAirfieldScenery.offset(pose, airport: airport)
            position = [offset.x, Float(altitudeMeters), offset.y]
            heading = Float(pose.heading)
        } else {
            // The offline catalog deliberately omits locations. Use runway-relative meters.
            let length = route?.runwayLengthM ?? runway?.lengthM ?? 3_000
            let touch = min(350, length * 0.12)
            let travel: Double
            if arriving {
                travel = flight.onGround ? touch + flight.landingRollM : touch - altitudeMeters * 12
            } else {
                travel = flight.runwayUsed + altitudeMeters * 10
            }
            position = [Float(travel - length / 2), Float(altitudeMeters), 0]
            heading = 90
        }
        if flight.onGround {
            visibility = 1
        } else {
            // Grade coverage by distance outside the selected runway corridor, not distance
            // from the airport reference point; an outlying runway still gets full ground detail.
            let length = Float(route?.runwayLengthM ?? runway?.lengthM ?? 3_000)
            let start = route.map { FlightAirfieldScenery.offset($0.threshold, airport: airport) }
                ?? SIMD2<Float>(-length / 2, 0)
            let end = route.map { FlightAirfieldScenery.offset($0.runwayExit, airport: airport) }
                ?? SIMD2<Float>(length / 2, 0)
            let axis = end - start
            let displacement = SIMD2(position.x, position.z) - start
            let station = min(1, max(0, simd_dot(displacement, axis) / max(1, simd_length_squared(axis))))
            let outside = Double(simd_length(displacement - station * axis))
            func remaining(_ value: Double, from start: Double, to end: Double) -> Double {
                let t = min(1, max(0, (value - start) / (end - start)))
                return 1 - t * t * (3 - 2 * t)
            }
            visibility = remaining(altitudeMeters, from: 75, to: 420) * remaining(outside, from: 350, to: 2_400)
        }
        guard visibility > 0 else { return nil }
    }
}
