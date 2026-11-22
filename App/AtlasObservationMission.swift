import SwiftUI

struct AtlasObservationQuestion {
    let prompt: String
    let choices: [String]
    let answer: Int
    let explanation: String

    init(_ prompt: String, _ choices: [String], answer: Int, explanation: String) {
        self.prompt = prompt
        self.choices = choices
        self.answer = answer
        self.explanation = explanation
    }
}

enum AtlasObservationProgress {
    static let airportsKey = "atlas.exploration.airports.completed"
    static let aircraftKey = "atlas.exploration.aircraft.completed"

    static func completed(in stored: String) -> Set<String> {
        Set(stored.split(separator: ",").map(String.init))
    }

    static func marking(_ id: String, in stored: String) -> String {
        completed(in: stored).union([id]).sorted().joined(separator: ",")
    }
}

@MainActor
struct AtlasObservationMission: View {
    let id: String
    let question: AtlasObservationQuestion
    let completed: Bool
    let palette: AtlasPalette
    let onComplete: () -> Void
    @State private var incorrectChoice: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.prompt)
                .font(AtlasTypography.font(.subheadline, weight: .semibold))
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if completed {
                Label("观察完成", systemImage: "checkmark.circle.fill")
                    .font(AtlasTypography.font(.subheadline, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .accessibilityIdentifier("exploration-completed-\(id)")
                Text(question.explanation)
                    .font(AtlasTypography.font(.footnote))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                    Button {
                        if index == question.answer {
                            onComplete()
                        } else {
                            incorrectChoice = index
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: incorrectChoice == index ? "arrow.counterclockwise.circle" : "circle")
                                .foregroundStyle(palette.accent)
                                .accessibilityHidden(true)
                            Text(choice)
                                .font(AtlasTypography.font(.subheadline))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(palette.surface, in: .rect(cornerRadius: 8))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("exploration-answer-\(id)-\(index)")
                    .accessibilityValue(incorrectChoice == index ? "再观察一下" : "")
                }
                if incorrectChoice != nil {
                    Text("再观察一下，可以继续选择。")
                        .font(AtlasTypography.font(.footnote))
                        .foregroundStyle(palette.muted)
                        .accessibilityIdentifier("exploration-retry-\(id)")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.subtle, in: .rect(cornerRadius: 12))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: completed)
    }
}
