import SwiftUI
import UIKit

enum AtlasAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色 · 青瓷航空图鉴"
        case .dark: "深色 · 深海飞行仪表"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Keep native status and control appearance in sync with the SwiftUI palette while a detail is visible.
struct AtlasWindowAppearance: UIViewRepresentable {
    let selection: AtlasAppearance

    func makeUIView(context: Context) -> AppearanceView {
        let view = AppearanceView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: AppearanceView, context: Context) {
        view.style = switch selection {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    final class AppearanceView: UIView {
        var style: UIUserInterfaceStyle = .unspecified {
            didSet { syncWindow() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            syncWindow()
        }

        private func syncWindow() {
            guard let window, window.overrideUserInterfaceStyle != style else { return }
            window.overrideUserInterfaceStyle = style
            DispatchQueue.main.async { [weak window] in
                window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
            }
        }
    }
}

struct AtlasPalette {
    let isDark: Bool
    private let increasedContrast: Bool

    init(_ scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) {
        isDark = scheme == .dark
        increasedContrast = contrast == .increased
    }

    var page: Color { pair(0xEDF3F0, 0x081A24) }
    var surface: Color { pair(0xFBFDFB, 0x102A36) }
    var subtle: Color { pair(0xE1EBE7, 0x163543) }
    var line: Color {
        increasedContrast ? pair(0x70867F, 0x72909E) : pair(0xC2D3CE, 0x345563)
    }
    var ink: Color { pair(0x132E2C, 0xEDF7F7) }
    var muted: Color {
        increasedContrast ? pair(0x354E49, 0xC9DCE5) : pair(0x486460, 0xA9C1CE)
    }
    var accent: Color {
        increasedContrast ? pair(0x004741, 0xA1FFE9) : pair(0x00665D, 0x7EE5D1)
    }
    var onAccent: Color { pair(0xFFFFFF, 0x062B2A) }
    var selection: Color { pair(0xD4EBE2, 0x1C434F) }
    var selectionInk: Color { pair(0x004B45, 0x9DF3E5) }
    var stage: Color { Color(atlasHex: 0x102435) }
    var stageInk: Color { Color(atlasHex: 0xEFF8FC) }
    var stageMuted: Color { Color(atlasHex: 0xBACED9) }
    var stageAccent: Color { Color(atlasHex: 0x89EBDD) }
    var corner: CGFloat { 18 }
    var contentGap: CGFloat { 16 }

    func readout(_ size: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(size, design: isDark ? .monospaced : .default, weight: weight)
    }

    private func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(atlasHex: isDark ? dark : light)
    }
}

private extension Color {
    init(atlasHex: UInt32) {
        self.init(
            red: Double((atlasHex >> 16) & 0xFF) / 255,
            green: Double((atlasHex >> 8) & 0xFF) / 255,
            blue: Double(atlasHex & 0xFF) / 255
        )
    }
}

extension View {
    func atlasPanel(_ palette: AtlasPalette, radius: CGFloat? = nil) -> some View {
        let boundary = RoundedRectangle(cornerRadius: radius ?? palette.corner)
        return background(palette.surface, in: boundary)
            .overlay { boundary.strokeBorder(palette.line, lineWidth: 1).allowsHitTesting(false) }
    }
}
