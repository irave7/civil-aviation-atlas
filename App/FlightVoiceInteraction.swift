import Observation
import SwiftUI

@MainActor
@Observable
final class FlightVoiceInteraction {
    private enum Status { case idle, loading, guide, cabin, paused, finished, unavailable }

    private struct Broadcast {
        let cue: ExplorationNarrationCue
        let voice: ExplorationVoice
        let recording: URL?
        let cabin: URL?
        let cabinTitle: String?
    }

    private struct Message {
        let heading: String
        let text: String
        let voice: ExplorationVoice
        let broadcast: Broadcast?
    }

    private struct PendingBroadcast {
        let message: Message
        let sound: FlightSimulatorSound
        let onStarted: (@MainActor () -> Void)?
        let onCabinStarted: (@MainActor () -> Void)?
    }

    private var status: Status = .idle
    private var message: Message?
    private var captionChannel = ExplorationNarrator.Channel.guide
    @ObservationIgnored private let narrator = ExplorationNarrator()
    @ObservationIgnored private var activeSound: FlightSimulatorSound?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var protectsManualPlayback = false
    @ObservationIgnored private var pendingBroadcast: PendingBroadcast?

    var isSpeaking: Bool { status == .guide || status == .cabin }
    var isPaused: Bool { status == .paused }
    var canPause: Bool { isSpeaking || isPaused }
    var canReplay: Bool { message != nil }
    var heading: String? { message?.heading }
    var summary: String? {
        if captionChannel == .cabin, let caption = FlightAudioText.transcript(for: message?.broadcast?.cabin) {
            return caption
        }
        return message?.text
    }

    var statusLabel: String {
        switch status {
        case .idle: message == nil ? "等待航程播报" : "播放已停止"
        case .finished: "播放完毕"
        case .loading: "正在准备语音"
        case .guide: message?.broadcast == nil ? "正在回答" : "航程播报中"
        case .cabin: message?.broadcast?.cabinTitle.map { "\($0)模拟广播" } ?? "航司广播中"
        case .paused: "语音已暂停"
        case .unavailable: "语音暂不可用，可查看文字"
        }
    }

    func play(_ cue: ExplorationNarrationCue, voice: ExplorationVoice, text: String,
              recording: URL?, cabin: URL?, cabinTitle: String?, sound: FlightSimulatorSound,
              onStarted: (@MainActor () -> Void)? = nil, onCabinStarted: (@MainActor () -> Void)? = nil) {
        let broadcast = Broadcast(cue: cue, voice: voice, recording: recording, cabin: cabin, cabinTitle: cabinTitle)
        let audio = recording ?? ExplorationNarrator.audioURL(for: cue, voice: voice)
        let caption = voice == .system ? text : FlightAudioText.transcript(for: audio) ?? text
        let next = Message(heading: cue.phaseLabel, text: caption, voice: voice, broadcast: broadcast)
        if protectsManualPlayback {
            // Keep the latest phase once, even if the pilot pauses the spoken reply.
            pendingBroadcast = PendingBroadcast(message: next, sound: sound,
                                                onStarted: onStarted, onCabinStarted: onCabinStarted)
        } else {
            load(next, sound: sound, onStarted: onStarted, onCabinStarted: onCabinStarted)
        }
    }

    func ask(_ question: FlightVoiceQuestion, voice: ExplorationVoice, sound: FlightSimulatorSound) {
        load(Message(heading: question.title, text: question.answer, voice: voice, broadcast: nil), sound: sound, manual: true)
    }

    func replay(sound: FlightSimulatorSound) {
        guard let message else { return }
        load(message, sound: sound, manual: true)
    }

    func togglePause() {
        if isPaused { narrator.resume() }
        else if isSpeaking { narrator.pause() }
    }

    func stop(clear: Bool = false) {
        generation &+= 1
        protectsManualPlayback = false
        pendingBroadcast = nil
        narrator.stop()
        activeSound?.setNarrationActive(false)
        activeSound = nil
        status = .idle
        if clear { message = nil }
    }

    func previewCabin(_ url: URL, onStarted: (@Sendable () -> Void)? = nil) {
        stop()
        narrator.previewCabin(url, onStarted: onStarted)
    }

    private func load(_ next: Message, sound: FlightSimulatorSound, manual: Bool = false,
                      onStarted: (@MainActor () -> Void)? = nil,
                      onCabinStarted: (@MainActor () -> Void)? = nil) {
        generation &+= 1
        let request = generation
        if activeSound !== sound {
            activeSound?.setNarrationActive(false)
            activeSound = sound
        }
        captionChannel = .guide
        message = next
        protectsManualPlayback = manual
        status = .loading
        let observer: @Sendable (ExplorationNarrator.Event) -> Void = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, generation == request else { return }
                updateStatus(for: event)
            }
        }
        if let broadcast = next.broadcast {
            narrator.speak(broadcast.cue, voice: broadcast.voice, fallback: next.text,
                           audibleInSilentMode: true, routeRecording: broadcast.recording, followedBy: broadcast.cabin,
                           observe: observer, onCabinStarted: callback(onCabinStarted, request: request),
                           onPlaybackStarted: callback(onStarted, request: request))
        } else {
            narrator.speakAnswer(next.text, voice: next.voice, observe: observer)
        }
    }

    private func callback(_ action: (@MainActor () -> Void)?, request: Int) -> (@Sendable () -> Void)? {
        guard let action else { return nil }
        return { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.generation == request else { return }
                action()
            }
        }
    }

    private func updateStatus(for event: ExplorationNarrator.Event) {
        switch event {
        case .playing(.guide):
            captionChannel = .guide
            status = .guide
        case .playing(.cabin):
            captionChannel = .cabin
            status = .cabin
        case .paused: status = .paused
        case .finished: finishPlayback(unavailable: false)
        case .unavailable: finishPlayback(unavailable: true)
        }
        activeSound?.setNarrationActive(isSpeaking)
    }

    private func finishPlayback(unavailable: Bool) {
        status = unavailable ? .unavailable : .finished
        protectsManualPlayback = false
        guard let pending = pendingBroadcast else { return }
        pendingBroadcast = nil
        load(pending.message, sound: pending.sound, onStarted: pending.onStarted, onCabinStarted: pending.onCabinStarted)
    }
}

struct FlightVoiceQuestion: Identifiable {
    enum Kind: String {
        case nextStep = "下一步做什么"
        case progress = "飞到哪里了"
        case instruments = "仪表怎么看"

        var symbol: String {
            switch self {
            case .nextStep: "checklist"
            case .progress: "location.circle"
            case .instruments: "gauge.with.dots.needle.50percent"
            }
        }
    }

    let kind: Kind
    let answer: String

    var id: Kind { kind }
    var title: String { kind.rawValue }

    static func flightQuestions(for simulation: FlightSimulation, origin: String, destination: String) -> [Self] {
        let progress = Int((simulation.progress * 100).rounded())
        let stage = (simulation.phase == .briefing ? nil : simulation.groundStage?.title) ?? simulation.phase.title
        let position = switch simulation.phase {
        case .briefing: "我们还停在\(origin)。这一程要去的是\(destination)。"
        case .arrived: "我们已经抵达\(destination)。打开飞行复盘，就能查看这次航程。"
        default: "现在是\(stage)阶段。从\(origin)飞往\(destination)的这段路，我们走过了百分之\(progress)。"
        }
        let airspeed = Int(simulation.airspeed.rounded())
        let groundSpeed = Int(simulation.groundSpeedKnots.rounded())
        let altitude = Int(simulation.altitude.rounded())
        let instruments = simulation.onGround
            ? "当前地速是\(groundSpeed)节。看看窗外的地面，它向后移动得越快，地速就越大。"
            : "高度表读作\(altitude)英尺。再看空速表，\(airspeed)节，表示飞机穿过周围空气的速度。"
        return [
            .init(kind: .nextStep, answer: simulation.instruction),
            .init(kind: .progress, answer: position),
            .init(kind: .instruments, answer: instruments)
        ]
    }
}

@MainActor
struct FlightVoiceDeck: View {
    let interaction: FlightVoiceInteraction
    @Binding var narration: Bool
    let voice: ExplorationVoice
    let sound: FlightSimulatorSound
    let questions: [FlightVoiceQuestion]

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        VStack(alignment: .leading, spacing: palette.contentGap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: interaction.isPaused ? "pause.fill" : "waveform")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 40, height: 40)
                        .background(palette.selection, in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(interaction.heading ?? "航程播报")
                            .font(AtlasTypography.font(.headline, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(interaction.statusLabel)
                            .font(AtlasTypography.font(.footnote, weight: .medium))
                            .foregroundStyle(palette.muted)
                            .accessibilityIdentifier("simulator-voice-status")
                    }
                }
                if let caption = interaction.summary {
                    Text(caption)
                        .font(AtlasTypography.font(.body))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("simulator-voice-summary")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { playbackButtons }
                        VStack(alignment: .leading, spacing: 6) { playbackButtons }
                    }
                }
                Divider()
                Toggle("自动播报", isOn: $narration)
                    .accessibilityIdentifier("simulator-voice-automatic")
            }
            .padding(15)
            .atlasPanel(palette)

            VStack(alignment: .leading, spacing: 0) {
                Text("问问向导")
                    .font(AtlasTypography.font(.headline, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 5)
                ForEach(questions) { question in
                    Button {
                        interaction.ask(question, voice: voice, sound: sound)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: question.kind.symbol)
                                .foregroundStyle(palette.accent)
                                .frame(width: 23)
                                .accessibilityHidden(true)
                            Text(question.title)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Image(systemName: "play.circle")
                                .foregroundStyle(palette.accent)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .font(AtlasTypography.font(.subheadline, weight: .medium))
                    .buttonStyle(.plain)
                    .accessibilityHint("播放回答并显示全文")
                    .accessibilityIdentifier("simulator-voice-question-\(question.id)")
                    if question.id != questions.last?.id { Divider() }
                }
            }
            .padding(15)
            .atlasPanel(palette)
        }
        .foregroundStyle(palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var playbackButtons: some View {
        Button("重播", systemImage: "arrow.counterclockwise") { interaction.replay(sound: sound) }
            .disabled(!interaction.canReplay)
            .accessibilityIdentifier("simulator-voice-replay")
            .buttonStyle(.glass)
            .controlSize(.large)
        Button(interaction.isPaused ? "继续语音" : "暂停语音", systemImage: interaction.isPaused ? "play" : "pause") {
            interaction.togglePause()
        }
        .disabled(!interaction.canPause)
        .accessibilityIdentifier("simulator-voice-pause")
        .buttonStyle(.glass)
        .controlSize(.large)
    }
}
