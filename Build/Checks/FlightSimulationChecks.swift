import Foundation

@main
enum FlightSimulationChecks {
    static func main() {
        do {
            for wind: FlightSimulation.Wind in [
                .calm, .turbulence, .crosswind,
                .observed(knots: 26, directionDegrees: 120, airport: .arrival),
                .observed(knots: 45, airport: .departure)
            ] {
                try completeRoute(wind: wind)
            }
            try checkObservedWind(at: .departure)
            try checkObservedWind(at: .arrival)
            try checkShortRunway()
            print("Passed complete flights, stage gates, runway limits, observed wind, route progress and debrief.")
            #if CHECK_TOUCH_MOVEMENT
            try checkTouchMovement()
            print("Passed two-finger zoom, three-finger separation, and lift-to-two isolation.")
            #endif
        } catch let failure as Failure {
            FileHandle.standardError.write(Data("\(failure.message)\n".utf8))
            exit(EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func completeRoute(wind: FlightSimulation.Wind) throws {
        let distance = 10_770.0
        var flight = FlightSimulation(wingspanM: 64.8, runwayLengthM: 3_300,
                                      originElevationFt: 19, destinationElevationFt: 116,
                                      distanceKm: distance, departureRunwayHeading: 90,
                                      destinationRunwayHeading: 180, destinationRunwayLengthM: 3_050)
        flight.wind = wind
        flight.advance(by: 1)
        try require(flight.phase == .briefing && flight.progress == 0 && flight.altitude == 19,
                    "Briefing advanced the aircraft before start.")
        flight.start()
        for _ in 0..<5 { flight.advance(by: 1) }
        try require(flight.phase == .takeoff && flight.airspeed == 0 && flight.runwayUsed == 0,
                    "A parked aircraft moved without releasing its brake and applying thrust.")

        flight.applyRecommendedControls()
        flight.pitch = 0
        for _ in 0..<80 where flight.airspeed < flight.rotationSpeed { flight.advance(by: 0.25) }
        try require(flight.phase == .takeoff && flight.onGround && flight.airspeed >= flight.rotationSpeed,
                    "Takeoff bypassed the pitch gate, or could not reach its reference speed.")
        try require(flight.progress == 0, "Takeoff roll moved the route marker away from departure.")
        try advance(to: .climb, flight: &flight)
        try require(!flight.onGround && flight.progress < 100 / distance, "Climb started outside the departure area.")
        try advance(to: .cruise, flight: &flight)
        try require(!flight.gearDown && flight.flaps == .retracted, "Cruise bypassed its configuration checks.")
        try advance(to: .approach, flight: &flight)
        try require(flight.progress >= 1 - 135 / distance, "Descent started outside the arrival area.")

        for _ in 0..<320 {
            flight.applyRecommendedControls()
            flight.gearDown = false
            flight.advance(by: 0.25)
            if flight.phaseProgress == 1 { break }
        }
        try require(flight.phase == .approach && flight.phaseProgress == 1 && flight.verticalSpeed == 0,
                    "An approach with the gear up did not hold before final landing.")

        let missedAltitude = flight.altitude
        flight.goAround()
        flight.advance(by: 0.25)
        try require(flight.phase == .climb && flight.altitude >= missedAltitude && flight.progress > 0.98,
                    "Go-around did not stay near the arrival airport and climb.")
        try advance(to: .approach, flight: &flight)
        try advance(to: .landing, flight: &flight)
        try require(flight.progress >= 1 - 15 / distance && flight.progress < 1 && !flight.onGround,
                    "Final approach did not start within 15 km of arrival.")
        try advance(to: .arrived, flight: &flight)
        try require(flight.progress == 1 && flight.onGround && flight.airspeed <= 3,
                    "Arrival did not stop at its airport.")

        guard let summary = flight.summary else { throw Failure("Arrival omitted its debrief.") }
        try require(summary.takeoffRollM > 500 && summary.landingRollM > 100 && !summary.landingRunwayExceeded,
                    "Debrief omitted or misreported the runway rolls.")
        try require((summary.touchdownVerticalSpeed ?? 0) < 0 && (summary.landingSpeed ?? 0) >= 115,
                    "Debrief omitted the touchdown descent rate or landing speed.")
        try require(summary.peakSpeed >= 220 && summary.peakAltitude >= 32_000 && summary.goArounds == 1,
                    "Debrief omitted the cruise readings or the missed approach.")
        try require(summary.samples.first?.elapsed == 0 && summary.samples.last?.elapsed == summary.elapsed,
                    "Telemetry did not cover the full flight.")
        try require(summary.samples.count <= 120 && zip(summary.samples, summary.samples.dropFirst()).allSatisfy {
            $0.elapsed < $1.elapsed
        }, "Telemetry was unbounded or out of order.")
        flight.reset()
        try require(flight.phase == .briefing && flight.summary == nil && flight.brake
                    && flight.altitude == 19 && flight.wind == wind,
                    "Replay retained flight state or discarded the selected weather.")
    }

    private static func checkObservedWind(at airport: FlightSimulation.WindAirport) throws {
        var flight = FlightSimulation(runwayLengthM: 3_000, distanceKm: 700,
                                      departureRunwayHeading: 90, destinationRunwayHeading: 90)
        flight.wind = .observed(knots: 20, directionDegrees: 90, airport: airport)
        try require(flight.headwindKnots == (airport == .departure ? 20 : nil),
                    "Incorrect runway components at departure.")
        flight.start()
        try advance(to: .cruise, flight: &flight)
        try require(flight.headwindKnots == nil && flight.crosswindKnots == nil,
                    "An airport's ground wind was displayed in cruise.")
        try advance(to: .approach, flight: &flight)
        try require(flight.headwindKnots == (airport == .arrival ? 20 : nil),
                    "Incorrect runway components at arrival.")
        if airport == .arrival {
            try require(abs(flight.crosswindKnots ?? .infinity) < 1e-9, "Headwind was projected as a crosswind.")
            flight.wind = .observed(knots: 20, airport: .arrival)
            try require(flight.headwindKnots == nil && flight.crosswindKnots == nil,
                        "Runway wind components were invented without a reported direction.")
        }
    }

    private static func checkShortRunway() throws {
        var flight = FlightSimulation(wingspanM: 79, runwayLengthM: 240, departureRunwayHeading: 90)
        flight.wind = .observed(knots: 12, directionDegrees: 180, airport: .departure)
        try require(abs(flight.headwindKnots ?? .infinity) < 1e-9 && abs((flight.crosswindKnots ?? 0) - 12) < 1e-9,
                    "Perpendicular weather was not projected entirely to the crosswind component.")
        flight.start()
        flight.applyRecommendedControls()
        for _ in 0..<60 { flight.advance(by: 1) }
        try require(flight.takeoffAborted && flight.phase == .takeoff && flight.progress == 0 && flight.summary == nil,
                    "The aircraft departed after exceeding the runway length.")
    }

    private static func advance(to target: FlightSimulation.Phase, flight: inout FlightSimulation) throws {
        for _ in 0..<800 {
            if flight.phase == target { return }
            flight.applyRecommendedControls()
            flight.advance(by: 0.25)
            try require((0...1).contains(flight.progress) && (0...1).contains(flight.phaseProgress)
                        && flight.altitude.isFinite && flight.airspeed.isFinite,
                        "Simulation produced an invalid reading during \(flight.phase).")
            try require(!flight.takeoffAborted, "Unexpected runway abort en route to \(target).")
        }
        throw Failure("Timed out at \(flight.phase) while advancing to \(target).")
    }

    #if CHECK_TOUCH_MOVEMENT
    private static func checkTouchMovement() throws {
        var movement = ModelTouchMovement()
        let pair = [CGPoint(x: 0, y: -30), CGPoint(x: 0, y: 30)]
        movement.contactsChanged(pair)
        guard case .transform(let pan, let zoom)? = movement.move(pair.map { CGPoint(x: $0.x, y: $0.y * 1.5) }) else {
            throw Failure("A vertical two-finger spread did not zoom.")
        }
        try require(pan == .zero && zoom == 1.5, "Two-finger spread panned or changed component separation.")

        let triangle = pair + [CGPoint(x: 35, y: 0)]
        movement.contactsChanged(triangle)
        try require(movement.move(triangle.map { CGPoint(x: $0.x + 10, y: $0.y + 10) }) == nil,
                    "Rigid movement of three contacts split the model.")
        guard case .separation(let spread)? = movement.move(triangle.map { CGPoint(x: $0.x * 1.5, y: $0.y * 1.5) }),
              case .separation(let pinch)? = movement.move(triangle) else {
            throw Failure("Three-finger spread and pinch did not change separation.")
        }
        try require(spread > 1 && pinch < 1, "Three-finger separation direction was reversed.")
        movement.contactsChanged(pair)
        try require(movement.move([CGPoint(x: 0, y: -70), CGPoint(x: 0, y: 70)]) == nil,
                    "Lifting a third finger changed the camera zoom before a new gesture.")
    }
    #endif

    private struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message) }
    }
}
