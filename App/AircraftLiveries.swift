import SwiftUI
import UIKit

struct AircraftLivery: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable, Hashable {
        case reference = "图鉴基准"
        case domestic = "国内航司"
        case international = "国际航司"
        case special = "特殊涂装"

        var id: Self { self }
    }

    struct Palette: Hashable {
        enum Pattern: String, Hashable {
            case lowStripe, tailSweep, wideBelly, ribbon, fullBody
        }

        let body: UInt32
        let primary: UInt32
        let accent: UInt32
        let pattern: Pattern

        var bodyColor: Color { Color(uiColor: bodyUIColor) }
        var primaryColor: Color { Color(uiColor: primaryUIColor) }
        var accentColor: Color { Color(uiColor: accentUIColor) }
        var bodyUIColor: UIColor { Self.uiColor(body) }
        var primaryUIColor: UIColor { Self.uiColor(primary) }
        var accentUIColor: UIColor { Self.uiColor(accent) }

        private static func uiColor(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }

    let id: String
    let name: String
    let operatorName: String?
    let category: Category
    let aircraftIDs: Set<String>
    let palette: Palette
    let source: AtlasSource?
    let registration: String?
    let period: String?

    init(id: String, name: String, operatorName: String?, category: Category, aircraftIDs: Set<String>,
         palette: Palette, source: AtlasSource?, registration: String? = nil, period: String? = nil) {
        self.id = id
        self.name = name
        self.operatorName = operatorName
        self.category = category
        self.aircraftIDs = aircraftIDs
        self.palette = palette
        self.source = source
        self.registration = registration
        self.period = period
    }
}

enum AircraftLiveries {
    static let reference = AircraftLivery(
        id: "reference", name: "图鉴基准涂装", operatorName: nil, category: .reference, aircraftIDs: [],
        palette: .init(body: 0xEDF2F2, primary: 0x103A50, accent: 0x38A99C, pattern: .lowStripe), source: nil
    )

    static func options(for profile: AircraftProfile) -> [AircraftLivery] {
        [reference] + (AircraftLiveryOperatorCatalog.entries + AircraftLiverySpecialCatalog.entries)
            .filter { $0.aircraftIDs.contains(profile.id) }
    }
}
