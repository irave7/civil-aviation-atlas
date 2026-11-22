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
}

/// Audio preparation and system voice discovery run outside the rendering and touch thread.
final class ExplorationNarrator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "aviation.atlas.narration", qos: .userInitiated)
    private let revision = OSAllocatedUnfairLock(initialState: 0)
    private var synthesizer: AVSpeechSynthesizer?
    private var player: AVAudioPlayer?

    func speak(_ cue: ExplorationNarrationCue, voice: ExplorationVoice, fallback text: String) {
        let request = invalidate()
        queue.async { [self] in
            guard revision.withLock({ $0 == request }) else { return }
            stopCurrentAudio()
            try? AVAudioSession.sharedInstance().setCategory(.ambient)

            if voice != .system,
               let file = audioURL(for: cue, voice: voice),
               let clip = try? AVAudioPlayer(contentsOf: file) {
                guard revision.withLock({ $0 == request }) else { return }
                player = clip
                if clip.play() { return }
                player = nil
            }

            guard revision.withLock({ $0 == request }),
                  let systemVoice = AVSpeechSynthesisVoice(language: "zh-CN"),
                  revision.withLock({ $0 == request }) else { return }

            let engine = synthesizer ?? AVSpeechSynthesizer()
            synthesizer = engine
            let message = AVSpeechUtterance(string: text)
            message.voice = systemVoice
            message.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
            engine.speak(message)
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

    private func invalidate() -> Int {
        revision.withLock { value in
            value &+= 1
            return value
        }
    }
}
