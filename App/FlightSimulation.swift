import Foundation

struct FlightGroundPose: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let heading: Double

    private static let earthRadius = 6_371_008.8

    func distance(to other: Self) -> Double {
        let phi = latitude * .pi / 180
        let otherPhi = other.latitude * .pi / 180
        let longitudeDelta = (other.longitude - longitude) * .pi / 180
        let a = pow(sin((otherPhi - phi) / 2), 2) + cos(phi) * cos(otherPhi) * pow(sin(longitudeDelta / 2), 2)
        return 2 * Self.earthRadius * asin(sqrt(min(1, max(0, a))))
    }

    func course(to other: Self) -> Double {
        let phi = latitude * .pi / 180
        let otherPhi = other.latitude * .pi / 180
        let longitudeDelta = (other.longitude - longitude) * .pi / 180
        let east = sin(longitudeDelta) * cos(otherPhi)
        let north = cos(phi) * sin(otherPhi) - sin(phi) * cos(otherPhi) * cos(longitudeDelta)
        return Self.normalize(atan2(east, north) * 180 / .pi)
    }

    func displaced(by distance: Double, toward bearing: Double) -> Self {
        let angle = distance / Self.earthRadius
        let theta = bearing * .pi / 180
        let phi = latitude * .pi / 180
        let sinPhi = sin(phi), cosPhi = cos(phi)
        let endPhi = asin(min(1, max(-1, sinPhi * cos(angle) + cosPhi * sin(angle) * cos(theta))))
        let longitudeShift = atan2(sin(theta) * sin(angle) * cosPhi, cos(angle) - sinPhi * sin(endPhi)) * 180 / .pi
        return Self(latitude: endPhi * 180 / .pi,
                    longitude: Self.normalize(longitude + longitudeShift + 180) - 180,
                    heading: Self.normalize(bearing))
    }

    func facing(_ heading: Double) -> Self {
        Self(latitude: latitude, longitude: longitude, heading: Self.normalize(heading))
    }

    static func normalize(_ heading: Double) -> Double {
        let value = heading.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    static func headingChange(from first: Double, to second: Double) -> Double {
        normalize(second - first + 180) - 180
    }
}

struct FlightGroundRoute: Sendable {
    enum Operation { case departure, arrival }

    struct Connector: Sendable {
        let runwayDistanceM: Double
        /// Coordinates start on the runway centerline and end on the connected taxiway.
        let outwardPath: [FlightGroundPose]
    }

    let threshold: FlightGroundPose
    let runwayLengthM: Double
    let directionName: String
    let recordedAxis: Bool
    let usesOpenStreetMapRunway: Bool
    let connectors: [Connector]

    var runwayHeading: Double { threshold.heading }
    var runwayExit: FlightGroundPose { pose(onRunway: runwayLengthM) }
    var touchdownDistanceM: Double { min(350, runwayLengthM * 0.12) }
    var touchdown: FlightGroundPose { pose(onRunway: touchdownDistanceM) }

    var sourceLabel: String {
        if !recordedAxis { return "参考跑道轴线" }
        return connectors.isEmpty ? "已收录跑道中心线" : "已收录跑道 · © OpenStreetMap contributors"
    }

    func pose(onRunway distance: Double) -> FlightGroundPose {
        threshold.displaced(by: min(runwayLengthM, max(0, distance)), toward: runwayHeading)
    }

    var departureConnector: Connector? { connectors.first }

    func exit(afterRunwayDistance distance: Double) -> Connector? {
        connectors.first { $0.runwayDistanceM >= distance }
    }
}

private struct FlightTaxiPath {
    let points: [FlightGroundPose]
    private let distances: [Double]
    private let headings: [Double]

    init(points: [FlightGroundPose]) {
        self.points = points
        var distances = [0.0]
        var headings: [Double] = []
        for (start, end) in zip(points, points.dropFirst()) {
            distances.append(distances[distances.count - 1] + start.distance(to: end))
            headings.append(start.course(to: end))
        }
        self.distances = distances
        self.headings = headings
    }

    var lengthM: Double { distances.last ?? 0 }

    func pose(at distance: Double, endHeading: Double? = nil) -> FlightGroundPose? {
        guard let lastPoint = points.last, let lastHeading = headings.last else { return points.first }
        guard let end = distances.dropFirst().firstIndex(where: { $0 > distance }) else {
            return lastPoint.facing(endHeading ?? lastHeading)
        }
        let start = end - 1
        let travel = max(0, distance - distances[start])
        let remaining = distances[end] - distance
        let heading = headings[start]
        let pose = points[start].displaced(by: travel, toward: heading)
        let nextHeading = end < headings.count ? headings[end] : endHeading
        let turnDistance = min(16, distances[end] - distances[start])
        guard let nextHeading, remaining < turnDistance else { return pose }
        let turn = (1 - remaining / turnDistance) * FlightGroundPose.headingChange(from: heading, to: nextHeading)
        return pose.facing(heading + turn)
    }
}

/// A time-compressed simulation that uses representative jet behavior, not aircraft performance tables.
struct FlightSimulation {
    enum Phase: Int, CaseIterable {
        case briefing, takeoff, climb, cruise, approach, landing, arrived

        var title: String {
            switch self {
            case .briefing: "飞行准备"
            case .takeoff: "起飞滑跑"
            case .climb: "离地与爬升"
            case .cruise: "巡航"
            case .approach: "下降与进近"
            case .landing: "着陆与减速"
            case .arrived: "飞行复盘"
            }
        }
    }

    enum Flaps: String, CaseIterable, Identifiable {
        case retracted, takeoff, landing
        var id: Self { self }
        var title: String {
            switch self {
            case .retracted: "收起"
            case .takeoff: "起飞"
            case .landing: "着陆"
            }
        }
    }

    enum GroundStage: Equatable {
        case taxiOut, takeoffRoll, landingRoll, taxiIn

        var title: String {
            switch self {
            case .taxiOut: "滑出与对正"
            case .takeoffRoll: "起飞滑跑"
            case .landingRoll: "接地后减速"
            case .taxiIn: "脱离跑道与滑入"
            }
        }
    }

    enum WindAirport: Equatable { case departure, arrival }

    enum Wind: Equatable {
        case calm, turbulence, crosswind
        case observed(knots: Double, directionDegrees: Double? = nil, airport: WindAirport? = nil)
    }

    struct Check: Identifiable, Equatable {
        let id: String
        let title: String
        let complete: Bool

        init(_ id: String, _ title: String, _ complete: Bool) {
            self.id = id
            self.title = title
            self.complete = complete
        }
    }

    struct Summary: Equatable {
        let takeoffRollM: Double
        let landingRollM: Double
        let taxiOutM: Double
        let taxiInM: Double
        let landingSpeed: Double?
        let touchdownVerticalSpeed: Double?
        let peakAltitude: Double
        let peakSpeed: Double
        let elapsed: Double
        let goArounds: Int
        let maxBank: Double
        let landingRunwayExceeded: Bool
        let samples: [Sample]
    }

    struct Sample: Equatable, Identifiable {
        let elapsed: Double
        let altitude: Double
        let airspeed: Double
        var id: Double { elapsed }
    }

    var throttle = 0.0
    var pitch = 0.0
    var bank = 0.0
    var flaps: Flaps = .retracted
    var gearDown = true
    var brake = true
    var reverseThrust = false
    var wind: Wind = .calm

    private(set) var phase: Phase = .briefing
    private(set) var airspeed = 0.0
    private(set) var altitude: Double
    private(set) var verticalSpeed = 0.0
    private(set) var runwayUsed = 0.0
    private(set) var landingRollM = 0.0
    private(set) var taxiDistanceM = 0.0
    private(set) var takeoffAborted = false
    private(set) var onGround = true
    let rotationSpeed: Double
    let referenceApproachSpeed: Double

    private let originElevation: Double
    private let destinationElevation: Double
    private let routeDistance: Double
    private let cruiseAltitude: Double
    private let cruiseDuration: Double
    private let departureRunwayLength: Double?
    private let destinationRunwayLength: Double?
    private let departureRunwayHeading: Double?
    private let destinationRunwayHeading: Double?
    let departureGround: FlightGroundRoute?
    let arrivalGround: FlightGroundRoute?
    private let departureTaxi: FlightTaxiPath?
    private var departureTaxiComplete = false
    private var arrivalTaxi: FlightTaxiPath?
    private var liftoffPose: FlightGroundPose?
    private var elapsed = 0.0
    private var phaseElapsed = 0.0
    private var goArounds = 0
    private var goAroundTargetAltitude: Double?
    private var landingSpeed: Double?
    private var touchdownVerticalSpeed: Double?
    private var peakAltitude = 0.0
    private var peakSpeed = 0.0
    private var maxBank = 0.0
    private var samples: [Sample] = []
    private var sampleInterval = 2.5

    init(wingspanM: Double? = nil, runwayLengthM: Double? = nil, originElevationFt: Int? = nil,
         destinationElevationFt: Int? = nil, distanceKm: Double = 0,
         departureRunwayHeading: Double? = nil, destinationRunwayHeading: Double? = nil,
         destinationRunwayLengthM: Double? = nil, departureGround: FlightGroundRoute? = nil,
         arrivalGround: FlightGroundRoute? = nil) {
        let span = wingspanM.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 36
        let size = min(1, max(0, (span - 30) / 48))
        let distance = distanceKm.isFinite ? max(0, distanceKm) : 0
        routeDistance = max(1, distance)
        originElevation = Double(originElevationFt ?? 0)
        destinationElevation = Double(destinationElevationFt ?? 0)
        cruiseAltitude = max(22_000 + min(1, distance / 2_500) * 12_000,
                             max(originElevation, destinationElevation) + 12_000)
        cruiseDuration = 12 + min(1, distance / 5_000) * 14
        altitude = originElevation
        rotationSpeed = (133 + 26 * size).rounded()
        referenceApproachSpeed = (130 + 23 * size).rounded()
        departureRunwayLength = departureGround?.runwayLengthM ?? runwayLengthM.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        destinationRunwayLength = arrivalGround?.runwayLengthM ?? destinationRunwayLengthM.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.departureRunwayHeading = departureGround?.runwayHeading ?? departureRunwayHeading.flatMap { $0.isFinite ? $0 : nil }
        self.destinationRunwayHeading = arrivalGround?.runwayHeading ?? destinationRunwayHeading.flatMap { $0.isFinite ? $0 : nil }
        self.departureGround = departureGround
        self.arrivalGround = arrivalGround
        departureTaxi = departureGround?.departureConnector.map { FlightTaxiPath(points: Array($0.outwardPath.reversed())) }
    }

    var groundStage: GroundStage? {
        switch phase {
        case .briefing, .takeoff:
            departureTaxi != nil && !departureTaxiComplete ? .taxiOut : .takeoffRoll
        case .landing where onGround, .arrived:
            arrivalTaxi == nil ? .landingRoll : .taxiIn
        default: nil
        }
    }

    var groundPose: FlightGroundPose? {
        switch groundStage {
        case .taxiOut: departureTaxi?.pose(at: taxiDistanceM, endHeading: departureGround?.runwayHeading)
        case .takeoffRoll: departureGround?.pose(onRunway: departureEntryM + runwayUsed)
        case .landingRoll: arrivalGround?.pose(onRunway: arrivalRunwayPositionM)
        case .taxiIn: arrivalTaxi?.pose(at: taxiDistanceM)
        case nil: nil
        }
    }

    var departureAirStart: FlightGroundPose? {
        liftoffPose ?? departureGround?.pose(onRunway: departureEntryM)
    }

    var arrivalAirEnd: FlightGroundPose? { arrivalGround?.touchdown }

    var groundTrack: [FlightGroundPose] {
        switch groundStage {
        case .taxiOut: departureTaxi?.points ?? []
        case .takeoffRoll: departureGround.map { [$0.pose(onRunway: departureEntryM), $0.runwayExit] } ?? []
        case .landingRoll: arrivalGround.map { [$0.touchdown, $0.runwayExit] } ?? []
        case .taxiIn: arrivalTaxi?.points ?? []
        case nil: []
        }
    }

    var runwayTrack: [FlightGroundPose] { activeGroundRoute.map { [$0.threshold, $0.runwayExit] } ?? [] }

    var groundSourceLabel: String? { activeGroundRoute?.sourceLabel }

    var groundSpeedKnots: Double { groundSpeed }

    var canUseReverseThrust: Bool { phase == .landing && groundStage == .landingRoll && throttle < 10 && airspeed > 15 }

    private var activeGroundRoute: FlightGroundRoute? {
        switch groundStage {
        case .taxiOut, .takeoffRoll: departureGround
        case .landingRoll, .taxiIn: arrivalGround
        case nil: nil
        }
    }

    private var departureEntryM: Double { departureGround?.departureConnector?.runwayDistanceM ?? 0 }
    private var arrivalRunwayPositionM: Double { (arrivalGround?.touchdownDistanceM ?? 0) + landingRollM }
    private var isTaxiing: Bool { groundStage == .taxiOut || groundStage == .taxiIn }

    var progress: Double {
        let climbEnd = min(0.24, 100 / routeDistance)
        let approachStart = 1 - min(0.24, 135 / routeDistance)
        let landingStart = 1 - min(0.08, 15 / routeDistance)
        let goAroundStart = landingStart - (landingStart - approachStart) * 0.2
        switch phase {
        case .briefing, .takeoff: return 0
        case .climb where returningToApproach: return goAroundStart
        case .climb: return climbEnd * phaseProgress
        case .cruise: return climbEnd + (approachStart - climbEnd) * phaseProgress
        case .approach:
            let start = returningToApproach ? goAroundStart : approachStart
            return start + (landingStart - start) * phaseProgress
        case .landing:
            return onGround ? 1 : landingStart + (1 - landingStart) * (1 - unit((altitude - destinationElevation) / 1_350))
        case .arrived: return 1
        }
    }

    var phaseProgress: Double {
        switch phase {
        case .briefing: return 0
        case .takeoff:
            if groundStage == .taxiOut, let departureTaxi { return 0.2 * unit(taxiDistanceM / departureTaxi.lengthM) }
            let portion = unit(airspeed / rotationSpeed)
            return departureTaxi == nil ? portion : 0.2 + 0.8 * portion
        case .climb:
            let start = returningToApproach ? destinationElevation : originElevation + 35
            return unit((altitude - start) / (climbTargetAltitude - start))
        case .cruise: return unit(phaseElapsed / cruiseDuration)
        case .approach:
            let height = climbTargetAltitude - destinationElevation
            return 1 - unit((altitude - destinationElevation - 1_350) / (height - 1_350))
        case .landing:
            if let arrivalTaxi { return 0.95 + 0.05 * unit(taxiDistanceM / arrivalTaxi.lengthM) }
            return onGround ? 0.8 + 0.2 * (1 - unit(airspeed / max(1, landingSpeed ?? airspeed)))
                : 0.8 * (1 - unit((altitude - destinationElevation) / 1_350))
        case .arrived: return 1
        }
    }

    var headwindKnots: Double? { windComponents?.headwind }
    var crosswindKnots: Double? { windComponents?.crosswind }
    var effectivePitch: Double { min(24, max(-24, pitch + gust * 0.7)) }
    var effectiveBank: Double { min(36, max(-36, bank + bankCorrection + gust * 1.25)) }
    var canGoAround: Bool { phase == .approach || (phase == .landing && !onGround) }

    var checklist: [Check] {
        if let stage = groundStage, stage == .taxiOut || stage == .taxiIn {
            return [Check("taxi-gear", "确认起落架放下", gearDown),
                    Check("taxi-brake", "按需松开刹车", !brake),
                    Check("taxi-power", "使用低推力滑行", (0.1...55).contains(throttle)),
                    Check("taxi-speed", "保持地面低速", (0.5...22).contains(groundSpeed))]
        }
        return switch phase {
        case .briefing, .takeoff:
            [Check("takeoff-flaps", "襟翼设为起飞", flaps == .takeoff),
             Check("takeoff-gear", "保持起落架放下", gearDown),
             Check("takeoff-brake", "松开刹车", !brake),
             Check("takeoff-power", "增加起飞推力", throttle >= 75),
             Check("takeoff-speed", "速度达到抬轮参考值", airspeed >= rotationSpeed),
             Check("takeoff-rotate", "轻抬机头并保持机翼平稳", (5...14).contains(pitch) && abs(effectiveBank) <= 8)]
        case .climb:
            [Check("climb-positive", "保持爬升", verticalSpeed > 200),
             Check("climb-gear", "离地后收起起落架", !gearDown),
             Check("climb-flaps", "收起襟翼", flaps == .retracted),
             Check("climb-altitude", "到达目标高度", altitude >= climbTargetAltitude - 50)]
        case .cruise:
            [Check("cruise-speed", "保持巡航速度", (215...330).contains(airspeed)),
             Check("cruise-level", "保持机翼平稳", abs(effectiveBank) <= 12),
             Check("cruise-configuration", "保持巡航构型", flaps == .retracted && !gearDown)]
        case .approach,
             .landing where !onGround:
            [Check("arrival-gear", "放下起落架", gearDown),
             Check("arrival-flaps", "襟翼设为着陆", flaps == .landing),
             Check("arrival-speed", "控制进近速度", approachSpeedRange.contains(airspeed)),
             Check("arrival-bank", "控制坡度", abs(effectiveBank) <= 10)]
        case .landing, .arrived:
            [Check("rollout-throttle", "将推力收至慢车", throttle < 10),
             Check("rollout-reverse", "按需使用反推减速", reverseThrust || airspeed <= 15),
             Check("rollout-brake", "使用刹车减速", brake),
             Check("rollout-stop", "在跑道上停稳", airspeed <= 3)]
        }
    }

    var instruction: String {
        if phase != .briefing && phase != .arrived {
            if groundStage == .taxiOut { return "松开刹车并增加少量推力，沿滑行道前往所选跑道入口。" }
            if groundStage == .taxiIn { return "松开刹车并以低推力滑行，从可用出口脱离跑道。" }
        }
        return switch phase {
        case .briefing: "检查机场跑道、客机和天气。准备好后开始飞行。"
        case .takeoff where takeoffAborted: "已用尽跑道，模拟已停止。重置航程后重新起飞。"
        case .takeoff where gearDown && flaps == .takeoff && !brake && throttle >= 75:
            airspeed < rotationSpeed ? "保持滑跑，达到参考速度后轻抬机头。" : "轻抬机头并保持机翼平稳，开始离地。"
        case .takeoff: "放下起落架，设置起飞襟翼，松开刹车并增加推力。"
        case .climb: "保持正爬升，收起起落架和襟翼，随后平稳进入巡航。"
        case .cruise: "维持巡航速度与机翼平稳，留意气流对姿态的影响。"
        case .approach: "设置着陆襟翼，放下起落架，减速下降。进近稳定后才会进入最终着陆。"
        case .landing where onGround: "飞机已接地。收回推力并踩刹车，在跑道上停稳。"
        case .landing where altitude - destinationElevation <= 65: "接地前轻抬机头，保持着陆构型和稳定速度。"
        case .landing: "对准跑道，保持稳定下降。进近不稳时可以复飞。"
        case .arrived: "航程结束。查看起飞、着陆和巡航记录。"
        }
    }

    var summary: Summary? {
        guard phase == .arrived else { return nil }
        return Summary(takeoffRollM: runwayUsed, landingRollM: landingRollM,
                       taxiOutM: departureTaxiComplete ? (departureTaxi?.lengthM ?? 0) : 0,
                       taxiInM: arrivalTaxi == nil ? 0 : taxiDistanceM, landingSpeed: landingSpeed,
                       touchdownVerticalSpeed: touchdownVerticalSpeed, peakAltitude: peakAltitude,
                       peakSpeed: peakSpeed, elapsed: elapsed, goArounds: goArounds, maxBank: maxBank,
                       landingRunwayExceeded: destinationRunwayLength.map { arrivalRunwayPositionM > $0 } ?? false,
                       samples: samples)
    }

    mutating func start() {
        guard phase == .briefing else { return }
        transition(to: .takeoff)
        recordSample()
    }

    mutating func reset() {
        throttle = 0
        pitch = 0
        bank = 0
        flaps = .retracted
        gearDown = true
        brake = true
        reverseThrust = false
        transition(to: .briefing)
        airspeed = 0
        altitude = originElevation
        verticalSpeed = 0
        runwayUsed = 0
        landingRollM = 0
        taxiDistanceM = 0
        departureTaxiComplete = false
        arrivalTaxi = nil
        liftoffPose = nil
        takeoffAborted = false
        onGround = true
        elapsed = 0
        goArounds = 0
        goAroundTargetAltitude = nil
        landingSpeed = nil
        touchdownVerticalSpeed = nil
        peakAltitude = originElevation
        peakSpeed = 0
        maxBank = 0
        samples.removeAll(keepingCapacity: true)
        sampleInterval = 2.5
    }

    mutating func goAround() {
        guard canGoAround else { return }
        goArounds += 1
        goAroundTargetAltitude = max(destinationElevation + 4_000, altitude + 1_500)
        transition(to: .climb)
        throttle = 92
        pitch = 8
        flaps = .takeoff
        brake = false
    }

    mutating func applyRecommendedControls() {
        bank = -bankCorrection
        brake = false
        if isTaxiing {
            throttle = 31
            pitch = 0
            gearDown = true
            reverseThrust = false
            return
        }
        switch phase {
        case .briefing, .takeoff:
            gearDown = true
            flaps = .takeoff
            throttle = 92
            pitch = 8
        case .climb:
            gearDown = false
            flaps = .retracted
            throttle = 84
            pitch = 9
        case .cruise:
            gearDown = false
            flaps = .retracted
            throttle = 65
            pitch = 1
        case .approach:
            setLandingConfiguration(pitch: -3)
        case .landing where !onGround:
            setLandingConfiguration(pitch: altitude - destinationElevation <= 65 ? 5 : -2)
        case .landing, .arrived:
            throttle = 0
            pitch = 0
            brake = true
            reverseThrust = canUseReverseThrust
        }
    }

    mutating func advance(by seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        // Bound catch-up after a suspended rendering tick, then use short integrator steps.
        var pending = min(1, seconds)
        while pending > 0.000_001, phase != .briefing, phase != .arrived, !takeoffAborted {
            let step = min(0.1, pending)
            advanceStep(step)
            pending -= step
        }
    }

    private var returningToApproach: Bool { goAroundTargetAltitude != nil }
    private var climbTargetAltitude: Double { goAroundTargetAltitude ?? cruiseAltitude }
    private var approachSpeedRange: ClosedRange<Double> { (referenceApproachSpeed - 12)...(referenceApproachSpeed + 28) }
    private var groundSpeed: Double {
        guard airspeed > 0 else { return 0 }
        return isTaxiing ? airspeed : max(0, airspeed - (headwindKnots ?? 0))
    }
    private var power: Double { unit(throttle / 100) }

    private var nearestAirport: WindAirport {
        phase == .approach || phase == .landing || returningToApproach || phase == .arrived ? .arrival : .departure
    }

    private var localObservedWind: (knots: Double, direction: Double?)? {
        guard case .observed(let knots, let direction, let airport) = wind, knots.isFinite,
              phase != .cruise, airport == nil || airport == nearestAirport else { return nil }
        return (max(0, knots), direction)
    }

    private var windComponents: (headwind: Double, crosswind: Double)? {
        guard let report = localObservedWind, let direction = report.direction, direction.isFinite,
              let heading = nearestAirport == .arrival ? destinationRunwayHeading : departureRunwayHeading else { return nil }
        let angle = (direction - heading) * .pi / 180
        return (report.knots * cos(angle), report.knots * sin(angle))
    }

    private var bankCorrection: Double {
        guard phase == .approach || phase == .landing || phase == .takeoff else { return 0 }
        let magnitude = wind == .crosswind && phase != .takeoff ? 7 : (crosswindKnots ?? 0) * 0.28
        return min(9, max(-9, magnitude))
    }

    private var gust: Double {
        guard !onGround else { return 0 }
        let fieldElevation = returningToApproach ? destinationElevation : originElevation
        let strength: Double = switch wind {
        case .calm: 0
        case .turbulence: phase == .cruise ? 4 : 1
        case .crosswind: phase == .approach || phase == .landing ? 2.2 : 0
        case .observed:
            if phase == .approach || phase == .landing { min(2.5, (localObservedWind?.knots ?? 0) / 14) }
            else if phase == .climb && altitude - fieldElevation < 1_800 { min(1.2, (localObservedWind?.knots ?? 0) / 22) }
            else { 0 }
        }
        return strength * (0.67 * sin(elapsed * 1.7) + 0.33 * sin(elapsed * 4.3))
    }

    private var approachStable: Bool {
        flaps == .landing && gearDown && approachSpeedRange.contains(airspeed) && abs(effectiveBank) <= 10
    }

    private mutating func advanceStep(_ step: Double) {
        elapsed += step
        switch phase {
        case .briefing, .arrived: break
        case .takeoff: advanceTakeoff(step)
        case .climb: advanceClimb(step)
        case .cruise: advanceCruise(step)
        case .approach: advanceApproach(step)
        case .landing: advanceLanding(step)
        }
        peakAltitude = max(peakAltitude, altitude)
        peakSpeed = max(peakSpeed, airspeed)
        maxBank = max(maxBank, abs(effectiveBank))
        if phase == .arrived || elapsed - (samples.last?.elapsed ?? 0) >= sampleInterval { recordSample() }
    }

    private mutating func advanceTakeoff(_ step: Double) {
        guard !takeoffAborted else { return }
        if !departureTaxiComplete, let departureTaxi {
            if advanceTaxi(step, along: departureTaxi) { departureTaxiComplete = true }
            return
        }
        let previousGroundSpeed = groundSpeed
        let acceleration = brake ? -19 : 10.5 * power - 1.7 - airspeed * 0.004
        airspeed = min(210, max(0, airspeed + acceleration * step))
        runwayUsed += (previousGroundSpeed + groundSpeed) * 0.5 * 0.514_444 * step
        verticalSpeed = 0
        if let runwayLength = departureRunwayLength, departureEntryM + runwayUsed > runwayLength {
            takeoffAborted = true
            airspeed = 0
        } else if gearDown && flaps == .takeoff && !brake && throttle >= 75 && airspeed >= rotationSpeed
                    && (5...14).contains(pitch) && abs(effectiveBank) <= 8 {
            liftoffPose = departureGround?.pose(onRunway: departureEntryM + runwayUsed)
            onGround = false
            altitude = originElevation + 35
            transition(to: .climb)
        }
    }

    private mutating func advanceClimb(_ step: Double) {
        flyTowardSpeed(106 + 225 * power, step: step)
        let climbFloor = (returningToApproach ? destinationElevation : originElevation) + 35
        verticalSpeed = max(-550, min(2_600, 150 * (effectivePitch - 1) + (airspeed - 155) * 3.8))
        altitude = min(climbTargetAltitude, max(climbFloor, altitude + verticalSpeed * step * 32 / 60))
        if altitude >= climbTargetAltitude - 50 && !gearDown && flaps == .retracted && airspeed >= 180 {
            transition(to: returningToApproach ? .approach : .cruise)
        }
    }

    private mutating func advanceCruise(_ step: Double) {
        flyTowardSpeed(158 + 193 * power, step: step)
        verticalSpeed = max(-850, min(850, (effectivePitch - 1) * 105))
        altitude = min(cruiseAltitude + 2_500, max(cruiseAltitude - 2_500, altitude + verticalSpeed * step / 4))
        if (215...330).contains(airspeed) && abs(effectiveBank) <= 12 && flaps == .retracted && !gearDown {
            phaseElapsed += step
            if phaseElapsed >= cruiseDuration { transition(to: .approach) }
        }
    }

    private mutating func advanceApproach(_ step: Double) {
        flyTowardSpeed(referenceApproachSpeed - 24 + 175 * power, step: step)
        let floor = destinationElevation + 1_350
        verticalSpeed = max(-2_200, min(500, (effectivePitch - 1) * 240))
        altitude = max(floor, min(climbTargetAltitude + 3_000, altitude + verticalSpeed * step * 65 / 60))
        if altitude == floor {
            verticalSpeed = max(0, verticalSpeed)
            if approachStable { transition(to: .landing) }
        }
    }

    private mutating func advanceLanding(_ step: Double) {
        if onGround {
            if let arrivalTaxi {
                if advanceTaxi(step, along: arrivalTaxi) { transition(to: .arrived) }
                return
            }
            let previousGroundSpeed = groundSpeed
            reverseThrust = reverseThrust && canUseReverseThrust
            let acceleration = 5 * power - (brake ? 17 : 4.0) - (reverseThrust ? 6 : 0)
            airspeed = max(0, airspeed + acceleration * step)
            landingRollM += (previousGroundSpeed + groundSpeed) * 0.5 * 0.514_444 * step
            if airspeed <= 3 && throttle < 10 { beginArrivalTaxi() }
            return
        }

        flyTowardSpeed(referenceApproachSpeed - 29 + 175 * power, step: step)
        let flareHeight = destinationElevation + 65
        if altitude > flareHeight {
            verticalSpeed = max(-1_450, min(300, (effectivePitch - 1) * 220))
            altitude = max(flareHeight, altitude + verticalSpeed * step * 26 / 60)
        } else if approachStable && (2...12).contains(pitch) {
            verticalSpeed = -max(110, 390 - pitch * 38)
            altitude = max(destinationElevation, altitude + verticalSpeed * step * 26 / 60)
            if altitude == destinationElevation {
                landingSpeed = airspeed
                touchdownVerticalSpeed = verticalSpeed
                onGround = true
                verticalSpeed = 0
            }
        } else {
            verticalSpeed = 0
        }
    }

    private mutating func beginArrivalTaxi() {
        guard let runway = arrivalGround, let connector = runway.exit(afterRunwayDistance: arrivalRunwayPositionM),
              let first = connector.outwardPath.first else {
            transition(to: .arrived)
            return
        }
        let current = runway.pose(onRunway: arrivalRunwayPositionM)
        let continuation = current.distance(to: first) > 1 ? [current] + connector.outwardPath : connector.outwardPath
        arrivalTaxi = FlightTaxiPath(points: continuation)
        taxiDistanceM = 0
        airspeed = 0
        reverseThrust = false
    }

    private mutating func advanceTaxi(_ step: Double, along path: FlightTaxiPath) -> Bool {
        let previousSpeed = airspeed
        let acceleration = brake || !gearDown ? -12 : 14 * power - 0.7 - airspeed * 0.10
        airspeed = min(22, max(0, airspeed + acceleration * step))
        // Preserve meter-scale geometry while compressing the time spent on each mapped taxiway.
        taxiDistanceM = min(path.lengthM, taxiDistanceM + (previousSpeed + airspeed) * 0.5 * 0.514_444 * step * 3.5)
        guard taxiDistanceM >= path.lengthM else { return false }
        airspeed = 0
        return true
    }

    private mutating func flyTowardSpeed(_ target: Double, step: Double) {
        let drag: Double = switch flaps { case .retracted: 0; case .takeoff: 13; case .landing: 26 }
        let targetSpeed = max(80, target - drag - (gearDown ? 10 : 0) - max(0, effectivePitch - 3) * 1.3)
        airspeed += (targetSpeed - airspeed) * (1 - exp(-step / 2.4))
    }

    private mutating func setLandingConfiguration(pitch: Double) {
        gearDown = true
        flaps = .landing
        throttle = 39
        self.pitch = pitch
    }

    private mutating func transition(to next: Phase) {
        phase = next
        phaseElapsed = 0
    }

    private mutating func recordSample() {
        // Retain the full time range as idle sessions grow, with lower detail for older readings.
        if samples.count >= 120 {
            samples = samples.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
            sampleInterval *= 2
        }
        samples.append(Sample(elapsed: elapsed, altitude: altitude, airspeed: airspeed))
    }

    private func unit(_ value: Double) -> Double { min(1, max(0, value)) }
}
