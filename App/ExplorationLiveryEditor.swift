import SwiftUI
import UIKit

@MainActor
struct ExplorationLiveryEditor: View {
    let profile: AircraftProfile
    let baseline: AircraftLivery
    let apply: (AircraftLivery) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ExplorationLiveryEditor.storageKey) private var savedPalette = ""
    @State private var bodyPaint: Color
    @State private var primaryPaint: Color
    @State private var accentPaint: Color
    @State private var pattern: AircraftLivery.Palette.Pattern

    private static let storageKey = "atlas.exploration.custom-livery.v1"
    private static let patterns: [AircraftLivery.Palette.Pattern] = [.lowStripe, .tailSweep, .wideBelly, .ribbon, .fullBody]

    init(profile: AircraftProfile, baseline: AircraftLivery, apply: @escaping (AircraftLivery) -> Void) {
        self.profile = profile
        self.baseline = baseline
        self.apply = apply
        let initial = Self.restoredLivery(for: profile)?.palette ?? baseline.palette
        _bodyPaint = State(initialValue: initial.bodyColor)
        _primaryPaint = State(initialValue: initial.primaryColor)
        _accentPaint = State(initialValue: initial.accentColor)
        _pattern = State(initialValue: initial.pattern)
    }

    static func restoredLivery(for profile: AircraftProfile) -> AircraftLivery? {
        guard let value = UserDefaults.standard.string(forKey: storageKey),
              let palette = AircraftLivery.Palette(explorationValue: value) else { return nil }
        return palette.explorationLivery(for: profile)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        ExplorationLiverySwatch(bodyPaint: bodyPaint, primaryPaint: primaryPaint,
                                                accentPaint: accentPaint, pattern: pattern)
                            .frame(height: 136)
                            .accessibilityHidden(true)
                        Text(profile.displayName)
                            .font(AtlasTypography.font(.headline, weight: .semibold))
                    }
                    .padding(.vertical, 5)
                }
                Section("颜色") {
                    ColorPicker("机身底色", selection: $bodyPaint, supportsOpacity: false)
                        .accessibilityIdentifier("exploration-livery-body")
                    ColorPicker("主涂装色", selection: $primaryPaint, supportsOpacity: false)
                        .accessibilityIdentifier("exploration-livery-primary")
                    ColorPicker("点缀色", selection: $accentPaint, supportsOpacity: false)
                        .accessibilityIdentifier("exploration-livery-accent")
                }
                Section("图案") {
                    Picker("图案", selection: $pattern) {
                        ForEach(Self.patterns, id: \.self) { choice in
                            Text(choice.explorationLabel)
                                .tag(choice)
                                .accessibilityIdentifier("exploration-livery-pattern-\(choice.rawValue)")
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("exploration-livery-pattern")
                }
                Section {
                    Button(baseline.operatorName == nil ? "恢复基准涂装" : "恢复航司涂装", systemImage: "arrow.uturn.backward") {
                        apply(baseline)
                        dismiss()
                    }
                    .accessibilityIdentifier("exploration-livery-restore")
                }
            }
            .navigationTitle("我的涂装")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("exploration-livery-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用", systemImage: "checkmark", action: applyCustomPalette)
                        .accessibilityIdentifier("exploration-livery-apply")
                }
            }
        }
        .accessibilityIdentifier("exploration-livery-sheet")
    }

    private func applyCustomPalette() {
        let palette = AircraftLivery.Palette(
            body: Self.hex(bodyPaint, fallback: baseline.palette.body),
            primary: Self.hex(primaryPaint, fallback: baseline.palette.primary),
            accent: Self.hex(accentPaint, fallback: baseline.palette.accent),
            pattern: pattern
        )
        savedPalette = palette.explorationValue
        apply(palette.explorationLivery(for: profile))
        dismiss()
    }

    private static func hex(_ color: Color, fallback: UInt32) -> UInt32 {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return fallback }
        func byte(_ channel: CGFloat) -> UInt32 {
            UInt32((min(1, max(0, channel)) * 255).rounded())
        }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }
}

private extension AircraftLivery.Palette {
    init?(explorationValue: String) {
        let fields = explorationValue.split(separator: "-")
        guard fields.count == 4, let pattern = Pattern(rawValue: String(fields[0])),
              let body = UInt32(fields[1], radix: 16), body <= 0xFFFFFF,
              let primary = UInt32(fields[2], radix: 16), primary <= 0xFFFFFF,
              let accent = UInt32(fields[3], radix: 16), accent <= 0xFFFFFF else { return nil }
        self.init(body: body, primary: primary, accent: accent, pattern: pattern)
    }

    var explorationValue: String {
        [pattern.rawValue, String(body, radix: 16), String(primary, radix: 16), String(accent, radix: 16)].joined(separator: "-")
    }

    func explorationLivery(for profile: AircraftProfile) -> AircraftLivery {
        AircraftLivery(id: "exploration-diy-\(profile.id)-\(explorationValue)", name: "我的涂装", operatorName: nil,
                       category: .reference, aircraftIDs: [profile.id], palette: self, source: nil)
    }
}

private extension AircraftLivery.Palette.Pattern {
    var explorationLabel: String {
        switch self {
        case .lowStripe: "双线细纹"
        case .tailSweep: "渐展尾纹"
        case .wideBelly: "宽幅腹纹"
        case .ribbon: "波浪飘带"
        case .fullBody: "机身双色"
        }
    }
}

private struct ExplorationLiverySwatch: View {
    let bodyPaint: Color
    let primaryPaint: Color
    let accentPaint: Color
    let pattern: AircraftLivery.Palette.Pattern

    var body: some View {
        Canvas { context, size in
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: size.width * x, y: size.height * y) }
            let fuselage = Path { path in
                path.move(to: point(0.06, 0.47))
                path.addQuadCurve(to: point(0.26, 0.43), control: point(0.15, 0.44))
                path.addLine(to: point(0.77, 0.43))
                path.addQuadCurve(to: point(0.93, 0.56), control: point(0.89, 0.44))
                path.addQuadCurve(to: point(0.76, 0.65), control: point(0.94, 0.64))
                path.addLine(to: point(0.28, 0.65))
                path.addQuadCurve(to: point(0.06, 0.49), control: point(0.14, 0.59))
                path.closeSubpath()
            }
            func shape(_ vertices: [(CGFloat, CGFloat)]) -> Path {
                Path { path in
                    path.addLines(vertices.map { point($0.0, $0.1) })
                    path.closeSubpath()
                }
            }
            context.fill(shape([(0.10, 0.48), (0.09, 0.22), (0.14, 0.21), (0.29, 0.50)]), with: .color(primaryPaint))
            context.fill(shape([(0.10, 0.26), (0.15, 0.28), (0.23, 0.43), (0.17, 0.36)]), with: .color(accentPaint))
            context.fill(shape([(0.43, 0.58), (0.67, 0.58), (0.40, 0.83), (0.33, 0.83)]), with: .color(Color(uiColor: .systemGray)))
            context.fill(fuselage, with: .color(bodyPaint))

            var painted = context
            painted.clip(to: fuselage)
            switch pattern {
            case .lowStripe:
                painted.fill(shape([(0.05, 0.54), (0.93, 0.54), (0.93, 0.58), (0.05, 0.58)]), with: .color(primaryPaint))
                painted.stroke(Path { path in
                    path.move(to: point(0.05, 0.60))
                    path.addLine(to: point(0.90, 0.60))
                }, with: .color(accentPaint), lineWidth: 1.5)
            case .tailSweep:
                let sweep = Path { path in
                    path.move(to: point(0.04, 0.34))
                    path.addLine(to: point(0.23, 0.41))
                    path.addQuadCurve(to: point(0.56, 0.66), control: point(0.30, 0.62))
                    path.addLine(to: point(0.04, 0.72))
                    path.closeSubpath()
                }
                painted.fill(sweep, with: .color(primaryPaint))
                painted.stroke(sweep, with: .color(accentPaint), lineWidth: 2)
            case .wideBelly, .fullBody:
                let edge: CGFloat = pattern == .wideBelly ? 0.58 : 0.48
                let belly = Path { path in
                    path.move(to: point(0.04, 0.55))
                    path.addQuadCurve(to: point(0.91, 0.59), control: point(0.43, edge - 0.12))
                    path.addLine(to: point(0.95, 0.73))
                    path.addLine(to: point(0.04, 0.73))
                    path.closeSubpath()
                }
                painted.fill(belly, with: .color(primaryPaint))
                painted.stroke(belly, with: .color(accentPaint), lineWidth: 1.5)
            case .ribbon:
                let ribbon = Path { path in
                    path.move(to: point(0.06, 0.43))
                    path.addCurve(to: point(0.94, 0.61), control1: point(0.43, 0.76), control2: point(0.59, 0.35))
                }
                painted.stroke(ribbon, with: .color(primaryPaint), lineWidth: size.height * 0.065)
                painted.stroke(ribbon, with: .color(accentPaint), lineWidth: size.height * 0.024)
            }

            context.stroke(fuselage, with: .color(.white.opacity(0.24)), lineWidth: 0.8)
            for index in 0..<16 {
                let window = point(0.28 + CGFloat(index) * 0.027, 0.51)
                context.fill(Path(roundedRect: CGRect(x: window.x, y: window.y, width: 3, height: 2.7), cornerRadius: 1),
                             with: .color(Color(red: 0.08, green: 0.16, blue: 0.23).opacity(0.8)))
            }
            context.fill(shape([(0.83, 0.49), (0.88, 0.53), (0.83, 0.53)]),
                         with: .color(Color(red: 0.08, green: 0.16, blue: 0.23).opacity(0.8)))
        }
        .background {
            RoundedRectangle(cornerRadius: 18).fill(
                LinearGradient(colors: [Color(red: 0.10, green: 0.24, blue: 0.32), Color(red: 0.18, green: 0.38, blue: 0.43)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
    }
}
