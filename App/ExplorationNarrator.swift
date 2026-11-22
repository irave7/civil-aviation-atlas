import AVFAudio
import Foundation
import os

enum ExplorationVoice: String, CaseIterable, Identifiable, Sendable {
    case captain, guide, story, system

    var id: Self { self }

    var title: String {
        switch self {
        case .captain: "机长广播"
        case .guide: "航程向导"
        case .story: "航旅解说"
        case .system: "系统朗读"
        }
    }

    var description: String {
        switch self {
        case .captain: "沉稳清楚的客机广播口吻"
        case .guide: "轻快亲切，侧重操作提示"
        case .story: "舒缓的航旅解说"
        case .system: "朗读当前机场和航程文字"
        }
    }

    var selectorTitle: String { self == .system ? title : "AI 配音 · \(title)" }
}

enum ExplorationNarrationCue: String, CaseIterable, Sendable {
    case departing, cruise, approach, arrived, rotate, gearUp, gearDown
    case briefing, taxiOut, roll, touchdown, taxiIn

    var phaseLabel: String {
        switch self {
        case .briefing: "航前准备"
        case .taxiOut: "滑出"
        case .departing, .roll, .rotate: "起飞"
        case .gearUp: "爬升"
        case .cruise: "巡航"
        case .approach, .gearDown: "进近"
        case .touchdown: "接地"
        case .taxiIn: "滑入"
        case .arrived: "抵达"
        }
    }
}

/// Audio preparation and system voice discovery run outside the rendering and touch thread.
final class ExplorationNarrator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "aviation.atlas.narration", qos: .userInitiated)
    private let revision = OSAllocatedUnfairLock(initialState: 0)
    private var synthesizer: AVSpeechSynthesizer?
    private var player: AVAudioPlayer?

    func speak(_ cue: ExplorationNarrationCue, voice: ExplorationVoice, fallback text: String,
               audibleInSilentMode: Bool = false, routeRecording: URL? = nil, followedBy cabin: URL? = nil,
               onCabinStarted: (@Sendable () -> Void)? = nil, onPlaybackStarted: (@Sendable () -> Void)? = nil) {
        let request = invalidate()
        queue.async { [self] in
            guard revision.withLock({ $0 == request }) else { return }
            stopCurrentAudio()
            let session = AVAudioSession.sharedInstance()
            if audibleInSilentMode {
                try? session.setCategory(.playback, mode: .default, options: .mixWithOthers)
                try? session.setActive(true)
            } else {
                try? session.setCategory(.ambient)
            }

            if voice != .system,
               let file = routeRecording ?? audioURL(for: cue, voice: voice),
               let clip = try? AVAudioPlayer(contentsOf: file) {
                guard revision.withLock({ $0 == request }) else { return }
                player = clip
                if clip.play() {
                    onPlaybackStarted?()
                    if let cabin {
                        enqueueCabin(cabin, after: clip.duration + 0.18, request: request, onStarted: onCabinStarted)
                    }
                    return
                }
                player = nil
            }

            guard revision.withLock({ $0 == request }) else { return }
            guard let systemVoice = AVSpeechSynthesisVoice(language: "zh-CN") else {
                if let cabin { playCabin(cabin, request: request, onStarted: onCabinStarted) }
                return
            }
            guard revision.withLock({ $0 == request }) else { return }

            let engine = synthesizer ?? AVSpeechSynthesizer()
            synthesizer = engine
            let message = AVSpeechUtterance(string: text)
            message.voice = systemVoice
            message.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
            engine.speak(message)
            if engine.isSpeaking { onPlaybackStarted?() }
            if let cabin { enqueueCabin(cabin, after: 0.4, request: request, onStarted: onCabinStarted) }
        }
    }

    func previewCabin(_ url: URL, onStarted: (@Sendable () -> Void)? = nil) {
        let request = invalidate()
        queue.async { [self] in
            guard revision.withLock({ $0 == request }) else { return }
            stopCurrentAudio()
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try? session.setActive(true)
            playCabin(url, request: request, onStarted: onStarted)
        }
    }

    func stop() {
        let request = invalidate()
        queue.async { [self] in
            if revision.withLock({ $0 == request }) {
                stopCurrentAudio()
            }
        }
    }

    private func audioURL(for cue: ExplorationNarrationCue, voice: ExplorationVoice) -> URL? {
        let filename = "narration-\(voice.rawValue)-\(cue.rawValue)"
        let bundle = Bundle.main
        return bundle.url(forResource: filename, withExtension: "m4a")
            ?? bundle.url(forResource: filename, withExtension: "m4a", subdirectory: "Narration")
            ?? bundle.url(forResource: filename, withExtension: "m4a", subdirectory: "Resources/Narration")
    }

    private func stopCurrentAudio() {
        player?.stop()
        player = nil
        synthesizer?.stopSpeaking(at: .immediate)
    }

    private func enqueueCabin(_ url: URL, after seconds: TimeInterval, request: Int,
                              onStarted: (@Sendable () -> Void)?) {
        queue.asyncAfter(deadline: .now() + seconds) { [self] in
            guard revision.withLock({ $0 == request }) else { return }
            if player?.isPlaying == true || synthesizer?.isSpeaking == true {
                enqueueCabin(url, after: 0.25, request: request, onStarted: onStarted)
            } else {
                playCabin(url, request: request, onStarted: onStarted)
            }
        }
    }

    private func playCabin(_ url: URL, request: Int, onStarted: (@Sendable () -> Void)?) {
        guard revision.withLock({ $0 == request }), let clip = try? AVAudioPlayer(contentsOf: url),
              revision.withLock({ $0 == request }) else { return }
        player = clip
        if clip.play() { onStarted?() }
    }

    private func invalidate() -> Int {
        revision.withLock { value in
            value &+= 1
            return value
        }
    }
}
