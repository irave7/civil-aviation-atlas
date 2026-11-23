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
    enum Channel: Sendable { case guide, cabin }

    enum Event: Sendable {
        case playing(Channel)
        case paused
        case finished
        case unavailable
    }

    private struct Playback {
        let revision: Int
        let observer: (@Sendable (Event) -> Void)?
        let onPlaybackStarted: (@Sendable () -> Void)?
        let onCabinStarted: (@Sendable () -> Void)?
        var cabin: URL?
        var channel: Channel = .guide
        var started = false
        var paused = false
        var startupDeadline = ContinuousClock.now + .seconds(3)
    }

    private let queue = DispatchQueue(label: "aviation.atlas.narration", qos: .userInitiated)
    private let revision = OSAllocatedUnfairLock(initialState: 0)
    private lazy var mandarinVoice: AVSpeechSynthesisVoice? = {
        let regionDefault = AVSpeechSynthesisVoice(language: "zh-CN")
        let installed = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.caseInsensitiveCompare("zh-CN") == .orderedSame
        }
        return installed.first { $0.quality == .premium }
            ?? installed.first { $0.quality == .enhanced } ?? regionDefault
    }()
    private var synthesizer: AVSpeechSynthesizer?
    private var player: AVAudioPlayer?
    private var playback: Playback?
    private var monitor: DispatchSourceTimer?

    func speak(_ cue: ExplorationNarrationCue, voice: ExplorationVoice, fallback text: String,
               audibleInSilentMode: Bool = false, routeRecording: URL? = nil, followedBy cabin: URL? = nil,
               observe: (@Sendable (Event) -> Void)? = nil,
               onCabinStarted: (@Sendable () -> Void)? = nil, onPlaybackStarted: (@Sendable () -> Void)? = nil) {
        let recording = voice == .system ? nil : routeRecording ?? Self.audioURL(for: cue, voice: voice)
        begin(recording: recording, text: text, voice: voice, cabin: cabin, audibleInSilentMode: audibleInSilentMode,
              observe: observe, onPlaybackStarted: onPlaybackStarted, onCabinStarted: onCabinStarted)
    }

    func speakAnswer(_ text: String, voice: ExplorationVoice, observe: @escaping @Sendable (Event) -> Void) {
        begin(recording: nil, text: text, voice: voice, cabin: nil, audibleInSilentMode: true,
              observe: observe, onPlaybackStarted: nil, onCabinStarted: nil)
    }

    func preview(_ recording: URL?, transcript: String, voice: ExplorationVoice,
                 observe: @escaping @Sendable (Event) -> Void) {
        begin(recording: voice == .system ? nil : recording, text: transcript, voice: voice, cabin: nil,
              audibleInSilentMode: true, observe: observe, onPlaybackStarted: nil, onCabinStarted: nil)
    }

    private func begin(recording: URL?, text: String, voice: ExplorationVoice, cabin: URL?, audibleInSilentMode: Bool,
                       observe: (@Sendable (Event) -> Void)?,
                       onPlaybackStarted: (@Sendable () -> Void)?, onCabinStarted: (@Sendable () -> Void)?) {
        let request = invalidate()
        queue.async { [self] in
            guard isCurrent(request) else { return }
            stopCurrentAudio()
            prepareAudioSession(audibleInSilentMode: audibleInSilentMode)
            guard isCurrent(request) else { return }
            playback = Playback(revision: request, observer: observe, onPlaybackStarted: onPlaybackStarted,
                                onCabinStarted: onCabinStarted, cabin: cabin)
            if let recording, playFile(recording, request: request) {
                didBeginPart()
                startMonitor()
            } else if isCurrent(request), !text.isEmpty, let systemVoice = mandarinVoice {
                let engine = synthesizer ?? AVSpeechSynthesizer()
                synthesizer = engine
                let message = AVSpeechUtterance(string: AviationSpeech.mandarin(text))
                message.voice = systemVoice
                let pace: Float = switch voice {
                case .captain: 0.91
                case .story: 0.87
                case .guide: 0.96
                case .system: 1.0
                }
                message.rate = AVSpeechUtteranceDefaultSpeechRate * pace
                engine.speak(message)
                checkPlayback()
                if playback != nil { startMonitor() }
            } else {
                advancePlayback(initiallyUnavailable: true)
            }
        }
    }

    func previewCabin(_ url: URL, onStarted: (@Sendable () -> Void)? = nil) {
        let request = invalidate()
        queue.async { [self] in
            guard isCurrent(request) else { return }
            stopCurrentAudio()
            prepareAudioSession(audibleInSilentMode: true)
            if playFile(url, request: request) { onStarted?() }
        }
    }

    func pause() {
        let request = revision.withLock { $0 }
        queue.async { [self] in
            guard isCurrent(request), playback?.revision == request, playback?.paused == false else { return }
            player?.pause()
            synthesizer?.pauseSpeaking(at: .immediate)
            playback?.paused = true
            cancelMonitor()
            playback?.observer?(.paused)
        }
    }

    func resume() {
        let request = revision.withLock { $0 }
        queue.async { [self] in
            guard isCurrent(request), playback?.revision == request, playback?.paused == true else { return }
            playback?.paused = false
            playback?.startupDeadline = ContinuousClock.now + .seconds(3)
            let resumed = player?.play() ?? (synthesizer?.continueSpeaking() == true)
            if resumed, let current = playback {
                current.observer?(.playing(current.channel))
                startMonitor()
            } else {
                advancePlayback(initiallyUnavailable: true)
            }
        }
    }

    func stop() {
        let request = invalidate()
        queue.async { [self] in
            if isCurrent(request) { stopCurrentAudio() }
        }
    }

    private func prepareAudioSession(audibleInSilentMode: Bool) {
        let session = AVAudioSession.sharedInstance()
        if audibleInSilentMode {
            if session.category != .playback || !session.categoryOptions.contains(.mixWithOthers) {
                try? session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            }
            try? session.setActive(true)
        } else if session.category != .ambient {
            try? session.setCategory(.ambient)
        }
    }

    static func audioURL(for cue: ExplorationNarrationCue, voice: ExplorationVoice) -> URL? {
        let filename = "narration-\(voice.rawValue)-\(cue.rawValue)"
        let bundle = Bundle.main
        return bundle.url(forResource: filename, withExtension: "m4a")
            ?? bundle.url(forResource: filename, withExtension: "m4a", subdirectory: "Narration")
            ?? bundle.url(forResource: filename, withExtension: "m4a", subdirectory: "Resources/Narration")
    }

    private func stopCurrentAudio() {
        cancelMonitor()
        playback = nil
        player?.stop()
        player = nil
        synthesizer?.stopSpeaking(at: .immediate)
    }

    private func startMonitor() {
        guard monitor == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(125), repeating: .milliseconds(125), leeway: .milliseconds(30))
        timer.setEventHandler { [weak self] in self?.checkPlayback() }
        monitor = timer
        timer.resume()
    }

    private func cancelMonitor() {
        monitor?.cancel()
        monitor = nil
    }

    private func checkPlayback() {
        guard let current = playback, isCurrent(current.revision), !current.paused else { return }
        let playing = player?.isPlaying ?? (synthesizer?.isSpeaking == true)
        if playing {
            if !current.started { didBeginPart() }
        } else if current.started || ContinuousClock.now >= current.startupDeadline {
            advancePlayback(initiallyUnavailable: !current.started)
        }
    }

    private func didBeginPart() {
        guard let current = playback, isCurrent(current.revision), !current.started else { return }
        playback?.started = true
        current.observer?(.playing(current.channel))
        switch current.channel {
        case .guide: current.onPlaybackStarted?()
        case .cabin: current.onCabinStarted?()
        }
    }

    private func advancePlayback(initiallyUnavailable: Bool) {
        guard let current = playback, isCurrent(current.revision) else { return }
        if let cabin = current.cabin {
            playback?.cabin = nil
            if playFile(cabin, request: current.revision) {
                playback?.channel = .cabin
                playback?.started = false
                didBeginPart()
                startMonitor()
                return
            }
        }
        stopCurrentAudio()
        current.observer?(initiallyUnavailable ? .unavailable : .finished)
    }

    private func playFile(_ url: URL, request: Int) -> Bool {
        guard isCurrent(request), let clip = try? AVAudioPlayer(contentsOf: url),
              isCurrent(request), clip.play() else { return false }
        player = clip
        return true
    }

    private func isCurrent(_ request: Int) -> Bool { revision.withLock { $0 == request } }

    private func invalidate() -> Int {
        revision.withLock { value in
            value &+= 1
            return value
        }
    }
}
