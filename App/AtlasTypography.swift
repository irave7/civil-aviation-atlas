import CoreText
import SwiftUI
import UIKit

@MainActor
enum AtlasTypography {
    private static let resource = "AtlasFallbackChinese"
    private static let fallbackName: String? = {
        let bundle = Bundle.main
        guard let file = bundle.url(forResource: resource, withExtension: "otf")
                ?? bundle.url(forResource: resource, withExtension: "otf", subdirectory: "Resources") else { return nil }
        #if !targetEnvironment(simulator)
        if hasSystemChinese() { return nil }
        #endif
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor],
              let font = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(font, kCTFontNameAttribute) as? String else { return nil }
        _ = CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        return UIFont(name: name, size: 17) == nil ? nil : name
    }()

    static func prepare() {
        guard let fallbackName,
              let title = UIFont(name: fallbackName, size: 17),
              let largeTitle = UIFont(name: fallbackName, size: 34) else { return }
        let bar = UINavigationBar.appearance()
        bar.titleTextAttributes = [.font: title]
        bar.largeTitleTextAttributes = [.font: largeTitle]
        if let option = UIFont(name: fallbackName, size: 13) {
            let segmentedControl = UISegmentedControl.appearance()
            segmentedControl.setTitleTextAttributes([.font: option], for: .normal)
            segmentedControl.setTitleTextAttributes([.font: option], for: .selected)
        }
    }

    static func font(_ style: Font.TextStyle, design: Font.Design = .default, weight: Font.Weight? = nil) -> Font {
        guard let fallbackName, design != .monospaced else {
            return .system(style, design: design, weight: weight)
        }
        let base = Font.custom(fallbackName, size: regularSize(for: style), relativeTo: style)
        if let weight { return base.weight(weight) }
        return style == .headline ? base.weight(.semibold) : base
    }

    private static func hasSystemChinese() -> Bool {
        let sample = "航空国际场站" as CFString
        guard let system = CTFontCreateUIFontForLanguage(.system, 17, "zh-Hans" as CFString) else { return false }
        let font = CTFontCreateForString(system, sample, CFRange(location: 0, length: CFStringGetLength(sample)))
        guard !(CTFontCopyPostScriptName(font) as String).localizedCaseInsensitiveContains("LastResort") else { return false }
        let characters = Array("航空国际场站".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        return CTFontGetGlyphsForCharacters(font, characters, &glyphs, glyphs.count) && !glyphs.contains(0)
    }

    private static func regularSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}
