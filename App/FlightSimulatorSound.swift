import AVFoundation
import Foundation

/// The mixer, players and audio-session activation are confined to the audio queue.
final class FlightSimulatorSound: @unchecked Sendable {
    enum Effect: String, Sendable {
        case chime
        case switchClick = "switch"
        case touchdown
        case gear
        case reverse
        case flaps

        var volume: Float {
            switch self {
            case .chime: 0.60
            case .switchClick: 0.42
            case .touchdown: 0.67
            case .gear, .flaps: 0.53
            case .reverse: 0.49
            }
        }
    }

    private enum Layer: String, CaseIterable { case cabin, engine, airflow, roll }

    private struct Mix {
        let volume: Float
        let rate: Float
    }

    private let queue = DispatchQueue(label: "aviation.atlas.flight-effects", qos: .userInitiated)
    private var layers: [Layer: AVAudioPlayer] = [:]
    private var previousMix: [Layer: Mix] = [:]
    private var effects: [Effect: AVAudioPlayer] = [:]
    private var unavailableEffects: Set<Effect> = []
    private var didPrepareLayers = false
    private var isRunning = false

    private static func activateSession() {
        let session = AVAudioSession.sharedInstance()
        // Playback remains audible under the hardware silent switch and coexists with narration.
        if session.category != .playback || session.mode != .default || !session.categoryOptions.contains(.mixWithOthers) {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try? session.setActive(true)
    }

    func update(throttle: Double, airspeed: Double, groundSpeed: Double, onGround: Bool,
                inCockpit: Bool, running: Bool) {
        queue.async { [self] in
            updateMix(throttle: throttle, airspeed: airspeed, groundSpeed: groundSpeed,
                      onGround: onGround, inCockpit: inCockpit, running: running)
        }
    }

    private func updateMix(throttle: Double, airspeed: Double, groundSpeed: Double, onGround: Bool,
                           inCockpit: Bool, running: Bool) {
        guard running else {
            if isRunning {
                for player in layers.values { player.pause() }
                stopEffects()
            }
            isRunning = false
            return
        }

        if !isRunning { Self.activateSession() }
        isRunning = true
        if !didPrepareLayers { prepareLayers() }
        let thrust = fraction(throttle, relativeTo: 100)
        let wind = fraction(airspeed, relativeTo: 330)
        let tires = onGround ? fraction(groundSpeed, relativeTo: 78) : 0

        mix(.cabin, volume: inCockpit ? 0.30 : 0.05, rate: 1)
        mix(.engine, volume: (inCockpit ? 0.12 : 0.19) + thrust * (inCockpit ? 0.19 : 0.33),
            rate: 0.73 + thrust * 0.51)
        mix(.airflow, volume: wind * wind * (inCockpit ? 0.15 : 0.29), rate: 0.87 + wind * 0.22)
        mix(.roll, volume: sqrt(tires) * (inCockpit ? 0.26 : 0.44), rate: 0.76 + tires * 0.46)
    }

    func play(_ effect: Effect) {
        queue.async { [self] in playEffect(effect) }
    }

    private func playEffect(_ effect: Effect) {
        guard !unavailableEffects.contains(effect) else { return }
        if effects[effect] == nil {
            guard let player = player(for: effect.rawValue) else {
                unavailableEffects.insert(effect)
                return
            }
            player.volume = effect.volume
            player.prepareToPlay()
            effects[effect] = player
        }
        guard let player = effects[effect] else { return }
        if !isRunning { Self.activateSession() }
        player.currentTime = 0
        player.play()
    }

    func stop() {
        queue.async { [self] in stopMix() }
    }

    private func stopMix() {
        isRunning = false
        previousMix.removeAll()
        for player in layers.values {
            player.stop()
            player.currentTime = 0
            player.volume = 0
        }
        stopEffects()
    }

    private func stopEffects() {
        for player in effects.values {
            player.stop()
            player.currentTime = 0
        }
    }

    private func prepareLayers() {
        didPrepareLayers = true
        for layer in Layer.allCases {
            guard let player = player(for: layer.rawValue) else { continue }
            player.numberOfLoops = -1
            player.enableRate = true
            player.volume = 0
            player.prepareToPlay()
            layers[layer] = player
        }
    }

    private func mix(_ layer: Layer, volume: Float, rate: Float) {
        guard let player = layers[layer] else { return }
        let previous = previousMix[layer]
        let volumeChanged = previous.map { abs($0.volume - volume) >= 0.015 || ($0.volume != 0 && volume == 0) } ?? true
        let rateChanged = previous.map { abs($0.rate - rate) >= 0.025 } ?? true
        if volumeChanged { player.setVolume(volume, fadeDuration: 0.12) }
        if rateChanged { player.rate = rate }
        previousMix[layer] = Mix(volume: volumeChanged ? volume : previous?.volume ?? volume,
                                 rate: rateChanged ? rate : previous?.rate ?? rate)
        if !player.isPlaying && volume >= 0.01 { player.play() }
    }

    private func fraction(_ value: Double, relativeTo maximum: Double) -> Float {
        value.isFinite ? Float(min(1, max(0, value / maximum))) : 0
    }

    private func player(for asset: String) -> AVAudioPlayer? {
        let name = "flight-\(asset)"
        let url = Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "FlightEffects")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a")
        guard let url else { return nil }
        return try? AVAudioPlayer(contentsOf: url)
    }
}
