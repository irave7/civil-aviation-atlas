import Observation
import SwiftUI

@MainActor
@Observable
final class FlightVoiceInteraction {
    private enum Status { case idle, loading, guide, cabin, paused, unavailable }

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
    var summary: String? { message?.text }
    var summaryLabel: String { message?.broadcast == nil ? "答复" : "播报摘要" }

    var statusLabel: String {
        switch status {
        case .idle: "语音待命"
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
        let next = Message(heading: cue.phaseLabel, text: text, broadcast: broadcast)
        if protectsManualPlayback {
            // Keep the latest phase once, even if the pilot pauses the spoken reply.
            pendingBroadcast = PendingBroadcast(message: next, sound: sound,
                                                onStarted: onStarted, onCabinStarted: onCabinStarted)
        } else {
            load(next, sound: sound, onStarted: onStarted, onCabinStarted: onCabinStarted)
        }
    }

    func ask(_ question: FlightVoiceQuestion, sound: FlightSimulatorSound) {
        load(Message(heading: question.title, text: question.answer, broadcast: nil), sound: sound, manual: true)
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
            narrator.speakAnswer(next.text, observe: observer)
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
        case .playing(.guide): status = .guide
        case .playing(.cabin): status = .cabin
        case .paused: status = .paused
        case .finished: finishPlayback(unavailable: false)
        case .unavailable: finishPlayback(unavailable: true)
        }
        activeSound?.setNarrationActive(isSpeaking)
    }

    private func finishPlayback(unavailable: Bool) {
        status = unavailable ? .unavailable : .idle
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
        case .briefing: "飞机还在\(origin)。准备就绪后，我们将飞往\(destination)。"
        case .arrived: "我们已经抵达\(destination)。打开飞行复盘，就能查看这次航程。"
        default: "我们正在\(stage)。从\(origin)到\(destination)的模拟航程已完成百分之\(progress)。"
        }
        let airspeed = Int(simulation.airspeed.rounded())
        let groundSpeed = Int(simulation.groundSpeedKnots.rounded())
        let altitude = Int(simulation.altitude.rounded())
        let instruments = simulation.onGround
            ? "当前地速是\(groundSpeed)节。地速表示飞机相对地面移动得多快。"
            : "当前空速是\(airspeed)节，海拔\(altitude)英尺。空速是飞机相对周围空气的速度。"
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
    let sound: FlightSimulatorSound
    let questions: [FlightVoiceQuestion]

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("飞行语音", systemImage: "waveform")
                    .font(AtlasTypography.font(.headline, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(interaction.statusLabel)
                    .font(AtlasTypography.font(.subheadline, weight: .medium))
                    .foregroundStyle(interaction.isSpeaking ? palette.accent : palette.muted)
                    .accessibilityIdentifier("simulator-voice-status")
            }
            Toggle("自动播报", isOn: $narration)
                .accessibilityIdentifier("simulator-voice-automatic")

            if let heading = interaction.heading, let summary = interaction.summary {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(interaction.summaryLabel) · \(heading)")
                        .font(AtlasTypography.font(.subheadline, weight: .bold))
                    Text(summary)
                        .font(AtlasTypography.font(.subheadline))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("simulator-voice-summary")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.page, in: .rect(cornerRadius: 8))
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { playbackButtons }
                VStack(alignment: .leading, spacing: 5) { playbackButtons }
            }
            Text("问问向导")
                .font(AtlasTypography.font(.subheadline, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            ForEach(questions) { question in
                Button {
                    interaction.ask(question, sound: sound)
                } label: {
                    Label(question.title, systemImage: question.kind.symbol)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .font(AtlasTypography.font(.subheadline, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .accessibilityIdentifier("simulator-voice-question-\(question.id)")
            }
        }
        .foregroundStyle(palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .atlasPanel(palette)
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
