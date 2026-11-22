import Foundation

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
    var wind: Wind = .calm

    private(set) var phase: Phase = .briefing
    private(set) var airspeed = 0.0
    private(set) var altitude: Double
    private(set) var verticalSpeed = 0.0
    private(set) var runwayUsed = 0.0
    private(set) var landingRollM = 0.0
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
         destinationRunwayLengthM: Double? = nil) {
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
        departureRunwayLength = runwayLengthM.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        destinationRunwayLength = destinationRunwayLengthM.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.departureRunwayHeading = departureRunwayHeading.flatMap { $0.isFinite ? $0 : nil }
        self.destinationRunwayHeading = destinationRunwayHeading.flatMap { $0.isFinite ? $0 : nil }
    }

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
        case .takeoff: return unit(airspeed / rotationSpeed)
        case .climb:
            let start = returningToApproach ? destinationElevation : originElevation
            return unit((altitude - start) / (climbTargetAltitude - start))
        case .cruise: return unit(phaseElapsed / cruiseDuration)
        case .approach:
            let height = climbTargetAltitude - destinationElevation
            return 1 - unit((altitude - destinationElevation - 1_350) / (height - 1_350))
        case .landing:
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
        switch phase {
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
             Check("rollout-brake", "使用刹车减速", brake),
             Check("rollout-stop", "在跑道上停稳", airspeed <= 3)]
        }
    }

    var instruction: String {
        switch phase {
        case .briefing: "检查机场跑道、客机和天气。准备好后开始起飞滑跑。"
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
        return Summary(takeoffRollM: runwayUsed, landingRollM: landingRollM, landingSpeed: landingSpeed,
                       touchdownVerticalSpeed: touchdownVerticalSpeed, peakAltitude: peakAltitude,
                       peakSpeed: peakSpeed, elapsed: elapsed, goArounds: goArounds, maxBank: maxBank,
                       landingRunwayExceeded: destinationRunwayLength.map { landingRollM > $0 } ?? false,
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
        transition(to: .briefing)
        airspeed = 0
        altitude = originElevation
        verticalSpeed = 0
        runwayUsed = 0
        landingRollM = 0
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
    private var groundSpeed: Double { airspeed > 0 ? max(0, airspeed - (headwindKnots ?? 0)) : 0 }
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
        let previousGroundSpeed = groundSpeed
        let acceleration = brake ? -19 : 10.5 * power - 1.7 - airspeed * 0.004
        airspeed = min(210, max(0, airspeed + acceleration * step))
        runwayUsed += (previousGroundSpeed + groundSpeed) * 0.5 * 0.514_444 * step
        verticalSpeed = 0
        if let runwayLength = departureRunwayLength, runwayUsed > runwayLength {
            takeoffAborted = true
            airspeed = 0
        } else if gearDown && flaps == .takeoff && !brake && throttle >= 75 && airspeed >= rotationSpeed
                    && (5...14).contains(pitch) && abs(effectiveBank) <= 8 {
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
            let previousGroundSpeed = groundSpeed
            let acceleration = 5 * power - (brake ? 17 : 4.0)
            airspeed = max(0, airspeed + acceleration * step)
            landingRollM += (previousGroundSpeed + groundSpeed) * 0.5 * 0.514_444 * step
            if airspeed <= 3 && throttle < 10 { transition(to: .arrived) }
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
