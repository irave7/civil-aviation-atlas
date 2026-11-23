import Observation
import SwiftUI

enum ExplorationListeningSource {
    case observation(id: String, fallback: String)
    case route(FlightChallenge)

    var id: String {
        switch self {
        case .observation(let id, _): id
        case .route(let challenge): challenge.id
        }
    }

    var transcript: String {
        switch self {
        case .observation(let id, let fallback): FlightAudioText.observation[id] ?? fallback
        case .route(let challenge): FlightAudioText.transcript(for: challenge.introductionAudio) ?? challenge.introduction
        }
    }

    func recording(voice: ExplorationVoice) -> URL? {
        guard voice != .system else { return nil }
        switch self {
        case .observation(let id, _):
            let role = voice == .guide ? "" : voice.rawValue + "-"
            return FlightAudioText.resource("observation-" + role + id, ext: "m4a", directory: "ObservationVoices")
        case .route(let challenge):
            return challenge.introductionAudio
        }
    }
}

@MainActor
@Observable
final class ExplorationListening {
    enum Phase { case idle, preparing, playing, finished, unavailable }

    private(set) var id: String?
    private(set) var phase = Phase.idle
    private(set) var transcript: String?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private let narrator = ExplorationNarrator()

    func toggle(_ source: ExplorationListeningSource, voice: ExplorationVoice) {
        let id = source.id
        if self.id == id && (phase == .preparing || phase == .playing) {
            stop()
            return
        }
        revision &+= 1
        let request = revision
        self.id = id
        phase = .preparing
        let line = source.transcript
        transcript = line
        narrator.preview(source.recording(voice: voice), transcript: line, voice: voice) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, revision == request else { return }
                switch event {
                case .playing: phase = .playing
                case .finished: phase = .finished
                case .unavailable: phase = .unavailable
                case .paused: break
                }
            }
        }
    }

    func stop() {
        revision &+= 1
        narrator.stop()
        id = nil
        phase = .idle
        transcript = nil
    }
}

@MainActor
struct ExplorationListenButton: View {
    let player: ExplorationListening
    let source: ExplorationListeningSource
    let accessibilityID: String
    @AppStorage("atlas.exploration.voice.v1") private var voice = ExplorationVoice.guide
    @Environment(\.scenePhase) private var scenePhase

    private var phase: ExplorationListening.Phase { player.id == source.id ? player.phase : .idle }

    private var title: String {
        switch phase {
        case .idle: source.recording(voice: voice) == nil ? "朗读导览" : "听 AI 导览"
        case .preparing: "准备中"
        case .playing: "停止播放"
        case .finished: "再听一次"
        case .unavailable: "重试朗读"
        }
    }

    var body: some View {
        Button {
            player.toggle(source, voice: voice)
        } label: {
            Label(title, systemImage: phase == .playing || phase == .preparing ? "stop.circle.fill" : "headphones")
                .frame(minHeight: 34)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityValue(phase == .playing ? "正在播放" : "")
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && player.id == source.id { player.stop() }
        }
        .onChange(of: voice) {
            if player.id == source.id { player.stop() }
        }
    }
}

@MainActor
struct ExplorationVoiceCaption: View {
    let player: ExplorationListening
    let id: String

    var body: some View {
        if player.id == id, let caption = player.transcript {
            VStack(alignment: .leading, spacing: 3) {
                if player.phase == .unavailable {
                    Text("语音暂时不可用，可阅读下方导览。")
                        .font(AtlasTypography.font(.footnote, weight: .semibold))
                }
                Text(caption)
                    .font(AtlasTypography.font(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
            .accessibilityIdentifier("exploration-transcript-\(id)")
        }
    }
}

struct ExplorationVoiceMenu: View {
    @AppStorage("atlas.exploration.voice.v1") private var voice = ExplorationVoice.guide

    var body: some View {
        Menu {
            Section {
                Picker("导览声音", selection: $voice) {
                    ForEach(ExplorationVoice.allCases) { style in
                        Text(style.selectorTitle).tag(style)
                    }
                }
            } footer: {
                Text("机场与机型导览可选声音。航线关卡和航司广播各有专属配音。")
            }
        } label: {
            Image(systemName: "waveform")
                .frame(minWidth: 32, minHeight: 36)
        }
        .accessibilityLabel("导览声音")
        .accessibilityValue(voice.title)
        .accessibilityIdentifier("exploration-voice-style")
    }
}
