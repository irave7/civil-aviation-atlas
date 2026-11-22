import AVFAudio
import Foundation
import os

/// Speech setup may wait for a system text-to-speech service. Keep it off the rendering and touch thread.
final class ExplorationNarrator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "aviation.atlas.narration", qos: .userInitiated)
    private let revision = OSAllocatedUnfairLock(initialState: 0)
    private var synthesizer: AVSpeechSynthesizer?

    func speak(_ text: String) {
        let request = invalidate()
        queue.async { [self] in
            guard revision.withLock({ $0 == request }),
                  let voice = AVSpeechSynthesisVoice(language: "zh-CN"),
                  revision.withLock({ $0 == request }) else { return }

            let engine = synthesizer ?? AVSpeechSynthesizer()
            synthesizer = engine
            engine.stopSpeaking(at: .immediate)
            let message = AVSpeechUtterance(string: text)
            message.voice = voice
            message.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
            engine.speak(message)
        }
    }

    func stop() {
        let request = invalidate()
        queue.async { [self] in
            if revision.withLock({ $0 == request }) {
                synthesizer?.stopSpeaking(at: .immediate)
            }
        }
    }

    private func invalidate() -> Int {
        revision.withLock { value in
            value &+= 1
            return value
        }
    }
}
